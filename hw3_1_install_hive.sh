#!/bin/bash

. ./func.sh
source .env

# Запрашиваем SSH пароль
read -r -s -p "Введите SSH пароль: " SSH_PASS
echo

IP_NODES=($IP_NODES)

# Формируем массив TARGET_NODES и USER_NODES на основе IP_NODES
for IP in "${IP_NODES[@]}"; do
    TARGET_NODES+=("team@$IP")
    USER_NODES+=("$NEW_USER@$IP")
done

IP_JN="${IP_NODES[0]}"
IP_NN="${IP_NODES[1]}"

# Формируем массив USER_NODES на основе IP_NODES
TARGET_NODES=()
USER_NODES=()
POSTGRES_NODES=()
for IP in "${IP_NODES[@]}"; do
    TARGET_NODES+=("$DEFAULT_USER@$IP")
    USER_NODES+=("$NEW_USER@$IP")
    POSTGRES_NODES+=("$POSTGRES_USER@$IP")
done

TARGET_JN="${TARGET_NODES[0]}"
TARGET_NN="${TARGET_NODES[1]}"

HADOOP_JN="${USER_NODES[0]}"
HADOOP_NN="${USER_NODES[1]}"
POSTGRES_NN="${POSTGRES_NODES[1]}"

HIVE_VERSION="4.0.1"
HIVE_DIR="apache-hive-$HIVE_VERSION-bin"
HIVE_TAR="$HIVE_DIR.tar.gz"
HIVE_URL="https://dlcdn.apache.org/hive/hive-$HIVE_VERSION/$HIVE_TAR"
PSQL_DRIVER="postgresql-42.7.4.jar"
PSQL_DRIVER_URL="https://jdbc.postgresql.org/download/$PSQL_DRIVER"

# Конфиги
DB_NAME="metastore"
DB_HIVE_USER="hive"
DB_HIVE_PASSWORD="hiveMegaPass1010"
HIVE_SITE_CONF=$(cat <<EOF
<configuration>
    <property>
        <name>hive.server2.authentication</name>
        <value>NONE</value>
    </property>
    <property>
        <name>hive.metastore.warehouse.dir</name>
        <value>/user/hive/warehouse</value>
    </property>
    <property>
        <name>hive.server2.thrift.port</name>
        <value>$HIVE_PORT</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:postgresql://$IP_NN:$HIVE_PORT/$DB_NAME</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>org.postgresql.Driver</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>$DB_HIVE_USER</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>$DB_HIVE_PASSWORD</value>
    </property>
</configuration>
EOF
)

