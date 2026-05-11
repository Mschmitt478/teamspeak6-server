output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.teamspeak.id
}

output "public_ip" {
  description = "Elastic public IP for the TeamSpeak server."
  value       = aws_eip.teamspeak.public_ip
}

output "teamspeak_address" {
  description = "Address users should connect to."
  value       = var.dns_name != null ? var.dns_name : aws_eip.teamspeak.public_ip
}

output "ssh_command" {
  description = "SSH command, if you configured an EC2 key pair."
  value       = var.ssh_key_name == null ? null : "ssh ubuntu@${aws_eip.teamspeak.public_ip}"
}

output "data_volume_id" {
  description = "Persistent EBS volume ID containing TeamSpeak data."
  value       = aws_ebs_volume.teamspeak_data.id
}

output "snapshot_policy_id" {
  description = "AWS DLM snapshot policy ID, if daily snapshots are enabled."
  value       = var.enable_ebs_snapshots ? aws_dlm_lifecycle_policy.teamspeak_data[0].id : null
}
