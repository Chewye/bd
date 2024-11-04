#!/bin/bash

install_utilities() {
    for utility in "$@"; do
        if ! command -v "$utility" &> /dev/null; then
            echo "$utility не установлен. Устанавливаем..."
            echo "$SSH_PASS" | sudo -S apt update -y
            echo "$SSH_PASS" | sudo -S apt install -y "$utility"
        else
            echo "$utility уже установлен."
        fi
    done
}


# Функция для выполнения команд на целевой ноде
create_user_on_node() {
    local NODE="$1"
    echo "Подключаемся к $NODE..."

#    sshpass -p "$SSH_PASS" ssh -J "$JUMP_SERVER" "$NODE" bash << EOF
#    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -J "$JUMP_SERVER" "$NODE" bash << EOF
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$NODE" bash << EOF

    # Очищаем файл /etc/hosts
    echo "$SSH_PASS" | sudo -p "" -S truncate -s 0 /etc/hosts

    # Записываем данные хостов в /etc/hosts
    echo "$SSH_PASS" | sudo -S bash -c 'echo -e "$HOSTS_DATA" >> /etc/hosts'


    # Проверяем, существует ли пользователь hadoop
    if getent passwd "$NEW_USER" > /dev/null; then

        echo "Пользователь $NEW_USER уже существует. Удаляем..."
        echo "$SSH_PASS" | sudo -S -p "" deluser --remove-home "$NEW_USER" > /dev/null
    fi

    # Создаем нового пользователя hadoop
    echo "$SSH_PASS" | sudo -S adduser "$NEW_USER" --gecos "" --disabled-password > /dev/null

    # Устанавливаем пароль для пользователя hadoop
    echo "$NEW_USER:$USER_PASS" | sudo chpasswd

    # Переключаемся на пользователя hadoop и создаем SSH-ключи
    sudo -i -u "$NEW_USER" bash << USER_SHELL

    # Создаем SSH-ключи
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q

    # Устанавливаем права на закрытый ключ
    chmod 600 ~/.ssh/id_ed25519

    # Устанавливаем права на открытый ключ
    chmod 644 ~/.ssh/id_ed25519.pub

USER_SHELL
EOF

    echo "Пользователь $NEW_USER создан, и SSH-ключи сгенерированы на $NODE."
    echo "*****************************************************************************"
    echo
}


# Функция для проверки ошибок
check_error() {
    if [[ $? -ne 0 ]]; then
        echo "$1"
        exit 1
    fi
}


# Функция для скачивания файла с попытками
download_file() {
    local url="$1"
    local filename="$2"
    local max_attempts=3
    local attempt=1

    if [[ -f "$filename" ]]; then
        echo "Файл $filename уже существует локально, пропускаем скачивание."
        return
    fi

    echo "Файл $filename не найден. Скачиваем из $url..."

    # Пытаемся скачать файл с ограничением по количеству попыток
    while (( attempt <= max_attempts )); do
        echo "Попытка $attempt из $max_attempts..."
        wget "$url" -O "$filename"

        check_error "Ошибка при скачивании $filename. Попробуем еще раз..."

        echo "$filename успешно скачан."
        return
    done

    echo "Не удалось скачать $filename после $max_attempts попыток. Завершаем выполнение."
    exit 1
}