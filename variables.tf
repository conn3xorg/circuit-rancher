variable "server" {
  type        = any
  description = "One k3s server to run Helm on: an address, or a host object with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "hostname" {
  type        = string
  description = "DNS name Rancher answers on. Every node that joins Rancher must be able to resolve it. A name such as rancher.203.0.113.10.sslip.io will do for a trial."

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$", var.hostname))
    error_message = "hostname must be a DNS name, with no scheme or port."
  }
}

variable "bootstrap_password" {
  type        = string
  ephemeral   = true
  description = "Password for the first login as admin. Rancher asks for a new one then, so it only matters until that first login."

  validation {
    condition     = length(var.bootstrap_password) >= 12
    error_message = "bootstrap_password must be at least 12 characters, which is what Rancher requires of the password that replaces it."
  }
}

variable "rancher_version" {
  type        = string
  default     = "2.15.3"
  description = "Rancher chart version from the stable repository, without a v. Change it with rancher_chart_sha256 and k3s_minors."
}

variable "rancher_chart_sha256" {
  type        = string
  default     = "343888c66421a9f5666b562cdfeca751d63da994edbe7b1b36752f8ffcf5ecd4"
  description = "SHA-256 of the Rancher chart, rancher-VERSION.tgz."
}

variable "k3s_minors" {
  type        = list(string)
  default     = ["1.34", "1.35", "1.36"]
  description = "Kubernetes minor versions the server's k3s may run, from the release notes of rancher_version. Anything else fails the apply before Rancher is touched."
}

variable "cert_manager_version" {
  type        = string
  default     = "v1.21.3"
  description = "cert-manager chart version. Change it with cert_manager_chart_sha256."
}

variable "cert_manager_chart_sha256" {
  type        = string
  default     = "9ec67938b2981d8b333af61b3fcf53e26b4f6f5deb7ccda3de4ea116bb373a17"
  description = "SHA-256 of the cert-manager chart, cert-manager-VERSION.tgz."
}

variable "helm_version" {
  type        = string
  default     = "v3.22.1"
  description = "Helm release to install under /var/lib/conn3x-rancher. Rancher's docs ask for Helm 3. Change it with helm_checksums."
}

variable "helm_checksums" {
  type        = map(string)
  description = "SHA-256 of the Helm tarball for each architecture, from get.helm.sh."
  default = {
    amd64 = "896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea"
    arm64 = "4c29e286b279d170fa048ddfc3e4e83dcd069ca9c52102766ba672d7149e694d"
  }
}

variable "replicas" {
  type        = number
  default     = -3
  description = "Rancher pods. A negative number means up to that many, one per node, so -3 runs one on a single node and three on three."
}

variable "chart_values" {
  type        = any
  default     = {}
  description = "More Helm values for the Rancher chart, such as { ingress = { tls = { source = \"letsEncrypt\" } } }. They replace hostname and replicas if they name them. The bootstrap password can't go here, since these reach state."

  validation {
    condition     = !can(var.chart_values.bootstrapPassword)
    error_message = "Use bootstrap_password, which stays out of state, rather than chart_values.bootstrapPassword."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}
