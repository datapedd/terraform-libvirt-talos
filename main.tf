# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.3.7"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
    # see https://registry.terraform.io/providers/siderolabs/talos
    # see https://github.com/siderolabs/terraform-provider-talos
    talos = {
      source  = "siderolabs/talos"
      version = "0.1.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

provider "talos" {
}

variable "prefix" {
  default = "terraform_talos_example"
}

variable "controller_count" {
  type    = number
  default = 1
  validation {
    condition     = var.controller_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "worker_count" {
  type    = number
  default = 1
  validation {
    condition     = var.worker_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
  default     = "example"
}

locals {
  gateway          = "10.17.3.1"
  nameservers      = [local.gateway]
  cluster_vip      = "10.17.3.9"
  cluster_endpoint = "https://${local.cluster_vip}:6443" # k8s api-server endpoint.
  controller_nodes = [
    for i in range(var.controller_count) : {
      name    = "c${i}"
      address = "10.17.3.${10 + i}"
    }
  ]
  worker_nodes = [
    for i in range(var.worker_count) : {
      name    = "w${i}"
      address = "10.17.3.${20 + i}"
    }
  ]
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/network.markdown
resource "libvirt_network" "talos" {
  name      = var.prefix
  mode      = "nat"
  domain    = "talos.test"
  addresses = ["10.17.3.0/24"]
  dhcp {
    enabled = false
  }
  dns {
    enabled    = true
    local_only = false
  }
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/volume.html.markdown
resource "libvirt_volume" "controller" {
  count            = var.controller_count
  name             = "${var.prefix}_c${count.index}.img"
  base_volume_name = "talos-1.3.2-amd64.qcow2"
  format           = "qcow2"
  size             = 40 * 1024 * 1024 * 1024 # 40GiB.
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/volume.html.markdown
resource "libvirt_volume" "worker" {
  count            = var.worker_count
  name             = "${var.prefix}_w${count.index}.img"
  base_volume_name = "talos-1.3.2-amd64.qcow2"
  format           = "qcow2"
  size             = 40 * 1024 * 1024 * 1024 # 40GiB.
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/domain.html.markdown
resource "libvirt_domain" "controller" {
  count = var.controller_count
  name  = "${var.prefix}_${local.controller_nodes[count.index].name}"
  cpu {
    mode = "host-passthrough"
  }
  vcpu   = 4
  memory = 2 * 1024
  disk {
    volume_id = libvirt_volume.controller[count.index].id
    scsi      = true
  }
  network_interface {
    network_id = libvirt_network.talos.id
    addresses  = [local.controller_nodes[count.index].address]
  }
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/domain.html.markdown
resource "libvirt_domain" "worker" {
  count = var.worker_count
  name  = "${var.prefix}_${local.worker_nodes[count.index].name}"
  cpu {
    mode = "host-passthrough"
  }
  vcpu   = 4
  memory = 2 * 1024
  disk {
    volume_id = libvirt_volume.worker[count.index].id
    scsi      = true
  }
  network_interface {
    network_id = libvirt_network.talos.id
    addresses  = [local.worker_nodes[count.index].address]
  }
}

resource "talos_machine_secrets" "machine_secrets" {
}

resource "talos_machine_configuration_controlplane" "controller" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
  config_patches = [
    yamlencode({
      cluster = {
        # see https://www.talos.dev/v1.3/talos-guides/discovery/
        discovery = {
          enabled = true
          registries = {
            service = {
              disabled = true
            }
          }
        }
      }
      machine = {
        # see https://www.talos.dev/v1.3/reference/configuration/#networkconfig
        # see https://www.talos.dev/v1.3/talos-guides/network/vip/
        network = {
          interfaces = [
            {
              interface = "eth0"
              dhcp      = false
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.gateway
                }
              ]
              vip = {
                ip = local.cluster_vip
              }
            }
          ]
          nameservers = local.nameservers
        }
      }
    })
  ]
}

resource "talos_machine_configuration_worker" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
  config_patches = [
    yamlencode({
      cluster = {
        # see https://www.talos.dev/v1.3/talos-guides/discovery/
        discovery = {
          enabled = true
          registries = {
            service = {
              disabled = true
            }
          }
        }
      }
      machine = {
        # see https://www.talos.dev/v1.3/reference/configuration/#networkconfig
        network = {
          interfaces = [
            {
              interface = "eth0"
              dhcp      = false
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.gateway
                }
              ]
            }
          ]
          nameservers = local.nameservers
        }
      }
    })
  ]
}

resource "talos_client_configuration" "talos" {
  cluster_name    = var.cluster_name
  machine_secrets = talos_machine_secrets.machine_secrets.machine_secrets
  endpoints       = [for n in local.controller_nodes : n.address]
}

resource "talos_machine_configuration_apply" "controller" {
  talos_config          = talos_client_configuration.talos.talos_config
  machine_configuration = talos_machine_configuration_controlplane.controller.machine_config
  for_each              = { for n in local.controller_nodes : n.name => n }
  endpoint              = each.value.address
  node                  = each.value.address
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        # see https://www.talos.dev/v1.3/reference/configuration/#networkconfig
        network = {
          hostname = each.value.name
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${each.value.address}/24"]
            }
          ]
        }
      }
    }),
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  talos_config          = talos_client_configuration.talos.talos_config
  machine_configuration = talos_machine_configuration_worker.worker.machine_config
  for_each              = { for n in local.worker_nodes : n.name => n }
  endpoint              = each.value.address
  node                  = each.value.address
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        # see https://www.talos.dev/v1.3/reference/configuration/#networkconfig
        network = {
          hostname = each.value.name
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${each.value.address}/24"]
            }
          ]
        }
      }
    }),
  ]
}

resource "talos_machine_bootstrap" "talos" {
  talos_config = talos_client_configuration.talos.talos_config
  endpoint     = local.controller_nodes[0].address
  node         = local.controller_nodes[0].address
}

resource "talos_cluster_kubeconfig" "talos" {
  talos_config = talos_client_configuration.talos.talos_config
  endpoint     = local.controller_nodes[0].address
  node         = local.controller_nodes[0].address
}

output "controller_machineconfig" {
  value     = talos_machine_configuration_controlplane.controller.machine_config
  sensitive = true
}

output "worker_machineconfig" {
  value     = talos_machine_configuration_worker.worker.machine_config
  sensitive = true
}

output "talosconfig" {
  value     = talos_client_configuration.talos.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.talos.kube_config
  sensitive = true
}
