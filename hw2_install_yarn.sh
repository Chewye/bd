#!/bin/bash

. ./func.sh
source .env

# Запрашиваем SSH пароль для удалённого доступа
read -s -p "Введите SSH пароль: " SSH_PASS
echo


IP_NODES=($IP_NODES)
USER_NODES=()

# Формируем массив TARGET_NODES и USER_NODES на основе IP_NODES
for IP in "${IP_NODES[@]}"; do
    TARGET_NODES+=("team@$IP")
    USER_NODES+=("$NEW_USER@$IP")
done

HADOOP_JN="${USER_NODES[0]}"
HADOOP_NN="${USER_NODES[1]}"
HADOOP_VERSION="3.4.0"

# Конфиги
# Директория с конфигурационными файлами
CONFIG_DIR="bigdata_team-7/config_files"

MAPRED_SITE_CONF="
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>\$HADOOP_HOME/share/hadoop/mapreduce/*:\$HADOOP_HOME/share/hadoop/mapreduce/lib/*</value>
    </property>
</configuration>"

YARN_SITE_CONF="
<configuration>
    <property>
        <name>yarn.nodemanagers.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME</value>
    </property>
</configuration>"


# Установка необходимых утилит
install_utilities sshpass wget tar rsync
echo "*****************************************************************************"
echo

# Копируем конфигурационные файлы на все узлы
for NODE in "${USER_NODES[@]}"; do
    echo "Конфигурационные файлы на $NODE..."
    # Пропускаем копирование конфигурационных файлов для узла HADOOP_JN
    if [[ "$NODE" == "$HADOOP_JN" ]]; then
        continue
    fi

    # Записываем конфигурации в файл на удаленном сервере
    sshpass -p "$SSH_PASS" ssh "$NODE" bash << EOF
        echo "Записываем конфигурации ..."

        cd ~/hadoop-$HADOOP_VERSION/etc/hadoop

        # Записываем конфигурации в mapred-site.xml
        echo -e "$MAPRED_SITE_CONF" > mapred-site.xml

        # Записываем конфигурации в yarn-site.xml
        echo -e "$YARN_SITE_CONF" > yarn-site.xml

EOF

    echo "Конфигурационные файлы успешно записаны на $NODE."
    echo "*****************************************************************************"
    echo
done

# Подключаемся к NameNode для запуска HDFS, YARN, DataHistory
echo "Подключаемся к $HADOOP_NN для запуска HDFS, YARN, DataHistory..."
sshpass -p "$SSH_PASS" ssh "$HADOOP_NN" bash << EOF
    echo "Запускаем распределенную файловую систему HDFS, YARN, DataHistory..."
    ~/hadoop-$HADOOP_VERSION/sbin/start-dfs.sh
    ~/hadoop-$HADOOP_VERSION/sbin/start-yarn.sh
    ~/hadoop-$HADOOP_VERSION/bin/mapred --daemon start historyserver
    echo "Запуск HDFS, YARN, DataHistory завершен."
    echo "Проверка запущенных процессов Java на $HADOOP_NN:"
    jps
EOF

echo "Подключение и запуск HDFS, YARN, DataHistory на $HADOOP_NN завершены."
echo "*****************************************************************************"
echo

# Настройка конфигурации YARN
echo "Копируем файл конфигурации YARN и вносим изменения..."
echo "$SSH_PASS" | sudo -S -p "" cp /etc/nginx/sites-available/default /etc/nginx/sites-available/ya
echo "$SSH_PASS" | sudo -S -p "" cp /etc/nginx/sites-available/default /etc/nginx/sites-available/dh

# Очистка содержимого файлов конфигурации
echo "$SSH_PASS" | sudo -S -p "" truncate -s 0 /etc/nginx/sites-available/ya
echo "$SSH_PASS" | sudo -S -p "" truncate -s 0 /etc/nginx/sites-available/dh

# Запись новых конфигураций в файлы
echo "$SSH_PASS" | sudo -S -p "" bash -c "cat $CONFIG_DIR/ya > /etc/nginx/sites-available/ya"
echo "$SSH_PASS" | sudo -S -p "" bash -c "cat $CONFIG_DIR/dh > /etc/nginx/sites-available/dh"

# Создание символических ссылок для активных конфигураций
echo "$SSH_PASS" | sudo -S -p "" ln -sf /etc/nginx/sites-available/ya /etc/nginx/sites-enabled/ya
echo "$SSH_PASS" | sudo -S -p "" ln -sf /etc/nginx/sites-available/dh /etc/nginx/sites-enabled/dh

# Перезагрузка Nginx для применения изменений
echo "$SSH_PASS" | sudo -S -p "" systemctl restart nginx
echo "Конфигурационные настройки YARN успешно выполнены."
echo "*****************************************************************************"
echo

# Проверка статуса процесса Java на каждой ноде
for NODE in "${USER_NODES[@]}"; do
    echo "Подключаемся к $NODE для проверки процессов Java через команду jps..."
    sshpass -p "$SSH_PASS" ssh "$NODE" bash << EOF
        echo "Запущенные процессы Java на $NODE:"
        jps
EOF
    echo "Проверка завершена для $NODE."
    echo "*****************************************************************************"
    echo
done

echo "Скрипт выполнен успешно."
