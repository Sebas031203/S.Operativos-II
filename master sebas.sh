#!/usr/bin/env bash
set -e

# --- VERIFICACIÓN DE ROOT ---
if [ "$EUID" -ne 0 ]; then
  echo "⚠️ Este script debe ejecutarse como root. Usa 'sudo ./master.sh'"
  exit 1
fi

# --- VARIABLES ---
PASSIVE_IP="23.22.16.147"           # <- IP del esclavo
REPL_USER="repluser"
REPL_PASS="TuClaveSegura123!"       # <- contraseña del usuario de replicación
BACKUP_DIR="/root/mariadb_backups"

echo "[1/9] Sincronizando hora con Chrony..."
apt update -y
apt install -y chrony
systemctl enable chrony
systemctl start chrony
timedatectl set-ntp true
date

echo "[2/9] Actualizando sistema..."
apt update && apt upgrade -y

echo "[3/9] Instalando MariaDB, ufw y cron..."
apt install -y mariadb-server mariadb-client ufw cron
systemctl enable cron
systemctl start cron

echo "[4/9] Configurando logs de binlog y server_id..."
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

echo "[5/9] Reiniciando MariaDB..."
systemctl restart mariadb

echo "[6/9] Creando usuario de replicación..."
mariadb -e "CREATE USER IF NOT EXISTS '${REPL_USER}'@'${PASSIVE_IP}' IDENTIFIED BY '${REPL_PASS}';"
mariadb -e "GRANT REPLICATION SLAVE ON . TO '${REPL_USER}'@'${PASSIVE_IP}';"
mariadb -e "FLUSH PRIVILEGES;"

echo "[7/9] Preparando directorio de backups..."
mkdir -p ${BACKUP_DIR}
chmod 700 ${BACKUP_DIR}

echo "[8/9] Generando dump inicial..."
mysqldump --all-databases --single-transaction --master-data=2 --events --routines --triggers > ${BACKUP_DIR}/all_databases.sql
echo "✅ Dump inicial creado en ${BACKUP_DIR}/all_databases.sql"

echo "[9/9] Configurando backup automático por cron cada hora..."
(crontab -l 2>/dev/null; echo "0 * * * * /usr/bin/mysqldump --all-databases --single-transaction --events --routines --triggers > ${BACKUP_DIR}/all_databases.sql") | crontab -
echo "✅ Cron configurado para hacer backups automáticos cada hora"

echo "==============================="
echo "✅ Script maestro completado con éxito."
echo "==============================="