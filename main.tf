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
# EC2 INSTANCE WITH WORDPRESS & LOCAL DATABASE
# -------------------------------------------
resource "aws_instance" "wordpress" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI for us-west-2
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = var.key_name
  security_groups = [aws_security_group.web_sg.name]

  associate_public_ip_address = true

  user_data = <<-EOF
     #!/bin/bash
    yum update -y

    # Enable 1GB swap memory
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

    # Install Apache, PHP, MariaDB
    yum install -y httpd php php-mysqlnd mariadb-server wget unzip

    # Start services
    systemctl start httpd
    systemctl enable httpd
    systemctl start mariadb
    systemctl enable mariadb

    # Configure Apache for performance
    echo "KeepAlive On" >> /etc/httpd/conf/httpd.conf
    echo "MaxKeepAliveRequests 100" >> /etc/httpd/conf/httpd.conf
    echo "KeepAliveTimeout 5" >> /etc/httpd/conf/httpd.conf
    echo 'AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css application/javascript' >> /etc/httpd/conf/httpd.conf

    # Configure MariaDB for performance
    cat <<EOT >> /etc/my.cnf.d/server.cnf
    [mysqld]
    innodb_buffer_pool_size=256M
    max_connections=50
    query_cache_type=1
    query_cache_size=64M
    EOT

    systemctl restart mariadb

    # Setup MySQL DB for WordPress
    mysql -e "CREATE DATABASE wordpress;"
    mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'password';"
    mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    # Download and install WordPress
    cd /var/www/html
    wget https://wordpress.org/latest.zip
    unzip latest.zip
    cp -r wordpress/* .
    rm -rf wordpress latest.zip
    cp wp-config-sample.php wp-config.php

    # Configure wp-config
    sed -i "s/database_name_here/wordpress/" wp-config.php
    sed -i "s/username_here/wpuser/" wp-config.php
    sed -i "s/password_here/password/" wp-config.php
    echo "define('DISABLE_WP_CRON', true);" >> wp-config.php

    # Set permissions
    chown -R apache:apache /var/www/html
    chmod -R 755 /var/www/html

    # Install LiteSpeed Cache plugin
    mkdir -p wp-content/plugins
    wget https://downloads.wordpress.org/plugin/litespeed-cache.latest-stable.zip
    unzip litespeed-cache.latest-stable.zip -d wp-content/plugins
    rm litespeed-cache.latest-stable.zip

    systemctl restart httpd
  EOF

  tags = {
    Name = "wordpress-instance"
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



