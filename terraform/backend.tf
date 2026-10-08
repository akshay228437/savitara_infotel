terraform {
  backend "s3" {
    bucket       = "clouddocs-am-tfstate-bucket22"
    key          = "clouddocs/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}