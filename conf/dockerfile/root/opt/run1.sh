#!/usr/bin/env bash
# -*- coding: utf-8 -*-

#=====================================================
# 文件名: run1.sh
# 版本: 1.0
# 描述: Spring Boot JAR / Nodejs / PHP 智能启动脚本
# 作者: AI Assistant
# 创建时间: 2025-03-21
#=====================================================

# 进程ID数组
declare -a G_PIDS=()

# 函数：日志记录
log() {
    case "${1:-}" in
    file)
        shift
        log_file="$2"
        if [ -f "$log_file" ]; then
            shift
        else
            log_file="/tmp/$(date +%Y%m%d).log"
        fi
        echo "[$(date +%Y%m%d_%u_%T.%3N)] [RUN1] $*" | tee -a "$log_file"
        ;;
    *)
        echo "[$(date +%Y%m%d_%u_%T.%3N)] [RUN1] $*"
        ;;
    esac
}

# 函数：日志轮转
rotate_log() {
    local log_file="$1" max_size="$2"
    local current_size timestamp base_name dir_name archive_name
    # 检查文件是否存在
    [ -f "$log_file" ] || return 0
    # 获取文件大小
    current_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null)
    # 如果文件大小超过阈值，进行轮转
    if [ "${current_size:-0}" -gt "$max_size" ]; then
        timestamp=$(date +%Y%m%d-%H%M%S)
        base_name=$(basename "$log_file")
        dir_name=$(dirname "$log_file")
        archive_name="${dir_name}/${base_name}.${timestamp}"
        # 重命名旧日志文件
        [ -f "$log_file" ] && mv "$log_file" "${archive_name}"
        # 创建新的日志文件
        touch "$log_file"
        # 清理旧的日志文件（5天前）
        find "$dir_name" -name "${base_name}.*" -type f -mtime +5 -delete 2>/dev/null
    fi
}

