resource "aws_ssm_document" "zabbix_phase1_connectivity_check" {
  name            = "HomeLab-Zabbix-Phase1-ConnectivityCheck"
  document_type   = "Command"
  document_format = "JSON"
  content         = file("${path.module}/documents/HomeLab-Zabbix-Phase1-ConnectivityCheck.json")

  tags = {
    Purpose = "Phase1ConnectivityValidation"
  }
}

resource "aws_ssm_document" "zabbix_phase2_package_preparation" {
  name            = "HomeLab-Zabbix-Phase2-PackagePreparation"
  document_type   = "Command"
  document_format = "JSON"
  content         = file("${path.module}/documents/HomeLab-Zabbix-Phase2-PackagePreparation.json")

  tags = {
    Purpose = "Phase2PackagePreparation"
  }
}

resource "aws_ssm_document" "zabbix_phase2_configuration" {
  name            = "HomeLab-Zabbix-Phase2-Configuration"
  document_type   = "Command"
  document_format = "JSON"
  content         = file("${path.module}/documents/HomeLab-Zabbix-Phase2-Configuration.json")

  tags = {
    Purpose = "Phase2Configuration"
  }
}
