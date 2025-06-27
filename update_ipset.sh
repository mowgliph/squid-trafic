#!/bin/bash

# Set de IPs autorizadas
ipset flush usuarios_empresariales
cat /var/log/squid/access.log | awk '{print $3, $9}' | sort | uniq | while read ip user; do
    ipset add usuarios_empresariales $ip
done
