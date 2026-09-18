resource "aws_instance" "zabbix" {
  ami                         = var.zabbix_ami_id
  instance_type               = var.zabbix_instance_type
  availability_zone           = var.availability_zone
  subnet_id                   = aws_subnet.zabbix.id
  private_ip                  = var.zabbix_private_ip
  associate_public_ip_address = true
  source_dest_check           = true
  vpc_security_group_ids      = [aws_security_group.zabbix.id]
  iam_instance_profile        = aws_iam_instance_profile.zabbix.name

  user_data = templatefile("${path.module}/templates/ssm-bootstrap.sh.tftpl", {
    aws_region = var.aws_region
  })

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.zabbix_root_volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125

    tags = {
      Name = "zabbix-root"
    }
  }

  lifecycle {
    precondition {
      condition     = data.aws_ami.zabbix_pinned.architecture == "arm64"
      error_message = "The selected Debian AMI is not ARM64 and cannot be used with t4g.small."
    }

    precondition {
      condition     = data.aws_ami.zabbix_pinned.owner_id == "123456789012"
      error_message = "The selected Debian AMI is not owned by the official Debian AWS publisher."
    }
  }

  tags = {
    Name    = "zabbix-server"
    Service = "Zabbix"
  }

  depends_on = [
    aws_iam_role_policy_attachment.zabbix_ssm_core,
    aws_route.monitoring_to_internet,
    aws_route_table_association.zabbix,
  ]
}
