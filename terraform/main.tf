data "aws_availability_zones" "available" {}

resource "aws_vpc" "this" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true
    tags = { Name = "${var.project_name}-vpc"}
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.this.id 
    tags = {Name = "${var.project_name}-igw"}
}

resource "aws_subnet" "public_a" {
    vpc_id = aws_vpc.this.id 
    cidr_block = "10.0.1.0/24"
    availability_zone = data.aws_availability_zones.available.names[0]
    map_public_ip_on_launch = true
    tags = {Name = "${var.project_name}-public-a"}
}

resource "aws_subnet" "public_b" {
    vpc_id = aws_vpc.this.id
    cidr_block = "10.0.2.0/24"
    availability_zone = data.aws_availability_zones.available.names[1]
    map_public_ip_on_launch = true
    tags = {Name = "${var.project_name}-public-b"}
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.this.id
    tags = {Name = "${var.project_name}-public-rt"}
}

resource "aws_route" "public_internet" {
    route_table_id = aws_route_table.public.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
    subnet_id = aws_subnet.public_a.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
    subnet_id = aws_subnet.public_b.id
    route_table_id = aws_route_table.public.id
}


resource "aws_ecr_repository" "app" {
    name = "${var.project_name}-repo"
    force_delete = true
}

resource "aws_cloudwatch_log_group" "app" {
    name = "/ecs/${var.project_name}"
    retention_in_days = 7
}


data "aws_iam_policy_document" "ecs_task_assume" {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = ["ecs-tasks.amazonaws.com"]
        }
        actions = ["sts:AssumeRole"]
    }
}

resource "aws_iam_role" "ecs_task_execution" {
    name = "${var.project_name}-ecs-task-exec"
    assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy" {
    role = aws_iam_role.ecs_task_execution.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_security_group" "alb" {
    name = "${var.project_name}-alb-sg"
    description = "ALB SG"
    vpc_id = aws_vpc.this.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "ecs" {
    name = "${var.project_name}-ecs-sg"
    description = "ECS SG"
    vpc_id = aws_vpc.this.id

    ingress {
        from_port = var.container_port
        to_port = var.container_port
        protocol = "tcp"
        security_groups = [aws_security_group.alb.id]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}


resource "aws_lb" "app" {
    name = "${var.project_name}-alb"
    load_balancer_type = "application"
    subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "app" {
    name = "${var.project_name}-tg"
    port = var.container_port
    protocol = "HTTP"
    vpc_id = aws_vpc.this.id
    target_type = "ip"

    health_check {
        path = "/health"
        protocol = "HTTP"
        matcher = "200"
        interval = 15
        timeout = 5
        healthy_threshold = 2
        unhealthy_threshold = 3
    }
}

resource "aws_lb_listener" "app" {
    load_balancer_arn = aws_lb.app.arn
    port = 80
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.app.arn
    }
}


resource "aws_ecs_cluster" "this" {
    name = "${var.project_name}-cluster"
}

resource "aws_ecs_task_definition" "app" {
    family = "${var.project_name}-task"
    requires_compatibilities = ["FARGATE"]
    network_mode =  "awsvpc"
    cpu = "256"
    memory = "512"
    execution_role_arn = aws_iam_role.ecs_task_execution.arn

    container_definitions = jsonencode([
        {
            name = "app-container"
            image = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
            portMappings = [
                {
                    containerPort = var.container_port
                    hostPort = var.container_port
                    protocol = "tcp"
                }
            ]
            logConfiguration = {
                logDriver = "awslogs"
                options = {
                    awslogs-group = aws_cloudwatch_log_group.app.name
                    awslogs-region = var.aws_region
                    awslogs-stream-prefix = "ecs"
                }
            }
        }
    ])
}

resource "aws_ecs_service" "app" {
    name = "${var.project_name}-service"
    cluster = aws_ecs_cluster.this.id
    task_definition = aws_ecs_task_definition.app.arn
    desired_count = 1
    launch_type = "FARGATE"

    network_configuration {
        subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
        security_groups = [aws_security_group.ecs.id]
        assign_public_ip = true
    }

    load_balancer {
        target_group_arn = aws_lb_target_group.app.arn
        container_name = "app-container"
        container_port = var.container_port
    }

    depends_on = [aws_lb_listener.app]
}