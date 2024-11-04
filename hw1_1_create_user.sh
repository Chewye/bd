#!/bin/bash

. ./func.sh
source .env

TARGET_NODES=()
USER_NODES=()
HOSTS_DATA=""

# Преобразуем строки в массивы
IP_NODES=($IP_NODES)
NAME_NODES=($NAME_NODES)

# Запрашиваем пароли
read -s -p "Введите SSH пароль: " SSH_PASS
echo

read -s -p "Введите пароль для нового пользователя $NEW_USER: " USER_PASS
echo

# Установка необходимых утилит
install_utilities sshpass wget tar rsync


PUBLIC_KEYS="# new keys for $NEW_USER"

# Формируем массив TARGET_NODES и USER_NODES на основе IP_NODES
for IP in "${IP_NODES[@]}"; do
    TARGET_NODES+=("team@$IP")
    USER_NODES+=("$NEW_USER@$IP")
done

# Данные для записи в /etc/hosts
for i in "${!IP_NODES[@]}"; do
  HOSTS_DATA+="${IP_NODES[i]} ${NAME_NODES[i]}\n"
done

# Убираем последний перенос строки и выводим результат
HOSTS_DATA=$(echo -e "$HOSTS_DATA" | sed '$ d')



# Цикл по всем целевым нодам
for NODE in "${TARGET_NODES[@]}"; do
    create_user_on_node "$NODE"
done

# Сбор публичных ключей с каждой ноды
echo "Собираем публичные ключи ..."
for NODE in "${USER_NODES[@]}"; do
#    PUBLIC_KEY=$(sshpass -p "$SSH_PASS" ssh -J "$JUMP_SERVER" "$NODE" "cat ~/.ssh/id_ed25519.pub")
    PUBLIC_KEY=$(sshpass -p "$SSH_PASS" ssh "$NODE" "cat ~/.ssh/id_ed25519.pub")
    PUBLIC_KEYS+="\n$PUBLIC_KEY"
done


# Добавление ключей PUBLIC_KEYS в authorized_keys на каждой ноде
echo "Добавляем публичные ключи ..."
for NODE in "${USER_NODES[@]}"; do
#    sshpass -p "$SSH_PASS" ssh -J "$JUMP_SERVER" "$NODE" bash << EOF
    sshpass -p "$SSH_PASS" ssh "$NODE" bash << EOF

    # Добавляем собранные ключи в authorized_keys
    bash -c 'echo -e "$PUBLIC_KEYS" >> ~/.ssh/authorized_keys'
    # с командой sudo
    # echo "$SSH_PASS" | sudo -S bash -c 'echo -e "$PUBLIC_KEYS" >> ~/.ssh/authorized_keys'

    echo "Ключи добавлены в ~/.ssh/authorized_keys на $NODE."
EOF
done
