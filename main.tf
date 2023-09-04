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


