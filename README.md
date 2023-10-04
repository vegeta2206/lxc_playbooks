# lxc_playbooks

Chaque répertoire contient un script en bash permettant depuis un hôte exécutant LXC d'automatiser la créations d'environnements containérisés.

# make_galera_cluster

# Description
Le script vous permet de créer un cluster MariaDB inspiré du très bon [article](https://www.it-connect.fr/comment-mettre-en-place-mariadb-galera-cluster-sur-debian-11/) de Florian BURNEL en 3 min sous LXC 

# Etape 1

**3 noeuds MariaDB vont être créés sous ubuntu 20.04** 

Dans mon script Bash, j'ai configuré les IPs que je souhaitais utiliser pour mes 3 noeuds, bien évidemment en dehors de mon pool DHCP LXC
Pour voir si vous avez un range DHCP configuré, la commande est LXC :

```
$ lxc network show lxdbr0

# vous devriez avoir une sortie standard comme celle-ci si vous avez restreint le pool DHCP :

config:
  ipv4.address: 10.58.157.1/24
  ipv4.dhcp.ranges: 10.58.157.50-10.58.157.200 <= ici
  ipv4.nat: "true"
  ipv6.address: none
description: ""
name: lxdbr0
type: bridge
used_by:
- /1.0/profiles/default
managed: true
status: Created
locations:
- none

# par defaut, LXC prend un réseau complet donc /24
C'est donc moi qui ait configuré ce range via :

lxc network set lxdbr0 ipv4.dhcp.ranges 10.58.157.50-10.58.157.200


```

Les 3 IPs qui seront utilisées sont spécifiés sur la ligne du script bash :

```
CONTAINER_BASE_NAME="galera"
CONTAINER_COUNT=3
CONTAINER_IPS=("10.58.157.5" "10.58.157.6" "10.58.157.7")
```

J'ai choisi également de construire les noms de chaque noeud MariaDB sous la forme : `galera1, galera2 et galera3` d'où les 2 variables supplémentaires.

**Maintenant vous savez comment cela marche :
Il suffit de lancer le script :** 

```
### ATTENTION : Le script toute trace de précédent container nommé galera1, 2 ou 3 !!!

$ ./create_galera_cluster.sh

```

3 min après vous avez un cluster MariaDB opérationnel :)

## Pour vérifier :
```
$ for i in $(lxc ls -f csv -cn|grep galera);do echo "$i:"; lxc exec $i -- ss -tlpn|grep mysql;echo;done

galera1:
LISTEN    0         80                 0.0.0.0:3306             0.0.0.0:*        users:(("mysqld",pid=2953,fd=30))                                              
LISTEN    0         128                0.0.0.0:4567             0.0.0.0:*        users:(("mysqld",pid=2953,fd=11))                                              

galera2:
LISTEN    0         80                 0.0.0.0:3306             0.0.0.0:*        users:(("mysqld",pid=2958,fd=31))                                              
LISTEN    0         128                0.0.0.0:4567             0.0.0.0:*        users:(("mysqld",pid=2958,fd=11))                                              

galera3:
LISTEN    0         80                 0.0.0.0:3306             0.0.0.0:*        users:(("mysqld",pid=2954,fd=32))                                              
LISTEN    0         128                0.0.0.0:4567             0.0.0.0:*        users:(("mysqld",pid=2954,fd=11))                                             
```

#
