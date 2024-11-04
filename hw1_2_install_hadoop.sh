#!/bin/bash

. ./func.sh
source .env

# Запрашиваем SSH пароль
read -s -p "Введите SSH пароль: " SSH_PASS
echo

USER_NODES=()

# Преобразуем строки в массивы
IP_NODES=($IP_NODES)

# Формируем массив TARGET_NODES и USER_NODES на основе IP_NODES
for IP in "${IP_NODES[@]}"; do
    TARGET_NODES+=("team@$IP")
    USER_NODES+=("$NEW_USER@$IP")
done

IP_NN="${IP_NODES[1]}"
HADOOP_JN="${USER_NODES[0]}"
HADOOP_NN="${USER_NODES[1]}"
HADOOP_VERSION="3.4.0"
HADOOP_TAR="hadoop-$HADOOP_VERSION.tar.gz"
HADOOP_URL="https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/$HADOOP_TAR"

# Конфиги
CORE_SITE_CONF="
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://$IP_NN:9000</value>
    </property>
</configuration>"

HDFS_SITE_CONF="
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>3</value>
    </property>
</configuration>"

WORKERS_CONF="
team-7-nn
team-7-dn-00
team-7-dn-01
"

HADOOP_ENV_CONF="export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"

PROFILE_HADOOP_CONF="
export HADOOP_HOME=/home/hadoop/hadoop-3.4.0
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
"

# Установка необходимых утилит
install_utilities sshpass wget tar rsync
echo "*****************************************************************************"
echo

# Скачиваем Hadoop локально
download_file "$HADOOP_URL" "$HADOOP_TAR"
echo "*****************************************************************************"
echo

# Копируем архив на все ноды и распаковываем
for NODE in "${USER_NODES[@]}"; do
    echo "Копируем Hadoop на $NODE..."
#    sshpass -p "$SSH_PASS" scp "$HADOOP_TAR" "$NODE:~"
    sshpass -p "$SSH_PASS" rsync --progress --info=progress2 --human-readable --partial "$HADOOP_TAR" "$NODE:~"
    echo "Hadoop успешно скопирован на $NODE..."
    echo

    echo "Распаковываем Hadoop на $NODE..."
    sshpass -p "$SSH_PASS" ssh "$NODE" bash << EOF
        if [ -f ~/$HADOOP_TAR ]; then
            if [ -d "hadoop-$HADOOP_VERSION" ]; then
                echo "Папка hadoop-$HADOOP_VERSION уже существует. Удаляем..."
                rm -rf "hadoop-$HADOOP_VERSION"
            fi
            tar -xzf ~/$HADOOP_TAR
            rm -f ~/$HADOOP_TAR  # Удаляем архив после распаковки
            # Удаляем старые данные
            cd ~/hadoop-$HADOOP_VERSION
            rm -rf /tmp/hadoop-hadoop/dfs/data/*
        else
            echo "Архив $HADOOP_TAR не найден на $NODE."
        fi
EOF
    echo "Hadoop успешно установлен на $NODE..."
    echo

    # Записываем конфигурации в файл на удаленном сервере
    sshpass -p "$SSH_PASS" ssh "$NODE" bash << EOF
        echo "Записываем конфигурации ..."

        # Добавляем переменные среды в .profile
        echo -e '$PROFILE_HADOOP_CONF' >> ~/.profile

        cd ~/hadoop-$HADOOP_VERSION/etc/hadoop

        # Записываем конфигурации в core-site.xml
        echo -e '$CORE_SITE_CONF' > core-site.xml

        # Записываем конфигурации в hdfs-site.xml
        echo -e '$HDFS_SITE_CONF' > hdfs-site.xml

        # Записываем конфигурации в workers
        echo -e '$WORKERS_CONF' > workers

        # Записываем конфигурации в hadoop-env.sh
        echo -e '$HADOOP_ENV_CONF' >> hadoop-env.sh
EOF

    echo "Конфигурационные файлы успешно скопированы на $NODE."

    echo "Проверка переменных окружения на $NODE..."
    sshpass -p "$SSH_PASS" ssh "$NODE" 'bash -l -c "source ~/.profile; echo \$JAVA_HOME"'
    echo "*****************************************************************************"
    echo
done


# Подключаемся к name node
echo "Подключаемся к $HADOOP_NN для форматирования NameNode и запуска HDFS..."

sshpass -p "$SSH_PASS" ssh "$HADOOP_NN" bash << EOF
    cd ~/hadoop-$HADOOP_VERSION

    echo "Форматируем NameNode..."
    echo "n" | bin/hdfs namenode -format
    echo "Форматирование NameNode завершено."

    echo "Запускаем распределенную файловую систему HDFS..."
    sbin/start-dfs.sh
    echo "Запуск HDFS завершен."

    echo "Проверка запущенных процессов Java на $HADOOP_NN:"
    jps
EOF

echo "Подключение и операции на $HADOOP_NN завершены."
echo "*****************************************************************************"
echo

# Проверяем вывод команды jps на каждой ноде
for NODE in "${USER_NODES[@]}"; do
    echo "Подключаемся к $NODE для проверки процесса через команду jps..."
    sshpass -p "$SSH_PASS" ssh "$NODE" bash << EOF
        echo "Запущенные процессы Java на $NODE:"
        jps
EOF
    echo "Проверка завершена для $NODE."
    echo "*****************************************************************************"
    echo
done

# Останавливаем HDFS
echo "Останавливаем распределенную файловую систему HDFS..."
sshpass -p "$SSH_PASS" ssh "$HADOOP_NN" bash << EOF
    cd ~/hadoop-$HADOOP_VERSION
    sbin/stop-dfs.sh
EOF
echo "HDFS остановлен."
echo

# Копируем файл конфигурации Nginx и делаем нужные изменения
# создание копии файла конфигурации Nginx
echo "$SSH_PASS" | sudo -S -p "" cp /etc/nginx/sites-available/default /etc/nginx/sites-available/nn

# Очистка содержимого и запись содержимого файла nn из каталога конфигурации
echo "$SSH_PASS" | sudo -S -p "" truncate -s 0 /etc/nginx/sites-available/nn

echo "$SSH_PASS" | sudo -S -p "" bash -c "cat $CONFIG_DIR/nn >> /etc/nginx/sites-available/nn"

# Создание символической ссылки - добавление конфигурации в директорию активных конфигураций.
echo "$SSH_PASS" | sudo -S -p "" ln -sf /etc/nginx/sites-available/nn /etc/nginx/sites-enabled/nn
echo
# Перезагрузка Nginx для принятия изменений конфигурации
echo "$SSH_PASS" | sudo -S -p "" systemctl reload nginx
echo
echo "Конфигурационные настройки Nginx успешно выполнены"
echo "*****************************************************************************"
echo

echo "Скрипт выполнен успешно."

