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

# -------------------------------------------
# EC2 INSTANCE FOR WORDPRESS
# -------------------------------------------
resource "aws_instance" "wordpress" {
  ami                    = data.aws_ami.amazon_linux.id # Use the data source for latest Amazon Linux 2 AMI
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              # Update system packages
              yum update -y
              amazon-linux-extras enable php8.0
              yum clean metadata
              yum install -y php php-mysqlnd httpd mariadb-server mariadb wget unzip

              # Start and enable Apache web server
              systemctl start httpd
              systemctl enable httpd

              # Start and enable MariaDB database server
              systemctl start mariadb
              systemctl enable mariadb

              # Create WordPress database and user
              mysql -e "CREATE DATABASE wordpress;"
              mysql -e "CREATE USER 'admin'@'localhost' IDENTIFIED BY 'password';"
              mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'admin'@'localhost';"
              mysql -e "FLUSH PRIVILEGES;"

              # Download and set up WordPress
              cd /var/www/html
              wget https://wordpress.org/latest.zip
              unzip latest.zip
              cp -r wordpress/* .
              rm -rf wordpress latest.zip

              # Set proper permissions
              chown -R apache:apache /var/www/html
              chmod -R 755 /var/www/html

              # Create wp-config with database credentials
              cp wp-config-sample.php wp-config.php
              sed -i "s/database_name_here/wordpress/" wp-config.php
              sed -i "s/username_here/admin/" wp-config.php
              sed -i "s/password_here/password/" wp-config.php
              sed -i "s/localhost/localhost/" wp-config.php

              # Generate WordPress salts for security
              SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
              sed -i "/define( 'AUTH_KEY'/,/define( 'NONCE_SALT'/d" wp-config.php
              printf '%s\n' "$SALTS" >> wp-config.php

              # Restart Apache
              systemctl restart httpd
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



