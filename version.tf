terraform {
  required_version = "<=1.43"

  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.67"
    }
  }
}