#! /bin/sh

export NODEIP="192.168.60.13"
export NAME="pg-patroni3"
# NAME must be uniqe

# Apply needed changes on Patroni configuration file.
# https://www.techsupportpk.com/2020/02/how-to-create-highly-available-postgresql-cluster-centos-rhel-8.html
tee -a /opt/app/patroni/etc/postgresql.yml <<EOF

scope: postgres
name: ${NAME}

restapi:
    listen: ${NODEIP}:8008
    connect_address: ${NODEIP}:8008

consul:
  host: 127.0.0.1:8500 
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