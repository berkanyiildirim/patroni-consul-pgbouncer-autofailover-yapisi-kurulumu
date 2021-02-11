# Patroni-Consul-PgBouncer-Autofailover-Yapisi-Kurulumu

# PostgreSQL Patroni + Consul + PgBouncer + Consul-template ile Autofailover Yapısının Kurulumu

[Patroni](https://patroni.readthedocs.io/en/latest/#), PostgreSQL HA Cluster yapısının kurulması ve yönetimi için kullanılan open source bir araçtır. PostgreSQL Cluster’inin kurulumu (bootstrap), replikasyonunun kurulumu, PostgreSQL otomatik failover yapılması amacıyla kullanılır. Patroni otomatik failover yapısını sağlamak için bir Distributed Configuration Store (DCS) aracına ihtiyaç duyar. Bunlardan bazıları; ETCD, Consul, ZooKeeper, Kubernetes. 

[Consul](https://www.consul.io); service discovery, distributed key-value store, health checking özellikleriyle kendini tanımlayan high available bir DevOps ürünü olarak ifade edilebilir. Node’lar üzerinde konumlanan, server veya client moddaki agentlar ile çalışan Consul, node’un ve kendine tanımlanmış servislerin sağlık durumlarını gözlemler, dağıtık olarak anahtar-değer ikililerini muhafaza ve servis eder, dinamik servislerin mevcut konumlarını (en temel haliyle IP:PORT olarak ifade edilebilir) bilir ve talep karşılığında iletir. Ayrıca, consul-template ile de dinamik konfigürasyon yönetimleri sağlar.

Çalışma kapsamında genel kullanım olan Patroni+etcd ikilisi yerine DCS aracı olarak consul kullanılmıştır. Büyük sistemlerde kullanımı gerekli olan pgBouncer connection pooler aracının patroni lider değişiminde konfigürasyon ayarlarını güncellemek için consul-template kullanılmış ve patroni + [pgbouncer](https://www.pgbouncer.org) + consul + [consul-template](https://github.com/hashicorp/consul-template) yapısı test edilmiştir.

## Test Ortamı için Kurulan Yapı
![Genel Yapı](/Patroni-1.jpeg)

**Kurulum**:

1. [Test Ortamı Kurulumu](##test-ortamı-kurulumu)
2. [Consul Cluster Kurulumu](##consul-cluster-kurulumu)
3. [Consul Agent'ların Client Modda Kurulumu](##consul-agentların-client-modda-kurulumu)
4. [Patroni Cluster Kurulumu](##patroni-cluster-kurulumu)
5. [Consul-template ve PgBouncer Kurulumu](##consul-template-ve-pgbouncer-kurulumu)

---

## Test Ortamı Kurulumu

- Test ortamının kurulumu için [vagrant](https://www.vagrantup.com) kullanılmıştır.

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "geerlingguy/centos8"

  config.ssh.insert_key = false
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider :virtualbox do |v|
    v.memory = 512 
    v.linked_clone = true
  end
  
  # Consul node-1 
  config.vm.define "consul-node1" do |consul|
    consul.vm.hostname = "consul-node1"
    consul.vm.network :private_network, ip: "192.168.60.2"
  end

  # Consul node-2 
  config.vm.define "consul-node2" do |consul|
    consul.vm.hostname = "consul-node1-2"
    consul.vm.network :private_network, ip: "192.168.60.3"
  end

  # Consul node-3 
  config.vm.define "consul-node3" do |consul|
    consul.vm.hostname = "consul-node3"
    consul.vm.network :private_network, ip: "192.168.60.4"
  end

  # PostgreSQL + Patroni server-1 
  config.vm.define "pg-patroni1" do |patroni|
    patroni.vm.hostname = "pg-patroni1"
    patroni.vm.network :private_network, ip: "192.168.60.11"
  end

  # PostgreSQL + Patroni server-2 
  config.vm.define "pg-patroni2" do |patroni|
    patroni.vm.hostname = "pg-patroni2"
    patroni.vm.network :private_network, ip: "192.168.60.12"
  end 

  # PostgreSQL + Patroni server-3 
  config.vm.define "pg-patroni3" do |patroni|
    patroni.vm.hostname = "pg-patroni3"
    patroni.vm.network :private_network, ip: "192.168.60.13"
  end

  # Pgbouncer node 
  config.vm.define "pgbouncer" do |pgbouncer|
    pgbouncer.vm.hostname = "pgbouncer"
    pgbouncer.vm.network :private_network, ip: "192.168.60.14"
  end
end 
```

## Consul Cluster Kurulumu

Test ortamı dışındaki kurulumlar, aşağıda verilen scripte şu değişiklileri gerektirir: 

- 3 makinaya key-value değerlerini depolayacak consul, server modda kurulur. `NODENAME`, `NODEIP` kurulan herbir node için özel olarak ayarlanır. Farklı `NODENAME` değerleri için DNS ayarları yapılan ve `retry_join` ve `start_join` script bölümlerinin verilen node ismine göre değiştirdiğinizden emin olun.  

- */etc/consul.d/config.json* dosyasındaki `encrypt` key alanı ilk consul kurulduktan sonra `consul keygen` komutunun çıktısı ile değiştirilir. Her düğümde aynı key kullanılmalıdır!    

```sh
#! /bin/sh

# https://learn.hashicorp.com/tutorials/consul/get-started-install
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install consul

export VER="1.9.2"
export NODEIP="192.168.60.4"
export NODENAME="consul-03"

sudo yum install -y wget unzip
wget https://releases.hashicorp.com/consul/${VER}/consul_${VER}_linux_amd64.zip

echo "Extract the file..."
unzip consul_${VER}_linux_amd64.zip

echo "Move extracted consul binary to  /usr/bin directory"
sudo mv consul /usr/bin/

echo "Enable bash completion:"
consul -autocomplete-install
complete -C /usr/bin/consul consul

echo "Create a consul system user/group"
sudo groupadd --system consul
sudo useradd -s /sbin/nologin --system -g consul consul

echo "Create consul data and configurations directory and set ownership to consul user"
sudo mkdir -p /var/lib/consul /etc/consul.d
sudo chown -R consul:consul /var/lib/consul /etc/consul.d
sudo chmod -R 775 /var/lib/consul /etc/consul.d

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
```

İlk consul kurulumu bittikten sonra  kendi "encrypt" değerinizi elde etme etmek için kullancağınız komut. Alınan çıktı */etc/consul.d/config.json* dosyasından default değerle değiştirilmelidir. Tüm node'ler aynı "encrypt" değerine sahip olmalıdır.

```sh
echo "Generate Consul secret:"
consul keygen
```

`consul validate /etc/consul.d/config.json` komutu ile servisi başlatmadan önce consul konfigrasyon dosyasını kontrol edilir.

- Herbir kurulum için yukarıdaki `NODENAME` ve `NODEIP` değerleri ayarlanarak script çalıştırılır. Tüm node'larda consul server kurulumu bittikten sonra sırayla consul servisi başlatılır:

```sh
sudo systemctl start consul
sudo systemctl enable consul
```

Bazı consul komutları:
```sh
consul members
consul operator raft list-peers

# IU arayüzüne kurulan nodelerın herhangi birisinin IP'si ile erişilir.
http://192.168.60.4:8500/ui/
```

## Consul Agent'ların Client Modda Kurulumu

Patroni ve pgBouncer kurulacak makinelere yukarda kurduğumuz consul cluster'ı ile konuşması için Consul Client kurulumları yapılır. Bu şekilde Patroni ve pgBouncer local agentlarla konuşarak consul clusterındaki failover işlemlerinden etkilenmez.

Aşağıdaki scripte `node_name` ve `bind_addr` alanları kurulum yapılan herbir node için özel olarak ayarlanarak çalıştırılır. Test dışı ve farklı IP kullanımı durumunda yukardaki consul cluster IP'lerini belirten `retry_join` alanını değiştirdiğinizden emin olun.

Ayrıca "encrypt" değerinde consul cluster kurulumdaki key değeri ile aynı olmalıdır.

```sh
#! /bin/sh

# https://learn.hashicorp.com/tutorials/consul/get-started-install
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install consul

export VER="1.9.2"
export NODEIP="192.168.60.13"
export NODENAME="patroni3-client"

sudo yum install -y wget unzip
wget https://releases.hashicorp.com/consul/${VER}/consul_${VER}_linux_amd64.zip

echo "Extract the file..."
unzip consul_${VER}_linux_amd64.zip

echo "Move extracted consul binary to  /usr/bin directory"
sudo mv consul /usr/bin/

echo "Enable bash completion:"
consul -autocomplete-install
complete -C /usr/bin/consul consul

echo "Create a consul system user/group"
sudo groupadd --system consul
sudo useradd -s /sbin/nologin --system -g consul consul

echo "Create consul data and configurations directory and set ownership to consul user"
sudo mkdir -p /etc/consul.d/client /var/consul
sudo chown -R consul:consul /var/consul /etc/consul.d/client
sudo chmod -R 775 /var/consul /etc/consul.d/client

# https://devopscube.com/hsetup-configure-consul-agent-client-mode/
# https://imaginea.gitbooks.io/consul-devops-handbook/content/agent_configuration.html
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

sudo systemctl daemon-reload
sudo systemctl start consul-client
sudo systemctl enable consul-client
```

## Patroni Kurulumu

3 node'da consul cluster kurulumunu ve patroni clusterını oluşturan diğer 3 node ve pgBouncer node'unda consul client kurulumlarını tamamladıktan sonra Patroni kurulumu yapılır. Buraya kadar şuan consul server cluster ve herbir makinadaki consul client çalışır durumdadır. 

Patroni kurulumu yapılmadan önce replikasyon için patroni node'larının herbiri arasında root kullanıcısı için passwordless ssh sağlanmalır. 

```sh
ssh-keygen -t rsa -b 4096 -C "your_email@domain.com"
ssh-copy-id root@server_ip_address
# veya
cat ~/.ssh/id_rsa.pub | ssh remote_username@server_ip_address "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Aşağıdaki script dosyası herbir patroni nodunda çalıştırılarak postgreSQL ve Patroni kurulumu yapılır. `NODEIP` ve  `NAME` değişkenlerinin kurulum yapılan makinaya özel olarak ayarladığınızdan emin olun. Aynı şekilde farklı IP'li kurulumlarda `pg_hba` ayarlarının buna uygun değiştilirdiğinden emin olun.  

```sh
#! /bin/sh
# CentOS Linux release 8.2.2004 (Core) 
export NODEIP="192.168.60.11"
export NAME="pg-patroni1" # herbir kurulum için benzersiz olmalıdır!

sudo dnf -y install epel-release
sudo dnf config-manager --set-enabled PowerTools
sudo dnf -y install yum-utils

# Install Postgresql
sudo dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo yum-config-manager --enable pgdg12
sudo dnf -qy module disable postgresql
sudo dnf -y install postgresql12-server postgresql12 postgresql12-devel

# Install Patroni
sudo dnf -y install https://github.com/cybertec-postgresql/patroni-packaging/releases/download/1.6.5-1/patroni-1.6.5-1.rhel7.x86_64.rpm
sudo cp -p /opt/app/patroni/etc/postgresql.yml.sample /opt/app/patroni/etc/postgresql.yml

# Log dizini oluştur
mkdir /var/log/patroni
chown postgres:postgres /var/log/patroni
chmod 755 /var/log/patroni

# Patroni konfigürasyon dosyası
sudo touch /opt/app/patroni/etc/postgresql.yml

# Konfigürasyon dosyasında gerekli değişiklikler yapılır
tee -a /opt/app/patroni/etc/postgresql.yml <<EOF

# https://www.techsupportpk.com/2020/02/how-to-create-highly-available-postgresql-cluster-centos-rhel-8.html
scope: postgres
name: ${NAME}

restapi:
    listen: ${NODEIP}:8008
    connect_address: ${NODEIP}:8008

consul:
  host: 127.0.0.1:8500 #Local consul agent ile konuşuyor. 
  protocol: http

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:

  initdb:
  - encoding: UTF8
  - data-checksums

  pg_hba:
  - host replication replicator 127.0.0.1/32 md5
  - host replication replicator 192.168.60.11/0 md5
  - host replication replicator 192.168.60.12/0 md5
  - host replication replicator 192.168.60.13/0 md5
  - host all all 0.0.0.0/0 md5

  users:
    admin:
      password: admin
      options:
        - createrole
        - createdb

postgresql:
  listen: ${NODEIP}:5432
  connect_address: ${NODEIP}:5432
  data_dir: /var/lib/pgsql/12/data
  bin_dir: /usr/pgsql-12/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator
    superuser:
      username: postgres
      password: postgres

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
EOF
```

Herbir makinada kurulum yapıldıktan sonra sırayla servisler başlatılır. Patroni clusterı başlatılmadan önce consul clusterının çalıştığından emin olun.
```sh
sudo systemctl daemon-reload
sudo systemctl start patroni.service
sudo systemctl enable patroni.service
```
 
Buraya kadar yapılan kurulumlarla Patroni + Consul yapısını sağlamış olduk. Geriye PgBouncer makinasında Consul-template ile dinamik değişen lider IP değerinin *pgbouncer.ini* dosyasının render edilmesini sağlamak kaldı. 

```sh
[root@pg-patroni2 vagrant] patronictl -c /opt/app/patroni/etc/postgresql.yml list
+ Cluster: postgres (6927913790415036887) -------+----+-----------+
|    Member   |      Host     |  Role  |  State  | TL | Lag in MB |
+-------------+---------------+--------+---------+----+-----------+
| pg-patroni1 | 192.168.60.11 |        | running |  1 |         0 |
| pg-patroni2 | 192.168.60.12 |        | running |  1 |         0 |
| pg-patroni3 | 192.168.60.13 | Leader | running |  1 |           |
+-------------+---------------+--------+---------+----+-----------+
```

Bazı patroni yönetim komutları:
```sh
#check cluster state
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml list

# stop patroni
sudo systemctl stop patroni

# check failover history
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml history

# manually initiate failover
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml failover

# disable auto failover
sudo patronictl -c /opt/app/patroni/etc/postgresql.yml pause
```


## Consul-template ve PgBouncer Kurulumu

Consul-template aracı consul binary paketiyle birlikte gelmez. Ayrı ayrı kurulmaları gerekir. Bu yüzden önce pgBouncer makinasına consul client kurulumu yapılır. PgBouncer consul cluster ile iletişimi local agent aracılığıyla yapar.   

## PgBouncer + Consul + Consul-template Yapısı
![PgBouncer + Consul + Consul-template Yapısı](/patroni-2.png)

consul-template kurulumu:
```sh
cd /opt
curl -O https://releases.hashicorp.com/consul-template/0.25.1/consul-template_0.25.1_linux_amd64.tgz
tar -zxf consul-template_*.tgz
```

PgBouncer Kurulumu:
```sh
sudo yum install epel-release
sudo yum install pgbouncer
```

Aşağıdaki komut herhangi bir patroni makinasında çalıştırılarak çıktısı *userlist.txt* dosyasına yazılır. 
````sql
select rolname,rolpassword from pg_authid where rolname='postgres';
````

örnek: 
```sh
cat /etc/pgbouncer/userlist.txt >> "postgres" "md53175bce1d3201d16594cebf9d7eb3f9d"
```

ve pgBouncer servisi başlatılır.
```sh
service pgbouncer start
```

PgBouncer kurulumu yapıldıktan sonra */etc/pgbouncer/pgbouncer.ini* dosyasını render eden consul-template oluşturulur. Bu template consul clusterdaki patroni verilerini tutan `postgres` servisini izleyerek lider değişiminde *pgbouncer.ini* dosyasında IP ve port alanlarını dinamik olarak değiştirir. **Kurulan bu yapıyla yapılan testlerde patroni failover sırasında uygulamadan gelen istekler 15-20 saniyelik aksaklıktan sonra sorunsuz devam etmiştir.**

*/etc/pgbouncer/* altında ``pgbouncer.ini.tmpl`` dosyasını yaratıp aşağıda verilen template'i kopyalayın. 
```go
[databases]
{{with $service := "postgres" }}{{with $leader := keyOrDefault (printf "service/%s/leader" $service) "NONE"}}{{if ne $leader "NONE"}}{{with $data := key (printf "pg_cluster/%s/members/%s" $service $leader) | parseJSON}}{{with $host_port := (index (index ($data.conn_url | split "://") 1 | split "/") 0) | split ":"}}* = host={{index $host_port 0}} port={{index $host_port 1}}{{end}}{{end}}{{end}}{{end}}{{end}}

[pgbouncer]
listen_port = 6432
listen_addr = *
admin_users = postgres
auth_type = md5
ignore_startup_parameters = extra_float_digits

auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
pool_mode = session
default_pool_size = 80
max_client_conn = 100
```
Konfügrasyon dosyasını render edecek template'i de hazırladıktan sonra arkada servis olarak çalışacak consul-template aşağıda verilen *consul-template-config.hcl* kullanılarak çalıştırılır. 

```go
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
  command     = "/bin/bash -c 'service pgbouncer reload'"
}
```

consul-template'i çalıştırmak için: 

```sh
/opt/consul-template -config=consul-template-config.hcl
```
