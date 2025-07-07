provider "aws" {
    region = "us-east-2"
}

# 1. Create a new VPC
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags = { Name = "team1-vpc" }
}

# 2. Create 2 public subnets
resource "aws_subnet" "public_a" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.1.0/24"
    availability_zone       = "us-east-2a"
    map_public_ip_on_launch = true
    tags = { Name = "team1-subnet-a" }
}

resource "aws_subnet" "public_b" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.2.0/24"
    availability_zone       = "us-east-2b"
    map_public_ip_on_launch = true
    tags = { Name = "team1-subnet-b" }
}

# 3. Create an Internet Gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.main.id
    tags = { Name = "team1-igw" }
}

# 4. Create a public route table
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
    tags = { Name = "team1-rt" }
}

# 5. Add route to IGW
resource "aws_route" "internet_access" {
    route_table_id         = aws_route_table.public.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id             = aws_internet_gateway.gw.id
}

# 6. Associate subnets with route table
resource "aws_route_table_association" "public_a" {
    subnet_id      = aws_subnet.public_a.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
    subnet_id      = aws_subnet.public_b.id
    route_table_id = aws_route_table.public.id
}

# 7. Create 2 Target Groups
resource "aws_lb_target_group" "app1" {
    name     = "app1-tg"
    port     = 80
    protocol = "HTTP"
    vpc_id   = aws_vpc.main.id
    health_check {
        path = "/"
        protocol = "HTTP"
    }
}

resource "aws_lb_target_group" "app2" {
    name     = "app2-tg"
    port     = 80
    protocol = "HTTP"
    vpc_id   = aws_vpc.main.id
    health_check {
        path = "/"
        protocol = "HTTP"
    }
}

# 8. Create Application Load Balancer
resource "aws_lb" "app" {
    name               = "app-alb"
    internal           = false
    load_balancer_type = "application"
    security_groups    = []
    subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    tags = { Name = "app-alb" }
}

# 9. Create ALB Listener
resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.app.arn
    port              = "80"
    protocol          = "HTTP"
    default_action {
        type = "fixed-response"
        fixed_response {
            content_type = "text/plain"
            message_body = "Not Found"
            status_code  = "404"
        }
    }
}

# 10. Listener Rules for /path1/* and /path2/*
resource "aws_lb_listener_rule" "app1" {
    listener_arn = aws_lb_listener.http.arn
    priority     = 10
    action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.app1.arn
    }
    condition {
        path_pattern {
            values = ["/path1/*"]
        }
    }
}

resource "aws_lb_listener_rule" "app2" {
    listener_arn = aws_lb_listener.http.arn
    priority     = 20
    action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.app2.arn
    }
    condition {
        path_pattern {
            values = ["/path2/*"]
        }
    }
}

# 11. Launch Templates
data "aws_ami" "amazon_linux" {
    most_recent = true
    owners      = ["amazon"]
    filter {
        name   = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

resource "aws_launch_template" "app1" {
    name_prefix   = "app1-lt-"
    image_id      = data.aws_ami.amazon_linux.id
    instance_type = "t2.micro"
    user_data     = base64encode(<<EOF
#!/bin/bash
sudo amazon-linux-extras install epel -y
sudo yum install stress -y
stress --cpu 2 --timeout 30000
yum install -y htop
echo "Hello from App1" > /var/www/html/index.html
yum install -y httpd
systemctl start httpd
systemctl enable httpd
EOF
    )
}

resource "aws_launch_template" "app2" {
    name_prefix   = "app2-lt-"
    image_id      = data.aws_ami.amazon_linux.id
    instance_type = "t2.micro"
    user_data     = base64encode(<<EOF
#!/bin/bash
sudo amazon-linux-extras install epel -y
sudo yum install stress -y
stress --cpu 2 --timeout 30000
yum install -y htop git
# Simulate CI/CD deploy
cd /home/ec2-user
git clone https://github.com/example/repo.git
cd repo
./deploy.sh
yum install -y httpd
systemctl start httpd
systemctl enable httpd
EOF
    )
}

# 12. Autoscaling Groups
resource "aws_autoscaling_group" "app1" {
    name                      = "asg-app1"
    max_size                  = 3
    min_size                  = 1
    desired_capacity          = 1
    vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    launch_template {
        id      = aws_launch_template.app1.id
        version = "$Latest"
    }
    target_group_arns         = [aws_lb_target_group.app1.arn]
    health_check_type         = "EC2"
    health_check_grace_period = 300
    tag {
        key                 = "Name"
        value               = "app1-instance"
        propagate_at_launch = true
    }
}

resource "aws_autoscaling_group" "app2" {
    name                      = "asg-app2"
    max_size                  = 3
    min_size                  = 1
    desired_capacity          = 1
    vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    launch_template {
        id      = aws_launch_template.app2.id
        version = "$Latest"
    }
    target_group_arns         = [aws_lb_target_group.app2.arn]
    health_check_type         = "EC2"
    health_check_grace_period = 300
    tag {
        key                 = "Name"
        value               = "app2-instance"
        propagate_at_launch = true
    }
}

# 13. Autoscaling Policy for Testing (scale out on CPU > 50%)
resource "aws_autoscaling_policy" "scale_out_app1" {
    name                   = "scale-out-app1"
    autoscaling_group_name = aws_autoscaling_group.app1.name
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = 1
    cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_out_app2" {
    name                   = "scale-out-app2"
    autoscaling_group_name = aws_autoscaling_group.app2.name
    adjustment_type        = "ChangeInCapacity"
    scaling_adjustment     = 1
    cooldown               = 300
}