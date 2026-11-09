# AWS lab for ServerForge: two small Ubuntu 24.04 servers (staging + production)
# in their own VPC. Terraform only creates bare servers; Ansible does everything
# that happens inside them. Created by scripts/aws-up.sh, removed by aws-down.sh.
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {}
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "name" {
  type    = string
  default = "serverforge"
}

variable "admin_cidrs" {
  description = "Who may SSH in (your public IP as x.x.x.x/32). Set by aws-up.sh."
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must list specific addresses - never 0.0.0.0/0 for SSH."
  }
}

variable "ssh_public_key" {
  description = "Public half of .keys/aws_ed25519 (aws-up.sh creates it)."
  type        = string
}

variable "instance_type" {
  description = "t4g.micro: 2 Graviton vCPUs (burstable), 1 GB RAM. Free tier eligible, so it also starts in accounts on the AWS Free plan (t4g.nano does not). Must be a Graviton (arm64) type: the Ubuntu image is arm64."
  type        = string
  default     = "t4g.micro"
}

variable "servers" {
  description = "Server name => Ansible group."
  type        = map(string)
  default = {
    "web-stg-1"  = "staging"
    "web-prod-1" = "production"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "serverforge"
      ManagedBy = "terraform"
      AutoStop  = "true"
      DataClass = "demo"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Canonical publishes the newest Ubuntu image IDs in SSM: no hard-coded AMI IDs.
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

# --- Network ------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.name}-vpc" }
}

# The VPC's default security group allows nothing (nothing should use it).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Firewall at the AWS edge (ufw on the server is the second layer) --------------
resource "aws_security_group" "web" {
  #checkov:skip=CKV_AWS_24:SSH is limited to var.admin_cidrs, whose validation rejects 0.0.0.0/0
  name        = "${var.name}-web"
  description = "SSH from admin IPs only; HTTP/HTTPS from anywhere"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from admin IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }

  ingress {
    description = "HTTP (redirects to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Package updates and Lets Encrypt"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-web" }
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.name}-admin"
  public_key = var.ssh_public_key
}

# --- Servers ------------------------------------------------------------------------
resource "aws_instance" "server" {
  for_each = var.servers

  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.admin.key_name
  ebs_optimized          = true
  monitoring             = false

  # "standard" credits: a runaway process is throttled instead of billed.
  # (t4g defaults to "unlimited", which can add surprise charges.)
  credit_specification {
    cpu_credits = "standard"
  }

  # IMDSv2 only: stolen-credential attacks through SSRF need IMDSv1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = each.key
    Role = each.value
  }

  lifecycle {
    ignore_changes = [ami] # a newer Ubuntu image must not replace a running server
  }
}

output "servers" {
  description = "Name => public IP and Ansible group (aws-up.sh writes the inventory from this)."
  value = {
    for name, s in aws_instance.server : name => {
      ip    = s.public_ip
      group = var.servers[name]
    }
  }
}

output "region" {
  value = var.aws_region
}
