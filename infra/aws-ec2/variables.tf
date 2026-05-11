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

variable "enable_apollo_bridge" {
  description = "Install ApolloBridge as a lightweight systemd service on the same EC2 instance. Secrets stay in /opt/apollo-bridge/.env.local on the host."
  type        = bool
  default     = false
}

variable "apollo_bridge_channel_id" {
  description = "TeamSpeak channel ID where ApolloBridge listens and replies."
  type        = number
  default     = 4
}

variable "apollo_bridge_prefix" {
  description = "Text prefix that addresses ApolloBridge in the TeamSpeak channel."
  type        = string
  default     = "@Apollo"
}

variable "apollo_bridge_openai_model" {
  description = "OpenAI model used by ApolloBridge when APOLLO_BRIDGE_MODE=openai."
  type        = string
  default     = "gpt-4.1-mini"
}

variable "apollo_bridge_source_base_url" {
  description = "Base raw URL containing ApolloBridge bridge.js and package.json. Used at boot to keep EC2 user-data small."
  type        = string
  default     = "https://raw.githubusercontent.com/Mschmitt478/teamspeak6-server/main/apollo-bridge"
}

variable "enable_ts6_gui_bot" {
  description = "Create a separate experimental slim EC2 host that runs the real TeamSpeak GUI client as a future presence/voice layer. Credentials stay in /opt/apollo-gui-bot/.env.local on that host."
  type        = bool
  default     = false
}

variable "ts6_gui_bot_instance_type" {
  description = "EC2 instance type for the experimental TS6 GUI client bot host. t3.small is the lean practical floor for a desktop stack."
  type        = string
  default     = "t3.small"
}

variable "ts6_gui_bot_root_volume_size_gb" {
  description = "Root volume size for the TS6 GUI client bot host."
  type        = number
  default     = 20
}

variable "ts6_gui_bot_client_download_url" {
  description = "Official TeamSpeak 6 Linux client tarball URL. Update when TS6 beta/stable changes."
  type        = string
  default     = "https://files.teamspeak-services.com/pre_releases/client/6.0.0-beta4/teamspeak-client.tar.gz"
}

variable "ts6_gui_bot_client_sha256" {
  description = "Optional SHA256 checksum for the TS6 Linux client tarball. Leave empty to skip checksum validation."
  type        = string
  default     = "b433040815a6878409cf255dbe59105bb32abbc327e898c5897309252e3911f8"
}

variable "ts6_gui_bot_display" {
  description = "X11 display used by the virtual GUI bot desktop."
  type        = string
  default     = ":99"
}

variable "ts6_gui_bot_screen_geometry" {
  description = "Virtual screen geometry for the GUI bot desktop."
  type        = string
  default     = "1280x800x24"
}

variable "enable_ts6_gui_bot_vnc" {
  description = "Run x11vnc bound to localhost on the GUI bot host for inspection over an SSH tunnel. No VNC port is opened publicly."
  type        = bool
  default     = true
}

variable "ts6_gui_bot_vnc_port" {
  description = "Localhost-only VNC port on the GUI bot host. Use SSH tunneling to access it."
  type        = number
  default     = 5900
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
