# Creating a security group for the Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Security group for Application Load Balancer"

  vpc_id = module.vpc.vpc_id

  // Define your security group rules here for ALB
  ingress {
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

# Creating an Application Load Balancer
resource "aws_lb" "ecs_lb" {
  name               = "ecs-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

# Creating a listener for the ALB
resource "aws_lb_listener" "ecs_lb_listener" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
  }
}

# Creating a target group for the ECS service
resource "aws_lb_target_group" "ecs_target_group" {
  name        = "ecs-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs_security_group"
  description = "Security group for ECS service"
  vpc_id = module.vpc.vpc_id
  
  # Define your security group rules here
  ingress {
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

# Creating an ECS cluster
resource "aws_ecs_cluster" "cluster" {
  name = "cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Creating an ECS task definition
resource "aws_ecs_task_definition" "task" {
  family                   = "service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE", "EC2"]
  cpu                      = 512
  memory                   = 2048

  container_definitions = jsonencode([
    {
      name: "nginx",
      image: "nginx:1.23.1", # 767397894475.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
      cpu: 512,
      memory: 2048,
      essential: true,
      portMappings: [
        {
          containerPort: 80,
          hostPort: 80,
        },
      ],
    },
  ])
}

# Creating an ECS service
resource "aws_ecs_service" "service" {
  name             = "service"
  cluster          = aws_ecs_cluster.cluster.id
  task_definition  = aws_ecs_task_definition.task.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
    container_name   = "nginx"
    container_port   = 80
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs_sg.id]
    #subnets          = [aws_subnet.subnet.id]

    subnets = module.vpc.public_subnets
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}