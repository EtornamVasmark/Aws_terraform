terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.94.1"
    }
  }
}

# Add your variable declarations here

variable "aws_availability_zone_a" {
  description = "The availability zone for the public subnet 1"
  type        = string
}

# Creating VPC
resource "aws_vpc" "wordpress-vpc" {
  cidr_block = "10.0.0.0/24"
}

# Creating Subnets
# Create Public Subnet 1 in the VPC
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.aws_capstone_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.aws_availability_zone_a
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet1"
  }
}