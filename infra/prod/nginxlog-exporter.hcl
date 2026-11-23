# Lee el log metrics_kv del Gateway (nginx.conf) y exporta conteos y latencia por ruta (SCRUM-1670).
# El formato debe coincidir con log_format metrics_kv de nginx.conf.
# El label "ambiente" lo pone Prometheus en el scrape (prometheus.yml); por eso este archivo
# es idéntico en QA (infra/qa) y PROD (infra/prod).
listen {
  port = 4040
}

namespace "nginx" {
  source {
    files = [
      "/var/log/nginx-metrics/metrics.log"
    ]
  }

  format = "$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent \"$http_referer\" \"$http_user_agent\" $request_time"

  labels {
    app = "mani-gateway"
  }

  histogram_buckets = [0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

  # Agrupa por servicio de destino para no crear una serie por URL.
  # Se evalúa en orden y se detiene en la primera coincidencia.
  relabel "route" {
    from  = "request"
    split = 2

    match "^/api/v1/core/auth/.*$" {
      replacement = "core-auth"
    }
    match "^/api/v1/core/.*$" {
      replacement = "core"
    }
    match "^/api/v1/rules/.*$" {
      replacement = "rules"
    }
    match "^/api/v1/dispatch/.*$" {
      replacement = "dispatch"
    }
    match "^/(health|metrics|nginx_status)([?].*)?$" {
      replacement = "infra"
    }
    match "^.*$" {
      replacement = "otros"
    }
  }
}
