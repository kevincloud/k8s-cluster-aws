resource "aws_instance" "k8s-master" {
    ami = data.aws_ami.ubuntu.id
    instance_type = var.instance_size
    key_name = var.key_pair
    vpc_security_group_ids = [aws_security_group.k8s-server-sg.id]
    user_data = templatefile("${path.module}/scripts/master_install.sh", {})
    subnet_id = aws_subnet.public-subnet.id
    iam_instance_profile = aws_iam_instance_profile.k8s-main-profile.id
    private_ip = "10.0.1.10"

    tags = {
        Name = "k8s-server-${var.unit_prefix}"
        # TTL = "-1"
        owner = var.owner_email
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_instance" "k8s-worker" {
    count = var.num_worker_nodes
    ami = data.aws_ami.ubuntu.id
    instance_type = var.instance_size
    key_name = var.key_pair
    vpc_security_group_ids = [aws_security_group.k8s-node-sg.id]
    user_data = templatefile("${path.module}/scripts/worker_install.sh", {
        NODE_ID = count.index + 1
    })
    subnet_id = aws_subnet.public-subnet.id
    iam_instance_profile = aws_iam_instance_profile.k8s-main-profile.id
    private_ip = "10.0.1.${count.index + 100}"

    tags = {
        Name = "k8s-worker-${var.unit_prefix}-${count.index + 1}"
        # TTL = "-1"
        owner = var.owner_email
        "kubernetes.io/cluster/javaperks" = "owned"
    }
}

resource "aws_security_group" "k8s-node-sg" {
    name = "k8s-node-sg-${var.unit_prefix}"
    description = "webserver security group"
    vpc_id = aws_vpc.primary-vpc.id
    tags = {
        "kubernetes.io/cluster/javaperks" = "owned"
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 6781
        to_port = 6784
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 6783
        to_port = 6784
        protocol = "udp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 10250
        to_port = 10250
        protocol = "tcp"
        cidr_blocks = ["10.0.1.0/24"]
    }

    ingress {
        from_port = 30000
        to_port = 32767
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

resource "aws_security_group" "k8s-server-sg" {
    name = "k8s-server-sg-${var.unit_prefix}"
    description = "webserver security group"
    vpc_id = aws_vpc.primary-vpc.id
    tags = {
        "kubernetes.io/cluster/javaperks" = "owned"
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 2379
        to_port = 2380
        protocol = "tcp"
        cidr_blocks = ["10.0.1.0/24"]
    }

    ingress {
        from_port = 5000
        to_port = 5000
        protocol = "tcp"
        cidr_blocks = ["10.0.1.0/24"]
    }

    ingress {
        from_port = 6443
        to_port = 6443
        protocol = "tcp"
        cidr_blocks = ["10.0.1.0/24"]
    }

    ingress {
        from_port = 6781
        to_port = 6784
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 6783
        to_port = 6784
        protocol = "udp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 10250
        to_port = 10252
        protocol = "tcp"
        cidr_blocks = ["10.0.1.0/24"]
    }

    ingress {
        from_port = 10255
        to_port = 10255
        protocol = "tcp"
        cidr_blocks = ["10.0.1.0/24"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

data "aws_iam_policy_document" "k8s-assume-role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "k8s-main-access-doc-data" {
    statement {
        sid       = "FullAccess"
        effect    = "Allow"
        resources = ["*"]

        actions = [
            "ecr:*",
            "ecr:GetAuthorizationToken",
            "ec2:*",
            "ec2:Describe*",
            "ec2messages:GetMessages",
            "elasticloadbalancing:*",
            "autoscaling:DescribeAutoScalingGroup",
            "autoscaling:UpdateAutoScalingGroup",
            "autoscaling:DescribeTags",
            "ssm:UpdateInstanceInformation",
            "ssm:ListInstanceAssociations",
            "ssm:ListAssociations",
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:DescribeKey",
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
         ]
    }
}

data "aws_iam_policy_document" "k8s-main-tag-doc-data" {
    statement {
        effect = "Allow"
        resources = ["arn:aws:ec2:*:*:network-interface/*"]
        actions = [
            "ec2:CreateTags"
        ]
    }
}

data "aws_iam_policy_document" "k8s-main-inst-doc-data" {
    statement {
        effect = "Allow"
        resources = ["arn:aws:ec2:*:*:instance/*"]
        actions = [
            "ec2:AttachVolume",
            "ec2:DetachVolume"
        ]
    }
}

resource "aws_iam_policy" "k8s-main-access-doc" {
    name = "k8s-access-policy-${var.unit_prefix}"
    policy = data.aws_iam_policy_document.k8s-main-access-doc-data.json
}

resource "aws_iam_policy" "k8s-main-tag-doc" {
    name = "k8s-tag-policy-${var.unit_prefix}"
    policy = data.aws_iam_policy_document.k8s-main-tag-doc-data.json
}

resource "aws_iam_policy" "k8s-main-inst-doc" {
    name = "k8s-inst-policy-${var.unit_prefix}"
    policy = data.aws_iam_policy_document.k8s-main-inst-doc-data.json
}

resource "aws_iam_role" "k8s-main-access-role" {
  name               = "k8s-access-role-${var.unit_prefix}"
  assume_role_policy = data.aws_iam_policy_document.k8s-assume-role.json
}

resource "aws_iam_role_policy_attachment" "k8s-main-access-policy-1" {
  role   = aws_iam_role.k8s-main-access-role.id
  policy_arn = aws_iam_policy.k8s-main-access-doc.arn
}

resource "aws_iam_role_policy_attachment" "k8s-main-access-policy-2" {
  role   = aws_iam_role.k8s-main-access-role.id
  policy_arn = aws_iam_policy.k8s-main-tag-doc.arn
}

resource "aws_iam_role_policy_attachment" "k8s-main-access-policy-3" {
  role   = aws_iam_role.k8s-main-access-role.id
  policy_arn = aws_iam_policy.k8s-main-inst-doc.arn
}

resource "aws_iam_instance_profile" "k8s-main-profile" {
  name = "k8s-access-profile-${var.unit_prefix}"
  role = aws_iam_role.k8s-main-access-role.name
}
