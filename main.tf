provider "aws" {
    region = "us-east-1"
}

resource "aws_vpc" "lab" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "main"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.lab.id
}

resource "aws_route_table" "lab-routes" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "lab"
  }
}

resource "aws_subnet" "main" {
    vpc_id = aws_vpc.lab.id
    availability_zone = "us-east-1a"
    cidr_block = "10.0.1.0/24"
    tags = {
        Name = "main"
    }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.lab-routes.id
}

resource "aws_security_group" "lab-sg" {
  description = "lab security group"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "lab-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow-hhtps" {
  security_group_id = aws_security_group.lab-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol          = "tcp"
  tags = {
    Name = "allow-https"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow-ssh" {
  security_group_id = aws_security_group.lab-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  tags = {
    Name = "allow-ssh"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.lab-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_instance" "web01" {
  ami           = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "lab-web-ec2"
  vpc_security_group_ids = [aws_security_group.lab-sg.id]
  subnet_id = aws_subnet.main.id

  tags = {
    Name = "WEB01"
  }
}