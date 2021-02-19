#! /bin/sh

export VER="1.9.2"

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