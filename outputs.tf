
output "master-server-ssh" {
    value = "ssh -i ~/keys/${var.key_pair}.pem ubuntu@${aws_instance.k8s-master.public_ip}"
}

output "worker-ssh" {
    value = [
        for instance in aws_instance.k8s-worker:
        "ssh -i ~/keys/${var.key_pair}.pem ubuntu@${instance.public_ip}"
    ]
}
