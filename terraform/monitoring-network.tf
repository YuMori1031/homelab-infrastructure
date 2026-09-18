resource "aws_subnet" "zabbix" {
  vpc_id                  = data.aws_vpc.homelab.id
  cidr_block              = var.monitoring_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "zabbix-monitoring-subnet"
  }

  lifecycle {
    precondition {
      condition     = var.zabbix_private_ip == cidrhost(var.monitoring_subnet_cidr, 14)
      error_message = "The Zabbix address must be host 14 (10.10.0.254) in the monitoring /28."
    }

    precondition {
      condition     = data.aws_network_interface.vpn.vpc_id == data.aws_vpc.homelab.id
      error_message = "The VPN ENI does not belong to the selected HomeLab VPC."
    }

    precondition {
      condition     = contains(data.aws_network_interface.vpn.private_ips, var.vpn_private_ip)
      error_message = "The VPN ENI does not contain the expected private IPv4 address."
    }

    precondition {
      condition     = data.aws_network_interface.vpn.availability_zone == var.availability_zone
      error_message = "The monitoring subnet and production VPN ENI must remain in the same Availability Zone."
    }
  }
}

resource "aws_route_table" "zabbix" {
  vpc_id = data.aws_vpc.homelab.id

  tags = {
    Name = "zabbix-monitoring-rt"
  }
}

resource "aws_route" "monitoring_to_internet" {
  route_table_id         = aws_route_table.zabbix.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.homelab.id
}

resource "aws_route" "monitoring_to_site_a" {
  # Route Site-to-Site traffic through the current production VPN ENI.
  route_table_id         = aws_route_table.zabbix.id
  destination_cidr_block = "10.10.1.0/24"
  network_interface_id   = data.aws_network_interface.vpn.id
}

resource "aws_route" "monitoring_to_site_b" {
  route_table_id         = aws_route_table.zabbix.id
  destination_cidr_block = "10.10.2.0/24"
  network_interface_id   = data.aws_network_interface.vpn.id
}

resource "aws_route" "monitoring_to_remote_access" {
  route_table_id         = aws_route_table.zabbix.id
  destination_cidr_block = "10.10.255.0/24"
  network_interface_id   = data.aws_network_interface.vpn.id
}

resource "aws_route_table_association" "zabbix" {
  subnet_id      = aws_subnet.zabbix.id
  route_table_id = aws_route_table.zabbix.id
}
