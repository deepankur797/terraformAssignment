     terraform {
       backend "remote" {
         # The name of your Terraform Cloud organization.
         organization = "dsb-enterprise"

         # The name of the Terraform Cloud workspace to store Terraform state files in.
         workspaces {
           name = "TetrisAwsInfra"
         }
       }
     }

resource "aws_launch_configuration" "TetrisLC" {
  name_prefix = "tetris-"

  image_id = "ami-0a91cd140a1fc148a"
  instance_type = "t2.micro"
  key_name = "Deepankur_Key"

  security_groups = [ "sg-0cb3d8bd6dbb30f22" ]
  associate_public_ip_address = true

  user_data = <<USER_DATA
#!/bin/bash
sudo apt-get update -y
sleep 60
sudo apt-get install apache2 -y
sleep 60
sudo git clone https://github.com/deepankur797/tetris.git
sudo cp /var/www/html/index.html /var/www/html/index.html.bkp
cd tetris
sudo cp -r ./ /var/www/html/
cd ..
sudo rm -rf tetris
  USER_DATA

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_security_group" "elb_http" {
  name        = "elb_http"
  description = "Allow HTTP traffic to instances through Elastic Load Balancer"
  vpc_id = "vpc-f856e193"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP through ELB Security Group"
  }
}


resource "aws_elb" "tetris_elb" {
  name = "tetris-elb"
  security_groups = [
    aws_security_group.elb_http.id
  ]
  subnets = [
    "subnet-4d766237",
    "subnet-65459a0e",
    "subnet-e04a36ac"
  ]

  cross_zone_load_balancing   = true

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }

}


resource "aws_autoscaling_group" "tetrisGroup" {
  name = "${aws_launch_configuration.TetrisLC.name}-asg"

  min_size             = 1
  desired_capacity     = 2
  max_size             = 4

  health_check_type    = "ELB"
  load_balancers = [
    aws_elb.tetris_elb.id
  ]

  launch_configuration = aws_launch_configuration.TetrisLC.name

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  vpc_zone_identifier  = [
    "subnet-4d766237",
    "subnet-65459a0e",
    "subnet-e04a36ac"
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "tetris"
    propagate_at_launch = true
  }

}

resource "aws_autoscaling_policy" "tetris_policy_up" {
  name = "tetris_policy_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.tetrisGroup.name
}


resource "aws_cloudwatch_metric_alarm" "tetris_cpu_alarm_up" {
  alarm_name = "tetris_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "60"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.tetrisGroup.name
  }

  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.tetris_policy_up.arn ]
}

resource "aws_autoscaling_policy" "tetris_policy_down" {
  name = "tetris_policy_down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.tetrisGroup.name
}

resource "aws_cloudwatch_metric_alarm" "tetris_cpu_alarm_down" {
  alarm_name = "tetris_cpu_alarm_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "10"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.tetrisGroup.name
  }

  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.tetris_policy_down.arn ]
}


output "elb_dns_name" {
  value = aws_elb.tetris_elb.dns_name
}
