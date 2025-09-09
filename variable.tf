
variable "aws_region" {
  description = "AWS region"
  default     = "ap-south-1"
}

variable "key_name" {
  description = "Key pair name for EC2 access"
  default     = "test-keypair"
}
