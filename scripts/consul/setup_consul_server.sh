#! /bin/sh

export NODEIP="192.168.60.4"
export NODENAME="consul-03"

# Kurulacak cluster yapısana göre değişiklik gerektirir!!
echo "Setup DNS or edit /etc/hosts file to configure hostnames for all servers ( set on all nodes)."
tee -a /etc/hosts <<EOF
# Consul Cluster Servers
192.168.60.2 consul-01.patroni.com consul-01
192.168.60.3 consul-02.patroni.com consul-02
192.168.60.4 consul-03.patroni.com consul-03
EOF

echo "Create a systemd service file /etc/systemd/system/consul.service" 
touch /etc/systemd/system/consul.service

tee -a /etc/systemd/system/consul.service <<EOF

# Consul systemd service unit file
[Unit]
Description=Consul Service Discovery Agent
Documentation=https://www.consul.io/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=consul
Group=consul
ExecStart=/usr/bin/consul agent \
	-node=${NODENAME} \
	-config-dir=/etc/consul.d

ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT
TimeoutStopSec=5
Restart=on-failure
SyslogIdentifier=consul

[Install]
WantedBy=multi-user.target
EOF

echo "Create Consul json configuration file:"
touch /etc/consul.d/config.json

# "encrypt" key alanı kurulumdan sonra 'consul keygen' komutunun çıktısı ile değiştirilir. Her düğümde aynı key kullanılmalıdır!
tee -a /etc/consul.d/config.json <<EOF
{
     "advertise_addr": "${NODEIP}",
     "bind_addr": "${NODEIP}",
     "bootstrap_expect": 3,
     "client_addr": "0.0.0.0",
     "datacenter": "DC1",
     "data_dir": "/var/lib/consul",
     "domain": "consul",
     "enable_script_checks": true,
     "dns_config": {
         "enable_truncate": true,
         "only_passing": true
     },
     "enable_syslog": true,
     "encrypt": "oXtFDsSFRWbicMOynL3FmzM0ZEMI/bWv+/ilC8OXh80=", 
     "leave_on_terminate": true,
     "log_level": "INFO",
     "rejoin_after_leave": true,
     "retry_join": [
         "consul-01",
         "consul-02",
         "consul-03"
     ],
     "server": true,
     "start_join": [
         "consul-01",
         "consul-02",
         "consul-03"
     ],
     "ui_config": {
        "enabled": true
        }
}
EOF