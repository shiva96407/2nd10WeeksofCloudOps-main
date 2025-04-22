terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = ">= 5.25.0"
    }
  }

  backend "s3" {
    bucket = "east-12345678"
    key    = "eggks/terraform.tfstate"
    region = "us-east-1"
  }

  required_version = ">= 1.6.3"
}
