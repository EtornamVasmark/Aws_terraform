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
  default = "us-west-2"
}

variable "instance_type" {
  default = "t3.micro"
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
# SECURITY GROUP FOR WORDPRESS INSTANCE
# -------------------------------------------
resource "aws_security_group" "web_sg" {
  name        = "wordpress-sg"
  description = "Allow HTTP and SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
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
    Name = "wordpress-web-sg"
  }
}

# -------------------------------------------
# EC2 INSTANCE WITH WORDPRESS & LOCAL DATABASE
# -------------------------------------------
resource "aws_instance" "wordpress" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = var.key_name

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras enable php8.0
              yum clean metadata
              yum install -y php php-mysqlnd httpd mariadb-server wget unzip
              
              systemctl start httpd
              systemctl enable httpd
              systemctl start mariadb
              systemctl enable mariadb
              
              # Set root password and secure MySQL
              mysql -e "CREATE DATABASE wordpress;"
              mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'password';"
              mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
              mysql -e "FLUSH PRIVILEGES;"

              # Install WordPress
              cd /var/www/html
              wget https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz
              cp -r wordpress/* .
              rm -rf wordpress latest.tar.gz

              cp wp-config-sample.php wp-config.php
              sed -i "s/database_name_here/wordpress/" wp-config.php
              sed -i "s/username_here/wpuser/" wp-config.php
              sed -i "s/password_here/password/" wp-config.php

              chown -R apache:apache /var/www/html/*
              chmod -R 755 /var/www/html/
              
              systemctl restart httpd
              systemctl restart mariadb

              # Create PHP info page for debugging
              echo "<?php phpinfo(); ?>" > /var/www/html/info.php
              EOF

  tags = {
    Name = "wordpress-server"
  }
}



# -------------------------------------------
# GET LATEST AMAZON LINUX 2 AMI
# -------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -------------------------------------------
# OUTPUT VALUES
# -------------------------------------------
output "wordpress_public_ip" {
  description = "Public IP address of the WordPress instance"
  value       = aws_instance.wordpress.public_ip
}

output "wordpress_url" {
  description = "URL to access the WordPress site"
  value       = "http://${aws_instance.wordpress.public_ip}"
}



