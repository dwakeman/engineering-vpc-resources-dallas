

data "ibm_schematics_workspace" "vpc" {
    workspace_id = var.vpc_schematics_workspace_id
}

data "ibm_schematics_output" "vpc" {
    workspace_id = var.vpc_schematics_workspace_id
    template_id  = "${data.ibm_schematics_workspace.vpc.template_id.0}"
}


/*
data "ibm_is_ssh_key" "samaritan" {
    name = var.ssh_key
}
*/

data "ibm_resource_group" "vsi_resource_group" {
    name = var.vsi_resource_group
}

data "ibm_resource_group" "app_resource_group" {
    name = var.app_resource_group
}


data "ibm_is_vpc" "vpc1" {
    name = var.vpc_name
}



data "ibm_is_subnet" "app_subnet1" {
    identifier = data.ibm_schematics_output.vpc.output_values.app_subnet1_id
}

data "ibm_is_subnet" "app_subnet2" {
    identifier = data.ibm_schematics_output.vpc.output_values.app_subnet2_id
}

data "ibm_is_subnet" "app_subnet3" {
    identifier = data.ibm_schematics_output.vpc.output_values.app_subnet3_id
}



data "ibm_resource_group" "cos_group" {
  name = var.admin_resource_group
}

data "ibm_resource_instance" "cos_instance" {
  name              = var.cos_registry_instance
  resource_group_id = data.ibm_resource_group.cos_group.id
  service           = "cloud-object-storage"
}

data "ibm_resource_group" "kms_group" {
  name = var.kms_resource_group
}

data "ibm_resource_instance" "kms_instance" {
  name              = var.kms_instance
  resource_group_id = data.ibm_resource_group.kms_group.id
  service           = "kms"
}


locals {
    ocp_01_name = "${var.environment}-ocp-01"
    zone1       = "${var.region}-1"
    zone2       = "${var.region}-2"
    zone3       = "${var.region}-3"
}

##############################################################################
# Create a customer root key
##############################################################################
resource "ibm_kp_key" "ocp_01_kp_key" {
    # punting for now; I can't get the reference to the data source to work...
#    key_protect_id = var.kms_instance
    key_protect_id = data.ibm_resource_instance.kms_instance.guid
    key_name       = "kube-${local.ocp_01_name}-crk"
    standard_key   = false
}

/*
##############################################################################
# Create IKS Cluster
##############################################################################
resource "ibm_container_vpc_cluster" "app_iks_cluster_01" {
    name                            = "${var.environment}-iks-01"
    vpc_id                          = data.ibm_schematics_output.vpc.output_values.vpc_id
    flavor                          = "bx2.4x16"
    kube_version                    = "1.17"
    worker_count                    = "1"
    wait_till                       = "MasterNodeReady"
    disable_public_service_endpoint = false
    resource_group_id               = data.ibm_resource_group.app_resource_group.id
    tags                            = ["env:${var.environment}","vpc:${var.vpc_name}","schematics:${var.schematics_workspace_id}"]

    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet1_id
        name      = "${var.region}-1"
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet2_id
        name      = "${var.region}-2"
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet3_id
        name      = "${var.region}-3"
    }
}
*/



##############################################################################
# Create OCP Cluster
##############################################################################
resource "ibm_container_vpc_cluster" "app_ocp_cluster_01" {
    name                            = local.ocp_01_name
    vpc_id                          = data.ibm_schematics_output.vpc.output_values.vpc_id
    flavor                          = "bx2.4x16"
    kube_version                    = "4.5_openshift"
    worker_count                    = "1"
    entitlement                     = "cloud_pak"
    wait_till                       = "MasterNodeReady"
    disable_public_service_endpoint = false
    cos_instance_crn                = data.ibm_resource_instance.cos_instance.id
    resource_group_id               = data.ibm_resource_group.app_resource_group.id
    tags                            = ["env:${var.environment}","vpc:${var.vpc_name}","schematics:${var.schematics_workspace_id}"]
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet1_id
        name      = "${var.region}-1"
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet2_id
        name      = "${var.region}-2"
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet3_id
        name      = "${var.region}-3"
    }

    kms_config {
        instance_id = data.ibm_resource_instance.kms_instance.guid
        crk_id = ibm_kp_key.ocp_01_kp_key.key_id
        private_endpoint = true
    }

    depends_on = [ibm_kp_key.ocp_01_kp_key]
}

##############################################################################
# Create Worker Pool for Portworx (SDS) for OCP cluster above
##############################################################################
resource "ibm_container_vpc_worker_pool" "sds_pool" {
    cluster           = ibm_container_vpc_cluster.app_ocp_cluster_01.name
    worker_pool_name  = "sds"
    flavor            = "bx2.8x32"
    vpc_id            = data.ibm_schematics_output.vpc.output_values.vpc_id
    worker_count      = 1
    entitlement       = "cloud_pak"
    resource_group_id = data.ibm_resource_group.app_resource_group.id

    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet1_id
        name      = "${var.region}-1"
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet2_id
        name      = "${var.region}-2"
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet3_id
        name      = "${var.region}-3"
    }
}

##############################################################################
# Create block storage volume for use with Portworx in OCP Cluster above
##############################################################################
resource "ibm_is_volume" "px_sds_volume1" {
    name           = "px-${ibm_container_vpc_cluster.app_ocp_cluster_01.id}-${local.zone1}-001"
    profile        = "10iops-tier"
    zone           = local.zone1
    capacity       = 200
    resource_group = data.ibm_resource_group.app_resource_group.id
    tags           = ["${ibm_container_vpc_cluster.app_ocp_cluster_01.name}", "${local.zone1}"]
}

##############################################################################
# Create block storage volume for use with Portworx in OCP Cluster above
##############################################################################
resource "ibm_is_volume" "px_sds_volume2" {
    name           = "px-${ibm_container_vpc_cluster.app_ocp_cluster_01.id}-${local.zone2}-001"
    profile        = "10iops-tier"
    zone           = local.zone2
    capacity       = 200
    resource_group = data.ibm_resource_group.app_resource_group.id
    tags           = ["${ibm_container_vpc_cluster.app_ocp_cluster_01.name}", "${local.zone2}"]
}

##############################################################################
# Create block storage volume for use with Portworx in OCP Cluster above
##############################################################################
resource "ibm_is_volume" "px_sds_volume3" {
    name           = "px-${ibm_container_vpc_cluster.app_ocp_cluster_01.id}-${local.zone3}-001"
    profile        = "10iops-tier"
    zone           = local.zone3
    capacity       = 200
    resource_group = data.ibm_resource_group.app_resource_group.id
    tags           = ["${ibm_container_vpc_cluster.app_ocp_cluster_01.name}", "${local.zone3}"]
}


