locals {
  production_cidr     = "10.128.0.0/16"
  inspection_cidr     = "10.1.0.0/16"
  ingress_egress_cidr = "10.2.0.0/16"
}

module "production" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.18.1"

  name                 = "production"
  cidr                 = local.production_cidr
  azs                  = ["${var.region}a"]
  private_subnets      = ["10.128.0.0/19"]
  public_subnets       = []
  enable_dns_hostnames = true
  enable_nat_gateway   = false
  single_nat_gateway   = true
  create_igw           = false

  create_egress_only_igw           = false
  create_private_nat_gateway_route = false
}

module "inspection" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.18.1"

  name                             = "inspection"
  cidr                             = local.inspection_cidr
  azs                              = ["${var.region}a"]
  private_subnets                  = ["10.1.0.0/19"]
  public_subnets                   = []
  enable_dns_hostnames             = true
  enable_nat_gateway               = false
  single_nat_gateway               = true
  create_igw                       = false
  create_egress_only_igw           = false
  create_private_nat_gateway_route = false
}

module "ingress_egress" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.18.1"

  name                   = "ingress_egress"
  cidr                   = local.ingress_egress_cidr
  azs                    = ["${var.region}a"]
  private_subnets        = ["10.2.0.0/19"]
  public_subnets         = ["10.2.96.0/19"]
  enable_dns_hostnames   = true
  enable_nat_gateway     = true
  single_nat_gateway     = true
  create_igw             = true
  create_egress_only_igw = true
}

resource "aws_ec2_transit_gateway" "this" {
  description = "hub"
  tags = {
    "Name" = "hub"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "inspection" {
  subnet_ids         = module.inspection.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.inspection.vpc_id

  tags = {
    Name = "inspection"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  subnet_ids         = module.production.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.production.vpc_id

  tags = {
    Name = "production"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "ingress_egress" {
  subnet_ids         = module.ingress_egress.public_subnets
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.ingress_egress.vpc_id

  tags = {
    Name = "ingress-egress"
  }
}

resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = {
    Name = "inspection"
  }
}

resource "aws_ec2_transit_gateway_route_table" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = {
    Name = "production"
  }
}

resource "aws_ec2_transit_gateway_route_table" "ingress_egress" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = {
    Name = "ingress-egress"
  }
}

# Route Table Propagations
resource "aws_ec2_transit_gateway_route_table_propagation" "inspection_to_production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "inspection_to_ingress_egress" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.ingress_egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "production_to_inspection" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "ingress_egress_to_inspection" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.ingress_egress.id
}

resource "aws_route" "production_to_internet" {
  count = length(module.production.private_route_table_ids)
  route_table_id = module.production.private_route_table_ids[count.index]
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "inspection_to_internet" {
  count = length(module.inspection.private_route_table_ids)
  route_table_id = module.inspection.private_route_table_ids[count.index]
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "ingress_egress_public_to_inspection" {
  count = length(module.ingress_egress.public_route_table_ids)
  route_table_id = module.ingress_egress.public_route_table_ids[count.index]
  destination_cidr_block = local.inspection_cidr
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "ingress_egress_public_to_production" {
  count = length(module.ingress_egress.public_route_table_ids)
  route_table_id = module.ingress_egress.public_route_table_ids[count.index]
  destination_cidr_block = local.production_cidr
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "ingress_egress_private_to_inspection" {
  count = length(module.ingress_egress.private_route_table_ids)
  route_table_id = module.ingress_egress.private_route_table_ids[count.index]
  destination_cidr_block = local.inspection_cidr
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "ingress_egress_private_to_production" {
  count = length(module.ingress_egress.private_route_table_ids)
  route_table_id = module.ingress_egress.private_route_table_ids[count.index]
  destination_cidr_block = local.production_cidr
  transit_gateway_id = aws_ec2_transit_gateway.this.id
}


# Transit Gateway Routes
# Production VPC to Internet (via Inspection and Ingress/Egress)
resource "aws_ec2_transit_gateway_route" "production_to_internet" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

# Inspection VPC to Internet (via Ingress/Egress)
resource "aws_ec2_transit_gateway_route" "inspection_to_internet" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.ingress_egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Ingress/Egress VPC to Production (via Inspection)
resource "aws_ec2_transit_gateway_route" "ingress_to_production" {
  destination_cidr_block         = local.production_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.ingress_egress.id
}

# Inspection VPC to Production
resource "aws_ec2_transit_gateway_route" "inspection_to_production" {
  destination_cidr_block         = local.production_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}
