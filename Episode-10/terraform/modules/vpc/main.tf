# Creates the main VPC — the virtual network for all our resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.cluster_name}-vpc" })
}

# Internet gateway allowing public subnets to reach the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.cluster_name}-igw" })
}

# First public subnet in availability zone 1 (for load balancers)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-public-1"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# Second public subnet in availability zone 2 (for high availability)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-public-2"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# First private subnet in AZ 1 (where EKS pods run, no public IP)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)
  availability_zone = var.availability_zones[0]

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-private-1"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# Second private subnet in AZ 2 (for multi-AZ resilience)
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 4)
  availability_zone = var.availability_zones[1]

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-private-2"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# Elastic IP for the NAT gateway (static public IP address)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.cluster_name}-nat-eip" })
}

# NAT gateway lets private subnets reach the internet for updates
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  tags          = merge(var.tags, { Name = "${var.cluster_name}-nat" })
  depends_on    = [aws_internet_gateway.main]
}

# Route table sending public subnet traffic to the internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.cluster_name}-public-rt" })
}

# Route table sending private subnet traffic through the NAT gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.cluster_name}-private-rt" })
}

# Links public subnet 1 to the public route table
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# Links public subnet 2 to the public route table
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Links private subnet 1 to the private route table
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

# Links private subnet 2 to the private route table
resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}
