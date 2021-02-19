#! /bin/sh

# Install git and clone pagila database
yum -y install git
cd /var/lib/pgsql
git clone https://github.com/devrimgunduz/pagila.git

cat << EOF | su - postgres -c psql
-- Create the database user:
CREATE USER pagila WITH SUPERUSER LOGIN PASSWORD 'postgres';
 Create the database:
CREATE DATABASE $APP_DB_NAME WITH OWNER=pagila
                                  LC_COLLATE='en_US.utf8'
                                  LC_CTYPE='en_US.utf8'
                                  ENCODING='UTF8'
                                  TEMPLATE=template0;
-- Insert data to pagila database
\c pagila
\i /var/lib/pgsql/pagila/pagila-schema.sql
\i /var/lib/pgsql/pagila/pagila-data.sql
EOF