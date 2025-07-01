provider "aws" {
    region = "us-east-1"
}

resource "aws_vpc" "lab_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "main"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.lab_vpc.id
}

resource "aws_eip" "nat_eip_a" {}
resource "aws_eip" "nat_eip_b" {}

resource "aws_nat_gateway" "nat_gw_a" {
  allocation_id = aws_eip.nat_eip_a.id
  subnet_id     = aws_subnet.lab_public_a.id
}

resource "aws_nat_gateway" "nat_gw_b" {
  allocation_id = aws_eip.nat_eip_b.id
  subnet_id     = aws_subnet.lab_public_b.id
}

resource "aws_route_table" "lab_public_route" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "lab"
  }
}

resource "aws_route_table" "private_rt_a" {
  vpc_id = aws_vpc.lab_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_a.id
  }
}

resource "aws_route_table" "private_rt_b" {
  vpc_id = aws_vpc.lab_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_b.id
  }
}

resource "aws_subnet" "lab_private_a" {
    vpc_id = aws_vpc.lab_vpc.id
    availability_zone = "us-east-1a"
    cidr_block = "10.0.0.0/24"
    
    tags = {
      Name = "lab-private-a"
    }
}

resource "aws_subnet" "lab_private_b" {
    vpc_id = aws_vpc.lab_vpc.id
    availability_zone = "us-east-1b"
    cidr_block = "10.0.1.0/24"
    tags = {
      Name = "lab-private-b"
    }
}

resource "aws_subnet" "lab_public_a" {
    vpc_id = aws_vpc.lab_vpc.id
    availability_zone = "us-east-1a"
    cidr_block = "10.0.2.0/24"
    tags = {
      Name = "lab-public-a"
    }
}

resource "aws_subnet" "lab_public_b" {
    vpc_id = aws_vpc.lab_vpc.id
    availability_zone = "us-east-1b"
    cidr_block = "10.0.3.0/24"
    tags = {
      Name = "lab-public-b"
    }
}

resource "aws_route_table_association" "lab_public_a_association" {
  subnet_id      = aws_subnet.lab_public_a.id
  route_table_id = aws_route_table.lab_public_route.id
}

resource "aws_route_table_association" "lab_public_b_association" {
  subnet_id      = aws_subnet.lab_public_b.id
  route_table_id = aws_route_table.lab_public_route.id
}

resource "aws_route_table_association" "private_a_association" {
  subnet_id      = aws_subnet.lab_private_a.id
  route_table_id = aws_route_table.private_rt_a.id
}

resource "aws_route_table_association" "private_b_association" {
  subnet_id      = aws_subnet.lab_private_b.id
  route_table_id = aws_route_table.private_rt_b.id
}

resource "aws_security_group" "lab_lb_sg" {
  name        = "lab-lb-sg"
  description = "Allow HTTP traffic from internet"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "lab_web_sg" {
  name        = "lab-web-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    description      = "Allow traffic from ALB"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    security_groups  = [aws_security_group.lab_lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#resource "aws_vpc_security_group_ingress_rule" "allow-ssh" {
#  security_group_id = aws_security_group.lab-sg.id
#  cidr_ipv4         = "0.0.0.0/0"
#  from_port         = 22
#  to_port           = 22
#  ip_protocol       = "tcp"
#  tags = {
#    Name = "allow-ssh"
#  }
#}

resource "aws_launch_template" "lab_template" {
  name = "lab-webserver-template"
  image_id           = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"
  key_name = "lab-web-ec2"
  vpc_security_group_ids = [aws_security_group.lab_web_sg.id]

  user_data = <<-EOF
#!/bin/bash
echo "Hello from $(hostname)" > /var/www/html/index.html
yum install -y httpd
systemctl enable httpd
systemctl start httpd
EOF

  lifecycle {
    create_before_destroy = true
  }
  
}

resource aws_autoscaling_group "lab_asg" {
  launch_template {
    id = aws_launch_template.lab_template.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.lab_private_a.id, aws_subnet.lab_private_b.id]
  target_group_arns = [aws_lb_target_group.lab_lb_tg.arn]
  health_check_type = "ELB"


  min_size = 2
  max_size = 5

  tag {
    key = "Name"
    value = "WEB"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "cpu-target-tracking"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.lab_asg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0  # Maintain avg CPU at 50%
  }
}


resource aws_lb "lab_lb" {
  name = "lab-lb"
  load_balancer_type = "application"
  subnets = [aws_subnet.lab_public_a.id, aws_subnet.lab_public_b.id]
  security_groups = [aws_security_group.lab_lb_sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lab_lb.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lab_lb_tg.arn
  }
}

resource "aws_lb_target_group" "lab_lb_tg" {
  name     = "lab-lb-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.lab_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

output "lb_dns_name" {
  value       = aws_lb.lab_lb.dns_name
  description = "The domain name of the load balancer"
}

# terraform {
#   backend "s3" {
#     # Replace this with your bucket name!
#     bucket         = "rileys-terraform-up-and-running-state"
#     key            = "global/s3/terraform.tfstate"
#     region         = "us-east-1"

#     # Replace this with your DynamoDB table name!
#     dynamodb_table = "terraform-up-and-running-locks"
#     encrypt        = true
#   }
# }