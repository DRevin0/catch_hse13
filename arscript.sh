#!/bin/bash

#Функция для проверки использования папки (возвращает процент)
get_folder_usage() {
    local folder_path="$1"
    
    if [ ! -d "$folder_path" ]; then
        echo "0"
        return
    fi

    local folder_size=$(du -sb "$folder_path" 2>/dev/null | awk '{print $1}')
    local device_info=$(stat -f -c "%S %b %a" "$folder_path" 2>/dev/null 2>/dev/null)
    
    if [ -z "$device_info" ] || [ -z "$folder_size" ] || [ "$folder_size" -eq 0 ]; then
        echo "0"
        return
    fi
    
    local block_size=$(echo "$device_info" | awk '{print $1}')
    local total_blocks=$(echo "$device_info" | awk '{print $2}')
    local partition_size=$((block_size * total_blocks))
    
    local usage_percent=$(echo "scale=2; ($folder_size * 100) / $partition_size" | bc 2>/dev/null)
    
    #запятую на точку для bc
    echo "$usage_percent" | tr ',' '.'
}

#Функция для отображения прогресс-бара
progress_bar() {
    local current=$1
    local total=$2
    local usage=$3
    local width=50
    
    #Если total = 0, избегаем деления на ноль
    if [ $total -eq 0 ]; then
        local percentage=0
        local completed=0
        local remaining=$width
    else
        local percentage=$((current * 100 / total))
        local completed=$((current * width / total))
        local remaining=$((width - completed))
    fi
    
    #Форматируем использование до одного знака после запятой
    local usage_formatted=$(echo "scale=1; $usage/1" | bc -l 2>/dev/null | tr -d '\n')
    
    printf "\r["
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $remaining | tr ' ' '-'
    printf "] %3d%% файлов (%d/%d) | Использование: %s%%" $percentage $current $total "$usage_formatted"
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

    #Получаем общее количество файлов для прогресс-бара
    local total_files=$(find "$folder_path" -maxdepth 1 -type f | wc -l)
    local processed_files=0
    
    if [ $total_files -eq 0 ]; then
        echo "В папке нет файлов для архивации"
        return
    fi

    echo "Начинаем процесс архивации..."
    echo "Всего файлов для обработки: $total_files"
    echo "Целевое использование: $precent%"
    echo ""

    mkdir -p "$backup_path"

    while true; do
        if [ -z "$(ls -A "$folder_path" 2>/dev/null)" ]; then
            echo -e "\nВсе файлы обработаны"
            break
        fi

        #Получаем текущее использование
        local current_usage=$(get_folder_usage "$folder_path")
        
        #Проверяем, достигли ли процента
        current_usage_fixed=$(echo "$current_usage" | tr ',' '.')
        if (( $(echo "$current_usage_fixed <= $precent" | bc -l 2>/dev/null) )); then
            echo -e "\nДостигнуто целевое использование ($current_usage% <= $precent%), остановка архивации"
            break
        fi

        #Получаем список самых старых файлов
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
        
        #обновляем прогресс-бар с текущим процентом использования
        current_usage_fixed=$(echo "$current_usage" | tr ',' '.')
        processed_files=$((processed_files + ${#oldest_files[@]}))
        progress_bar $processed_files $total_files $current_usage_fixed
        
        #переходим в папку чтобы использовать относительные пути
        cd "$folder_path"
        
        #архивируем файлы
        if tar -czf "$archive_path" "${oldest_files[@]##*/}" 2>/dev/null; then
            #удаляем заархивированные файлы
            for file in "${oldest_files[@]}"; do
                local filename=$(basename "$file")
                if [ -f "$filename" ]; then
                    rm -f "$filename"
                fi
            done
        else
            echo -e "\nОшибка при создании архива"
            cd - > /dev/null
            break
        fi
        
        cd - > /dev/null
        
        #небольшая задержка для плавного обновления
        sleep 0.1
    done
    
    #финальное обновление прогресс-бара
    local final_usage=$(get_folder_usage "$folder_path")
    local final_usage_fixed=$(echo "$final_usage" | tr ',' '.')
    progress_bar $processed_files $total_files $final_usage_fixed
    echo -e "\n\nПроцесс архивации завершен"
    echo "Обработано файлов: $processed_files из $total_files"
    echo "Финальное использование: $final_usage%"
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
    
    #проверяем начальное использование
    local initial_usage=$(get_folder_usage "$folder_path")
    echo "Текущее использование: $initial_usage%"
    
    if (( $(echo "$initial_usage <= $precent" | bc -l 2>/dev/null) )); then
        echo "Папка не нуждается в очистке (использование в пределах нормы)."
    else
        echo "Начинаем процесс архивации для снижения использования до $precent%..."
        archive_oldest_files "$folder_path" "$backup_path" "$precent"
    fi
}

#запуск функции с аргументами командной строки
main "$@"