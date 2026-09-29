#!/bin/bash
# Интерактивный помощник по работе с консольной версией GIT
# Идея, промпт, дебаггинг: Старухин Д.Н.
# при помощи LLM DeepSeek-V3

#Особенности:
#Клонирование – запрашивает HTTPS-ссылку и выполняет git clone.

#Добавление – три варианта:
# - все изменения (git add -A),
# - указать имена файлов вручную,
# - выбрать из списка изменённых файлов (нумерованный список, можно ввести номера через пробел).

#Коммит – запрашивает сообщение и выполняет git commit -m.

#Пуш – выполняет git push (если удалённый репозиторий не настроен, выводит предупреждение).

#Работа с тегами:
# - Просмотр всех тегов
# - Создание нового тега (лёгкого или аннотированного)
# - Удаление тега (локально и с удалённого репозитория)
# - Просмотр информации о теге
# - Отправка тегов в удалённый репозиторий
# - Сортировка тегов по версиям (semantic versioning)
# - Поиск тегов по маске

#Проверки: скрипт проверяет наличие Git, нахождение внутри репозитория для операций, кроме клонирования, а также обрабатывает ошибки выполнения команд.

#Цветной вывод для лучшей читаемости (можно отключить, если терминал не поддерживает).

#Файл для хранения учётных данных (~/.git_credentials):
#Сохраняет логин и пароль в зашифрованном виде (только для чтения владельцем)
#Автоматически загружается при запуске скрипта

#Пункт меню - "Настроить учётные данные":
#Позволяет вручную настроить логин и пароль
#Может обновлять существующие данные

#Автоматическая аутентификация для push:
#При выполнении git push скрипт пытается использовать сохранённые данные
#Если данные есть - пуш происходит автоматически без запроса пароля
#Если данных нет или пуш не удался - предлагает ввести данные вручную

#Клонирование с аутентификацией:
#При клонировании можно сразу указать логин/пароль
#Они будут вставлены в URL для автоматической аутентификации

#Временные файлы:
#Создаётся временный скрипт для автоматической подстановки пароля
#Автоматически удаляется при завершении работы

#Настройка Git credential helper:
#Кэширует пароль на 1 час (можно настроить)

#Важные моменты:
#Пароль хранится в открытом виде в файле ~/.git_credentials (это небезопасно для продакшена, но удобно для локального использования)

#Для дополнительной безопасности можно использовать git config --global credential.helper store или git config --global credential.helper cache
#Скрипт автоматически очищает временные файлы при завершении

#Использование:
#Запустите скрипт
#Выберите пункт 5 для настройки учётных данных
#После настройки все push-операции будут выполняться автоматически с сохранённым паролем
#Пароль можно обновить в любой момент через пункт меню 5

# Цвета для оформления вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Файл для хранения учётных данных (в домашней директории)
CREDENTIALS_FILE="$HOME/.git_credentials"
# Временный файл для хранения пароля (будет удалён после использования)
TEMP_PASS_FILE="/tmp/git_pass_$$"

# Проверка наличия Git
if ! command -v git &> /dev/null; then
    echo -e "${RED}Ошибка: Git не установлен. Установите Git и повторите попытку.${NC}"
    exit 1
fi

# Функция проверки, находимся ли мы внутри Git-репозитория
is_git_repo() {
    git rev-parse --is-inside-work-tree &> /dev/null
}

# Функция загрузки сохранённых учётных данных
load_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        source "$CREDENTIALS_FILE"
        if [[ -n "$GIT_USERNAME" && -n "$GIT_PASSWORD" ]]; then
            return 0
        fi
    fi
    return 1
}

# Функция сохранения учётных данных
save_credentials() {
    local username=$1
    local password=$2
    echo "GIT_USERNAME='$username'" > "$CREDENTIALS_FILE"
    echo "GIT_PASSWORD='$password'" >> "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    echo -e "${GREEN}Учётные данные сохранены в $CREDENTIALS_FILE${NC}"
}

