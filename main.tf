provider "aws" {
  region = "us-east-1"
}

# Resources #

resource "aws_launch_configuration" "server" {
  image_id        = "ami-0c7217cdde317cfec"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

   # Required when using a launch configuration with an ASG.
  lifecycle {
    create_before_destroy = true
}
}

resource "aws_autoscaling_group" "asg-server" {
  launch_configuration = aws_launch_configuration.server.name
  vpc_zone_identifier  = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.alb-tg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 5

  tag {
    key                 = "Name"
    value               = "terraform-asg-server"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "instance" {
  name = "tf-server1-instance"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb-server" {
  name               = "terraform-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.sg-alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb-server.arn
  port              = 80
  protocol          = "HTTP"

  # Return a simple 404 page by default
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "sg-alb" {
  name = "terraform-sg-alb"
  # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "alb-tg" {
  name     = "terraform-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

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

resource "aws_lb_listener_rule" "l-rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.arn
  }
}

# Data Sources #

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Variables #

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default = 8080
}

# Outputs #

output "alb_dns_name" {
  value       = aws_lb.alb-server.dns_name
  description = "The domain name of the load balancer"
}