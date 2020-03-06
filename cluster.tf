data "template_file" "k8s-server-setup" {
    template = "${file("${path.module}/scripts/master_install.sh")}"

    vars = {

    }
}

data "template_file" "k8s-worker-1-setup" {
    template = "${file("${path.module}/scripts/worker_install.sh")}"

    vars = {
        NODE_ID = "1"
    }
}

data "template_file" "k8s-worker-2-setup" {
    template = "${file("${path.module}/scripts/worker_install.sh")}"

    vars = {
        NODE_ID = "2"
    }
}

resource "aws_instance" "k8s-master" {
    ami = "${data.aws_ami.ubuntu.id}"
    instance_type = "${var.instance_size}"
    key_name = "${var.key_pair}"
    vpc_security_group_ids = ["${aws_security_group.k8s-server-sg.id}"]
    user_data = "${data.template_file.k8s-server-setup.rendered}"
    subnet_id = "${aws_subnet.public-subnet.id}"
    iam_instance_profile = "${aws_iam_instance_profile.k8s-main-profile.id}"
    private_ip = "10.0.1.10"

    tags = {
        Name = "k8s-server-${var.unit_prefix}"
        # TTL = "-1"
        owner = "kcochran@hashicorp.com"
    }
}

resource "aws_instance" "k8s-worker-1" {
    ami = "${data.aws_ami.ubuntu.id}"
    instance_type = "${var.instance_size}"
    key_name = "${var.key_pair}"
    vpc_security_group_ids = ["${aws_security_group.k8s-node-sg.id}"]
    user_data = "${data.template_file.k8s-worker-1-setup.rendered}"
    subnet_id = "${aws_subnet.public-subnet.id}"
    iam_instance_profile = "${aws_iam_instance_profile.k8s-main-profile.id}"
    private_ip = "10.0.1.20"

    tags = {
        Name = "k8s-server-${var.unit_prefix}"
        # TTL = "-1"
        owner = "kcochran@hashicorp.com"
    }
}

resource "aws_instance" "k8s-worker-2" {
    ami = "${data.aws_ami.ubuntu.id}"
    instance_type = "${var.instance_size}"
    key_name = "${var.key_pair}"
    vpc_security_group_ids = ["${aws_security_group.k8s-node-sg.id}"]
    user_data = "${data.template_file.k8s-worker-2-setup.rendered}"
    subnet_id = "${aws_subnet.public-subnet.id}"
    iam_instance_profile = "${aws_iam_instance_profile.k8s-main-profile.id}"
    private_ip = "10.0.1.40"

    tags = {
        Name = "k8s-server-${var.unit_prefix}"
        # TTL = "-1"
        owner = "kcochran@hashicorp.com"
    }
}

resource "aws_security_group" "k8s-node-sg" {
    name = "k8s-node-sg-${var.unit_prefix}"
    description = "webserver security group"
    vpc_id = "${aws_vpc.primary-vpc.id}"

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
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
    vpc_id = "${aws_vpc.primary-vpc.id}"

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
        from_port = 5000
        to_port = 5000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 6443
        to_port = 6443
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

data "aws_iam_policy_document" "k8s-main-access-doc" {
    statement {
        sid       = "FullAccess"
        effect    = "Allow"
        resources = ["*"]

        actions = [
            "ecr:*",
            "ecr:GetAuthorizationToken",
            "ec2:*",
            "ec2messages:GetMessages",
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

data "aws_iam_policy_document" "k8s-main-tag-doc" {
    statement {
        effect = "Allow"
        resources = ["arn:aws:ec2:*:*:network-interface/*"]
        actions = [
            "ec2:CreateTags"
        ]
    }
}

resource "aws_iam_role" "k8s-main-access-role" {
  name               = "k8s-access-role-${var.unit_prefix}"
  assume_role_policy = "${data.aws_iam_policy_document.k8s-assume-role.json}"
}

resource "aws_iam_role_policy" "k8s-main-access-policy-1" {
  name   = "k8s-access-policy-${var.unit_prefix}"
  role   = "${aws_iam_role.k8s-main-access-role.id}"
  policy = "${data.aws_iam_policy_document.k8s-main-access-doc.json}"
}

resource "aws_iam_role_policy" "k8s-main-access-policy-2" {
  name   = "k8s-access-policy-${var.unit_prefix}"
  role   = "${aws_iam_role.k8s-main-access-role.id}"
  policy = "${data.aws_iam_policy_document.k8s-main-tag-doc.json}"
}

resource "aws_iam_instance_profile" "k8s-main-profile" {
  name = "k8s-access-profile-${var.unit_prefix}"
  role = "${aws_iam_role.k8s-main-access-role.name}"
}
