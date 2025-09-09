
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }

  required_version = ">= 1.0.0"

  backend "s3" {
    bucket         = "devops-tfstate-hu1"
    key            = "devlake/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "devlake_vpc" {
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = "devlake-vpc"
  }
}

resource "aws_internet_gateway" "devlake_igw" {
  vpc_id = aws_vpc.devlake_vpc.id
}

resource "aws_subnet" "devlake_public_1" {
  vpc_id                  = aws_vpc.devlake_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "devlake-public-subnet-1"
  }
}

resource "aws_subnet" "devlake_public_2" {
  vpc_id                  = aws_vpc.devlake_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "devlake-public-subnet-2"
  }
}

resource "aws_route_table" "devlake_public_rt" {
  vpc_id = aws_vpc.devlake_vpc.id
}

resource "aws_route" "devlake_internet_access" {
  route_table_id         = aws_route_table.devlake_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.devlake_igw.id
}

resource "aws_route_table_association" "devlake_public_1_assoc" {
  subnet_id      = aws_subnet.devlake_public_1.id
  route_table_id = aws_route_table.devlake_public_rt.id
}

resource "aws_route_table_association" "devlake_public_2_assoc" {
  subnet_id      = aws_subnet.devlake_public_2.id
  route_table_id = aws_route_table.devlake_public_rt.id
}

resource "aws_security_group" "devlake_sg" {
  name        = "devlake-sg"
  description = "Allow HTTP, SSH, and DevLake ports"
  vpc_id      = aws_vpc.devlake_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "DevLake UI"
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "DevLake API"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3002
    to_port     = 3002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "devlake_ec2" {
  ami                         = "ami-0861f4e788f5069dd"
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.devlake_public_1.id
  vpc_security_group_ids      = [aws_security_group.devlake_sg.id]
  key_name                    = "test-keypair"
  associate_public_ip_address = true

  tags = {
    Name = "devlake-ec2-ubuntu"
  }
}

resource "null_resource" "devlake_setup" {
  depends_on = [aws_instance.devlake_ec2]

  connection {
    type        = "ssh"
    host        = aws_instance.devlake_ec2.public_ip
    user        = "ec2-user"
    private_key = file("test-keypair.pem")
  }

  provisioner "remote-exec" {
  inline = [
  "sudo dnf update -y",
  "sudo dnf install -y docker",
  "sudo curl -L \"https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
  "sudo chmod +x /usr/local/bin/docker-compose",
  "sudo systemctl enable docker",
  "sudo systemctl start docker",
  "sudo usermod -aG docker ec2-user",
  "mkdir -p ~/devlake",
  "cd ~/devlake",
  "sudo docker-compose -f docker-compose-dev.yml --env-file .env up -d"
]
  }
}

resource "aws_lb" "devlake_alb" {
  name               = "devlake-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.devlake_sg.id]
  subnets            = [aws_subnet.devlake_public_1.id, aws_subnet.devlake_public_2.id]

  tags = {
    Name = "devlake-alb"
  }
}

resource "aws_lb_target_group" "devlake_tg" {
  name     = "devlake-tg"
  port     = 4000
  protocol = "HTTP"
  vpc_id   = aws_vpc.devlake_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "devlake_listener" {
  load_balancer_arn = aws_lb.devlake_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.devlake_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "devlake_ec2_attach" {
  target_group_arn = aws_lb_target_group.devlake_tg.arn
  target_id        = aws_instance.devlake_ec2.id
  port             = 4000
}