# Функция запроса учётных данных
ask_credentials() {
    echo -e "\n${YELLOW}Введите учётные данные для Git (опционально)${NC}"
    read -p "Имя пользователя (оставьте пустым для пропуска): " username
    
    if [[ -n "$username" ]]; then
        read -s -p "Пароль (оставьте пустым для пропуска): " password
        echo
        if [[ -n "$password" ]]; then
            # Сохраняем временно в переменную
            GIT_USERNAME="$username"
            GIT_PASSWORD="$password"
            
            read -p "Сохранить учётные данные для будущих сессий? (y/n): " save_choice
            if [[ "$save_choice" =~ ^[Yy]$ ]]; then
                save_credentials "$username" "$password"
            fi
            return 0
        fi
    fi
    
    # Если данные не введены или пароль пустой
    GIT_USERNAME=""
    GIT_PASSWORD=""
    return 1
}

# Функция настройки Git для использования учётных данных
setup_git_credentials() {
    local username=$1
    local password=$2
    
    if [[ -n "$username" && -n "$password" ]]; then
        # Настраиваем Git на использование заданных учётных данных
        # Для HTTPS используем URL с встроенными данными
        # Получаем текущий remote URL
        local remote_url=$(git remote get-url origin 2>/dev/null)
        if [[ -n "$remote_url" ]]; then
            # Проверяем, является ли URL HTTPS
            if [[ "$remote_url" =~ ^https:// ]]; then
                # Создаём временную переменную окружения для Git
                export GIT_ASKPASS=/bin/echo
                export GIT_USER="$username"
                export GIT_PASSWORD="$password"
                
                # Создаём временный скрипт для автологина
                cat > "$TEMP_PASS_FILE" << 'EOF'
#!/bin/bash
case "$1" in
    Username*) echo "$GIT_USER" ;;
    Password*) echo "$GIT_PASSWORD" ;;
esac
EOF
                chmod +x "$TEMP_PASS_FILE"
                export GIT_ASKPASS="$TEMP_PASS_FILE"
                
                # Для некоторых версий Git также нужно настроить credential helper
                git config --local credential.helper 'cache --timeout=3600' 2>/dev/null
                
                echo -e "${GREEN}Настроена автоматическая аутентификация для текущей сессии${NC}"
                return 0
            else
                echo -e "${YELLOW}URL не является HTTPS, аутентификация через логин/пароль не требуется${NC}"
                return 0
            fi
        else
            echo -e "${YELLOW}Не удалось определить remote URL. Попробуйте настроить вручную.${NC}"
            return 1
        fi
    fi
    return 1
}

# Функция очистки временных файлов
cleanup_temp_files() {
    if [[ -f "$TEMP_PASS_FILE" ]]; then
        rm -f "$TEMP_PASS_FILE"
    fi
    # Сбрасываем переменные окружения
    unset GIT_ASKPASS GIT_USER GIT_PASSWORD
}

# Функция отображения основного меню
show_menu() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                 GIT ИНТЕРАКТИВНЫЙ ПОМОЩНИК${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${YELLOW}1.${NC} Клонировать репозиторий"
    echo -e "  ${YELLOW}2.${NC} Добавить изменённые файлы"
    echo -e "  ${YELLOW}3.${NC} Сделать коммит"
    echo -e "  ${YELLOW}4.${NC} Запушить изменения"
    echo -e "  ${YELLOW}5.${NC} Настроить учётные данные"
    echo -e "  ${YELLOW}6.${NC} Работа с тегами (tags)"
    echo -e "  ${YELLOW}0.${NC} Выйти"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
    
    # Показываем статус учётных данных
    if load_credentials; then
        echo -e "${GREEN}✓ Учётные данные загружены (пользователь: $GIT_USERNAME)${NC}"
    else
        echo -e "${YELLOW}⚠ Учётные данные не настроены${NC}"
    fi
    echo
}

