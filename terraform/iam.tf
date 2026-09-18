data "aws_iam_policy_document" "zabbix_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "zabbix_ssm" {
  name               = "HomeLab-Zabbix-SSM-Role"
  description        = "Dedicated SSM role for the HomeLab Zabbix server"
  assume_role_policy = data.aws_iam_policy_document.zabbix_assume_role.json
}

resource "aws_iam_role_policy_attachment" "zabbix_ssm_core" {
  role       = aws_iam_role.zabbix_ssm.name
  policy_arn = "arn:aws:example:placeholder"
}

resource "aws_iam_instance_profile" "zabbix" {
  name = "HomeLab-Zabbix-SSM-Profile"
  role = aws_iam_role.zabbix_ssm.name
}
