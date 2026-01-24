terraform {
    backend "s3" {
        bucket = "terraform-test-bucket-1112"
        key = "terraform-backend/terraform.tfstate"
        region = "us-east-1"
        dynamodb_table = "terraform-state-locking"
        encrypt = true
    }
}