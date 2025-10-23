#!/bin/bash

CURRENT_DIR="$(pwd)"
TEST_DISK_MOUNT="$CURRENT_DIR/test_disk"
TEST_LOG_DIR="$TEST_DISK_MOUNT/log"
BACKUP_DIR="$CURRENT_DIR/backup"
SCRIPT_PATH="./arscript.sh"

# Функция для проверки результатов теста
check_test_result() {
    local test_name="$1"
    local threshold="$2"
    
    echo "=== Результаты теста: $test_name (порог: $threshold%) ==="
    
    # Проверяем что скрипт завершился успешно
    if [ $? -eq 0 ]; then
        echo "Скрипт завершился успешно"
    else
        echo "Скрипт завершился с ошибкой"
        return 1
    fi
    
    # Проверяем созданные архивы
    local backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)
    echo "Создано архивов: $backup_count"
    
    # Проверяем оставшиеся файлы
    local remaining_files=$(find "$TEST_LOG_DIR" -type f 2>/dev/null | wc -l)
    echo "Осталось файлов: $remaining_files"
    
    # Проверяем размер папки /log
    local log_size=$(du -sb "$TEST_LOG_DIR" 2>/dev/null | cut -f1)
    local log_size_gb=$(echo "scale=2; $log_size/1024/1024/1024" | bc)
    echo "Размер папки /log: ${log_size_gb} GB"
    
    echo ""
}

# Создаем тестовое окружение
echo "=== ПОДГОТОВКА ТЕСТОВОГО ОКРУЖЕНИЯ ==="

# Создаем точку монтирования
mkdir -p "$TEST_DISK_MOUNT"

echo "Создаем временный раздел диска для тестов..."
# Создаем файл-образ диска размером 1GB
dd if=/dev/zero of="$CURRENT_DIR/test_disk.img" bs=1M count=1000 status=none

# Форматируем в ext4
mkfs.ext4 -F "$CURRENT_DIR/test_disk.img" > /dev/null 2>&1

# Монтируем образ
sudo mount -o loop "$CURRENT_DIR/test_disk.img" "$TEST_DISK_MOUNT"

# Настраиваем права
sudo chown $USER:$USER "$TEST_DISK_MOUNT"

# Создаем тестовые папки
mkdir -p "$TEST_LOG_DIR"
mkdir -p "$BACKUP_DIR"

# Проверяем существование тестируемого скрипта
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Ошибка: Скрипт $SCRIPT_PATH не найден!"
    exit 1
fi

# Делаем скрипт исполняемым
chmod +x "$SCRIPT_PATH"

echo "=== ЗАПУСК ТЕСТОВ ==="

# Тест 1: Проверка с порогом 70%
echo "========================================"
echo "Тест 1: Проверка с порогом 70%"

# Очищаем перед тестом
rm -rf "$TEST_LOG_DIR"/* "$BACKUP_DIR"/*

# Создаем файлы общим размером 0.5GB в папке /log
echo "Создаем тестовые файлы в /log..."
cd "$TEST_LOG_DIR"
for i in {1..500}; do
    dd if=/dev/urandom of="logfile_$i.log" bs=1M count=1 status=none 2>/dev/null
done
cd - > /dev/null

echo "Размер папки /log перед тестом:"
du -sh "$TEST_LOG_DIR"

# Запускаем тестируемый скрипт
"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 70
check_test_result "Тест 1" "70"

# Тест 2: Проверка с порогом 55%
echo "========================================"
echo "Тест 2: Проверка с порогом 55%"

# Очищаем и создаем новые файлы
rm -rf "$TEST_LOG_DIR"/* "$BACKUP_DIR"/*

cd "$TEST_LOG_DIR"
for i in {1..500}; do
    dd if=/dev/urandom of="logfile_$i.log" bs=1M count=1 status=none 2>/dev/null
done
cd - > /dev/null

"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 55
check_test_result "Тест 2" "55"

# Тест 3: Проверка с порогом 20%
echo "========================================"
echo "Тест 3: Проверка с порогом 20%"

# Очищаем и создаем новые файлы
rm -rf "$TEST_LOG_DIR"/* "$BACKUP_DIR"/*

cd "$TEST_LOG_DIR"
for i in {1..500}; do
    dd if=/dev/urandom of="logfile_$i.log" bs=1M count=1 status=none 2>/dev/null
done
cd - > /dev/null

"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 20
check_test_result "Тест 3" "20"

# Тест 4: Проверка с порогом 10%
echo "========================================"
echo "Тест 4: Проверка с порогом 10%"

# Очищаем и создаем новые файлы
rm -rf "$TEST_LOG_DIR"/* "$BACKUP_DIR"/*

cd "$TEST_LOG_DIR"
for i in {1..500}; do
    dd if=/dev/urandom of="logfile_$i.log" bs=1M count=1 status=none 2>/dev/null
done
cd - > /dev/null

"$SCRIPT_PATH" -f "$TEST_LOG_DIR" -b "$BACKUP_DIR" -t 10
check_test_result "Тест 4" "10"

echo "========================================"
echo "=== ВСЕ ТЕСТЫ ЗАВЕРШЕНЫ ==="

# Финальная статистика
echo "Финальная статистика:"
echo "Всего создано архивов во всех тестах: $(find "$BACKUP_DIR" -name "*.tar.gz" | wc -l)"
echo "Файлы архивов:"
ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "Архивы не созданы"

# Очистка после тестов
echo "========================================"
echo "Очистка временного раздела..."
sudo umount "$TEST_DISK_MOUNT"
rm -f "$CURRENT_DIR/test_disk.img"
rmdir "$TEST_DISK_MOUNT"
echo "Тестовое окружение очищено"
