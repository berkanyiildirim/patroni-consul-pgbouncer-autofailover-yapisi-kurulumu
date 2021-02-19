#!/bin/bash

FLOATINGIP=$(curl -s http://127.0.0.1:8500/v1/kv/service/postgres/floating-ip?raw)
LEADER=$(curl -s http://127.0.0.1:8500/v1/kv/service/postgres/leader?raw)

if [[ $LEADER == "pg-patroni1" ]];
then
    ip a add ${FLOATINGIP} dev enp0s8
else
    ip a del ${FLOATINGIP} dev enp0s8
fi