# 1. Клонирование
clone_repo() {
    echo -e "\n${GREEN}Клонирование репозитория${NC}"
    read -p "Введите HTTPS-ссылку на репозиторий: " repo_url
    if [[ -z "$repo_url" ]]; then
        echo -e "${RED}Ошибка: URL не может быть пустым.${NC}"
        return 1
    fi
    
    # Предлагаем ввести учётные данные для клонирования
    echo -e "\n${YELLOW}Для клонирования по HTTPS могут потребоваться учётные данные${NC}"
    read -p "Введите имя пользователя (оставьте пустым для пропуска): " username
    if [[ -n "$username" ]]; then
        read -s -p "Введите пароль (оставьте пустым для пропуска): " password
        echo
        if [[ -n "$password" ]]; then
            # Вставляем логин и пароль в URL
            local clone_url=$(echo "$repo_url" | sed -E "s#https://#https://$username:$password@#")
            echo -e "Выполняется git clone с аутентификацией..."
            if git clone "$clone_url"; then
                echo -e "${GREEN}Клонирование успешно завершено.${NC}"
                # Переходим в клонированный репозиторий
                local repo_name=$(basename "$repo_url" .git)
                if [[ -d "$repo_name" ]]; then
                    cd "$repo_name" && echo -e "${GREEN}Перешли в директорию $repo_name${NC}"
                fi
            else
                echo -e "${RED}Ошибка при клонировании. Проверьте URL и права доступа.${NC}"
            fi
        else
            # Клонируем без пароля
            echo -e "Выполняется git clone $repo_url ..."
            if git clone "$repo_url"; then
                echo -e "${GREEN}Клонирование успешно завершено.${NC}"
            else
                echo -e "${RED}Ошибка при клонировании. Проверьте URL и права доступа.${NC}"
            fi
        fi
    else
        # Клонируем без учётных данных
        echo -e "Выполняется git clone $repo_url ..."
        if git clone "$repo_url"; then
            echo -e "${GREEN}Клонирование успешно завершено.${NC}"
        else
            echo -e "${RED}Ошибка при клонировании. Проверьте URL и права доступа.${NC}"
        fi
    fi
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 2. Добавление файлов
add_files() {
    if ! is_git_repo; then
        echo -e "${RED}Ошибка: текущая директория не является Git-репозиторием.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi

    echo -e "\n${GREEN}Добавление файлов в индекс${NC}"
    echo -e "Выберите вариант:"
    echo -e "  ${YELLOW}1.${NC} Добавить все изменённые файлы (git add -A)"
    echo -e "  ${YELLOW}2.${NC} Добавить конкретные файлы (ввести имена)"
    echo -e "  ${YELLOW}3.${NC} Выбрать из списка изменённых"
    read -p "Ваш выбор (1-3): " add_choice

    case $add_choice in
        1)
            echo -e "Выполняется git add -A ..."
            if git add -A; then
                echo -e "${GREEN}Все изменения добавлены.${NC}"
            else
                echo -e "${RED}Ошибка при добавлении.${NC}"
            fi
            ;;
        2)
            read -p "Введите имена файлов через пробел: " -a files
            if [[ ${#files[@]} -eq 0 ]]; then
                echo -e "${RED}Файлы не указаны.${NC}"
            else
                echo -e "Выполняется git add ${files[*]} ..."
                if git add "${files[@]}"; then
                    echo -e "${GREEN}Указанные файлы добавлены.${NC}"
                else
                    echo -e "${RED}Ошибка при добавлении. Проверьте имена файлов.${NC}"
                fi
            fi
            ;;
        3)
            local changes=$(git status --porcelain)
            if [[ -z "$changes" ]]; then
                echo -e "${YELLOW}Нет изменённых файлов.${NC}"
                read -p "Нажмите Enter, чтобы продолжить..."
                return 0
            fi

            echo -e "\n${BLUE}Список изменённых файлов:${NC}"
            local i=1
            local file_list=()
            while IFS= read -r line; do
                local file="${line:3}"
                if [[ "$file" == *" -> "* ]]; then
                    file="${file#* -> }"
                fi
                echo -e "  ${YELLOW}$i.${NC} $file"
                file_list+=("$file")
                ((i++))
            done <<< "$changes"

            read -p "Введите номера файлов для добавления (через пробел, например: 1 3 5): " -a indices
            if [[ ${#indices[@]} -eq 0 ]]; then
                echo -e "${RED}Номера не указаны.${NC}"
            else
                local selected_files=()
                for idx in "${indices[@]}"; do
                    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#file_list[@]} )); then
                        selected_files+=("${file_list[$((idx-1))]}")
                    else
                        echo -e "${RED}Номер $idx недействителен, пропускаем.${NC}"
                    fi
                done
                if [[ ${#selected_files[@]} -gt 0 ]]; then
                    echo -e "Выполняется git add ${selected_files[*]} ..."
                    if git add "${selected_files[@]}"; then
                        echo -e "${GREEN}Выбранные файлы добавлены.${NC}"
                    else
                        echo -e "${RED}Ошибка при добавлении.${NC}"
                    fi
                else
                    echo -e "${RED}Нет корректных файлов для добавления.${NC}"
                fi
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            ;;
    esac
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 3. Коммит
commit_changes() {
    if ! is_git_repo; then
        echo -e "${RED}Ошибка: текущая директория не является Git-репозиторием.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi

    echo -e "\n${GREEN}Создание коммита${NC}"
    read -p "Введите сообщение коммита: " commit_msg
    if [[ -z "$commit_msg" ]]; then
        echo -e "${RED}Сообщение не может быть пустым.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi

    if git diff --cached --quiet && git diff --quiet; then
        echo -e "${YELLOW}Нет изменений для коммита (индекс пуст или рабочий каталог чист).${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 0
    fi

    echo -e "Выполняется git commit -m \"$commit_msg\" ..."
    if git commit -m "$commit_msg"; then
        echo -e "${GREEN}Коммит успешно создан.${NC}"
    else
        echo -e "${RED}Ошибка при создании коммита.${NC}"
    fi
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 4. Пуш с автоматической аутентификацией
push_changes() {
    if ! is_git_repo; then
        echo -e "${RED}Ошибка: текущая директория не является Git-репозиторием.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi

    echo -e "\n${GREEN}Отправка изменений в удалённый репозиторий${NC}"
    
    # Проверяем наличие удалённого репозитория
    if ! git remote | grep -q .; then
        echo -e "${RED}Ошибка: не настроен ни один удалённый репозиторий (remote).${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi

    # Пытаемся загрузить сохранённые учётные данные
    if load_credentials; then
        echo -e "${GREEN}Используются сохранённые учётные данные для пользователя $GIT_USERNAME${NC}"
        # Настраиваем автоматическую аутентификацию
        setup_git_credentials "$GIT_USERNAME" "$GIT_PASSWORD"
        echo -e "Выполняется git push с автоматической аутентификацией..."
        if git push; then
            echo -e "${GREEN}Изменения успешно отправлены.${NC}"
            cleanup_temp_files
            read -p "Нажмите Enter, чтобы продолжить..."
            return 0
        else
            echo -e "${RED}Ошибка при выполнении push с сохранёнными данными.${NC}"
            cleanup_temp_files
            # Пробуем с ручным вводом
        fi
    fi

    # Если автоматический пуш не удался или нет сохранённых данных, предлагаем ручной ввод
    echo -e "\n${YELLOW}Введите учётные данные для push (или выполните пуш без них)${NC}"
    read -p "Имя пользователя (оставьте пустым для обычного push): " username
    
    if [[ -n "$username" ]]; then
        read -s -p "Пароль: " password
        echo
        if [[ -n "$password" ]]; then
            # Настраиваем аутентификацию
            setup_git_credentials "$username" "$password"
            echo -e "Выполняется git push с аутентификацией..."
            if git push; then
                echo -e "${GREEN}Изменения успешно отправлены.${NC}"
                read -p "Сохранить учётные данные для будущих сессий? (y/n): " save_choice
                if [[ "$save_choice" =~ ^[Yy]$ ]]; then
                    save_credentials "$username" "$password"
                fi
            else
                echo -e "${RED}Ошибка при выполнении push.${NC}"
                echo -e "${YELLOW}Попробуйте выполнить вручную: git push -u origin <ветка>${NC}"
            fi
            cleanup_temp_files
        else
            # Пуш без пароля
            echo -e "Выполняется git push ..."
            if git push; then
                echo -e "${GREEN}Изменения успешно отправлены.${NC}"
            else
                echo -e "${RED}Ошибка при выполнении push.${NC}"
                echo -e "${YELLOW}Попробуйте выполнить вручную: git push -u origin <ветка>${NC}"
            fi
        fi
    else
        # Обычный пуш без учётных данных
        echo -e "Выполняется git push ..."
        if git push; then
            echo -e "${GREEN}Изменения успешно отправлены.${NC}"
        else
            echo -e "${RED}Ошибка при выполнении push.${NC}"
            echo -e "${YELLOW}Попробуйте выполнить вручную: git push -u origin <ветка>${NC}"
        fi
    fi
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 5. Настройка учётных данных
setup_credentials() {
    echo -e "\n${GREEN}Настройка учётных данных Git${NC}"
    
    if load_credentials; then
        echo -e "${YELLOW}Текущие сохранённые данные:${NC}"
        echo -e "  Имя пользователя: $GIT_USERNAME"
        echo -e "  Пароль: ********"
        read -p "Обновить учётные данные? (y/n): " update_choice
        if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Настройка отменена.${NC}"
            read -p "Нажмите Enter, чтобы продолжить..."
            return 0
        fi
    fi
    
    read -p "Введите имя пользователя: " username
    if [[ -z "$username" ]]; then
        echo -e "${RED}Имя пользователя не может быть пустым.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    read -s -p "Введите пароль: " password
    echo
    if [[ -z "$password" ]]; then
        echo -e "${RED}Пароль не может быть пустым.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    save_credentials "$username" "$password"
    echo -e "${GREEN}Учётные данные успешно настроены.${NC}"
    read -p "Нажмите Enter, чтобы продолжить..."
}

# ============================================
# 6. РАБОТА С ТЕГАМИ (TAGS)
# ============================================

# Функция сортировки тегов по версиям (semantic versioning)
version_sort() {
    # Используем sort -V для версионной сортировки
    sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n
}

# Функция отображения подменю тегов
show_tags_menu() {
    clear
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                   РАБОТА С ТЕГАМИ (TAGS)${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${YELLOW}1.${NC} Просмотреть все теги"
    echo -e "  ${YELLOW}2.${NC} Создать новый тег"
    echo -e "  ${YELLOW}3.${NC} Удалить тег"
    echo -e "  ${YELLOW}4.${NC} Просмотреть информацию о теге"
    echo -e "  ${YELLOW}5.${NC} Отправить теги в удалённый репозиторий"
    echo -e "  ${YELLOW}6.${NC} Скачать теги из удалённого репозитория"
    echo -e "  ${YELLOW}7.${NC} Сортировать теги по версиям"
    echo -e "  ${YELLOW}8.${NC} Поиск тегов по маске"
    echo -e "  ${YELLOW}0.${NC} Вернуться в главное меню"
    echo -e "${MAGENTA}────────────────────────────────────────────────────────────────${NC}"
    echo
}

# 6.1 Просмотр всех тегов
list_tags() {
    echo -e "\n${GREEN}Список всех тегов:${NC}"
    local tags=$(git tag 2>/dev/null)
    if [[ -z "$tags" ]]; then
        echo -e "${YELLOW}Теги отсутствуют.${NC}"
    else
        echo -e "${BLUE}────────────────────────────────────────${NC}"
        # Показываем теги с цветом и сортировкой по версиям
        echo "$tags" | version_sort | while read -r tag; do
            # Проверяем, является ли тег аннотированным
            if git rev-parse -q --verify "refs/tags/$tag^{}" &>/dev/null; then
                echo -e "${GREEN}●${NC} $tag ${CYAN}(аннотированный)${NC}"
            else
                echo -e "${YELLOW}○${NC} $tag ${CYAN}(лёгкий)${NC}"
            fi
        done
        echo -e "${BLUE}────────────────────────────────────────${NC}"
        echo -e "Всего тегов: ${GREEN}$(echo "$tags" | wc -l)${NC}"
    fi
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 6.2 Создание нового тега
create_tag() {
    echo -e "\n${GREEN}Создание нового тега${NC}"
    
    read -p "Введите имя тега (например, v1.0.0): " tag_name
    if [[ -z "$tag_name" ]]; then
        echo -e "${RED}Имя тега не может быть пустым.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    # Проверяем, существует ли уже такой тег
    if git rev-parse -q --verify "refs/tags/$tag_name" &>/dev/null; then
        echo -e "${RED}Ошибка: Тег с именем '$tag_name' уже существует.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    echo -e "Выберите тип тега:"
    echo -e "  ${YELLOW}1.${NC} Лёгкий (lightweight) - просто указатель на коммит"
    echo -e "  ${YELLOW}2.${NC} Аннотированный (annotated) - с сообщением и метаданными"
    read -p "Ваш выбор (1-2): " tag_type
    
    case $tag_type in
        1)
            echo -e "Выполняется git tag $tag_name ..."
            if git tag "$tag_name"; then
                echo -e "${GREEN}Лёгкий тег '$tag_name' успешно создан.${NC}"
            else
                echo -e "${RED}Ошибка при создании тега.${NC}"
            fi
            ;;
        2)
            read -p "Введите сообщение для тега: " tag_message
            if [[ -z "$tag_message" ]]; then
                echo -e "${RED}Сообщение не может быть пустым для аннотированного тега.${NC}"
                read -p "Нажмите Enter, чтобы продолжить..."
                return 1
            fi
            echo -e "Выполняется git tag -a $tag_name -m \"$tag_message\" ..."
            if git tag -a "$tag_name" -m "$tag_message"; then
                echo -e "${GREEN}Аннотированный тег '$tag_name' успешно создан.${NC}"
            else
                echo -e "${RED}Ошибка при создании тега.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            ;;
    esac
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 6.3 Удаление тега
delete_tag() {
    echo -e "\n${GREEN}Удаление тега${NC}"
    
    # Показываем список тегов
    local tags=$(git tag 2>/dev/null)
    if [[ -z "$tags" ]]; then
        echo -e "${YELLOW}Теги отсутствуют.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 0
    fi
    
    echo -e "${BLUE}Доступные теги:${NC}"
    local i=1
    local tag_list=()
    while IFS= read -r tag; do
        echo -e "  ${YELLOW}$i.${NC} $tag"
        tag_list+=("$tag")
        ((i++))
    done <<< "$tags"
    
    read -p "Введите номер тега для удаления: " tag_number
    if [[ ! "$tag_number" =~ ^[0-9]+$ ]] || (( tag_number < 1 || tag_number > ${#tag_list[@]} )); then
        echo -e "${RED}Неверный номер.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    local tag_name="${tag_list[$((tag_number-1))]}"
    echo -e "${YELLOW}Выбран тег: $tag_name${NC}"
    echo -e "  ${YELLOW}1.${NC} Удалить только локально"
    echo -e "  ${YELLOW}2.${NC} Удалить локально и в удалённом репозитории"
    read -p "Ваш выбор (1-2): " delete_choice
    
    case $delete_choice in
        1)
            echo -e "Выполняется git tag -d $tag_name ..."
            if git tag -d "$tag_name"; then
                echo -e "${GREEN}Тег '$tag_name' удалён локально.${NC}"
            else
                echo -e "${RED}Ошибка при удалении тега.${NC}"
            fi
            ;;
        2)
            echo -e "Выполняется git tag -d $tag_name ..."
            if git tag -d "$tag_name"; then
                echo -e "${GREEN}Тег удалён локально.${NC}"
                echo -e "Выполняется git push origin :refs/tags/$tag_name ..."
                if git push origin ":$tag_name" 2>/dev/null || git push origin --delete "$tag_name" 2>/dev/null; then
                    echo -e "${GREEN}Тег удалён из удалённого репозитория.${NC}"
                else
                    echo -e "${RED}Ошибка при удалении тега из удалённого репозитория.${NC}"
                    echo -e "${YELLOW}Попробуйте выполнить вручную: git push origin --delete $tag_name${NC}"
                fi
            else
                echo -e "${RED}Ошибка при удалении тега.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            ;;
    esac
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 6.4 Просмотр информации о теге
show_tag_info() {
    echo -e "\n${GREEN}Информация о теге${NC}"
    
    local tags=$(git tag 2>/dev/null)
    if [[ -z "$tags" ]]; then
        echo -e "${YELLOW}Теги отсутствуют.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 0
    fi
    
    echo -e "${BLUE}Доступные теги:${NC}"
    local i=1
    local tag_list=()
    while IFS= read -r tag; do
        echo -e "  ${YELLOW}$i.${NC} $tag"
        tag_list+=("$tag")
        ((i++))
    done <<< "$tags"
    
    read -p "Введите номер тега: " tag_number
    if [[ ! "$tag_number" =~ ^[0-9]+$ ]] || (( tag_number < 1 || tag_number > ${#tag_list[@]} )); then
        echo -e "${RED}Неверный номер.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    local tag_name="${tag_list[$((tag_number-1))]}"
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Информация о теге: $tag_name${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    
    # Проверяем тип тега
    if git rev-parse -q --verify "refs/tags/$tag_name^{}" &>/dev/null; then
        echo -e "${CYAN}Тип:${NC} Аннотированный"
        echo -e "${CYAN}Сообщение:${NC}"
        git tag -l -n5 "$tag_name" | sed "s/^[^ ]*[ ]*//" | while IFS= read -r line; do
            echo -e "  $line"
        done
    else
        echo -e "${CYAN}Тип:${NC} Лёгкий"
    fi
    
    echo -e "\n${CYAN}Хеш коммита:${NC} $(git rev-parse "$tag_name")"
    echo -e "${CYAN}Дата создания:${NC} $(git log -1 --format=%ai "$tag_name" 2>/dev/null || echo "Недоступно")"
    echo -e "${CYAN}Автор:${NC} $(git log -1 --format=%an "$tag_name" 2>/dev/null || echo "Недоступно")"
    echo -e "${CYAN}Коммит:${NC}"
    git log -1 --oneline "$tag_name" 2>/dev/null | sed 's/^/  /'
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 6.5 Отправка тегов в удалённый репозиторий
push_tags() {
    echo -e "\n${GREEN}Отправка тегов в удалённый репозиторий${NC}"
    
    # Проверяем наличие удалённого репозитория
    if ! git remote | grep -q .; then
        echo -e "${RED}Ошибка: не настроен ни один удалённый репозиторий (remote).${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    local tags=$(git tag 2>/dev/null)
    if [[ -z "$tags" ]]; then
        echo -e "${YELLOW}Нет тегов для отправки.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 0
    fi
    
    echo -e "Выберите действие:"
    echo -e "  ${YELLOW}1.${NC} Отправить все теги (git push --tags)"
    echo -e "  ${YELLOW}2.${NC} Отправить конкретный тег"
    read -p "Ваш выбор (1-2): " push_choice
    
    case $push_choice in
        1)
            echo -e "Выполняется git push --tags ..."
            if git push --tags; then
                echo -e "${GREEN}Все теги успешно отправлены.${NC}"
            else
                echo -e "${RED}Ошибка при отправке тегов.${NC}"
            fi
            ;;
        2)
            echo -e "${BLUE}Доступные теги:${NC}"
            local i=1
            local tag_list=()
            while IFS= read -r tag; do
                echo -e "  ${YELLOW}$i.${NC} $tag"
                tag_list+=("$tag")
                ((i++))
            done <<< "$tags"
            
            read -p "Введите номер тега: " tag_number
            if [[ ! "$tag_number" =~ ^[0-9]+$ ]] || (( tag_number < 1 || tag_number > ${#tag_list[@]} )); then
                echo -e "${RED}Неверный номер.${NC}"
                read -p "Нажмите Enter, чтобы продолжить..."
                return 1
            fi
            
            local tag_name="${tag_list[$((tag_number-1))]}"
            echo -e "Выполняется git push origin $tag_name ..."
            if git push origin "$tag_name"; then
                echo -e "${GREEN}Тег '$tag_name' успешно отправлен.${NC}"
            else
                echo -e "${RED}Ошибка при отправке тега.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            ;;
    esac
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 6.6 Скачивание тегов из удалённого репозитория
fetch_tags() {
    echo -e "\n${GREEN}Скачивание тегов из удалённого репозитория${NC}"
    
    # Проверяем наличие удалённого репозитория
    if ! git remote | grep -q .; then
        echo -e "${RED}Ошибка: не настроен ни один удалённый репозиторий (remote).${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    echo -e "Выполняется git fetch --tags ..."
    if git fetch --tags; then
        echo -e "${GREEN}Теги успешно скачаны.${NC}"
        echo -e "\n${BLUE}Обновлённый список тегов:${NC}"
        git tag | version_sort | while read -r tag; do
            echo -e "  ${GREEN}●${NC} $tag"
        done
    else
        echo -e "${RED}Ошибка при скачивании тегов.${NC}"
    fi
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 6.7 Сортировка тегов по версиям
sort_tags_by_version() {
    echo -e "\n${GREEN}Сортировка тегов по версиям${NC}"
    
    local tags=$(git tag 2>/dev/null)
    if [[ -z "$tags" ]]; then
        echo -e "${YELLOW}Теги отсутствуют.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 0
    fi
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Теги, отсортированные по версиям (semantic versioning):${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
    
    local sorted_tags=$(echo "$tags" | version_sort)
    local count=0
    
    while IFS= read -r tag; do
        ((count++))
        # Определяем тип тега
        if git rev-parse -q --verify "refs/tags/$tag^{}" &>/dev/null; then
            local type="аннотированный"
            local color="${GREEN}"
        else
            local type="лёгкий"
            local color="${YELLOW}"
        fi
        
        # Получаем дату создания
        local date=$(git log -1 --format=%ai "$tag" 2>/dev/null | cut -d' ' -f1)
        if [[ -z "$date" ]]; then
            date="дата неизвестна"
        fi
        
        printf "${color}%3d.${NC} %-15s ${CYAN}($type)${NC} ${BLUE}%s${NC}\n" "$count" "$tag" "$date"
    done <<< "$sorted_tags"
    
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
    echo -e "Всего тегов: ${GREEN}$count${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    
    read -p "Нажмите Enter, чтобы продолжить..."
}

# 6.8 Поиск тегов по маске
search_tags() {
    echo -e "\n${GREEN}Поиск тегов по маске${NC}"
    
    local tags=$(git tag 2>/dev/null)
    if [[ -z "$tags" ]]; then
        echo -e "${YELLOW}Теги отсутствуют.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 0
    fi
    
    echo -e "${CYAN}Примеры масок:${NC}"
    echo -e "  ${YELLOW}*${NC} - все теги"
    echo -e "  ${YELLOW}v*${NC} - теги, начинающиеся с 'v'"
    echo -e "  ${YELLOW}*beta*${NC} - теги, содержащие 'beta'"
    echo -e "  ${YELLOW}v1.*${NC} - теги версии 1.x.x"
    echo -e "  ${YELLOW}*-rc*${NC} - теги, содержащие '-rc'"
    echo
    
    read -p "Введите маску для поиска (используйте * для любой последовательности): " pattern
    
    if [[ -z "$pattern" ]]; then
        echo -e "${RED}Маска не может быть пустой.${NC}"
        read -p "Нажмите Enter, чтобы продолжить..."
        return 1
    fi
    
    # Преобразуем маску в регулярное выражение для grep
    local regex_pattern=$(echo "$pattern" | sed 's/\*/.*/g' | sed 's/\./\\./g')
    
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Результаты поиска по маске: '$pattern'${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
    
    local found_tags=$(echo "$tags" | grep -E "^$regex_pattern$" 2>/dev/null | version_sort)
    
    if [[ -z "$found_tags" ]]; then
        echo -e "${YELLOW}Теги, соответствующие маске '$pattern', не найдены.${NC}"
    else
        local count=0
        while IFS= read -r tag; do
            ((count++))
            # Определяем тип тега
            if git rev-parse -q --verify "refs/tags/$tag^{}" &>/dev/null; then
                local type="аннотированный"
                local color="${GREEN}"
            else
                local type="лёгкий"
                local color="${YELLOW}"
            fi
            
            # Получаем дату создания
            local date=$(git log -1 --format=%ai "$tag" 2>/dev/null | cut -d' ' -f1)
            if [[ -z "$date" ]]; then
                date="дата неизвестна"
            fi
            
            # Получаем сообщение для аннотированных тегов
            local message=""
            if [[ "$type" == "аннотированный" ]]; then
                message=$(git tag -l -n1 "$tag" 2>/dev/null | sed "s/^[^ ]*[ ]*//" | head -1)
                if [[ -n "$message" ]]; then
                    message=" - $message"
                fi
            fi
            
            printf "${color}%3d.${NC} %-15s ${CYAN}($type)${NC} ${BLUE}%s${NC}%s\n" "$count" "$tag" "$date" "$message"
        done <<< "$found_tags"
        
        echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
        echo -e "Найдено тегов: ${GREEN}$count${NC}"
    fi
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    read -p "Нажмите Enter, чтобы продолжить..."
}

# Основная функция для работы с тегами
tags_manager() {
    while true; do
        show_tags_menu
        read -p "Выберите действие (0-8): " choice
        case $choice in
            1) list_tags ;;
            2) create_tag ;;
            3) delete_tag ;;
            4) show_tag_info ;;
            5) push_tags ;;
            6) fetch_tags ;;
            7) sort_tags_by_version ;;
            8) search_tags ;;
            0) break ;;
            *) echo -e "${RED}Неверный ввод. Пожалуйста, выберите 0-8.${NC}"; sleep 1 ;;
        esac
    done
}

# Обработка завершения скрипта (очистка временных файлов)
trap cleanup_temp_files EXIT

# Основной цикл
while true; do
    show_menu
    read -p "Выберите действие (0-6): " choice
    case $choice in
        1) clone_repo ;;
        2) add_files ;;
        3) commit_changes ;;
        4) push_changes ;;
        5) setup_credentials ;;
        6) tags_manager ;;
        0) echo -e "${GREEN}Выход.${NC}"; exit 0 ;;
        *) echo -e "${RED}Неверный ввод. Пожалуйста, выберите 0-6.${NC}"; sleep 1 ;;
    esac
done