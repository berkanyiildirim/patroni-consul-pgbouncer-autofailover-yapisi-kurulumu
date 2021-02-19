#! /bin/sh
# https://devopscube.com/hsetup-configure-consul-agent-client-mode/
# https://imaginea.gitbooks.io/consul-devops-handbook/content/agent_configuration.html

export NODEIP="192.168.60.13"
export NODENAME="patroni3-client"

sudo touch /etc/consul.d/client/config.json
tee -a /etc/consul.d/client/config.json <<EOF 
{
    "node_name": "${NODENAME}", 
    "bind_addr": "${NODEIP}",
    "server": false,
    "datacenter": "dc1",
    "data_dir": "/var/consul",
    "encrypt": "oXtFDsSFRWbicMOynL3FmzM0ZEMI/bWv+/ilC8OXh80=",
    "log_level": "INFO",
    "enable_syslog": true,
    "rejoin_after_leave": true,
    "retry_join": [
        "192.168.60.2",
        "192.168.60.3",
        "192.168.60.4"
    ]
}
EOF

sudo touch /etc/systemd/system/consul-client.service
tee -a /etc/systemd/system/consul-client.service <<EOF
[Unit]
Description=Consul Startup process
After=network.target
 
[Service]
Type=simple
ExecStart=/bin/bash -c '/usr/bin/consul agent -config-dir /etc/consul.d/client'
TimeoutStartSec=0
Restart=on-failure
RestartSec=2s
 
[Install]
WantedBy=default.target
EOF