# 函数：清理进程
cleanup() {
    log "begin clean..."

    for pid in "${G_PIDS[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null
            rm -f "${G_PATH}"/*.pid
        fi
    done
}

# 函数：获取JVM参数
get_jvm_opts() {
    local final_opts="" file_opts
    local default_jvm_opts="-Xms512m -Xmx1024m" # 默认JVM参数
    local jvm_opts_files=(
        "./jvm.options"                # 当前目录
        "${G_PATH}/jvm.options"        # 脚本目录
        "${G_PATH}/config/jvm.options" # 配置目录
        "/etc/jvm.options"             # 系统配置目录
    )

    # 1. 首先使用默认值
    final_opts="${default_jvm_opts}"

    # 2. 从配置文件获取（按优先级从低到高）
    for opts_file in "${jvm_opts_files[@]}"; do
        [ -f "$opts_file" ] || continue
        file_opts=$(grep -vE '^\s*$|^\s*#' "${opts_file}" | xargs)
        if [ -n "${file_opts}" ]; then
            log "从配置文件加载JVM参数: ${opts_file}"
            final_opts="${file_opts}"
        fi
    done

    # 3. 从环境变量获取（覆盖配置文件）
    if [ -n "${JAVA_OPTS}" ]; then
        log "从JAVA_OPTS环境变量加载JVM参数"
        final_opts="${JAVA_OPTS}"
    fi

    # 4. 从JVM_OPTS环境变量获取（最高优先级）
    if [ -n "${JVM_OPTS}" ]; then
        log "从JVM_OPTS环境变量加载JVM参数"
        final_opts="${JVM_OPTS}"
    fi

    echo "${final_opts}"
}

# 函数：按文件名自然排序查找所有配置文件
find_configs() {
    local configs=() yml_files properties_files profile_files

    # 使用-V参数进行自然排序获取所有配置文件
    mapfile -t yml_files < <(find . -maxdepth 2 -type f \( -iname "*.yml" -o -iname "*.yaml" \) | sort -V)
    mapfile -t properties_files < <(find . -maxdepth 2 -name "*.properties" -type f | sort -V)
    mapfile -t profile_files < <(find . -maxdepth 2 -type f -iname "profile.*" | sort -V)

    # 返回找到的配置文件数组，保持类型信息
    # 优先使用 profile 文件
    if [ ${#profile_files[@]} -gt 0 ]; then
        configs+=("profile:${profile_files[0]}")
    # 如果没有 profile，则使用 yml 文件
    elif [ ${#yml_files[@]} -gt 0 ]; then
        for file in "${yml_files[@]}"; do
            case "${file}" in
            *.yml | *.yaml) configs+=("yml:${file}") ;;
            esac
        done
    # 如果既没有 profile 也没有 yml，则使用 properties
    elif [ ${#properties_files[@]} -gt 0 ]; then
        for file in "${properties_files[@]}"; do
            configs+=("properties:${file}")
        done
    fi

    printf "%s\n" "${configs[@]}"
}

# 函数：启动Java应用
start_java() {
    command -v redis-server && redis-server --daemonize yes

    local jar_files jvm_opts i=0 pid config_name config_path config_files start_cmd
    local config_entry config_type config_file last_config_entry

    # 获取JVM参数
    jvm_opts=$(get_jvm_opts)
    log "使用JVM参数: ${jvm_opts}"

    # 按文件名自然排序查找所有jar文件
    mapfile -t jar_files < <(find . -maxdepth 2 -name "*.jar" -type f | sort -V)
    if [ ${#jar_files[@]} -eq 0 ]; then
        log "错误: 未找到JAR文件"
        return 1
    fi
    log "找到 ${#jar_files[@]} 个JAR文件: ${jar_files[*]}"

    # 按文件名自然排序查找所有配置文件
    mapfile -t config_files < <(find_configs)
    log "找到 ${#config_files[@]} 个配置文件: ${config_files[*]}"

    # 获取最后一个配置文件
    if [ ${#config_files[@]} -gt 0 ]; then
        last_config_entry="${config_files[-1]}"
    fi

    # 启动每个jar文件
    for jar_file in "${jar_files[@]}"; do
        # 检查jar文件是否存在
        if [ ! -f "${jar_file}" ]; then
            log "错误: JAR文件 ${jar_file} 不存在"
            continue
        fi
        ## 跳过sdk开头的jar文件
        case "$(basename "${jar_file}")" in
        sdk* | core*)
            log "跳过sdk/core开头的JAR文件: ${jar_file}"
            continue
            ;;
        esac

        start_cmd="java ${jvm_opts} -jar ${jar_file}"

        # 使用对应序号的配置文件（如果存在），否则使用最后一个配置文件
        if [ "$i" -lt ${#config_files[@]} ]; then
            config_entry="${config_files[$i]}"
        elif [ -n "$last_config_entry" ]; then
            config_entry="$last_config_entry"
            log "使用最后一个配置文件用于额外的JAR"
        fi

        if [ -n "$config_entry" ]; then
            config_type="${config_entry%%:*}"
            config_file="${config_entry#*:}"

            case "${config_type}" in
            "yml")
                log "正在启动第 $((i + 1)) 个JAR: ${jar_file}，使用yml配置: ${config_file}"
                start_cmd="${start_cmd} --spring.config.location=${config_file}"
                ;;
            "properties")
                log "正在启动第 $((i + 1)) 个JAR: ${jar_file}，使用properties配置: ${config_file}"
                config_name=$(basename "${config_file}" .properties)
                config_path=$(dirname "${config_file}")
                start_cmd="${start_cmd} --spring.config.name=${config_name} --spring.config.location=${config_path}/"
                ;;
            "profile")
                log "正在启动第 $((i + 1)) 个JAR: ${jar_file}, 使用profile: ${config_file##*.}"
                start_cmd="${start_cmd} --spring.profiles.active=${config_file##*.}"
                ;;
            esac
        fi

        # 根据start mode决定启动方式
        if [ "${START_MODE:-}" = "nohup" ]; then
            # shellcheck disable=SC2086
            nohup ${start_cmd} >"${G_PATH}/$(basename "${jar_file}").nohup.out" 2>&1 &
            log "应用已在后台启动，日志输出到 ${G_PATH}/$(basename "${jar_file}").nohup.out"
        else
            ${start_cmd} &
        fi

        # 保存进程ID
        pid=$!
        G_PIDS+=("${pid}")
        echo "${pid}" >"${G_PATH}/$(basename "${jar_file}").pid"
        log "应用已在后台启动，进程ID: ${pid}"

        i=$((i + 1))
    done
}

# 函数：启动PHP应用
start_php() {
    php -v

    local php_count=0
    for i in /usr/sbin/php-fpm*; do
        [ -f "$i" ] && php_count=$((php_count + 1))
    done
    [[ "$php_count" -eq 0 ]] && return

    [ -d /var/lib/php/sessions ] && chmod -R 777 /var/lib/php/sessions
    [ -d /run/php ] || mkdir -p /run/php
    [ -d "$G_HTML" ] || mkdir "$G_HTML"
    [ -f "$G_HTML/index.html" ] || date >>"$G_HTML/index.html"

    # 启动PHP-FPM
    for fpm in /usr/sbin/php-fpm*; do
        [ -x "$fpm" ] && $fpm -F &
        G_PIDS+=("$!")
        if pgrep -a -i -n php-fpm; then
            log "PHP-FPM启动成功"
        else
            log "PHP-FPM启动失败"
        fi
    done

    # 启动Web服务器
    if command -v nginx && nginx -t; then
        nginx -g "daemon off;" &
        G_PIDS+=("$!")
    elif command -v apachectl && apachectl -t; then
        apachectl -k start -D FOREGROUND &
        G_PIDS+=("$!")
    else
        log "未找到Web服务器"
    fi

    # 创建ThinkPHP运行时目录
    while [ -d "$G_HTML" ]; do
        for dir in "$G_HTML"/ "$G_HTML"/*/ "$G_HTML"/*/*/; do
            [ -d "$dir" ] || continue
            if [[ -f "${dir}"think && -d ${dir}thinkphp ]]; then
                if [[ -d ${dir}application || -d ${dir}app ]]; then
                    run_dir="${dir}runtime"
                    [[ -d "$run_dir" ]] || mkdir "$run_dir"
                    dir_owner="$(stat -t -c %U "$run_dir")"
                    [[ "$dir_owner" == www-data ]] || chown -R www-data:www-data "$run_dir"
                fi
            fi
        done
        sleep 10m
    done &

    # 清理运行时日志文件
    while [ -d "$G_HTML" ]; do
        for dir in "$G_HTML/runtime/" "$G_HTML"/*/runtime/ "$G_HTML"/*/*/runtime/; do
            [ -d "$dir" ] || continue
            find "${dir}" -type f -iname '*.log' -ctime +3 -print0 | xargs -0 rm -f >/dev/null 2>&1
        done
        sleep 1d
    done &
}

