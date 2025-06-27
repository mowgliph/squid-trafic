#!/bin/bash

iptables -F LIMITA_EMPRESA
iptables -X LIMITA_EMPRESA
ipset flush usuarios_empresariales

# Reaplicar reglas de iptables
ipset create usuarios_empresariales hash:ip
iptables -N LIMITA_EMPRESA
iptables -A OUTPUT -m set --match-set usuarios_empresariales src -j LIMITA_EMPRESA
iptables -A INPUT -m set --match-set usuarios_empresariales dst -j LIMITA_EMPRESA
iptables -A LIMITA_EMPRESA -m quota --quota 26214400000 -j ACCEPT
iptables -A LIMITA_EMPRESA -j DROP

# Guardar reglas
iptables-save > /etc/iptables/rules.v4
