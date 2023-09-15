terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

## VPC

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.prefix}-vpc"
  }
}

## Public Subnet

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  availability_zone       = "us-east-1a"
  cidr_block              = "10.0.32.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.prefix}-public-subnet"
  }
}

## Internet Gateway

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

## Route Tables

resource "aws_default_route_table" "public" {
  default_route_table_id = aws_vpc.this.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_default_route_table.public.id
}

## Security group

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Profiles
resource "aws_iam_role" "this" {
  name = "sql-downgrade-test-role"
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

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "sql-downgrade-test-role-profile"
  role = aws_iam_role.this.name
}

## SQL Enterprise EC2 Instance

data "aws_ami" "windows_sql_enterprise" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-*-English-Full-SQL_*_Enterprise-*"]
  }
}

resource "aws_instance" "sql_enterprise" {
  ami                  = data.aws_ami.windows_sql_enterprise.id
  instance_type        = "t3.2xlarge"
  iam_instance_profile = aws_iam_instance_profile.this.name

  security_groups = [aws_default_security_group.this.id]
  subnet_id       = aws_subnet.public.id

  tags = {
    Name = "${local.prefix}-instance"
  }
}

module "instance_sql_standard" {
  source = "./.."

  instance_id = aws_instance.sql_enterprise.id
}
