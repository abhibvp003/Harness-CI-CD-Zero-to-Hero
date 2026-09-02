terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------
# VPC
# ---------------------------------------------------------

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "harness-demo-vpc"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}
