# TeamSpeak 6 on AWS EC2

This Terraform project creates a low-cost single-node TeamSpeak 6 server on AWS:

- Ubuntu EC2 instance running the official TeamSpeak 6 Docker image
- Elastic IP
- Security group for TeamSpeak voice and file transfer
- Encrypted EBS data volume mounted at `/opt/teamspeak-data`
- Daily EBS snapshots with 7-day retention by default
- Optional Route 53 `A` record

This is intentionally not Kubernetes. For a 20-50 person TeamSpeak server, EKS adds a fixed control-plane cost and extra operational overhead without helping much because the server is stateful.

## Prerequisites

Install these locally:

- Terraform `>= 1.6`
- AWS CLI
- AWS credentials with permissions to manage EC2, EBS, security groups, Elastic IPs, and optionally Route 53
- IAM permissions for AWS Data Lifecycle Manager if `enable_ebs_snapshots = true`

Confirm AWS credentials:

```powershell
aws sts get-caller-identity
```

## Configure

Copy the example variable file:

```powershell
cd infra/aws-ec2
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. This file is intentionally gitignored because it contains local/account-specific values.

At minimum, set:

```hcl
aws_region    = "us-east-1"
instance_type = "t3.small"
```

Recommended for admin access:

```hcl
admin_cidrs  = ["YOUR_PUBLIC_IP/32"]
ssh_key_name = "YOUR_EXISTING_EC2_KEYPAIR"
```

For ServerQuery automation/bots, enable SSH Query and keep it restricted to `admin_cidrs`:

```hcl
enable_query_http = false
enable_query_ssh  = true
```

You can find your public IP with:

```powershell
(Invoke-WebRequest -UseBasicParsing https://checkip.amazonaws.com).Content.Trim()
```

## Deploy

```powershell
terraform init
terraform plan
terraform apply
```

After apply, Terraform prints `teamspeak_address`. Connect TeamSpeak clients to that address.

If you configured DNS, wait a few minutes for the Route 53 record TTL.

## Get Initial Server Logs

If you enabled SSH access:

```powershell
ssh ubuntu@PUBLIC_IP
sudo docker logs teamspeak-server
```

The initial server admin/privilege information is shown in the container logs.

## Ports

Public:

- `9987/udp` TeamSpeak voice
- `30033/tcp` file transfer, when `enable_file_transfer = true`

Admin-only, restricted to `admin_cidrs` when enabled:

- `22/tcp` SSH
- `10080/tcp` TeamSpeak HTTP query
- `10022/tcp` TeamSpeak SSH query

## Local Files That Must Not Be Committed

Keep these local only:

- `terraform.tfvars` — real AWS region, admin CIDRs, DNS, key-pair name, feature toggles
- `terraform.tfstate` / `terraform.tfstate.backup` — resource IDs, outputs, provider metadata
- `.terraform/` — provider/plugin cache
- `tfplan` / `*.tfplan` — generated Terraform plans
- `after-terraform-files/` — local deployment outputs such as public IPs and instance IDs
- private keys such as `*.pem`

The committed source should contain only generic defaults and examples.

## Data and Backups

TeamSpeak data is stored on the attached EBS volume mounted at:

```text
/opt/teamspeak-data
```

By default, Terraform also creates an AWS Data Lifecycle Manager policy that snapshots the data volume daily and retains 7 snapshots. Change `snapshot_retention_count`, `snapshot_time_utc`, or set `enable_ebs_snapshots = false` in `terraform.tfvars` if you want different behavior.

## Updating TeamSpeak

SSH to the instance and run:

```bash
cd /opt/teamspeak
sudo docker compose pull
sudo docker compose up -d
```

## Destroy

To remove the infrastructure:

```powershell
terraform destroy
```

Destroying the stack deletes the EC2 instance and the data EBS volume. Take a snapshot first if you need to keep the server data.
