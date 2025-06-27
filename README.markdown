# Guía para Limitar Consumo Mensual de Datos por IP con Squid e iptables

Esta guía describe cómo implementar un sistema para limitar el consumo total de datos a 25 GB mensuales por IP en un servidor proxy Squid, utilizando iptables para el control de tráfico y autenticación LDAP para usuarios. Aunque Squid no tiene soporte nativo para limitar el consumo acumulado mensual, esta solución combina herramientas externas para lograrlo.

---

## Requisitos previos
- Servidor con Squid instalado.
- Módulo `ipset` y `iptables` instalados.
- Acceso a un servidor LDAP para autenticación (opcional, si deseas limitar por usuario).
- Paquetes adicionales: `squid-ldap-auth` para autenticación LDAP.
- Herramientas de monitoreo como `sarg` o `squid-analyzer` (opcional, para análisis de tráfico).

---

## Paso 1: Configurar autenticación LDAP en Squid
Configura Squid para autenticar usuarios contra un servidor LDAP.

1. **Edita el archivo `squid.conf`** (generalmente en `/etc/squid/squid.conf`):
   ```bash
   auth_param basic program /usr/lib/squid/basic_ldap_auth -b "dc=midominio,dc=com" -D "cn=admin,dc=midominio,dc=com" -w 'tu_contraseña' -f "uid=%s" -h ldap.servidor.cu
   auth_param basic children 5
   auth_param basic realm Ingrese sus credenciales corporativas
   auth_param basic credentialsttl 2 hours
   auth_param basic casesensitive on

   acl usuarios_autenticados proxy_auth REQUIRED
   http_access allow usuarios_autenticados
   ```

2. **Instala el helper de autenticación LDAP**:
   ```bash
   apt install squid-ldap-auth
   ```

3. **Reinicia Squid**:
   ```bash
   systemctl restart squid
   ```

---

## Paso 2: Configurar logging extendido en Squid
Para asociar usuarios con sus IPs, activa un formato de log personalizado en Squid.

1. **Edita `squid.conf`** y agrega el siguiente formato de log:
   ```bash
   logformat squid %ts.%03tu %6tr %>a %ul %>Hs %<st %rm %ru %un
   access_log /var/log/squid/access.log squid
   ```

2. **Reinicia Squid** para aplicar los cambios:
   ```bash
   systemctl restart squid
   ```

---

## Paso 3: Crear un script para vincular usuario a IP
Este script lee los logs de Squid y actualiza un conjunto de IPs en `ipset` basado en las asociaciones usuario-IP.

1. **Crea el script `/usr/local/bin/update_ipset.sh`**:
   ```bash
   #!/bin/bash

   # Set de IPs autorizadas
   ipset flush usuarios_empresariales
   cat /var/log/squid/access.log | awk '{print $3, $9}' | sort | uniq | while read ip user; do
       ipset add usuarios_empresariales $ip
   done
   ```

2. **Dale permisos de ejecución**:
   ```bash
   chmod +x /usr/local/bin/update_ipset.sh
   ```

3. **Configura un cron para ejecutarlo cada 10 minutos**:
   ```bash
   crontab -e
   ```
   Agrega la siguiente línea:
   ```bash
   */10 * * * * /usr/local/bin/update_ipset.sh
   ```

---

## Paso 4: Configurar reglas de iptables para limitar el tráfico
Usa `iptables` y `ipset` para limitar el consumo de datos a 25 GB mensuales por IP.

1. **Crea el conjunto de IPs y las reglas de iptables**:
   ```bash
   # Crear conjunto de IPs
   ipset create usuarios_empresariales hash:ip

   # Crear cadena personalizada
   iptables -N LIMITA_EMPRESA

   # Aplicar reglas a IPs del conjunto
   iptables -A OUTPUT -m set --match-set usuarios_empresariales src -j LIMITA_EMPRESA
   iptables -A INPUT -m set --match-set usuarios_empresariales dst -j LIMITA_EMPRESA

   # Limitar a 25 GB (26214400000 bytes)
   iptables -A LIMITA_EMPRESA -m quota --quota 26214400000 -j ACCEPT
   iptables -A LIMITA_EMPRESA -j DROP
   ```

2. **Guarda las reglas de iptables**:
   ```bash
   iptables-save > /etc/iptables/rules.v4
   ```

---

## Paso 5: Resetear las cuotas mensualmente
Configura un script para reiniciar las cuotas al inicio de cada mes.

1. **Crea el script `/etc/cron.monthly/reset_quota.sh`**:
   ```bash
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
   ```

2. **Dale permisos de ejecución**:
   ```bash
   chmod +x /etc/cron.monthly/reset_quota.sh
   ```

3. **Asegúrate de que el cron se ejecute**:
   Verifica que el directorio `/etc/cron.monthly/` esté configurado para ejecutarse mensualmente.

---

## Consejo adicional
- Usa herramientas como `sarg` o `squid-analyzer` para monitorear el tráfico por usuario/IP y verificar que las cuotas se respeten.
- Instala `sarg`:
  ```bash
  apt install sarg
  ```
- Genera reportes:
  ```bash
  sarg -l /var/log/squid/access.log
  ```

---

## Notas finales
- Asegúrate de que el servidor LDAP esté accesible y correctamente configurado.
- Monitorea los logs de Squid (`/var/log/squid/access.log`) para depurar problemas.
- Si necesitas limitar por usuario en lugar de IP, considera integrar un sistema de monitoreo más avanzado (como `squidGuard`) o scripts personalizados para mapear usuarios a cuotas específicas.