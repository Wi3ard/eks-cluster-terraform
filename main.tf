/*
 * Input variables.
 */

variable "cidr_block" {
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
  type        = "string"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = "string"
}

variable "initial_node_count" {
  description = "Initial number of nodes in a cluster"
  default     = 2
  type        = "string"
}

variable "machine_type" {
  description = "Type of instances to use for a cluster (on demand)"
  default     = "t3.medium"
  type        = "string"
}

variable "machine_type_spot" {
  description = "Type of instances to use for a cluster (spot)"
  default     = "t3.large"
  type        = "string"
}

variable "max_node_count" {
  description = "Maximum number of nodes in a cluster"
  default     = 50
  type        = "string"
}

variable "private_subnets" {
  description = "VPC private subnets"
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
  type        = "list"
}

variable "public_subnets" {
  description = "VPC public subnets"
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
  type        = "list"
}

variable "region" {
  description = "Region to create resources in"
  default     = "us-east-1"
  type        = "string"
}

variable "spot_percentage" {
  description = "The percentages of spot instances to allocate for the cluster"
  default     = 50
  type        = "string"
}

variable "zones" {
  description = "Availability zones to create a cluster in"
  default     = ["us-east-1a", "us-east-1b"]
  type        = "list"
}

/*
 * Local definitions.
 */

locals {
  worker_groups = [
    {
      asg_desired_capacity = "${var.initial_node_count}"
      asg_max_size         = "${var.max_node_count}"
      asg_min_size         = "${var.initial_node_count}"
      autoscaling_enabled  = true
      instance_type        = "${var.machine_type}"
      name                 = "worker-group-1"
      root_volume_size     = "100"
      subnets              = "${join(",", module.vpc.private_subnets)}"

      on_demand_percentage_above_base_capacity = "${100 - var.spot_percentage}"
      override_instance_type                   = "${var.machine_type_spot}"
      spot_instance_pools                      = 20
    },
  ]
}

/*
 * Terraform providers.
 */

provider "aws" {
  region  = "${var.region}"
  version = "~> 2.6"
}

provider "local" {
  version = "~> 1.2"
}

provider "null" {
  version = "~> 2.1"
}

provider "template" {
  version = "~> 2.1"
}

/*
 * S3 remote storage for storing Terraform state.
 */

terraform {
  backend "s3" {
    encrypt = true
  }
}

/*
 * Terraform resources.
 */

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "1.60.0"

  name                 = "${var.cluster_name}-vpc"
  cidr                 = "${var.cidr_block}"
  azs                  = "${var.zones}"
  public_subnets       = ["${var.public_subnets}"]
  private_subnets      = ["${var.private_subnets}"]
  enable_dns_hostnames = true
  enable_nat_gateway   = true
  single_nat_gateway   = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "3.0.0"

  cluster_name           = "${var.cluster_name}"
  local_exec_interpreter = ["sh", "-c"]
  subnets                = ["${module.vpc.private_subnets}"]
  vpc_id                 = "${module.vpc.vpc_id}"
  worker_groups          = "${local.worker_groups}"
  worker_group_count     = "1"
}

resource "kubernetes_storage_class" "fast" {
  metadata {
    name = "fast"
  }

  storage_provisioner = "kubernetes.io/aws-ebs"
  reclaim_policy      = "Delete"

  parameters {
    fsType = "ext4"
    type = "io1"
  }
}
