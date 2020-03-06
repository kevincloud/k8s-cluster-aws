
output "master-server-ssh" {
    value = "ssh -i ~/keys/${var.key_pair}.pem ubuntu@${aws_instance.k8s-master.public_ip}"
}

output "worker-1-server-ssh" {
    value = "ssh -i ~/keys/${var.key_pair}.pem ubuntu@${aws_instance.k8s-worker-1.public_ip}"
}

output "worker-2-server-ssh" {
    value = "ssh -i ~/keys/${var.key_pair}.pem ubuntu@${aws_instance.k8s-worker-2.public_ip}"
}
