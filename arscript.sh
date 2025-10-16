#!/bin/bash


#функция для проверки сколько занимает папка относительно раздела диска
check_folder_usage() {
    local folder_path="$1"
    local threshold="$2"

    # Проверяем, существует ли папка
    if [ ! -d "$folder_path" ]; then
        echo "Ошибка: папка $folder_path не существует"
        return 0
    fi

    # Получаем размер папки
    local folder_size=$(du -sb "$folder_path" 2>/dev/null | awk '{print $1}')
    
    # Получаем информацию о файловой системе через stat (более надежно)
    local device_info
    device_info=$(stat -f -c "%S %b %a" "$folder_path" 2>/dev/null)
    
    if [ -z "$device_info" ]; then
        echo "Ошибка: не удалось получить информацию о файловой системе"
        return 0
    fi
    
    local block_size=$(echo "$device_info" | awk '{print $1}')
    local total_blocks=$(echo "$device_info" | awk '{print $2}')
    local available_blocks=$(echo "$device_info" | awk '{print $3}')
    
    local partition_size=$((block_size * total_blocks))
    local mount_point=$(df -P "$folder_path" | awk 'NR==2 {print $6}')
    
    # Если папка пуста
    if [ -z "$folder_size" ] || [ "$folder_size" -eq 0 ]; then
        echo "Папка $folder_path пуста"
        echo "Размер папки: 0 байт"
        echo "Раздел: $mount_point ($partition_size байт)"
        echo "Использование: 0%"
        return 0
    fi

    # Рассчитываем использование папки относительно раздела
    local usage_percent=$(echo "scale=2; ($folder_size * 100) / $partition_size" | bc)
    
    local usage_rounded=$(echo "$usage_percent" | awk '{printf "%.0f", $1}' 2>/dev/null)

    echo "Папка: $folder_path"
    echo "Размер папки: $folder_size байт"
    echo "Раздел: $mount_point ($partition_size байт)"
    echo "Заполнение папки: $usage_rounded%"

    if (( $(echo "$usage_percent > $threshold" | bc -l) )); then
        echo "Превышен порог в $threshold%."
        return 1  
    else
        echo "Использование в пределах нормы."
        return 0  
    fi
}

archive_oldest_files() {
    local folder_path="$1"
    local backup_path="$2"
    local precent="$3"
    local files_per_batch=3

    if [ -z "$(ls -A "$folder_path" 2>/dev/null)" ]; then
        echo "Папка $folder_path пуста, нечего архивировать"
        return
    fi

    if check_folder_usage "$folder_path" "$precent"; then
        return 
    fi

    mkdir -p "$backup_path"

    while true; do
        if [ -z "$(ls -A "$folder_path" 2>/dev/null)" ]; then
            echo "В папке больше нет файлов"
            break
        fi

        # Получаем список самых старых файлов
        local oldest_files=()
        while IFS= read -r -d '' file; do
            oldest_files+=("$file")
            [ ${#oldest_files[@]} -eq $files_per_batch ] && break
        done < <(find "$folder_path" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | sort -n -z | cut -d' ' -f2-)

        if [ ${#oldest_files[@]} -eq 0 ]; then
            break
        fi

        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local archive_name="batch_${timestamp}.tar.gz"
        local archive_path="$backup_path/$archive_name"
        
        echo "Архивируем ${#oldest_files[@]} файлов в $archive_path"
        
        # Переходим в папку чтобы использовать относительные пути
        cd "$folder_path"
        
        # Архивируем файлы
        if tar -czf "$archive_path" "${oldest_files[@]##*/}" 2>/dev/null; then
            echo "Архив успешно создан"
            
            # Удаляем заархивированные файлы
            for file in "${oldest_files[@]}"; do
                local filename=$(basename "$file")
                if [ -f "$filename" ]; then
                    rm -f "$filename"
                    echo "Удален файл: $filename"
                fi
            done
        else
            echo "Ошибка при создании архива"
        fi
        
        cd - > /dev/null
        
        # Проверяем использование
        if check_folder_usage "$folder_path" "$precent"; then
            echo "Достигнуто целевое использование, остановка архивации"
            break
        fi
    done
    echo "Процесс архивации завершен"
}

main() {
    local folder_path=""
    local backup_path=""
    local precent=70
    
    #обработка ввода пользователя
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--folder)
                folder_path="$2"
                shift 2
                ;;
            -b|--backup)
                backup_path="$2"
                shift 2
                ;;
            -t|--precent)
                precent="$2"
                shift 2
                ;;
            -h|--help)
                echo "Использование: $0 -f <папка> -b <папка_бэкапа> [-t <порог>]"
                echo "Пример: $0 -f /home/user/data -b /home/user/backups -t 70"
                exit 0
                ;;
            *)
                echo "Неизвестный параметр: $1"
                exit 1
                ;;
        esac
    done
#если не указаны аргументы при вызове, запращиваем интерактивно
    if [ -z "$folder_path" ] || [ -z "$backup_path" ]; then
        echo "Аргументы не указаны. Введите данные вручную:"
        
        read -p "Введите путь к папке для мониторинга: " folder_path
        read -p "Введите путь к папке для бэкапов: " backup_path
        read -p "Введите пороговое значение в процентах (по умолчанию 70): " threshold_input
        
        #без порога - значение по умолчанию(70)
        if [ -n "$threshold_input" ]; then
            precent="$threshold_input"
        fi
        
        echo "----------------------------------------"
    fi
    
    #проверки обязательных параметров
    if [ -z "$folder_path" ] || [ -z "$backup_path" ]; then
        echo "Ошибка: необходимо указать пути к папкам"
        echo "Использование: $0 -f <папка> -b <папка_бэкапа> [-t <порог>]"
        exit 1
    fi
    
    if [ ! -d "$folder_path" ]; then
        echo "Ошибка: папка $folder_path не существует"
        exit 1
    fi

    mkdir -p "$backup_path"
    
    echo "Мониторинг папки: $folder_path"
    echo "Папка для бэкапов: $backup_path"
    echo "Пороговое значение: $precent%"
    echo "----------------------------------------"
    
    if check_folder_usage "$folder_path" "$precent"; then
        echo "Папка не нуждается в очистке."
    else
        echo "Начинаем процесс архивации..."
        archive_oldest_files "$folder_path" "$backup_path" "$precent"
    fi
}
#запуск функции с аргументами командной строки
main "$@"
