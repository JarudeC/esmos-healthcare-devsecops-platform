data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.main.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  }
}

# ─────────────────────────────────────────────────
# ArgoCD - GitOps Controller
# ─────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.55.0"
  namespace        = "argocd"
  create_namespace = true
  wait             = false
  timeout          = 900

  # Budget-friendly: disable HA components
  set {
    name  = "redis-ha.enabled"
    value = "false"
  }

  set {
    name  = "controller.replicas"
    value = "1"
  }

  set {
    name  = "server.replicas"
    value = "1"
  }

  set {
    name  = "repoServer.replicas"
    value = "1"
  }

  set {
    name  = "applicationSet.replicas"
    value = "1"
  }

  # Resource limits for e2-medium nodes
  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "repoServer.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "repoServer.resources.limits.memory"
    value = "128Mi"
  }
}

# ─────────────────────────────────────────────────
# Prometheus + Grafana - Monitoring Stack
# ─────────────────────────────────────────────────
resource "helm_release" "prometheus_stack" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "55.5.0"
  namespace        = "monitoring"
  create_namespace = true
  wait             = false
  timeout          = 1200
  skip_crds        = true
  disable_webhooks = true

  # Budget-friendly: reduce resource usage
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "3d"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "5Gi"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
    value = "standard-rwo"
  }

  # Grafana config
  set {
    name  = "grafana.adminPassword"
    value = "esmos-admin"
  }

  set {
    name  = "grafana.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "grafana.resources.limits.memory"
    value = "256Mi"
  }

  set {
    name  = "grafana.service.type"
    value = "ClusterIP"
  }

  # Disable components we don't need to save resources
  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  set {
    name  = "nodeExporter.enabled"
    value = "true"
  }
}

# ─────────────────────────────────────────────────
# ArgoCD Application CRDs - applied via kubectl
# (kubernetes_manifest fails at plan time when cluster doesn't exist yet)
# ─────────────────────────────────────────────────
resource "null_resource" "argocd_apps" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud container clusters get-credentials ${google_container_cluster.main.name} \
        --zone ${google_container_cluster.main.location} \
        --project ${var.project_id}
      kubectl apply -f ${path.module}/../kubernetes/odoo/argocd-odoo-app.yaml
      kubectl apply -f ${path.module}/../kubernetes/moodle/argocd-moodle-app.yaml
    EOT
  }
}
