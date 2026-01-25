variable "aws_region" {
    description =  "AWS region to deploy resources"
    type = string
    default = "us-east-1"
}

variable "project_name" {
    description = "Name of the project"
    type = string
    default = "fastapi-hello-app"
}

variable "image_tag" {
    description = "Docker image tag for the application"
    type = string
    default = "latest"

    validation {
    condition     = length(trim(var.image_tag)) > 0
    error_message = "image_tag cannot be empty"
    }
}

variable "container_port" {
    description = "Port on which the container listens"
    type = number
    default = 8000
}