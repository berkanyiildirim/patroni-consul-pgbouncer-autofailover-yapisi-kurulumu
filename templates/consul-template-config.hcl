consul {
  address = "127.0.0.1:8500"

  retry {
    enabled  = true
    attempts = 12
    backoff  = "250ms"
  }
}
template {
  source      = "/etc/pgbouncer/pgbouncer.ini.tmpl"
  destination = "/etc/pgbouncer/pgbouncer.ini"
  perms       = 0644
  command     = "/bin/bash -c 'systemctl reload pgbouncer.service'"
}