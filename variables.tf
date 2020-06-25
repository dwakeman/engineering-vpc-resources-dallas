variable "ssh_key" {
    description = "The name of the SSH key to be used for VSIs"
}

/*
variable "ibmcloud_api_key" {
    description = "A valid API Key for IBM Cloud.  Not needed if using Schematics"
}
*/

variable "region" {
    default = "us-south"
}

variable "generation" {
    default = 2
}

variable "vsi_resource_group" {
    description = "The name of the resource group for VSIs"
}

variable "app_resource_group" {
    description = "The name of the resource group for the App IKS cluster"
}

variable "admin_resource_group" {
    description = "The name of the resource group for the Admin IKS cluster"
}