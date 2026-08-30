# Latest Amazon Linux 2023 AMI 
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# IAM role that lets the bastion EC2 instance call AWS services
resource "aws_iam_role" "bastion" {
  name = "${var.cluster_name}-bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach admin permissions so bastion can manage all AWS resources
resource "aws_iam_role_policy_attachment" "bastion_admin" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.bastion.name
}

# Instance profile that links the IAM role to the EC2 instance
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.cluster_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

# Security group controlling network traffic to/from the bastion
resource "aws_security_group" "bastion" {
  name_prefix = "${var.cluster_name}-bastion-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-bastion-sg" })
}

# bastion EC2 instance used to access the {private EKS cluster}
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data = templatefile("${path.module}/tools.sh", {
    cluster_name = var.eks_cluster_name
    aws_region   = var.aws_region
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-bastion" })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# Grants the bastion IAM role access to the EKS cluster
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.bastion.arn
  type          = "STANDARD"
  lifecycle { ignore_changes = [principal_arn] }
}

# Gives the bastion full admin access within the EKS cluster
resource "aws_eks_access_policy_association" "bastion_admin" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.bastion.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
