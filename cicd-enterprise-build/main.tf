terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
 }
}

provider "docker" {
}

variable "student_name" {
  type        = string
  description = "Your student identifier (e.g., jsmith, mgarcia)"

  validation {
    condition     = can(regex("^[a-z]{2,10}$", var.student_name))
    error_message = "Student name must be 2-10 lowercase letters."
  }
}

variable "services" {
  description = "Docker services on the host. Key = short name (gitea, wordpress)."
  type = map(object({
    image   = string
    network = string
    ports   = optional(list(object({
      internal = number
      external = number
    })), [])
    env = optional(map(string), {})
  }))
  default = {}
}

variable "vms" {
  description = "Windows VM containers. Key = container name (prefix with student_name)."
  type = map(object({
    os          = string                 # "win11" or "win2025"
    rdp_port    = optional(number, 3389) # host port published to guest RDP 3389
    viewer_port = optional(number, 8006) # host port published to the dockur web viewer 8006
    memory_mb   = optional(number)
    vcpu        = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for v in values(var.vms) :
      contains(["win11", "win2025"], v.os)
    ])
    error_message = "OS must be one of: win11, win2025."
  }

  validation {
    condition     = length(distinct([for v in values(var.vms) : v.rdp_port])) == length(var.vms)
    error_message = "Each VM needs its own rdp_port, shared-server collision."
  }

  validation {
    condition     = length(distinct([for v in values(var.vms) : v.viewer_port])) == length(var.vms)
    error_message = "Each VM needs its own viewer_port, shared-server collision."
  }
}

variable "networks" {
  description = "Docker network segments. Each becomes student_name-NAME-net"
  type        = list(string)
  default     = ["devops", "internal", "web"]
}

variable "bind_ip" {
variable "cloud_image_path" {
  description = "Host address that published ports bind to. Hardening for shared servers: set 127.0.0.1 and reach RDP through an SSH tunnel (ssh -L 3002:localhost:3002 for the win11 rdp_port) so the network never sees RDP."
  description = "Path to the Ubuntu cloud image on the hypervisor host"
  type        = string
  type        = string
  default     = "0.0.0.0"

locals {
  os_defaults = {
   win11 = {
     version    = "11"
     memory_mb  = 4096
     vcpu       = 2
     disk_gb    = 64
   }
   win2025 = {
     version    = "2025"
     memory_mb  = 4096
     vcpu       = 2
     disk_gb    = 64
   }
 }

  windows = { for name, cfg in var.vms : name => {
  vms = { for name, cfg in var.vms : name => {
    os         = cfg.os
    version     = local.os_defaults[cfg.os].version
    image      = local.os_defaults[cfg.os].image
    ram         = "${coalesce(cfg.memory_mb, local.os_defaults[cfg.os].memory_mb) / 1024}G"
    memory     = (coalesce(cfg.memory_mb, local.os_defaults[cfg.os].memory_mb)) * 1024
    cpus        = tostring(coalesce(cfg.vcpu, local.os_defaults[cfg.os].vcpu))
    vcpu       = coalesce(cfg.vcpu, local.os_defaults[cfg.os].vcpu)
    disk        = "${local.os_defaults[cfg.os].disk_gb}G"
    disk_bus   = local.os_defaults[cfg.os].disk_bus
    rdp_port    = cfg.rdp_port
    disk_dev   = local.os_defaults[cfg.os].disk_dev
    viewer_port = cfg.viewer_port

 } }
}

resource "docker_network" "segment" {
  for_each = toset(var.networks)

  name   = "${var.student_name}-${each.value}-net"
  driver = "bridge"
}

resource "docker_container" "service" {
  for_each = var.services

  name  = "${var.student_name}-${each.key}"
  image = each.value.image

  networks_advanced {
    name = "${var.student_name}-${each.value.network}-net"
  }

  dynamic "ports" {
    for_each = each.value.ports
    content {
      internal = ports.value.internal
      external = ports.value.external
      ip       = var.bind_ip
      protocol = "tcp"
    }
  }

  env = [for k, v in each.value.env : "${k}=${v}"]

  restart = "unless-stopped"
}

resource "docker_volume" "win_storage" {
  for_each = local.windows

  name   = "${each.key}-storage"
  driver = "local"
}

resource "docker_container" "windows" {
  for_each = local.windows

  name  = each.key
  image = "dockurr/windows"

  env = [
    "VERSION=${each.value.version}",
    "RAM_SIZE=${each.value.ram}",
    "CPU_CORES=${each.value.cpus}",
    "DISK_SIZE=${each.value.disk}",
  ]

  devices {
    host_path      = "/dev/kvm"
    container_path = "/dev/kvm"
    permissions    = "rwm"
  }

  devices {
    host_path      = "/dev/net/tun"
    container_path = "/dev/net/tun"
    permissions    = "rwm"
  }

  capabilities {
    add = ["CAP_NET_ADMIN"]
  }

  ports {
    internal = 8006
    external = each.value.viewer_port
    ip       = var.bind_ip
    protocol = "tcp"
  }

  ports {
    internal = 3389
    external = each.value.rdp_port
    ip       = var.bind_ip
    protocol = "tcp"
  }

  ports {
    internal = 3389
    external = each.value.rdp_port
    ip       = var.bind_ip
    protocol = "udp"
  }

  volumes {
    volume_name    = docker_volume.win_storage[each.key].name
    container_path = "/storage"
  }

  restart      = "unless-stopped"
  stop_timeout = 120

  depends_on = [docker_volume.win_storage]
}

output "windows_containers" {
  description = "Windows VM containers (dockur)"
  value = {
    for name, w in local.windows : name => "windows ${w.version} | ${w.ram} | ${w.cpus} vCPU | rdp localhost:${w.rdp_port} | viewer localhost:${w.viewer_port}"
  }
}

output "corp_network" {
  description = "KVM NAT network"
  value       = libvirt_network.corp.name
}

# Optional: lets you save the SSH private key locally with
# terraform output -raw deploy_private_key_pem > deploy_key
output "deploy_private_key_pem" {
  value     = tls_private_key.deploy.private_key_pem
  sensitive = true
}
