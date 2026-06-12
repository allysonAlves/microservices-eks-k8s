data "aws_caller_identity" "current" {}

locals {
  ecr_base  = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}"
  image_tag = "latest"

  namespace = "togglemaster"

  # Connection strings assembled from Terraform outputs
  auth_db_url      = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.services["auth"].address}:5432/auth_db"
  flags_db_url     = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.services["flags"].address}:5432/flags_db"
  targeting_db_url = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.services["targeting"].address}:5432/targeting_db"
  redis_url        = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
  sqs_url          = aws_sqs_queue.analytics.url
  dynamodb_table   = aws_dynamodb_table.analytics.name
}

# ── Namespace ───────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "togglemaster" {
  metadata {
    name = local.namespace
    labels = {
      app = "togglemaster"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# ── Secrets ─────────────────────────────────────────────────────────────────

resource "kubernetes_secret" "auth_service" {
  metadata {
    name      = "auth-service-secrets"
    namespace = local.namespace
  }
  data = {
    DATABASE_URL = local.auth_db_url
    MASTER_KEY   = var.auth_master_key
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_secret" "flag_service" {
  metadata {
    name      = "flag-service-secrets"
    namespace = local.namespace
  }
  data = {
    DATABASE_URL = local.flags_db_url
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_secret" "targeting_service" {
  metadata {
    name      = "targeting-service-secrets"
    namespace = local.namespace
  }
  data = {
    DATABASE_URL = local.targeting_db_url
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_secret" "evaluation_service" {
  metadata {
    name      = "evaluation-service-secrets"
    namespace = local.namespace
  }
  data = {
    REDIS_URL       = local.redis_url
    SERVICE_API_KEY = var.service_api_key
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_secret" "analytics_service" {
  metadata {
    name      = "analytics-service-secrets"
    namespace = local.namespace
  }
  data = {
    AWS_SQS_URL = local.sqs_url
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

# ── ConfigMaps ──────────────────────────────────────────────────────────────

resource "kubernetes_config_map" "migrations" {
  metadata {
    name      = "db-migrations"
    namespace = local.namespace
  }
  data = {
    "auth.sql" = <<-SQL
      CREATE TABLE IF NOT EXISTS api_keys (
        id         SERIAL PRIMARY KEY,
        name       VARCHAR(100) NOT NULL,
        key_hash   VARCHAR(64)  NOT NULL UNIQUE,
        is_active  BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    "flags.sql" = <<-SQL
      CREATE TABLE IF NOT EXISTS flags (
        id          SERIAL PRIMARY KEY,
        name        VARCHAR(100) UNIQUE NOT NULL,
        description TEXT,
        is_enabled  BOOLEAN NOT NULL DEFAULT false,
        created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE OR REPLACE FUNCTION trigger_set_timestamp()
      RETURNS TRIGGER AS $$
      BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
      $$ LANGUAGE plpgsql;
      DROP TRIGGER IF EXISTS set_timestamp ON flags;
      CREATE TRIGGER set_timestamp BEFORE UPDATE ON flags
        FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
    SQL

    "targeting.sql" = <<-SQL
      CREATE TABLE IF NOT EXISTS targeting_rules (
        id         SERIAL PRIMARY KEY,
        flag_name  VARCHAR(100) UNIQUE NOT NULL,
        is_enabled BOOLEAN NOT NULL DEFAULT true,
        rules      JSONB NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE OR REPLACE FUNCTION trigger_set_timestamp()
      RETURNS TRIGGER AS $$
      BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
      $$ LANGUAGE plpgsql;
      DROP TRIGGER IF EXISTS set_timestamp ON targeting_rules;
      CREATE TRIGGER set_timestamp BEFORE UPDATE ON targeting_rules
        FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
    SQL
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_config_map" "shared" {
  metadata {
    name      = "shared-config"
    namespace = local.namespace
  }
  data = {
    AWS_REGION            = var.aws_region
    AUTH_SERVICE_URL      = "http://auth-service:8001"
    FLAG_SERVICE_URL      = "http://flag-service:8002"
    TARGETING_SERVICE_URL = "http://targeting-service:8003"
    AWS_DYNAMODB_TABLE    = local.dynamodb_table
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

# ── Deployments ─────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "auth_service" {
  wait_for_rollout = false

  metadata {
    name      = "auth-service"
    namespace = local.namespace
    labels    = { app = "auth-service" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "auth-service" }
    }
    template {
      metadata {
        labels = { app = "auth-service" }
      }
      spec {
        init_container {
          name    = "migrate-db"
          image   = "postgres:15-alpine"
          command = ["sh", "-c", "psql $$DATABASE_URL -f /migrations/auth.sql"]
          env_from {
            secret_ref { name = "auth-service-secrets" }
          }
          volume_mount {
            name       = "migrations"
            mount_path = "/migrations"
          }
        }
        volume {
          name = "migrations"
          config_map { name = "db-migrations" }
        }
        container {
          name  = "auth-service"
          image = "${local.ecr_base}/auth-service:${local.image_tag}"
          port { container_port = 8001 }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }

          env_from {
            secret_ref { name = "auth-service-secrets" }
          }
          env_from {
            config_map_ref { name = "shared-config" }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8001
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8001
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
  depends_on = [kubernetes_secret.auth_service, kubernetes_config_map.shared]
}

resource "kubernetes_deployment" "flag_service" {
  wait_for_rollout = false

  metadata {
    name      = "flag-service"
    namespace = local.namespace
    labels    = { app = "flag-service" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "flag-service" }
    }
    template {
      metadata {
        labels = { app = "flag-service" }
      }
      spec {
        init_container {
          name    = "migrate-db"
          image   = "postgres:15-alpine"
          command = ["sh", "-c", "psql $$DATABASE_URL -f /migrations/flags.sql"]
          env_from {
            secret_ref { name = "flag-service-secrets" }
          }
          volume_mount {
            name       = "migrations"
            mount_path = "/migrations"
          }
        }
        volume {
          name = "migrations"
          config_map { name = "db-migrations" }
        }
        container {
          name  = "flag-service"
          image = "${local.ecr_base}/flag-service:${local.image_tag}"
          port { container_port = 8002 }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }

          env_from {
            secret_ref { name = "flag-service-secrets" }
          }
          env_from {
            config_map_ref { name = "shared-config" }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8002
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8002
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
  depends_on = [kubernetes_secret.flag_service, kubernetes_config_map.shared]
}

resource "kubernetes_deployment" "targeting_service" {
  wait_for_rollout = false

  metadata {
    name      = "targeting-service"
    namespace = local.namespace
    labels    = { app = "targeting-service" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "targeting-service" }
    }
    template {
      metadata {
        labels = { app = "targeting-service" }
      }
      spec {
        init_container {
          name    = "migrate-db"
          image   = "postgres:15-alpine"
          command = ["sh", "-c", "psql $$DATABASE_URL -f /migrations/targeting.sql"]
          env_from {
            secret_ref { name = "targeting-service-secrets" }
          }
          volume_mount {
            name       = "migrations"
            mount_path = "/migrations"
          }
        }
        volume {
          name = "migrations"
          config_map { name = "db-migrations" }
        }
        container {
          name  = "targeting-service"
          image = "${local.ecr_base}/targeting-service:${local.image_tag}"
          port { container_port = 8003 }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }

          env_from {
            secret_ref { name = "targeting-service-secrets" }
          }
          env_from {
            config_map_ref { name = "shared-config" }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8003
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8003
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
  depends_on = [kubernetes_secret.targeting_service, kubernetes_config_map.shared]
}

resource "kubernetes_deployment" "evaluation_service" {
  wait_for_rollout = false

  metadata {
    name      = "evaluation-service"
    namespace = local.namespace
    labels    = { app = "evaluation-service" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "evaluation-service" }
    }
    template {
      metadata {
        labels = { app = "evaluation-service" }
      }
      spec {
        container {
          name  = "evaluation-service"
          image = "${local.ecr_base}/evaluation-service:${local.image_tag}"
          port { container_port = 8004 }

          resources {
            requests = { cpu = "200m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }

          env_from {
            secret_ref { name = "evaluation-service-secrets" }
          }
          env_from {
            config_map_ref { name = "shared-config" }
          }

          env {
            name = "AWS_SQS_URL"
            value_from {
              secret_key_ref {
                name = "analytics-service-secrets"
                key  = "AWS_SQS_URL"
              }
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8004
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8004
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
  depends_on = [kubernetes_secret.evaluation_service, kubernetes_secret.analytics_service, kubernetes_config_map.shared]
}

resource "kubernetes_deployment" "analytics_service" {
  wait_for_rollout = false

  metadata {
    name      = "analytics-service"
    namespace = local.namespace
    labels    = { app = "analytics-service" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "analytics-service" }
    }
    template {
      metadata {
        labels = { app = "analytics-service" }
      }
      spec {
        container {
          name  = "analytics-service"
          image = "${local.ecr_base}/analytics-service:${local.image_tag}"
          port { container_port = 8005 }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "300m", memory = "256Mi" }
          }

          env_from {
            secret_ref { name = "analytics-service-secrets" }
          }
          env_from {
            config_map_ref { name = "shared-config" }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8005
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8005
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
  depends_on = [kubernetes_secret.analytics_service, kubernetes_config_map.shared]
}

# ── Services ────────────────────────────────────────────────────────────────

resource "kubernetes_service" "auth_service" {
  metadata {
    name      = "auth-service"
    namespace = local.namespace
  }
  spec {
    selector = { app = "auth-service" }
    port {
      port        = 8001
      target_port = 8001
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_service" "flag_service" {
  metadata {
    name      = "flag-service"
    namespace = local.namespace
  }
  spec {
    selector = { app = "flag-service" }
    port {
      port        = 8002
      target_port = 8002
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_service" "targeting_service" {
  metadata {
    name      = "targeting-service"
    namespace = local.namespace
  }
  spec {
    selector = { app = "targeting-service" }
    port {
      port        = 8003
      target_port = 8003
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_service" "evaluation_service" {
  metadata {
    name      = "evaluation-service"
    namespace = local.namespace
  }
  spec {
    selector = { app = "evaluation-service" }
    port {
      port        = 8004
      target_port = 8004
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

resource "kubernetes_service" "analytics_service" {
  metadata {
    name      = "analytics-service"
    namespace = local.namespace
  }
  spec {
    selector = { app = "analytics-service" }
    port {
      port        = 8005
      target_port = 8005
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_namespace.togglemaster]
}

# ── Ingress ─────────────────────────────────────────────────────────────────

resource "kubernetes_ingress_v1" "main" {
  metadata {
    name      = "togglemaster-ingress"
    namespace = local.namespace
    annotations = {
      "kubernetes.io/ingress.class"                = "nginx"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
    }
  }
  spec {
    rule {
      http {
        path {
          path      = "/auth(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "auth-service"
              port { number = 8001 }
            }
          }
        }
        path {
          path      = "/flags(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "flag-service"
              port { number = 8002 }
            }
          }
        }
        path {
          path      = "/targeting(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "targeting-service"
              port { number = 8003 }
            }
          }
        }
        path {
          path      = "/evaluate(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "evaluation-service"
              port { number = 8004 }
            }
          }
        }
        path {
          path      = "/analytics(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "analytics-service"
              port { number = 8005 }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.nginx_ingress]
}

# ── HPA ─────────────────────────────────────────────────────────────────────

resource "kubernetes_horizontal_pod_autoscaler_v2" "evaluation_service" {
  metadata {
    name      = "evaluation-service-hpa"
    namespace = local.namespace
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "evaluation-service"
    }
    min_replicas = 1
    max_replicas = 4
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 30
        }
      }
    }
  }
  depends_on = [kubernetes_deployment.evaluation_service, helm_release.metrics_server]
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "analytics_service" {
  metadata {
    name      = "analytics-service-hpa"
    namespace = local.namespace
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "analytics-service"
    }
    min_replicas = 1
    max_replicas = 3
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
  depends_on = [kubernetes_deployment.analytics_service, helm_release.metrics_server]
}
