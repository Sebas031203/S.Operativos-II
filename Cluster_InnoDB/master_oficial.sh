#!/usr/bin/env bash
set -e

# --- VARIABLES ---
PASSIVE_IP="192.168.56.57"   # <- reemplaza con IP del slave
REPL_USER="repluser"
REPL_PASS="TuClaveSegura123!"  # <- reemplaza
BACKUP_DIR="/root/mariadb_backups"

echo "[1/8] Sincronizando hora con NTP..."
apt update -y
apt install -y ntp
systemctl enable ntp
systemctl start ntp
timedatectl set-ntp true
date

echo "[2/8] Actualizando sistema..."
apt update && apt upgrade -y

echo "[3/8] Instalando MariaDB y ufw..."
apt install -y mariadb-server mariadb-client ufw

echo "[4/8] Configurando logs de binlog y server_id..."
mkdir -p /var/log/mysql
chown mysql:mysql /var/log/mysql
chmod 750 /var/log/mysql

cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf.bak

cat >> /etc/mysql/mariadb.conf.d/50-server.cnf <<EOF

# --- configuración para replicación ---
[mysqld]
server-id = 1
bind-address = 0.0.0.0
log_bin = /var/log/mysql/mariadb-bin
log_bin_index = /var/log/mysql/mariadb-bin.index
binlog_format = ROW
innodb_file_per_table = 1
expire_logs_days = 7
EOF

echo "[5/8] Reiniciando MariaDB..."
systemctl restart mariadb

echo "[6/8] Creando usuario de replicación..."
mariadb -e "CREATE USER IF NOT EXISTS '${REPL_USER}'@'${PASSIVE_IP}' IDENTIFIED BY '${REPL_PASS}';"
mariadb -e "GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'${PASSIVE_IP}';"
mariadb -e "FLUSH PRIVILEGES;"

echo "[7/8] Preparando directorio de backups..."
mkdir -p ${BACKUP_DIR}
chmod 700 ${BACKUP_DIR}

echo "[8/8] Generando dump inicial..."
mysqldump --all-databases --single-transaction --master-data=2 --events --routines --triggers > ${BACKUP_DIR}/all_databases.sql
echo "✅ Dump inicial creado en ${BACKUP_DIR}/all_databases.sql"

# --- Configurar cron para backup automático cada hora ---
(crontab -l 2>/dev/null; echo "0 * * * * /usr/bin/mysqldump --all-databases --single-transaction --events --routines --triggers > ${BACKUP_DIR}/all_databases.sql") | crontab -

echo "El cron hará backups automáticos cada hora."
