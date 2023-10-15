#!/bin/bash

# Définition des noms de conteneurs et IP
CONTAINER_BASE_NAME="galera"
CONTAINER_NAMES=""
CONTAINER_COUNT=3
HAPROXY_CONTAINER="vipgalera"

# il doit y avoir autant d'IP que de $CONTAINER_COUNT !!!
CONTAINER_IPS=("10.58.157.5" "10.58.157.6" "10.58.157.7")
HAPROXY_IP="10.58.157.8"

# Convertir tableau CONTAINER_IPS en chaine de caracteres à virgules
IP_STRING=$(IFS=,; echo "${CONTAINER_IPS[*]}")
CNT=0

# Création de la variable du fichier de conf
read -r -d '' GALERACNF <<EOM
[galera]
# Mandatory settings
wsrep_on = ON
wsrep_provider = /usr/lib/galera/libgalera_smm.so
wsrep_cluster_name = "Galera_Cluster_IT-Connect"
wsrep_replicate_myisam = ON
wsrep_cluster_address = gcomm://$IP_STRING
binlog_format = row
default_storage_engine = InnoDB
innodb_autoinc_lock_mode = 2
innodb_force_primary_key = 1

# Allow server to accept connections on all interfaces.
bind-address = 0.0.0.0

# Optional settings
wsrep_slave_threads = 2
#innodb_flush_log_at_trx_commit = 0
log_error = /var/log/mysql/error-galera.log
EOM

# Création des noms des conteneurs en fonction de $CONTAINER_COUNT
for i in $(seq 1 $CONTAINER_COUNT); do
    CONTAINER_NAMES="$CONTAINER_NAMES $CONTAINER_BASE_NAME$i"
done

# Suppression forcée des conteneurs précédemment créés
for container in $CONTAINER_NAMES; do
    lxc info $container > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Suppression du conteneur $container..."
        lxc stop $container --force
        lxc delete $container
    fi
done

# Création des conteneurs
for container in $CONTAINER_NAMES; do
    echo "Création du conteneur $container..."
    lxc launch ubuntu:20.04 $container
    lxc network attach lxdbr0 $container eth0
    lxc config device set $container eth0 ipv4.address ${CONTAINER_IPS[$CNT]}
    sleep 2
    lxc exec $container -- bash -c "apt-get update >/dev/null && apt-get upgrade -y >/dev/null"
    lxc exec $container -- bash -c "apt-get install -y mariadb-server mariadb-client rsync >/dev/null"
    lxc exec $container -- bash -c "sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf"
    lxc exec $container -- mysql -e "show variables like 'default_storage_engine';"
    lxc exec $container -- bash -c "echo '${GALERACNF}' >/etc/mysql/mariadb.conf.d/60-galera.cnf"
    lxc exec $container -- bash -c "systemctl --no-pager status mariadb.service"
    lxc exec $container -- bash -c "systemctl stop mariadb.service"
    CNT=$((CNT + 1))
done

# Création du cluster
echo "Création du cluster Galera..."
lxc exec galera1 -- bash -c "galera_new_cluster"

# Vérification du  nombre de membres dans le cluster Galera
echo "Hôte(s) actifs dans le cluster..."
lxc exec galera1 -- mysql -e "show status like 'wsrep_cluster_size';"

# Re-Démarrage des noeuds éteints
for i in $(seq 2 $CONTAINER_COUNT); do
	echo "Démarrage du noeud MariaDB marrage du noeud MariaDB $CONTAINER_BASE_NAME$i ..."
	lxc exec $CONTAINER_BASE_NAME$i -- bash -c "systemctl start mariadb.service"
done

sleep 1

# Vérification des membres du cluster
echo "Hôte(s) actifs dans le cluster à présent ..."
lxc exec galera1 -- mysql -e "show status like 'wsrep_cluster_size';"

for i in $(seq 1 $CONTAINER_COUNT); do
	echo "Host $CONTAINER_BASE_NAME$i Status :"
        lxc exec $CONTAINER_BASE_NAME$i -- mysql -e "show status like 'wsrep_local_state_comment';"
done

lxc exec galera1 -- mysql -e "GRANT ALL privileges ON *.* TO 'janusweb'@'%' IDENTIFIED BY 'janusweb' WITH GRANT OPTION;"
lxc exec galera1 -- mysql -e "FLUSH PRIVILEGES;";
lxc exec galera1 -- mysql -e "CREATE USER 'haproxy'@'${HAPROXY_IP}';";
lxc exec galera1 -- mysql -e "FLUSH PRIVILEGES;"

echo "Cluster Galera MariaDB de base prêt."


# Création du conteneur HAProxy
echo "Création du conteneur HAProxy..."
lxc launch ubuntu:20.04 $HAPROXY_CONTAINER
lxc network attach lxdbr0 $HAPROXY_CONTAINER eth0
lxc config device set $HAPROXY_CONTAINER eth0 ipv4.address $HAPROXY_IP
sleep 2
lxc exec $HAPROXY_CONTAINER -- bash -c "apt-get update >/dev/null && apt-get upgrade -y >/dev/null"
lxc exec $HAPROXY_CONTAINER -- bash -c "apt-get install -y haproxy >/dev/null"

# Configuration de HAProxy pour le load balancing de MariaDB
read -r -d '' HAPROXYCNF <<EOM
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend galera_frontend
    bind *:3306
    mode tcp
    default_backend galera_backend

backend galera_backend
    mode tcp
    balance roundrobin
EOM

for i in $(seq 1 $CONTAINER_COUNT); do
    HAPROXYCNF="${HAPROXYCNF}
    server ${CONTAINER_BASE_NAME}${i} ${CONTAINER_IPS[$((i-1))]}:3306 check"
done

lxc exec $HAPROXY_CONTAINER -- bash -c "echo '${HAPROXYCNF}' > /etc/haproxy/haproxy.cfg"
lxc exec $HAPROXY_CONTAINER -- bash -c "systemctl restart haproxy"

echo "Conteneur HAProxy prêt et configuré pour la répartition de charge des instances MariaDB."
