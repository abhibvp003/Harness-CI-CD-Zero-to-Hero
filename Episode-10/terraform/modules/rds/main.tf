# Generates a random password for the RDS database
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Subnet group telling RDS which subnets it can use
resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.cluster_name}-db-subnet-group" })
}

# Security group that only allows PostgreSQL traffic from the VPC
resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-rds-sg"
  description = "RDS - allows access from EKS pods only"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-rds-sg" })
}

# The PostgreSQL RDS instance used by our application
resource "aws_db_instance" "main" {
  identifier              = "${var.cluster_name}-postgres"
  engine                  = "postgres"
  engine_version          = "16.3"
  instance_class          = var.instance_class
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = false
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 7

  tags = merge(var.tags, { Name = "${var.cluster_name}-postgres" })
}

# Stores the DB credentials securely in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.secret_prefix}/db-credentials"
  recovery_window_in_days = 0
  tags                    = var.tags
}

# Populates the secret with DB connection details like host and password
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    DB_HOST     = aws_db_instance.main.endpoint
    DB_PORT     = tostring(aws_db_instance.main.port)
    DB_NAME     = var.db_name
    DB_USERNAME = var.db_username
    DB_PASSWORD = random_password.db_password.result
    DB_URL      = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.main.endpoint}/${var.db_name}"
  })
}
