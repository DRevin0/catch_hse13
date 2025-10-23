#!/bin/bash

CURRENT_DIR="$(pwd)"
TEST_DISK_MOUNT="$CURRENT_DIR/test_disk"
TEST_LOG_DIR="$TEST_DISK_MOUNT/log"
BACKUP_DIR="$CURRENT_DIR/backup"
SCRIPT_PATH="./arscript.sh"

#cоздаем образ диска и монтируем его
echo "Создаем временный раздел диска для тестов..."
mkdir -p "$TEST_DISK_MOUNT"

#cоздаем файл-образ диска размером 1GB
dd if=/dev/zero of="$CURRENT_DIR/test_disk.img" bs=1M count=1000 status=none

#форматируем в ext4
mkfs.ext4 -F "$CURRENT_DIR/test_disk.img" > /dev/null 2>&1

#vонтируем образ
sudo mount -o loop "$CURRENT_DIR/test_disk.img" "$TEST_DISK_MOUNT"

#yнастраиваем права
sudo chown $USER:$USER "$TEST_DISK_MOUNT"

#создаем тестовые папки
mkdir -p "$TEST_LOG_DIR"
mkdir -p "$BACKUP_DIR"

#очистка перед началом
echo "Очищаем тестовую папку..."
rm -f "$TEST_LOG_DIR"/*
rm -f "$BACKUP_DIR"/*

#создание файлов
echo "Создаем тестовые файлы общим размером ~0.5GB..."
cd "$TEST_LOG_DIR"

#создаем 2500 файлов по 200KB = 500MB (0.5GB)
for i in {1..2500}; do
    dd if=/dev/zero of="file_$i.txt" bs=200K count=1 status=none
done

echo "Тестовые файлы созданы. Общий размер:"
du -sh "$TEST_LOG_DIR"

echo "Использование раздела диска:"
df -h "$TEST_DISK_MOUNT"

#возвращаемся в исходную директорию
cd - > /dev/null

echo "========================================"
echo "Тест 1: Проверка с порогом 70%"
"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 70

echo "========================================"
echo "Тест 2: Проверка с порогом 55%"
"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 55

echo "========================================"
echo "Тест 3: Проверка с порогом 20%"
"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 20

echo "========================================"
echo "Тест 4: Проверка с порогом 10%"
"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 10

echo "========================================"
echo "Все тесты завершены"
echo "Проверьте архивы в: $BACKUP_DIR"
echo "Остаточные файлы в тестовой папке: $(ls -la "$TEST_LOG_DIR" | wc -l)"
echo "Созданные архивы:"
ls -la "$BACKUP_DIR"

#очистка после тестов
echo "========================================"
echo "Очистка временного раздела..."
sudo umount "$TEST_DISK_MOUNT"
rm -f "$CURRENT_DIR/test_disk.img"
rmdir "$TEST_DISK_MOUNT"
echo "Временный раздел удален"
