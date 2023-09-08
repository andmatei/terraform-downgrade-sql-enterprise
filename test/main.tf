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

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.this.id
}

## Route Tables

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

## Security group

resource "aws_security_group" "this" {
  name   = "${local.prefix}-sg"
  vpc_id = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
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

resource "aws_instance" "this" {
  ami           = data.aws_ami.windows_sql_enterprise.id
  instance_type = "t3.2xlarge"

  security_groups = [aws_security_group.this.id]
  subnet_id       = aws_subnet.public.id

  tags = {
    Name = "${local.prefix}-instance"
  }
}

module "aws_instance_copy" {
  source = "./.."

  instance_id = aws_instance.this.id
}