# Конфигурация для .profile
PROFILE_HIVE_CONF="
export HIVE_HOME=/home/hadoop/apache-hive-4.0.1-bin
export HIVE_CONF_DIR=\$HIVE_HOME/conf
export HIVE_AUX_JARS_PATH=\$HIVE_HOME/lib/*
export PATH=\$PATH:\$HIVE_HOME/bin
"


# Установка необходимых утилит
install_utilities sshpass wget tar rsync unzip
echo "*****************************************************************************"
echo


# Скачиваем HIVE
download_file "$HIVE_URL" "$HIVE_TAR"
echo
# Скачиваем postgresql driver
download_file "$PSQL_DRIVER_URL" "$PSQL_DRIVER"
echo "*****************************************************************************"
echo

# Копируем архив HIVE
echo "Копируем HIVE на HADOOP_JN..."
sshpass -p "$SSH_PASS" rsync --progress --info=progress2 --human-readable --partial "$HIVE_TAR" "$HADOOP_JN:~"
check_error "Ошибка при копировании HIVE на $HADOOP_JN. Завершаем выполнение."
echo "HIVE успешно скопирован на $HADOOP_JN..."
echo


echo "Распаковываем HIVE на $HADOOP_JN..."
sshpass -p "$SSH_PASS" ssh "$HADOOP_JN" bash << EOF
    if [ -f ~/$HIVE_TAR ]; then
        if [ -d "$HIVE_DIR" ]; then
            echo "Папка $HIVE_DIR уже существует. Удаляем..."
            rm -rf "$HIVE_DIR"
        fi
        tar -xzf ~/$HIVE_TAR
        echo "HIVE успешно установлен на $HADOOP_NN."
        rm -f ~/$HIVE_TAR  # Удаляем архив после распаковки
    else
        echo "Архив $HIVE_TAR не найден на $HADOOP_NN."
    fi
EOF
check_error "Ошибка при распаковке HIVE на $HADOOP_JN. Завершаем выполнение."
echo "HIVE успешно распакован на $HADOOP_JN..."
echo

# Копируем драйвер PostgreSQL
echo "Копируем $PSQL_DRIVER на $HADOOP_JN..."
sshpass -p "$SSH_PASS" rsync --progress --info=progress2 --human-readable --partial "$PSQL_DRIVER" "$HADOOP_JN:~/$HIVE_DIR/lib"
check_error "Ошибка при копировании драйвера PostgreSQL на $HADOOP_JN. Завершаем выполнение."
echo "$PSQL_DRIVER успешно скопирован на $HADOOP_JN..."
echo "*****************************************************************************"
echo


# Установка PostgreSQL на узле TARGET_NN
sshpass -p "$SSH_PASS" ssh "$TARGET_NN" bash << EOF
    echo "Устанавливаем postgresql на $TARGET_NN"
    echo "$SSH_PASS" | sudo -S -p "" apt install -y postgresql
EOF
check_error "Ошибка при установке PostgreSQL на $TARGET_NN. Завершаем выполнение."
echo "PostgreSQL успешно установлен на $TARGET_NN"
echo "*****************************************************************************"
echo


# Установка PostgreSQL Client на узле TARGET_JN
sshpass -p "$SSH_PASS" ssh "$TARGET_JN" bash << EOF
    echo "Устанавливаем postgresql-client-16 на $TARGET_JN"
    echo "$SSH_PASS" | sudo -S -p "" apt install -y postgresql-client-16
EOF
check_error "Ошибка при установке PostgreSQL Client на $TARGET_JN. Завершаем выполнение."
echo "PostgreSQL Client успешно установлен на $TARGET_JN"
echo "*****************************************************************************"
echo


# Создаем базу данных
echo "Создаем базу данных"
sshpass -p "$SSH_PASS" ssh "$TARGET_NN" bash << EOF
    echo "$SSH_PASS" | sudo -S -p "" -u postgres bash -c '
        echo
        psql -c "CREATE DATABASE $DB_NAME;"
        psql -c "CREATE USER $DB_HIVE_USER WITH PASSWORD '\''$DB_HIVE_PASSWORD'\'';"
        psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_HIVE_USER;"
        psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_HIVE_USER;"
    '
EOF

check_error "Ошибка при выполнении команды psql на $POSTGRES_NN. Завершаем выполнение."
echo "База данных успешно создана на $POSTGRES_NN"
echo "*****************************************************************************"
echo


# Определяем значение для listen_addresses
PSQL_LISTEN_IP="listen_addresses = $IP_NN           # what IP address(es) to listen on;"
PG_HBA_CONF="host    metastore       hive            $IP_EXTERNAL/32        password"

# Настройка конфигураций PostgreSQL на узле TARGET_NN
echo "Настройка конфигураций postgresql.conf"
sshpass -p "$SSH_PASS" ssh "$TARGET_NN" bash << EOF
    # Записываем конфигурации
    echo "$SSH_PASS" | sudo -S -p "" bash -c "echo '$PSQL_LISTEN_IP' >> ~/etc/postgresql/16/main/postgresql.conf"
    echo "$SSH_PASS" | sudo -S -p "" bash -c "echo '$PG_HBA_CONF' >> ~/etc/postgresql/16/main/pg_hba.conf"
EOF
echo

# Записываем конфигурации в файл на удаленном сервере

sshpass -p "$SSH_PASS" ssh "$HADOOP_JN" bash << EOF
    echo "Записываем конфигурации ..."
    # Добавляем переменные среды в .profile
    echo -e '$PROFILE_HIVE_CONF' >> ~/.profile

    cd ~/$HIVE_DIR/conf/
    # Записываем конфигурации в hive-site.xml
    echo -e '$HIVE_SITE_CONF' > hive-site.xml

    cd ~/$HIVE_DIR/
    # Создаем директорию warehouse в HDFS
    hdfs dfs -mkdir -p /user/hive/warehouse

    # Устанавливаем права на папки tmp и warehouse
    hdfs dfs -chmod g+w /tmp
    hdfs dfs -chmod g+w /user/hive/warehouse
EOF
# Загружаем новые переменные окружения и проверяем значение переменной HIVE_HOME
sshpass -p "$SSH_PASS" ssh "$HADOOP_JN" "bash -l -c 'source ~/.profile; echo \$HIVE_HOME'"
echo "Конфигурационные настройки HIVE успешно выполнены"
echo "*****************************************************************************"
echo


echo "Запуск HIVE выполнен."
echo "*****************************************************************************"
echo

# Завершение скрипта
echo "Скрипт выполнен успешно."
