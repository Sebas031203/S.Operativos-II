#!/usr/bin/env bash
set -e

# --- VERIFICACIÓN DE ROOT ---
if [ "$EUID" -ne 0 ]; then
  echo "⚠️ Este script debe ejecutarse como root. Usa 'sudo ./slave.sh'"
  exit 1
fi

# --- VARIABLES ---
MASTER_IP="54.147.128.12"
REPL_USER="repluser"
REPL_PASS="TuClaveSegura123!"
SLAVE_ID=2
BACKUP_DIR="/root/mariadb_backups"
LOG_DIR="/var/log/mysql"
DUMP_FILE="$BACKUP_DIR/all_databases.sql"

echo "==============================="
echo "   CONFIGURACIÓN DEL ESCLAVO"
echo "==============================="
echo "Flujo de replicación:"
echo "Maestro (server-id=1, IP=$MASTER_IP) --> Dump inicial --> Esclavo (server-id=$SLAVE_ID) --> Replica en tiempo real"
echo "==============================="

# 1. Actualizar sistema e instalar MariaDB
echo "[1/7] Actualizando sistema..."
apt update && apt upgrade -y
apt install -y mariadb-server mariadb-client ufw ntp

# 2. Preparar directorios
echo "[2/7] Preparando directorios de backups y logs..."
mkdir -p "$BACKUP_DIR"
mkdir -p "$LOG_DIR"
chown -R mysql:mysql "$BACKUP_DIR" "$LOG_DIR"
chmod 700 "$BACKUP_DIR"

# 3. Configurar MariaDB como esclavo
echo "[3/7] Configurando MariaDB como esclavo..."
cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf.bak

cat > /etc/mysql/mariadb.conf.d/50-server.cnf <<EOF
[mysqld]
server-id = $SLAVE_ID
bind-address = 0.0.0.0
log_bin = $LOG_DIR/mariadb-bin
log_bin_index = $LOG_DIR/mariadb-bin.index
binlog_format = ROW
innodb_file_per_table = 1
default_storage_engine = InnoDB
relay_log = $LOG_DIR/relay-bin
relay_log_index = $LOG_DIR/relay-bin.index
read_only = 1
EOF

systemctl restart mariadb

# 4. Configurar firewall
echo "[4/7] Configurando firewall..."
ufw allow from "$MASTER_IP" to any port 3306 proto tcp
ufw --force enable

# 5. Importar dump inicial del maestro
echo "[5/7] Importando dump inicial del maestro..."
if [ -f "$DUMP_FILE" ]; then
    mariadb < "$DUMP_FILE"
else
    echo "❌ Dump $DUMP_FILE no encontrado. Copia el dump del maestro primero con:"
    echo "scp root@$MASTER_IP:$DUMP_FILE $BACKUP_DIR/"
    exit 1
fi

# 6. Configurar replicación
echo "[6/7] Configurando replicación en tiempo real..."
MASTER_LOG_FILE="mariadb-bin.000001"
MASTER_LOG_POS=4

mariadb -e "STOP SLAVE;"
mariadb -e "CHANGE MASTER TO
    MASTER_HOST='$MASTER_IP',
    MASTER_USER='$REPL_USER',
    MASTER_PASSWORD='$REPL_PASS',
    MASTER_LOG_FILE='$MASTER_LOG_FILE',
    MASTER_LOG_POS=$MASTER_LOG_POS;"
mariadb -e "START SLAVE;"

# 7. Verificación
echo "[7/7] Verificando estado del esclavo..."
mariadb -e "SHOW SLAVE STATUS\G"

echo "==============================="
echo "✅ Servidor esclavo configurado con MariaDB + InnoDB."
echo "==============================="
