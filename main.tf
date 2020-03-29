provider "aws" {
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
    region = var.aws_region
}

resource "aws_vpc" "primary-vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true

    tags = {
        Name = "k8s-vpc-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.primary-vpc.id

    tags = {
        Name = "k8s-igw-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_subnet" "public-subnet" {
    count = length(var.aws_azs)
    vpc_id = aws_vpc.primary-vpc.id
    cidr_block = "10.0.${count.index+1}.0/24"
    availability_zone = element(var.aws_azs, count.index)
    map_public_ip_on_launch = true
    depends_on = [aws_internet_gateway.igw]

    tags = {
        Name = "k8s-public-subnet-${count.index+1}-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_route" "public-routes" {
    route_table_id = aws_vpc.primary-vpc.default_route_table_id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
}

resource "aws_eip" "nat-ip" {
    vpc = true

    tags = {
        Name = "k8s-eip-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_nat_gateway" "natgw" {
    allocation_id   = aws_eip.nat-ip.id
    subnet_id       = aws_subnet.public-subnet[0].id
    depends_on      = [aws_internet_gateway.igw, aws_subnet.public-subnet[0]]

    tags = {
        Name = "k8s-natgw-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_route_table" "igw-route" {
    count = length(var.aws_azs)
    vpc_id = aws_vpc.primary-vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

    tags = {
        Name = "k8s-igw-route-${var.unit_prefix}-${count.index+1}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_route_table_association" "route-out" {
    count = 3
    route_table_id = aws_route_table.igw-route[count.index].id
    subnet_id      = aws_subnet.public-subnet[count.index].id
}

# resource "aws_route_table_association" "route-out" {
#     count = length(var.aws_azs) - 1
#     subnet_id = aws_subnet.public-subnet[count.index+1].id
#     route_table_id = aws_route_table.natgw-route.id
# }

