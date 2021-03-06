/**
* This module creates an etcd cluster.
*
* Usage:
*
* ```hcl
* module "etcd" {
*   source                    = "github.com/scipian/quoins//etcd"
*   name                      = "elb-unsecure"
*   availability_zones        = "us-west-2a,us-west-2b,us-west-2c"
*   bastion_security_group_id = "sg-****"
*   cost_center               = "1000"
*   key_name                  = "quoin-etcd"
*   name                      = "prod-us-etcd"
*   region                    = "us-west-2"
*   role_type                 = "abcd"
*   subnet_ids                = "pub-1,pub-2,pub-3"
*   tls_provision             = "${file(format("%s/../provision.sh", path.cwd))}"
*   vpc_cidr                  = "172.16.0.0/16"
*   vpc_id                    = "vpc-123456"
* }

* provider "aws" {
*   region = "us-west-2"
* }
* ```
*/

/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "name" {
  description = "The name of your quoin."
}

variable "version" {
  description = "The version number of your infrastructure, used to aid in zero downtime deployments of new infrastructure."
  default     = "latest"
}

variable "region" {
  description = "Region where resources will be created."
}

variable "role_type" {
  description = "The role type to attach resource usage."
}

variable "cost_center" {
  description = "The cost center to attach resource usage."
}

variable "coreos_version" {
  description = "CoreOS version (https://coreos.com/releases)."
  default = "1465.8.0"
}

variable "coreos_channel" {
  description = "Channel for CoreOS version (https://coreos.com/releases)."
  default = "stable"
}

variable "tls_provision" {
  description = "The TLS ca and assets provision script."
}

variable "vpc_id" {
  description = "The ID of the VPC to create the resources within."
}

variable "vpc_cidr" {
  description = "A CIDR block for the VPC that specifies the set of IP addresses to use."
}

variable "availability_zones" {
  description = "Comma separated list of availability zones for a region."
}

variable "assume_role_principal_service" {
  description = "Principal service used for assume role policy. More information can be found at https://docs.aws.amazon.com/general/latest/gr/rande.html#iam_region."
  default     = "ec2.amazonaws.com"
}

variable "arn_region" {
  description = "Amazon Resource Name based on region, aws for most regions and aws-cn for Beijing"
  default = "aws"  
}

variable "http_proxy" {
  description = "Proxy server to use for http."
  default     = ""
}

variable "https_proxy" {
  description = "Proxy server to use for https."
  default     = ""
}

variable "no_proxy" {
  description = "List of domains or IP's that do not require a proxy."
  default     = ""
}

variable "aws_cli_image_repo" {
  description = "Docker image repository for the AWS CLI image."
  default     = "quay.io/concur_platform/awscli"
}
 
variable "aws_cli_version" {
  description = "Version of AWS CLI image."
  default     = "0.1.1"
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Certificates Provision Script
resource "aws_s3_bucket_object" "tls_provision" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/common/tls/tls-provision.sh"
  content = "${var.tls_provision}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

data "template_file" "docker_environment_bootstrap" {
  template = "${file(format("%s/environment/docker_proxy.config", path.module))}"

  vars {
    http_proxy  = "${var.http_proxy}"
    https_proxy = "${var.https_proxy}"
    no_proxy    = "${var.no_proxy}"
  }
}

data "template_file" "docker_service_proxy_bootstrap" {
  template = "${file(format("%s/environment/docker_service_proxy_bootstrap.config", path.module))}"

  vars {
    http_proxy         = "${var.http_proxy}"
    https_proxy        = "${var.https_proxy}"
    no_proxy           = "${var.no_proxy}"
    docker_environment = "${data.template_file.docker_environment_bootstrap.rendered}"
  }
}

data "template_file" "s3_cloudconfig_bootstrap" {
  template = "${file(format("%s/bootstrapper/s3-cloudconfig-bootstrap.sh", path.module))}"

  vars {
    name                 = "${var.name}"
    aws_cli_image_repo   = "${var.aws_cli_image_repo}"
    aws_cli_version      = "${var.aws_cli_version}"
    docker_environment   = "${data.template_file.docker_environment_bootstrap.rendered}"
    docker_service_proxy = "${var.http_proxy != "" || var.https_proxy != "" || var.no_proxy != "" ? data.template_file.docker_service_proxy_bootstrap.rendered : ""}"
  }
}

# Latest stable CoreOS AMI
data "aws_ami" "coreos_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["${format("CoreOS-%s-%s-hvm", var.coreos_channel, var.coreos_version)}"]
  }
}

data "template_file" "assume_role_policy" {
  template = "${file(format("%s/policies/assume-role-policy.json", path.module))}"

  vars {
    assume_role_principal_service = "${var.assume_role_principal_service}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The name of our quoin
output "name" {
  value = "${var.name}"
}

# The region where the quoin lives
output "region" {
  value = "${var.region}"
}

# The CoreOS AMI ID
output "coreos_ami" {
  value = "${data.aws_ami.coreos_ami.id}"
}
