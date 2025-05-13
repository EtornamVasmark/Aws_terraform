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

# -------------------------------------------
# SECURITY GROUP
# -------------------------------------------
resource "aws_security_group" "web_sg" {
  name        = "wordpress-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

  tags = { Name = "wordpress-web-sg" }
}

# EC2 Instance (Amazon Linux)
resource "aws_instance" "wordpress_instance" {
  ami                         = "ami-0cbd40f694b804622" # ✅ Amazon Linux 2023 AMI for eu-north-1
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.wordpress_sg.id]
  associate_public_ip_address = true
  key_name                    = "your-keypair-name" # ✅ Replace with your EC2 key pair name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras enable php8.2
              yum clean metadata
              yum install -y httpd php php-mysqlnd php-fpm mariadb
              systemctl enable httpd
              systemctl start httpd
              cd /var/www/html
              wget https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz
              cp -r wordpress/* .
              chown -R apache:apache /var/www/html
              chmod -R 755 /var/www/html
              EOF

  tags = {
    Name = "wordpress-instance"
  }
}