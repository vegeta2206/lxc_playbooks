#!/bin/bash

# Définition des noms de conteneurs et IP
CONTAINER_BASE_NAME="galera"
CONTAINER_COUNT=3
CONTAINER_NAMES=""
CONTAINER_IPS=("10.58.157.5" "10.58.157.6" "10.58.157.7")

# Convert CONTAINER_IPS array to comma separated string
IP_STRING=$(IFS=,; echo "${CONTAINER_IPS[*]}")


CNT=0
read -r -d '' GALERACNF <<EOM
[galera]
# Mandatory settings
wsrep_on = ON
wsrep_provider = /usr/lib/galera/libgalera_smm.so
wsrep_cluster_name = "Galera_Cluster_IT-Connect"
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

# Création des noms des conteneurs
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
    lxc exec $container -- bash -c "apt-get update >/dev/null && apt-get upgrade -y /dev/null"
    lxc exec $container -- bash -c "apt-get install -y mariadb-server mariadb-client rsync >/dev/null"
    lxc exec $container -- bash -c "sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf"
    lxc exec $container -- mysql -e "show variables like 'default_storage_engine';"
    lxc exec $container -- bash -c "echo '${GALERACNF}' >/etc/mysql/mariadb.conf.d/60-galera.cnf"
    lxc exec $container -- bash -c "systemctl --no-pager status mariadb.service"
    lxc exec $container -- bash -c "systemctl stop mariadb.service"
    CNT=$((CNT + 1))
done


lxc exec galera1 -- bash -c "galera_new_cluster"
lxc exec galera1 -- mysql -e "show status like 'wsrep_cluster_size';"

for i in $(seq 2 $CONTAINER_COUNT); do
	lxc exec $CONTAINER_BASE_NAME$i -- bash -c "systemctl start mariadb.service"
done

lxc exec galera1 -- mysql -e "show status like 'wsrep_cluster_size';"
lxc exec galera1 -- mysql -e "show status like 'wsrep_local_state_comment';"
lxc exec galera2 -- mysql -e "show status like 'wsrep_local_state_comment';"
lxc exec galera3 -- mysql -e "show status like 'wsrep_local_state_comment';"

echo "Cluster Galera MariaDB de base prêt."

