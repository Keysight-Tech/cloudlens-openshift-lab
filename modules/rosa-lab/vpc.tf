# ============================================================================
# VPC AND NETWORKING
# ============================================================================
# Note: ROSA HCP requires private subnets tagged with
# kubernetes.io/role/internal-elb = "1" for worker nodes.
# Public subnets tagged with kubernetes.io/role/elb = "1" are used
# for load balancers (Routes/Services of type LoadBalancer).
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = local.vpc_name })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.vpc_name}-igw" })
}

# ============================================================================
# MANAGEMENT / KEYSIGHT PRODUCT SUBNETS
# ============================================================================

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.management_subnet_cidr
  availability_zone       = local.az_primary
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.vpc_name}-mgmt-subnet", Type = "Management" })
}

resource "aws_subnet" "ingress" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.ingress_subnet_cidr
  availability_zone       = local.az_primary
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.vpc_name}-ingress-subnet", Type = "Ingress" })
}

resource "aws_subnet" "egress" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.egress_subnet_cidr
  availability_zone       = local.az_primary
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.vpc_name}-egress-subnet", Type = "Egress" })
}

# Main Route Table (management/ingress/egress subnets)
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.vpc_name}-rt" })
}

resource "aws_route" "default" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "management" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "ingress" {
  subnet_id      = aws_subnet.ingress.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "egress" {
  subnet_id      = aws_subnet.egress.id
  route_table_id = aws_route_table.main.id
}

# ============================================================================
# ROSA SUBNETS (conditional on rosa_enabled)
# ============================================================================

# Public Subnet AZ1 - for load balancers (OpenShift Routes)
resource "aws_subnet" "rosa_public_az1" {
  count = var.rosa_enabled ? 1 : 0

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.rosa_public_subnet_az1_cidr
  availability_zone       = local.az_primary
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                                = "${var.deployment_prefix}-rosa-public-az1"
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${local.rosa_cluster_name}"  = "shared"
    Type                                                = "ROSA-Public"
  })
}

# Public Subnet AZ2
resource "aws_subnet" "rosa_public_az2" {
  count = var.rosa_enabled ? 1 : 0

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.rosa_public_subnet_az2_cidr
  availability_zone       = local.az_secondary
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                                = "${var.deployment_prefix}-rosa-public-az2"
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${local.rosa_cluster_name}"  = "shared"
    Type                                                = "ROSA-Public"
  })
}

# Private Subnet AZ1 - worker nodes run here
resource "aws_subnet" "rosa_private_az1" {
  count = var.rosa_enabled ? 1 : 0

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.rosa_private_subnet_az1_cidr
  availability_zone = local.az_primary

  tags = merge(local.common_tags, {
    Name                                                = "${var.deployment_prefix}-rosa-private-az1"
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/${local.rosa_cluster_name}"  = "shared"
    Type                                                = "ROSA-Private"
  })
}

# Private Subnet AZ2 - worker nodes run here
resource "aws_subnet" "rosa_private_az2" {
  count = var.rosa_enabled ? 1 : 0

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.rosa_private_subnet_az2_cidr
  availability_zone = local.az_secondary

  tags = merge(local.common_tags, {
    Name                                                = "${var.deployment_prefix}-rosa-private-az2"
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/${local.rosa_cluster_name}"  = "shared"
    Type                                                = "ROSA-Private"
  })
}

# ============================================================================
# NAT GATEWAYS FOR ROSA (worker nodes need outbound internet for pulls)
# ============================================================================

resource "aws_eip" "rosa_nat_az1" {
  count  = var.rosa_enabled ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.deployment_prefix}-rosa-nat-az1" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "rosa_nat_az2" {
  count  = var.rosa_enabled ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.deployment_prefix}-rosa-nat-az2" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "rosa_az1" {
  count         = var.rosa_enabled ? 1 : 0
  allocation_id = aws_eip.rosa_nat_az1[0].id
  subnet_id     = aws_subnet.rosa_public_az1[0].id
  tags          = merge(local.common_tags, { Name = "${var.deployment_prefix}-rosa-nat-az1" })
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "rosa_az2" {
  count         = var.rosa_enabled ? 1 : 0
  allocation_id = aws_eip.rosa_nat_az2[0].id
  subnet_id     = aws_subnet.rosa_public_az2[0].id
  tags          = merge(local.common_tags, { Name = "${var.deployment_prefix}-rosa-nat-az2" })
  depends_on    = [aws_internet_gateway.main]
}

# Private route tables for ROSA worker nodes (egress via NAT)
resource "aws_route_table" "rosa_private_az1" {
  count  = var.rosa_enabled ? 1 : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.rosa_az1[0].id
  }

  tags = merge(local.common_tags, { Name = "${var.deployment_prefix}-rosa-private-az1-rt", Type = "ROSA-Private" })
}

resource "aws_route_table" "rosa_private_az2" {
  count  = var.rosa_enabled ? 1 : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.rosa_az2[0].id
  }

  tags = merge(local.common_tags, { Name = "${var.deployment_prefix}-rosa-private-az2-rt", Type = "ROSA-Private" })
}

resource "aws_route_table_association" "rosa_private_az1" {
  count          = var.rosa_enabled ? 1 : 0
  subnet_id      = aws_subnet.rosa_private_az1[0].id
  route_table_id = aws_route_table.rosa_private_az1[0].id
}

resource "aws_route_table_association" "rosa_private_az2" {
  count          = var.rosa_enabled ? 1 : 0
  subnet_id      = aws_subnet.rosa_private_az2[0].id
  route_table_id = aws_route_table.rosa_private_az2[0].id
}

resource "aws_route_table_association" "rosa_public_az1" {
  count          = var.rosa_enabled ? 1 : 0
  subnet_id      = aws_subnet.rosa_public_az1[0].id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "rosa_public_az2" {
  count          = var.rosa_enabled ? 1 : 0
  subnet_id      = aws_subnet.rosa_public_az2[0].id
  route_table_id = aws_route_table.main.id
}
