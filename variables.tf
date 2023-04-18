variable "aws_profile" {}
variable "aws_account_id" {}
variable "owner" {}
variable "region" {}
variable "public_key_file_path" {}

variable "confluent_cloud_api_key" {}
variable "confluent_cloud_api_secret" {}

data "template_file" "public_key" {
  template = "${file("${pathexpand(var.public_key_file_path)}")}"
}
