terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.94.1"
    }
  }
}

# Creating VPC
#resource "aws_vpc" "wordpress-vpc" {
#  cidr_block = "10.0.0.0/24"
#}

# -------------------------------------------
# VARIABLES (optional customization)
# -------------------------------------------
variable "region" {
  default = "eu-north-1"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "key_name" {
  description = "Name of your existing EC2 key pair"
  default     = "vockey"
}

# -------------------------------------------
# NETWORKING: VPC, SUBNET, IGW, ROUTE TABLE
# -------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "wordpress-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "wordpress-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags = { Name = "wordpress-public-subnet" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "wordpress-public-rt" }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

