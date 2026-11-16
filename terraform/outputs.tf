# These outputs are read by scripts/gen_inventory.py (terraform output -json).

output "web_public_ip" {
  description = "Public IP of the web server."
  value       = aws_instance.web.public_ip
}

output "web_private_ip" {
  description = "Private IP of the web server."
  value       = aws_instance.web.private_ip
}

output "db_public_ip" {
  description = "Public IP of the DB server (used only for SSH/Ansible)."
  value       = aws_instance.db.public_ip
}

output "db_private_ip" {
  description = "Private IP of the DB server (used by Flask to connect to Postgres)."
  value       = aws_instance.db.private_ip
}

output "s3_bucket_name" {
  description = "S3 bucket that stores the database backups."
  value       = aws_s3_bucket.backups.bucket
}

output "aws_region" {
  description = "Region of the deployment."
  value       = var.aws_region
}

output "ssh_user" {
  description = "Default SSH user of the Ubuntu AMI."
  value       = "ubuntu"
}
