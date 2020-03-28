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

resource "aws_subnet" "public-subnet-1" {
    vpc_id = aws_vpc.primary-vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "${var.aws_region}a"
    map_public_ip_on_launch = true
    depends_on = [aws_internet_gateway.igw]

    tags = {
        Name = "k8s-public-subnet-1-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_subnet" "public-subnet-2" {
    vpc_id = aws_vpc.primary-vpc.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "${var.aws_region}b"
    map_public_ip_on_launch = true
    depends_on = [aws_internet_gateway.igw]

    tags = {
        Name = "k8s-public-subnet-2-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_subnet" "public-subnet-3" {
    vpc_id = aws_vpc.primary-vpc.id
    cidr_block = "10.0.3.0/24"
    availability_zone = "${var.aws_region}c"
    map_public_ip_on_launch = true
    depends_on = [aws_internet_gateway.igw]

    tags = {
        Name = "k8s-private-subnet-1-${var.unit_prefix}"
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
    subnet_id       = aws_subnet.public-subnet.id
    depends_on      = [aws_internet_gateway.igw, aws_subnet.public-subnet]

    tags = {
        Name = "k8s-natgw-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_route_table" "natgw-route" {
    vpc_id = aws_vpc.primary-vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.natgw.id
    }

    tags = {
        Name = "k8s-natgw-route-${var.unit_prefix}"
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_route_table_association" "route-out" {
    subnet_id = aws_subnet.private-subnet.id
    route_table_id = aws_route_table.natgw-route.id
}

