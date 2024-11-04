#!/bin/bash

# Проверим, что скрипты исполняемые 
chmod +x hw1_1_create_user.sh hw1_2_install_hadoop.sh hw2_install_yarn.sh hw3_1_install_hive.sh

# Запуск скриптов по порядку
./hw1_1_create_user.sh
./hw1_2_install_hadoop.sh
./hw2_install_yarn.sh
./hw3_1_install_hive.sh