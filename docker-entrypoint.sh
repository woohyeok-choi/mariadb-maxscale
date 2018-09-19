#!/bin/bash
set -e

function info() {
    >&2 echo "[$(date "+%Y-%m-%d %H:%M:%S")][Info]" "$@"
}

function warning() {
    >&2 echo "[$(date "+%Y-%m-%d %H:%M:%S")][Warning]" "$@"
}

function error() {
    >&2 echo "[$(date "+%Y-%m-%d %H:%M:%S")][Error]" "$@"
}

MAX_SPLITTER_PORT=3306
ENV CONN_TIMEOUT 3600
ENV PERSIST_POOLMAX 10
ENV PERSIST_MAXTIME 600

SECRETS_FILE="/run/secrets/${SECRETS}"

if [ -f ${SECRETS_FILE} ]; then
    info "Found a secret file: ${SECRETS_FILE}"

    MAXSCALE_USER=$(crudini --get ${SECRETS_FILE} database db_user)
    MAXSCALE_PASSWORD=$(crudini --get ${SECRETS_FILE} database db_password)
    CLUSTER_SERVICES=$(crudini --list --get ${SECRETS_FILE} database cluster_addresses)
    NUM_CLUSTER_NODES=$(crudini --get ${SECRETS_FILE} database cluster_num_nodes)
fi


if [ -z ${MAXSCALE_USER} ] || [ -z ${MAXSCALE_PASSWORD} ]; then
    error "Maxscale account has non-zero user name and password."
    exit 1
fi

IFS=',' read -r -a DATABASE_SERVICES <<< "${CLUSTER_SERVICES}"

for COUNT in {30..0}; do
    info "Try to find galera cluster nodes..."
    DATABASE_ADDRESSES=( )

    for DATABASE_SERVICE in ${DATABASE_SERVICES[@]}; do
        if DATABASE_ADDRESS=$(getent hosts tasks."${DATABASE_SERVICE}" | awk '{print $1}'); then
            read -a DATABASE_ADDRESS <<< $DATABASE_ADDRESS
            DATABASE_ADDRESSES=( "${DATABASE_ADDRESSES[@]}" "${DATABASE_ADDRESS[@]}")
        fi
    done
    if [ -n "${NUM_CLUSTER_NODES}"]; then
        info "Found ${#DATABASE_ADDRESSES[@]} from the total ${NUM_CLUSTER_NODES} nodes: ${DATABASE_ADDRESSES[@]}"
        if [ ${#DATABASE_ADDRESSES[@]} -ge ${NUM_CLUSTER_NODES} ]; then
            break
        fi
        warning "More nodes should be discovered."
    else
        info "Found ${#DATABASE_ADDRESSES[@]}. Try to find more nodes."
    fi

    sleep 5
done

if [ -n "${NUM_CLUSTER_NODES}"] && [ $COUNT -eq 0 ]; then
    error "Failed to find galera cluster nodes. Check the status of a galera cluster."
    exit 1
fi

info "Succeed to find galera cluster nodes."

for DATABASE_ADDRESS in ${DATABASE_ADDRESSES[@]}; do
    for COUNT in {30..0}; do
        info "Try to check connection to a node in the galera cluster: ${DATABASE_ADDRESS}"
        
        if mysql -u${MAXSCALE_USER} -p"${MAXSCALE_PASSWORD}" -h${DATABASE_ADDRESS} -e "SHOW DATABASES;" &> /dev/null; then
            break
        fi
        warning "Failed to connect a node in the galera cluster: ${DATABASE_ADDRESS}. Retry it."
        sleep 3
    done

    if [ ${COUNT} -eq 0 ]; then
        error "Failed to connect a node in the galera cluster: ${DATABASE_ADDRESS}. Please check it."
        exit 1
    fi
    info "Success to connect a node in the galera cluster: ${DATABASE_ADDRESS}."
done

DATABASE_SERVER_NAMES=( )
for COUNT in ${!DATABASE_ADDRESSES[@]}; do
    DATABASE_SERVER_NAMES[${COUNT}]="DBServer-$((${COUNT} + 1))"
done


maxkeys /var/lib/maxscale/
chown -R maxscale:maxscale /var/lib/maxscale/
chown -R maxscale:maxscale /var/log/maxscale/

cat <<EOF > /etc/maxscale/maxscale.cnf
[MaxScale]
threads=auto
auth_connect_timeout=10
auth_read_timeout=10
auth_write_timeout=10
logdir=/var/log/maxscale/
maxlog=1
log_info=1

[Router-Service]
type=service
router=readwritesplit
servers=$(echo "${DATABASE_SERVER_NAMES[@]}" | tr ' ' ',')
user=${MAXSCALE_USER}
passwd=${MAXSCALE_PASSWORD}
enable_root_user=1

[Router-Listener]
type=listener
service=Router-Service
protocol=MariaDBClient
port=${MAX_SPLITTER_PORT}

[MaxAdmin-Service]
type=service
router=cli

[MaxAdmin-Socket-Listener]
type=listener
service=MaxAdmin-Service
protocol=maxscaled
socket=default

[Galera-Monitor]
type=monitor
module=galeramon
servers=$(echo "${DATABASE_SERVER_NAMES[@]}" | tr ' ' ',')
disable_master_failback=true
user=${MAXSCALE_USER}
passwd=${MAXSCALE_PASSWORD}

EOF

for COUNT in ${!DATABASE_SERVER_NAMES[@]}; do
cat <<EOF >> /etc/maxscale/maxscale.cnf
[${DATABASE_SERVER_NAMES[${COUNT}]}]
type=server
address=${DATABASE_ADDRESSES[${COUNT}]}
port=3306
protocol=MariaDBBackend
persistpoolmax=${PERSIST_POOLMAX}
persistmaxtime=${PERSIST_MAXTIME}

EOF

done

info "Print final settings..."

cat /etc/maxscale/maxscale.cnf

info "Complete to write config. Start Maxscale."

maxscale -U maxscale -d -f /etc/maxscale/maxscale.cnf -L /var/log/maxscale
