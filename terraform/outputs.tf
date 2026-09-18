output "monitoring_subnet_id" {
  description = "ID of the Zabbix monitoring subnet."
  value       = aws_subnet.zabbix.id
}

output "monitoring_subnet_cidr" {
  description = "CIDR of the Zabbix monitoring subnet."
  value       = aws_subnet.zabbix.cidr_block
}

output "zabbix_private_ip" {
  description = "Fixed private IPv4 address of the Zabbix EC2 instance."
  value       = aws_instance.zabbix.private_ip
}

output "monitoring_route_table_id" {
  description = "ID of the monitoring route table."
  value       = aws_route_table.zabbix.id
}

output "zabbix_security_group_id" {
  description = "ID of the Zabbix security group."
  value       = aws_security_group.zabbix.id
}

output "vpn_route_target_eni_id" {
  description = "VPN ENI currently selected as the HomeLab route target."
  value       = data.aws_network_interface.vpn.id
}

output "zabbix_instance_id" {
  description = "ID of the Zabbix EC2 instance."
  value       = aws_instance.zabbix.id
}

output "zabbix_public_ip" {
  description = "Dynamic public IPv4 address used for outbound-only Internet access."
  value       = aws_instance.zabbix.public_ip
}

output "debian_ami_id" {
  description = "Pinned Debian 13 ARM64 AMI used by the Zabbix EC2 instance."
  value       = var.zabbix_ami_id
}
