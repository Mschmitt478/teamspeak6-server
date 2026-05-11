data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

data "aws_vpc" "selected" {
  count = var.vpc_id == null ? 0 : 1
  id    = var.vpc_id
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

data "aws_subnet" "selected" {
  id = local.subnet_id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  vpc_id    = var.vpc_id == null ? data.aws_vpc.default[0].id : data.aws_vpc.selected[0].id
  subnet_id = var.subnet_id == null ? data.aws_subnets.selected.ids[0] : var.subnet_id

  common_tags = merge(
    {
      Project   = "teamspeak6"
      ManagedBy = "terraform"
    },
    var.tags
  )
}

resource "aws_security_group" "teamspeak" {
  name        = "${var.name_prefix}-sg"
  description = "TeamSpeak 6 server access"
  vpc_id      = local.vpc_id

  ingress {
    description = "TeamSpeak voice"
    from_port   = var.voice_port
    to_port     = var.voice_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_file_transfer ? [1] : []

    content {
      description = "TeamSpeak file transfer"
      from_port   = var.file_transfer_port
      to_port     = var.file_transfer_port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = length(var.admin_cidrs) > 0 ? [1] : []

    content {
      description = "SSH admin"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.admin_cidrs
    }
  }

  dynamic "ingress" {
    for_each = var.enable_query_http && length(var.admin_cidrs) > 0 ? [1] : []

    content {
      description = "TeamSpeak HTTP query"
      from_port   = var.query_http_port
      to_port     = var.query_http_port
      protocol    = "tcp"
      cidr_blocks = var.admin_cidrs
    }
  }

  dynamic "ingress" {
    for_each = var.enable_query_ssh && length(var.admin_cidrs) > 0 ? [1] : []

    content {
      description = "TeamSpeak SSH query"
      from_port   = var.query_ssh_port
      to_port     = var.query_ssh_port
      protocol    = "tcp"
      cidr_blocks = var.admin_cidrs
    }
  }

  egress {
    description = "Outbound internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sg"
  })
}

resource "aws_instance" "teamspeak" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.teamspeak.id]
  key_name                    = var.ssh_key_name
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    voice_port           = var.voice_port
    file_transfer_port   = var.file_transfer_port
    enable_file_transfer = var.enable_file_transfer
    enable_query_http    = var.enable_query_http
    query_http_port      = var.query_http_port
    enable_query_ssh     = var.enable_query_ssh
    query_ssh_port       = var.query_ssh_port
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-server"
  })
}

resource "aws_ebs_volume" "teamspeak_data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = var.data_volume_size_gb
  type              = var.data_volume_type
  encrypted         = true

  tags = merge(local.common_tags, {
    Name   = "${var.name_prefix}-data"
    Backup = var.enable_ebs_snapshots ? "daily" : "disabled"
  })
}

resource "aws_volume_attachment" "teamspeak_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.teamspeak_data.id
  instance_id = aws_instance.teamspeak.id
}

resource "aws_eip" "teamspeak" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eip"
  })
}

resource "aws_eip_association" "teamspeak" {
  allocation_id = aws_eip.teamspeak.id
  instance_id   = aws_instance.teamspeak.id
}

data "aws_iam_policy_document" "dlm_assume_role" {
  count = var.enable_ebs_snapshots ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  count              = var.enable_ebs_snapshots ? 1 : 0
  name               = "${var.name_prefix}-dlm-role"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume_role[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  count      = var.enable_ebs_snapshots ? 1 : 0
  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "teamspeak_data" {
  count              = var.enable_ebs_snapshots ? 1 : 0
  description        = "Daily snapshots for ${var.name_prefix} TeamSpeak data volume"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      Name   = "${var.name_prefix}-data"
      Backup = "daily"
    }

    schedule {
      name      = "daily"
      copy_tags = true

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = [var.snapshot_time_utc]
      }

      retain_rule {
        count = var.snapshot_retention_count
      }

      tags_to_add = {
        SnapshotCreator = "dlm"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-data-snapshots"
  })
}

resource "aws_route53_record" "teamspeak" {
  count   = var.hosted_zone_id != null && var.dns_name != null ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.dns_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.teamspeak.public_ip]
}
