#! /bin/sh

# Install Postgresql
sudo dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo yum-config-manager --enable pgdg12
sudo dnf -qy module disable postgresql
sudo dnf -y install postgresql12-server postgresql12 postgresql12-devel