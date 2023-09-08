terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

data "aws_instance" "source" {
  instance_id = var.instance_id
}

resource "aws_ami_from_instance" "ami" {
  name               = "ami-copy-${var.instance_id}"
  source_instance_id = var.instance_id
}

resource "aws_instance" "copy" {
  ami = aws_ami_from_instance.ami.id

  instance_type = data.aws_instance.source.instance_type
  key_name      = data.aws_instance.source.key_name

  security_groups = data.aws_instance.source.security_groups
  subnet_id       = data.aws_instance.source.subnet_id

  tags = {
    Name = "copy-${data.aws_instance.source.id}"
  }
}

locals {
  sql_downgrader = templatefile(
    "${path.module}/assets/sql-downgrade.ps1",
    {
      sql_sa_user = var.sql_sa_user,
      sql_sa_password = var.sql_sa_password,
      sql_installation_folder = var.sql_installation_folder,
      sql_source_edition = var.sql_source_edition
    }
  )
}

resource "aws_ssm_document" "downgrade_sql" {
  name          = "downgrade-sql"
  document_type = "Command"
  content = jsonencode(
    {
      schemaVersion = "2.2",
      description   = "Downgrade SQL Enterprise to SQL Enterprise / Developer",
      mainSteps = [
        {
          action = "aws:runPowerShellScript",
          name   = "downgradeSQL",
          inputs = {
            runCommand = [
              "${local.sql_downgrader}",
            ]
          }
        },
      ]
    }
  )
}

resource "aws_ssm_association" "downgrade_sql" {
  name = aws_ssm_document.downgrade_sql.name
  targets {
    key    = "InstanceIds"
    values = [aws_instance.copy.id]
  }
}
