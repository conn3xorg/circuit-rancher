variable "port" {
  type    = number
  default = 2222
}

variable "hostname" {
  type    = string
  default = "rancher.127.0.0.1.sslip.io"
}

variable "token" {
  type      = string
  ephemeral = true
  default   = "example-token-change-me"
}

variable "bootstrap_password" {
  type      = string
  ephemeral = true
  default   = "example-bootstrap-change-me"
}

module "k3s" {
  source = "github.com/conn3xorg/circuit-k3s?ref=v0.1.3"

  servers = { server1 = "127.0.0.1" }
  token   = var.token

  # circuit-k3s defaults to v1.37, which Rancher 2.15 doesn't support.
  k3s_version = "v1.36.5+k3s1"
  checksums = {
    k3s         = "d73847bcd3c5fccef0115b372e2f9a91f3032dc84bbf71518a4617565294d313"
    "k3s-arm64" = "135e34cb9e8a1cfae3cb55577789e93501efe7edc080a8b2630458a85b07721e"
  }

  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}

module "rancher" {
  source     = "../.."
  depends_on = [module.k3s]

  server             = "127.0.0.1"
  hostname           = var.hostname
  bootstrap_password = var.bootstrap_password

  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}

output "url" {
  value = module.rancher.url
}
