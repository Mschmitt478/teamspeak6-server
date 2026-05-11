variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for AWS resource names."
  type        = string
  default     = "teamspeak6"
}

variable "instance_type" {
  description = "EC2 instance type. t3.small is a good starting point for a small TS6 server."
  type        = string
  default     = "t3.small"
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name for SSH. Leave null to disable SSH key login."
  type        = string
  default     = null
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to SSH to the instance and use optional admin/query ports. Example: [\"203.0.113.10/32\"]."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID. Leave null to use the default VPC."
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Subnet ID. Leave null to use the first subnet in the selected/default VPC."
  type        = string
  default     = null
}

variable "data_volume_size_gb" {
  description = "Size of the persistent TeamSpeak data EBS volume."
  type        = number
  default     = 50
}

variable "data_volume_type" {
  description = "EBS volume type for TeamSpeak data."
  type        = string
  default     = "gp3"
}

variable "enable_ebs_snapshots" {
  description = "Create an AWS DLM policy for daily snapshots of the TeamSpeak data volume."
  type        = bool
  default     = true
}

variable "snapshot_time_utc" {
  description = "UTC time for daily EBS snapshots in HH:MM format."
  type        = string
  default     = "08:00"
}

variable "snapshot_retention_count" {
  description = "Number of daily EBS snapshots to retain."
  type        = number
  default     = 7
}

variable "voice_port" {
  description = "TeamSpeak UDP voice port."
  type        = number
  default     = 9987
}

variable "file_transfer_port" {
  description = "TeamSpeak TCP file transfer port."
  type        = number
  default     = 30033
}

variable "enable_file_transfer" {
  description = "Open and publish the file transfer port."
  type        = bool
  default     = true
}

variable "enable_query_http" {
  description = "Open the TeamSpeak HTTP query port to admin_cidrs and enable it in the container."
  type        = bool
  default     = false
}

variable "query_http_port" {
  description = "TeamSpeak HTTP query port."
  type        = number
  default     = 10080
}

variable "enable_query_ssh" {
  description = "Open the TeamSpeak SSH query port to admin_cidrs and enable it in the container."
  type        = bool
  default     = false
}

variable "query_ssh_port" {
  description = "TeamSpeak SSH query port."
  type        = number
  default     = 10022
}

variable "hosted_zone_id" {
  description = "Optional Route 53 hosted zone ID. When set with dns_name, an A record is created."
  type        = string
  default     = null
}

variable "dns_name" {
  description = "Optional DNS name to point at the Elastic IP, such as ts.example.com."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for AWS resources."
  type        = map(string)
  default     = {}
}
