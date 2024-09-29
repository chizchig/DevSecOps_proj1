
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "subnets" {
  for_each = local.all_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-${each.key}-subnet"
    Type = each.value.public ? "Public" : "Private"
  })
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  for_each = local.public_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.subnets[each.key].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  for_each = local.public_subnets

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-eip-${each.key}"
  })
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[element(keys(local.public_subnets), each.value.az_index)].id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-rt-${each.key}"
  })
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# Security Group
resource "aws_security_group" "main" {
  name        = "${var.project_name}-sg"
  description = "Main security group for ${var.project_name}"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.sg_ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-sg"
  })
}

# DevSecOps: Enable VPC Flow Logs
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "/aws/vpc-flow-log/${var.project_name}"

  retention_in_days = 30

  tags = merge(var.tags, {
    Name = "${var.project_name}-flow-log-group"
  })
}



# DevSecOps: Enable default encryption for EBS volumes
resource "aws_ebs_encryption_by_default" "example" {
  enabled = true
}

# DevSecOps: Enable GuardDuty
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}

# DevSecOps: AWS Config
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-config-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-config-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config.id
  s3_key_prefix  = "config"
  sns_topic_arn  = aws_sns_topic.config.arn

  depends_on = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.config]
}


resource "aws_sns_topic" "config" {
  name = "${var.project_name}-config-topic"
}