# 函数：启动Node.js应用
start_node() {
    cd "/app" || return
    npm run start &
    G_PIDS+=("$!")
    log "Node.js应用启动成功"
}

# 函数：设置jemalloc
set_jemalloc() {
    case "$PHP_VERSION" in
    5.* | 7.* | 8.*)
        log "禁用 jemalloc (PHP $PHP_VERSION)"
        ;;
    *)
        lib_jemalloc=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
        lib_jemalloc2=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2
        for f in "$lib_jemalloc" "$lib_jemalloc2"; do
            [ -f "$f" ] || continue
            export LD_PRELOAD=$f
            log "设置 LD_PRELOAD=$LD_PRELOAD ..."
            break
        done
        ;;
    esac
}

# 函数：检查jemalloc
check_jemalloc() {
    sleep 5
    for pid in "${G_PIDS[@]}"; do
        [ -f "/proc/$pid/smaps" ] || continue
        if grep -q jemalloc "/proc/$pid/smaps"; then
            log "进程 $pid 正在使用 jemalloc..."
        else
            log "进程 $pid 未使用 jemalloc"
        fi
    done
}

# 函数：自动更新
schedule_upgrade() {
    local trigger_file=.trigger_file upgrade_type=""
    local app_path="/app"

    if [[ -f "$G_HTML/$trigger_file" ]]; then
        upgrade_type="$G_HTML"
    fi
    if [[ -f "$app_path/$trigger_file" ]]; then
        upgrade_type="$app_path"
    fi
    if [[ -z "$upgrade_type" ]]; then
        return 0
    fi

    local upgrade_url=http://o.flyh5.cn/d
    local upgrade_file=upgrade_check.txt
    local upgrade_file_tmp=/tmp/$upgrade_file
    touch "$upgrade_file_tmp"
    curl -fsSLo "$upgrade_file_tmp" "${upgrade_url}/$upgrade_file" 2>/dev/null
    local app_id_remote app_ver_remote
    app_id_remote=$(awk -F= '/^app_id=/ {print $2}' "$upgrade_file_tmp")
    app_ver_remote=$(awk -F= '/^app_ver=/ {print $2}' "$upgrade_file_tmp")

    # shellcheck source=/dev/null
    source "$upgrade_type/$trigger_file"
    if [[ "${app_id:-1}" == "$app_id_remote" && "${app_ver:-1}" == "$app_ver_remote" ]]; then
        return 0
    fi

    while read -r line; do
        curl -fsSLo /tmp/"${line}" "${upgrade_url}/$line"
        curl -fsSLo /tmp/"${line}".sha256 "${upgrade_url}/${line}.sha256"
        if cd /tmp && sha256sum -c "${line}".sha256; then
            log "decompress $line"
            tar -C "$upgrade_type/" -zxf /tmp/"${line}" && rm -f /tmp/"${line}"*
        fi
    done < <(awk -F= '/^app_zip=/ {print $2}' "$upgrade_file_tmp")

    log "set app_ver=$app_ver_remote 到 $upgrade_type/$trigger_file"
    sed -i "/^app_ver=/s/=.*/=$app_ver_remote/" "$upgrade_type/$trigger_file"
    rm -f /tmp/${upgrade_file}*
}

