terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# locals {
#   has_instance_profile = data.aws_instance.source.iam_instance_profile != null
#   has_role = local.has_instance_profile ? data.aws_iam_instance_profile.source[0].role_name != null : false
# }

data "aws_instance" "source" {
  instance_id = var.instance_id
}

# data "aws_iam_instance_profile" "source" {
#   count = local.has_instance_profile ? 1 : 0
#   name = data.aws_instance.source.iam_instance_profile
# }

# data "aws_iam_role" "source" {
#   count = local.has_role ? 1 : 0
#   name = data.aws_iam_instance_profile.source[0].role_name
# }

resource "aws_iam_instance_profile" "this" {
  # count = local.has_instance_profile ? 0 : 1

  name = "sql-downgrade-ssm-profile"
  role = aws_iam_role.this.name
}

resource "aws_iam_role" "this" {
  # count = local.has_role ? 0 : 1

  name = "sql-downgrade-ssm-role"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Principal = {
            Service = "ec2.amazonaws.com"
          },
          Action = "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "ssm_role" {
  role       =  aws_iam_role.this.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_ami_from_instance" "source" {
  name               = "ami-copy-${var.instance_id}"
  source_instance_id = var.instance_id
}

resource "aws_instance" "copy" {
  count = var.inplace_downgrade ? 0 : 1

  ami = aws_ami_from_instance.source.id

  iam_instance_profile = aws_iam_instance_profile.this.name
  instance_type        = data.aws_instance.source.instance_type
  key_name             = data.aws_instance.source.key_name

  security_groups = data.aws_instance.source.security_groups
  subnet_id       = data.aws_instance.source.subnet_id

  user_data = local.sql_downgrader

  tags = {
    Name = "copy-${data.aws_instance.source.id}"
  }
}

locals {
  sql_downgrader = templatefile(
    "${path.module}/assets/sql-downgrade.ps1",
    {
      sql_sa_user             = var.sql_sa_user,
      sql_sa_password         = var.sql_sa_password,
      sql_installation_folder = var.sql_installation_folder,
      sql_source_edition      = var.sql_source_edition
    }
  )
}

resource "aws_ssm_document" "downgrade_sql" {
  name          = "downgrade-sql"
  document_type = "Command"
  content = jsonencode(
    {
      schemaVersion = "2.2",
      description   = "Downgrade SQL Enterprise to SQL Standard",
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
    values = [var.inplace_downgrade ? data.aws_instance.source.id : aws_instance.copy[0].id]
  }
}
