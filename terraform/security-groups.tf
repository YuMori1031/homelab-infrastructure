locals {
  homelab_site_cidrs = {
    site_a        = "10.10.1.0/24"
    site_b        = "10.10.2.0/24"
    remote_access = "10.10.255.0/24"
  }

  monitored_cidrs = merge(local.homelab_site_cidrs, {
    vpn_server = "${var.vpn_private_ip}/32"
  })

  zabbix_admin_icmp_cidrs = {
    site_a        = local.homelab_site_cidrs.site_a
    remote_access = local.homelab_site_cidrs.remote_access
  }
}

resource "aws_security_group" "zabbix" {
  name_prefix            = "zabbix-"
  description            = "Least-privilege security group for the Zabbix server"
  vpc_id                 = data.aws_vpc.homelab.id
  revoke_rules_on_delete = true

  tags = {
    Name = "zabbix-sg"
  }
}


resource "aws_vpc_security_group_ingress_rule" "frontend_https" {
  for_each = local.homelab_site_cidrs

  security_group_id = aws_security_group.zabbix.id
  description       = "HTTPS frontend from ${each.key}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "admin_icmp" {
  for_each = local.zabbix_admin_icmp_cidrs

  security_group_id = aws_security_group.zabbix.id
  description       = "ICMP Echo Request to Zabbix from ${each.key}"
  cidr_ipv4         = each.value
  from_port         = 8
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_vpc_security_group_ingress_rule" "homelab_admin_ssh" {
  security_group_id = aws_security_group.zabbix.id
  description       = "Management SSH from HomeLab"
  cidr_ipv4         = "10.10.0.0/16"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "homelab_admin_icmp" {
  security_group_id = aws_security_group.zabbix.id
  description       = "IPv4 ICMP from HomeLab"
  cidr_ipv4         = "10.10.0.0/16"
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_vpc_security_group_ingress_rule" "production_vpn_active_agent" {
  security_group_id = aws_security_group.zabbix.id
  description       = "Zabbix Agent 2 active checks from Production VPN Server"
  cidr_ipv4         = "${var.vpn_private_ip}/32"
  from_port         = 10051
  to_port           = 10051
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "production_vpn_snmp_transit" {
  provider          = aws.production_untagged
  security_group_id = one(data.aws_network_interface.vpn.security_groups)
  description       = "Zabbix SNMP monitoring transit"
  cidr_ipv4         = "${var.zabbix_private_ip}/32"
  from_port         = 161
  to_port           = 161
  ip_protocol       = "udp"

  lifecycle {
    precondition {
      condition     = length(data.aws_network_interface.vpn.security_groups) == 1
      error_message = "The production VPN ENI must have exactly one security group before adding the SNMP transit rule."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "zabbix_trapper" {
  for_each = var.enable_zabbix_trapper_ingress ? local.monitored_cidrs : {}

  security_group_id = aws_security_group.zabbix.id
  description       = "Optional Zabbix active-agent or trapper traffic from ${each.key}"
  cidr_ipv4         = each.value
  from_port         = 10051
  to_port           = 10051
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "https_internet" {
  security_group_id = aws_security_group.zabbix.id
  description       = "HTTPS for SSM, package repositories, updates, and notifications"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.zabbix.id
  description       = "DNS to the VPC Route 53 Resolver"
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.zabbix.id
  description       = "TCP DNS fallback to the VPC Route 53 Resolver"
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ntp" {
  security_group_id = aws_security_group.zabbix.id
  description       = "NTP to the Amazon Time Sync Service"
  cidr_ipv4         = "169.254.169.123/32"
  from_port         = 123
  to_port           = 123
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "icmp_monitoring" {
  for_each = local.monitored_cidrs

  security_group_id = aws_security_group.zabbix.id
  description       = "ICMP monitoring of ${each.key}"
  cidr_ipv4         = each.value
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_vpc_security_group_egress_rule" "snmp_monitoring" {
  for_each = local.homelab_site_cidrs

  security_group_id = aws_security_group.zabbix.id
  description       = "SNMP polling of ${each.key}"
  cidr_ipv4         = each.value
  from_port         = 161
  to_port           = 161
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "agent_monitoring" {
  for_each = local.monitored_cidrs

  security_group_id = aws_security_group.zabbix.id
  description       = "Passive Zabbix agent polling of ${each.key}"
  cidr_ipv4         = each.value
  from_port         = 10050
  to_port           = 10050
  ip_protocol       = "tcp"
}
