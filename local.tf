locals {
  subnet_count = var.public_subnet_count + var.private_subnet_count
  subnet_bits  = ceil(log(local.subnet_count, 2))
  subnet_newbits = var.vpc_cidr_newbits + local.subnet_bits

  public_subnets = {
    for i in range(var.public_subnet_count) : 
    "public-${i + 1}" => {
      cidr_block = cidrsubnet(var.vpc_cidr, local.subnet_newbits, i),
      az_index   = i % length(data.aws_availability_zones.available.names),
      public     = true
    }
  }

  private_subnets = {
    for i in range(var.private_subnet_count) :
    "private-${i + 1}" => {
      cidr_block = cidrsubnet(var.vpc_cidr, local.subnet_newbits, i + var.public_subnet_count),
      az_index   = i % length(data.aws_availability_zones.available.names),
      public     = false
    }
  }

  all_subnets = merge(local.public_subnets, local.private_subnets)
}