# 主函数
main() {
    set -Eeo pipefail

    # 定义全局变量
    G_NAME=$(basename "$0")
    G_PATH=$(dirname "$(readlink -f "$0")")
    G_HTML=/var/www/html

    # 初始化日志文件路径
    if [ -w "/app" ]; then
        G_LOG="/app/${G_NAME}.log"
    elif [ -w "$G_PATH" ]; then
        G_LOG="${G_PATH}/${G_NAME}.log"
    else
        G_LOG="/tmp/${G_NAME}.log"
    fi
    touch "$G_LOG"

    log file "$G_LOG" "$G_PATH/$G_NAME 开始执行..."

    # 设置jemalloc
    # set_jemalloc

    # 设置启动模式
    if [[ "$1" == nohup || -f "$G_PATH"/.nohup ]]; then
        START_MODE='nohup'
    elif [[ "$1" == debug || -f "$G_PATH"/.debug ]]; then
        START_MODE='debug'
    fi

    # 启动各类应用
    command -v npm >/dev/null 2>&1 && start_node "$@"
    command -v php >/dev/null 2>&1 && start_php "$@"
    command -v java >/dev/null 2>&1 && start_java "$@"

    # 启动自动更新
    while true; do
        schedule_upgrade
        sleep 60
    done &
    G_PIDS+=("$!")

    # 检查jemalloc
    # check_jemalloc &

    # 启动日志处理
    local max_size=$((1024 * 1024 * 1024)) # 1GB
    while true; do
        # 处理所有日志文件
        for log_file in "$G_LOG" /app/log/*.log; do
            [ -f "$log_file" ] || continue
            rotate_log "$log_file" "$max_size"
        done
        sleep 1d
    done &
    G_PIDS+=("$!")

    # 注册信号处理
    trap cleanup SIGTERM SIGINT SIGQUIT EXIT

    # 根据启动模式决定后续行为
    case "${START_MODE:-wait}" in
    nohup)
        log "使用nohup方式启动，即将返回"
        return
        ;;
    debug)
        # 调试模式：允许直接终止Java进程而不停止容器
        exec tail -f "$G_LOG"
        ;;
    *)
        # 等待模式：终止Java进程将导致容器停止
        tail -f "$G_LOG" &
        G_PIDS+=("$!")
        wait
        ;;
    esac
}

# 执行主函数
main "$@"
