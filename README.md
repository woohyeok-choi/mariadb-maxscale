# woohyeokchoi/mariadb-maxscale

This image automatically setup [MariaDB](https://mariadb.com/products/technology/maxscale) Maxscale for connection routing with Galera Clusters.

## How to use

```bash
docker run -d -p 3306:3306 -p 8989:8989 -p 6603:6603\
            -n
            -e MAXSCALE_USER=your-maxscale-name
            -e MAXSCALE_PASSWORD=your-maxscale-password
            -e CLUSTER_SERVICES=service1,service2,service3
            -e NUM_CLUSTER_NODES=3
```

If successfuly setup, you can connect MariaDB client with 3306 port. Also, you can see nodes in a cluster with [Maxadmin](https://maxscale.readthedocs.io/en/stable/Documentation/Reference/MaxAdmin) like below:

```bash
docker exec -it your-maxscale-container-name maxadmin list servers
```

## Prerequistes

* You should setup your own galera clusters (I strongly recommend this [image](https://github.com/woohyeok-choi/mariadb-galera-cluster)).
* The number of nodes should be equal to or greater than 3.
* Each node should be run as a docker service, and share same network interface with this image.
* Each node should open a port, 3306
* Each node in clusters should grant Maxscale's access like below:

```sql
CREATE USER '${MAXSCALE_USER}'@'%' IDENTIFIED BY '${MAXSCALE_PASSWORD}' ;
GRANT SELECT ON mysql.user TO '${MAXSCALE_USER}'@'%' ;
GRANT SELECT ON mysql.db TO '${MAXSCALE_USER}'@'%' ;
GRANT SELECT ON mysql.tables_priv TO '${MAXSCALE_USER}'@'%' ;
GRANT CREATE ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT SHOW DATABASES ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT REPLICATION CLIENT ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT DROP ON *.* TO '${MAXSCALE_USER}'@'%' ;
FLUSH PRIVILEGES ;
```

I strongly recommend to use this image in a docker compose like below:

```yaml
version: '3.5'
services:
 maxscale:
    image: woohyeokchoi/mariadb-maxscale
    environment:
      MAXSCALE_USER: maxscale
      MAXSCALE_PASSWORD: maxscale
      CLUSTER_SERVICES: cluster-doner,cluster-joiners
      NUM_CLUSTER_NODES: 3
    volumes:
      - "/home/server/logs/:/var/log/maxscale"
    deploy:
      replicas: 1
      restart_policy:
        delay: 5s
        max_attempts: 10
      placement:
        constraints:
          - node.role == manager
    ports:
      - "3306:3306"
    networks:
      - db-network

  cluster-doner:
    image: woohyeokchoi/mariadb-galera-cluster
    command: ["mysqld", "--wsrep-new-cluster"]
    environment:
      GALERA_CLUSTER_NAME: galera_cluster
      MAXSCALE_USER: maxscale
      MAXSCALE_PASSWORD: maxscale
    secrets:
      - settings
    deploy:
      replicas: 1
      restart_policy:
        delay: 5s
        max_attempts: 5
      placement:
        constraints:
          - node.role == manager
    networks:
      - db-network

  cluster-joiners:
    image: woohyeok.choi//mariadb-galera-cluster
    environment:
      GALERA_DONER_SERVICE: cluster-doner
      GALERA_CLUSTER_NAME: galera_cluster
      MAXSCALE_USER: maxscale
      MAXSCALE_PASSWORD: maxscale
    command: ["mysqld"]
    secrets:
      - settings
    deploy:
      replicas: 2
      restart_policy:
        delay: 5s
        max_attempts: 10
    networks:
      - db-network
networks:
  db-network:
    driver: overlay
    attachable: true
```

And, run command below:

```bash
docker stack deploy --compose-file this-file-name stack-name
```

## Environment variables

* (require) **MAXSCALE_USER**: a user name that connects with galera clusters.
* (require) **MAXSCALE_PASSWORD**: a user password that connects with galera clusters.
* (require) **CLUSTER_SERVICES**: list of nodes (e.g., container names, service names in docker deploy or docker swarm). It should be separated by comma without space (e.g., service1,service2; not service1, service2).
* **NUM_CLUSTER_NODES**: the number of cluster nodes. If not set, this tries to found nodes until 150 sec.
* **SECRETS**: If you want to use **Docker Secrets**, you should specify secret name here. The secret file should be a INI format like below:

```bash
[database]
user = maxscale-user-name
password = maxscale-user-password
cluster_addresses = service-name-of-your-galera-cluster
cluster_num_nodes = number-of-nodes-in-your galera-cluster
```
