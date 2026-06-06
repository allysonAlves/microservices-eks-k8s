locals {
  rds_services = {
    auth      = "auth_db"
    flags     = "flags_db"
    targeting = "targeting_db"
  }
}

resource "aws_db_instance" "services" {
  for_each = local.rds_services

  identifier        = "${var.project_name}-${each.key}-db"
  engine            = "postgres"
  engine_version    = "15.8"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = each.value
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true

  tags = { Name = "${var.project_name}-${each.key}-db" }
}
