provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = var.common_tags
  }
}

provider "aws" {
  alias   = "production_untagged"
  region  = var.aws_region
  profile = var.aws_profile
}
