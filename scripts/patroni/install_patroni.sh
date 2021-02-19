#! /bin/sh

sudo dnf -y install epel-release
sudo dnf config-manager --set-enabled PowerTools
sudo dnf -y install yum-utils

# Install Patroni
sudo dnf -y install https://github.com/cybertec-postgresql/patroni-packaging/releases/download/1.6.5-1/patroni-1.6.5-1.rhel7.x86_64.rpm
sudo cp -p /opt/app/patroni/etc/postgresql.yml.sample /opt/app/patroni/etc/postgresql.yml

# Create Log directory
mkdir /var/log/patroni
chown postgres:postgres /var/log/patroni
chmod 755 /var/log/patroni
