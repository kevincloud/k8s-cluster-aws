variable "aws_access_key" {
    type = string
    description = "AWS Access Key ID"
}

variable "aws_secret_key" {
    type = string
    description = "AWS Secret Key ID"
}

variable "aws_region" {
    type = string
    description = "AWS Region"
    default = "us-east-1"
}

variable "aws_azs" {
    type = list(string)
    description = "The availability zones to be used for this cluster"
    default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "key_pair" {
    type = string
    description = "Your AWS key pair name"
}

variable "unit_prefix" {
    type = string
    description = "A unique identifier to name each resource"
}

variable "instance_size" {
    type = string
    description = "The instance size to be used for each machine in the cluster"
    default = "t3.small"
}

variable "num_worker_nodes" {
    type = number
    description = "The number of worker nodes to spin up"
    default = 3

    # validation {
    #     condition = var.num_worker_nodes >= 3
    #     error_message = "You must specify a minimum of 3 worker nodes"
    # }
}

variable "owner_email" { }
