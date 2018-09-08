terraform {
  required_version = ">= 0.10.3" # introduction of Local Values configuration language feature
}

provider "aws" {
  region = "${var.region}"
}

resource "aws_key_pair" "terraform_ec2_key" {
  key_name   = "terraform_ec2_key"
  public_key = "${file("./.ssh/terraform.pub")}"
}

module "mgmt_vpc" {
  source = "./modules/vpc"
  env    = "${var.mgmt_env}"

  cidr             = "${var.mgmt_cidr}"
  private_subnets  = ["${var.mgmt_private_subnets}"]
  public_subnets   = ["${var.mgmt_public_subnets}"]
  database_subnets = ["${var.mgmt_database_subnets}"]

  map_public_ip_on_launch = "${var.map_public_ip_on_launch}"

  create_database_subnet_group = "${var.mgmt_create_database_subnet_group}"
  enable_nat_gateway           = "${var.mgmt_enable_nat_gateway}"
  enable_vpn_gateway           = "${var.mgmt_enable_vpn_gateway}"
}

module "mgmt_sg" {
  source = "./modules/security_groups"
  env    = "${var.mgmt_env}"

  vpc_id = "${module.mgmt_vpc.id}"
}

module "prod_vpc" {
  source = "./modules/vpc"
  env    = "${var.prod_env}"

  create_vpc       = "${var.create_prod_vpc}"
  cidr             = "${var.prod_cidr}"
  private_subnets  = ["${var.prod_private_subnets}"]
  public_subnets   = ["${var.prod_public_subnets}"]
  database_subnets = ["${var.prod_database_subnets}"]

  map_public_ip_on_launch = "${var.map_public_ip_on_launch}"

  create_database_subnet_group = "${var.prod_create_database_subnet_group}"
  enable_nat_gateway           = "${var.prod_enable_nat_gateway}"
  enable_vpn_gateway           = "${var.prod_enable_vpn_gateway}"
}

module "prod_sg" {
  source = "./modules/security_groups"

  create_security_groups = "${var.create_prod_vpc}"

  env    = "${var.prod_env}"
  vpc_id = "${module.prod_vpc.id}"
}

module "prod_vpc_peering" {
  source = "./modules/vpc_peering"

  create_vpc_peering = "${var.create_prod_vpc}"

  owner_account_id = ""
  vpc_peer_id      = "${module.prod_vpc.id}"
  vpc_id           = "${module.mgmt_vpc.id}"

  source_private_route_count     = "${length(var.mgmt_private_subnets)}"
  source_private_route_table_ids = ["${module.mgmt_vpc.private_route_table_ids}"]
  source_public_route_count      = 1 # only one public route table is created
  source_public_route_table_ids  = ["${module.mgmt_vpc.public_route_table_ids}"]
  source_peer_cird_block         = "${var.mgmt_cidr}"
  target_private_route_count     = "${length(var.prod_private_subnets)}"
  target_private_route_table_ids = ["${module.prod_vpc.private_route_table_ids}"]
  target_public_route_count      = 1 # only one public route table is created
  target_public_route_table_ids  = ["${module.prod_vpc.public_route_table_ids}"]
  target_peer_cird_block         = "${var.prod_cidr}"
  auto_accept_peering            = true
}

module "dev_vpc" {
  source = "./modules/vpc"
  env    = "${var.dev_env}"

  create_vpc       = "${var.create_dev_vpc}"
  cidr             = "${var.dev_cidr}"
  private_subnets  = ["${var.dev_private_subnets}"]
  public_subnets   = ["${var.dev_public_subnets}"]
  database_subnets = ["${var.dev_database_subnets}"]

  map_public_ip_on_launch = "${var.map_public_ip_on_launch}"

  create_database_subnet_group = "${var.dev_create_database_subnet_group}"
  enable_nat_gateway           = "${var.dev_enable_nat_gateway}"
  enable_vpn_gateway           = "${var.dev_enable_vpn_gateway}"
}

module "dev_sg" {
  source = "./modules/security_groups"

  create_security_groups = "${var.create_dev_vpc}"

  env    = "${var.dev_env}"
  vpc_id = "${module.dev_vpc.id}"
}

module "dev_vpc_peering" {
  source = "./modules/vpc_peering"

  create_vpc_peering = "${var.create_dev_vpc}"

  owner_account_id = ""
  vpc_peer_id      = "${module.dev_vpc.id}"
  vpc_id           = "${module.mgmt_vpc.id}"

  source_private_route_count     = "${length(var.mgmt_private_subnets)}"
  source_private_route_table_ids = ["${module.mgmt_vpc.private_route_table_ids}"]
  source_public_route_count      = 1 # only one public route table is created
  source_public_route_table_ids  = ["${module.mgmt_vpc.public_route_table_ids}"]
  source_peer_cird_block         = "${var.mgmt_cidr}"
  target_private_route_count     = "${length(var.dev_private_subnets)}"
  target_private_route_table_ids = ["${module.dev_vpc.private_route_table_ids}"]
  target_public_route_count      = 1 # only one public route table is created
  target_public_route_table_ids  = ["${module.dev_vpc.public_route_table_ids}"]
  target_peer_cird_block         = "${var.dev_cidr}"
  auto_accept_peering            = true
}

module "bastion" {
  source = "./modules/bastion"
  env    = "${var.mgmt_env}"

  vpc_ids = {
    mgmt = "${module.mgmt_vpc.id}"
    dev  = "${module.dev_vpc.id}"
    prod = "${module.prod_vpc.id}"
  }

  create_prod_sg = "${var.create_prod_vpc}"
  create_dev_sg  = "${var.create_dev_vpc}"

  security_groups = [
    "${module.mgmt_sg.public_ssh}",
    "${module.mgmt_sg.allow_egress}",
  ]

  # count can't be calculated, so we have to get it from a hard variable
  count   = "${var.bastion_count ? var.bastion_count: length(var.mgmt_public_subnets)}"
  subnets = ["${module.mgmt_vpc.public_subnets}"]
}