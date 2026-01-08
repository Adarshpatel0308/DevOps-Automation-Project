
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "controller_sg" {
  name        = "${var.project}-ansible-controller-sg"
  description = "SG for Ansible controller"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-ansible-controller-sg"
    Project = var.project
  }
}

resource "aws_instance" "controller" {
  ami                         = var.ami_id   # Ubuntu 22.04
  instance_type               = var.instance_type
  subnet_id                   = element(data.aws_subnets.public.ids, 0)
  vpc_security_group_ids      = [aws_security_group.controller_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  tags = {
    Name    = "${var.project}-ansible-controller"
    Project = var.project
    Role    = "ansible-controller"
  }
}
