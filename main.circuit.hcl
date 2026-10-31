# Facts give the server's architecture, which picks the Helm build.
data "conn3x_host" "facts" {
  for_each = { server = var.server }

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }
}

locals {
  dir     = "/var/lib/conn3x-rancher"
  etc     = "/etc/rancher/manager"
  arch    = { x86_64 = "amd64", aarch64 = "arm64" }[data.conn3x_host.facts["server"].arch]
  tarball = "helm-${var.helm_version}-linux-${local.arch}.tar.gz"
  helm    = "${local.dir}/helm-${var.helm_version}/linux-${local.arch}/helm"

  rancher_chart      = "${local.dir}/rancher-${var.rancher_version}.tgz"
  cert_manager_chart = "${local.dir}/cert-manager-${var.cert_manager_version}.tgz"
  password_file      = "${local.etc}/bootstrap-password"
  values_file        = "${local.etc}/values.yaml"

  # Reads the binary rather than the API, so a plan doesn't depend on the
  # cluster being up.
  k3s_minor = "k3s --version | sed -n 's/^k3s version v\\([0-9]*\\.[0-9]*\\).*/\\1/p'"
  k3s_fits  = "case ' ${join(" ", var.k3s_minors)} ' in *\" $(${local.k3s_minor}) \"*) ;; *) false;; esac"

  # k3s listens on 6443 before its API can answer.
  crd_ready = "k3s kubectl wait --for=condition=Established crd/helmcharts.helm.cattle.io"

  wait_api = "for _ in $(seq 60); do k3s kubectl get --raw=/readyz >/dev/null 2>&1 && break; sleep 5; done"
}

circuit "rancher" {
  hosts = { server = var.server }

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Rancher's chart refuses a Kubernetes newer than it knows, but only after
  # cert-manager has gone in, and it has no lower bound.
  step "k3s_version" {
    command {
      command = "${local.k3s_fits} || { echo \"k3s $(${local.k3s_minor}) is not on k3s_minors (${join(", ", var.k3s_minors)}), the versions Rancher ${var.rancher_version} supports. Set k3s_version and checksums on circuit-k3s to a supported release.\" >&2; exit 1; }"
      unless  = local.k3s_fits
    }
  }

  # k3s installs Traefik through this CRD, and Rancher is reached through
  # Traefik. A restart can't clear one that's stuck, so stop with a pointer.
  step "helm_controller" {
    command {
      command = "${local.wait_api}; for _ in $(seq 60); do ${local.crd_ready} --timeout=5s >/dev/null 2>&1 && exit 0; sleep 5; done; echo 'k3s CRDs did not become Established. See Troubleshooting in the circuit-k3s README: https://github.com/conn3xorg/circuit-k3s#troubleshooting' >&2; exit 1"
    }
  }

  step "helm_tarball" {
    download {
      url    = "https://get.helm.sh/${local.tarball}"
      sha256 = var.helm_checksums[local.arch]
      dest   = "${local.dir}/${local.tarball}"
    }
  }

  step "helm" {
    archive {
      src     = "${local.dir}/${local.tarball}"
      dest    = "${local.dir}/helm-${var.helm_version}"
      creates = local.helm
    }
  }

  step "cert_manager_chart" {
    download {
      url    = "https://charts.jetstack.io/charts/cert-manager-${var.cert_manager_version}.tgz"
      sha256 = var.cert_manager_chart_sha256
      dest   = local.cert_manager_chart
    }
  }

  step "rancher_chart" {
    download {
      url    = "https://releases.rancher.com/server-charts/stable/rancher-${var.rancher_version}.tgz"
      sha256 = var.rancher_chart_sha256
      dest   = local.rancher_chart
    }
  }

  step "etc" {
    directory {
      path = local.etc
      mode = "0700"
    }
  }

  step "password" {
    file {
      path       = local.password_file
      content_wo = var.bootstrap_password
    }
  }

  step "values" {
    file {
      path = local.values_file
      mode = "0600"
      content = yamlencode(merge({
        hostname = var.hostname
        replicas = var.replicas
      }, var.chart_values))
    }
  }

  # The chart's --set bootstrapPassword would put the password in ps and in
  # Helm's stored values. Its template also takes a bootstrap-secret that's
  # already there, and Rancher reads the secret itself.
  step "bootstrap_secret" {
    command {
      command  = "${local.wait_api}; k3s kubectl create namespace cattle-system --dry-run=client -o yaml | k3s kubectl apply -f - && k3s kubectl -n cattle-system create secret generic bootstrap-secret --from-file=bootstrapPassword=${local.password_file} --dry-run=client -o yaml | k3s kubectl apply -f - >/dev/null"
      triggers = { password = conn3x_file.rancher__password[each.key].revision }
    }
  }

  # Triggers alone decide when Helm runs, since a guard that held would also
  # hold back an upgrade.
  step "cert_manager" {
    command {
      command  = "${local.wait_api}; KUBECONFIG=/etc/rancher/k3s/k3s.yaml ${local.helm} upgrade --install cert-manager ${local.cert_manager_chart} --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m"
      triggers = { chart = conn3x_download.rancher__cert_manager_chart[each.key].revision }
    }
  }

  # With one replica, Helm's --wait counts Rancher as ready while its pod
  # is still starting, since the Deployment allows one unavailable.
  step "install" {
    command {
      command = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml ${local.helm} upgrade --install rancher ${local.rancher_chart} --namespace cattle-system -f ${local.values_file} --wait --timeout 20m && k3s kubectl -n cattle-system rollout status deploy/rancher --timeout=20m"
      triggers = {
        chart  = conn3x_download.rancher__rancher_chart[each.key].revision
        values = conn3x_file.rancher__values[each.key].revision
      }
    }
  }

  # Rancher's pods are ready before it has finished taking on the cluster
  # it runs on. The cluster's Ready condition turns true early; Waiting turns
  # true last, when the API calls the cluster active.
  step "local_cluster" {
    command {
      command  = "for _ in $(seq 120); do k3s kubectl wait --for=condition=Waiting=True clusters.management.cattle.io/local --timeout=5s >/dev/null 2>&1 && exit 0; sleep 5; done; echo 'The local cluster did not become ready in 10 minutes. See kubectl -n cattle-system logs deploy/rancher.' >&2; exit 1"
      triggers = { install = conn3x_command.rancher__install[each.key].revision }
    }
  }
}
