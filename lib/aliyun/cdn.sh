#!/usr/bin/env bash
# -*- coding: utf-8 -*-
show_cdn_help() {
    echo "CDN (内容分发网络) 操作："
    echo "  list [format]                           - 列出 CDN 域名"
    echo "  create <域名> <源站> <源站类型>         - 添加 CDN 加速域名"
    echo "  delete <域名>                           - 删除 CDN 加速域名"
    echo "  update <域名> <源站> <源站类型>         - 修改 CDN 域名配置"
    echo "  refresh <类型> <路径>                   - 刷新 CDN 目录或文件"
    echo "  prefetch <路径>                         - 预热 CDN 文件"
    echo "  pay [show_message]                      - 购买 CDN 资源包（自动判断余量）"
    echo
    echo "示例："
    echo "  $0 cdn list                                                  # 列出所有域名"
    echo "  $0 cdn list json                                            # 以 JSON 格式列出域名"
    echo "  $0 cdn create example.com example.oss-cn-hangzhou.aliyuncs.com oss  # 添加域名加速"
    echo "  $0 cdn delete example.com                                   # 删除加速域名"
    echo "  $0 cdn update example.com new-origin.com ip                 # 更新域名配置"
    echo "  $0 cdn refresh directory https://example.com/dir           # 刷新目录"
    echo "  $0 cdn refresh file https://example.com/path/to/file.jpg   # 刷新文件"
    echo "  $0 cdn prefetch https://example.com/path/to/file.jpg       # 预热文件"
    echo "  $0 cdn pay                                                  # 静默购买资源包"
    echo "  $0 cdn pay true                                            # 显示购买信息"
}

handle_cdn_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) cdn_list "$@" ;;
    create) cdn_create "$@" ;;
    delete) cdn_delete "$@" ;;
    update) cdn_update "$@" ;;
    refresh) cdn_refresh "$@" ;;
    prefetch) cdn_prefetch "$@" ;;
    pay) cdn_pay "$@" ;;
    *)
        echo "错误：未知的 CDN 操作：$operation" >&2
        show_cdn_help
        exit 1
        ;;
    esac
}

cdn_list() {
    local format=${1:-human}
    echo "列出 CDN 域名："
    local result
    result=$(aliyun --profile "${profile:-}" cdn DescribeUserDomains)
    ret=$?
    if [ "$ret" -ne 0 ]; then
        echo "错误：无法获取 CDN 域名列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "DomainName\tCname\tDomainStatus\tGmtCreated"
        echo "$result" | jq -r '.Domains.PageData[] | [.DomainName, .Cname, .DomainStatus, .GmtCreated] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.Domains.PageData | length') -eq 0 ]]; then
            echo "没有找到 CDN 域名。"
        else
            echo "域名                  CNAME                                  状态    创建时间"
            echo "--------------------  --------------------------------------  ------  -------------------------"
            echo "$result" | jq -r '.Domains.PageData[] | [.DomainName, .Cname, .DomainStatus, .GmtCreated] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-20s  %-38s  %-6s  %s\n", $1, $2, $3, $4
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "cdn" "list" "$result" "$format"
}

cdn_create() {
    local domain_name=$1 sources=$2 source_type=$3
    echo "添加 CDN 加速域名："
    local result
    result=$(aliyun --profile "${profile:-}" cdn AddCdnDomain \
        --DomainName "$domain_name" \
        --Sources "[{\"content\":\"$sources\",\"type\":\"$source_type\",\"priority\":\"20\",\"port\":80,\"weight\":\"15\"}]" \
        --CdnType web \
        --Scope domestic)
    echo "$result" | jq '.'
    log_result "$profile" "$region" "cdn" "create" "$result"
}

cdn_delete() {
    local domain_name=$1
    echo "删除 CDN 加速域名："
    local result
    result=$(aliyun --profile "${profile:-}" cdn DeleteCdnDomain --DomainName "$domain_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "cdn" "delete" "$result"
}

cdn_update() {
    local domain_name=$1 sources=$2 source_type=$3
    echo "修改 CDN 域名配置："
    local result
    result=$(aliyun --profile "${profile:-}" cdn ModifyCdnDomain \
        --DomainName "$domain_name" \
        --Sources "[{\"content\":\"$sources\",\"type\":\"$source_type\",\"priority\":\"20\",\"port\":80,\"weight\":\"15\"}]")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "cdn" "update" "$result"
}

cdn_refresh() {
    local type=$1
    local path=$2

    if [ -z "$type" ] || [ -z "$path" ]; then
        echo "错误：刷新操作需要指定类型（directory 或 file）和路径。" >&2
        return 1
    fi

    local object_type
    case "$type" in
    directory) object_type="Directory" ;;
    file) object_type="File" ;;
    *)
        echo "错误：无效的刷新类型。请使用 'directory' 或 'file'。" >&2
        return 1
        ;;
    esac

    echo "刷新 CDN $type ："
    local result
    result=$(aliyun --profile "${profile:-}" cdn RefreshObjectCaches \
        --region "$region" \
        --Force true \
        --ObjectPath "$path" \
        --ObjectType "$object_type")

    ret=$?
    if [ "$ret" -eq 0 ]; then
        echo "CDN $type 刷新请求已提交："
        echo "$result" | jq '.'
    else
        echo "错误：CDN $type 刷新请求失败。"
        echo "$result"
    fi
    log_result "$profile" "$region" "cdn" "refresh" "$result"
}

cdn_prefetch() {
    local path=$1
    if [ -z "$path" ]; then
        echo "错误：预热操作需要指定文件路径。" >&2
        return 1
    fi

    echo "预热 CDN 文件："
    local result
    result=$(aliyun --profile "${profile:-}" cdn PushObjectCache \
        --region "$region" \
        --ObjectPath "$path")

    ret=$?
    if [ "$ret" -eq 0 ]; then
        echo "CDN 文件预热请求已提交："
        echo "$result" | jq '.'
    else
        echo "错误：CDN 文件预热请求失败。"
        echo "$result"
    fi
    log_result "$profile" "$region" "cdn" "prefetch" "$result"
}

# CDN 资源包购买函数
cdn_pay() {
    set -e
    local show_message="$1"

    # 资源包规格和价格配置
    local package_unit_size=1024 # 1TB = 1024GB
    local package_unit_price=126 # 每 TB 单价 126 元

    # 阈值配置
    local remaining_threshold=1.000 # 剩余容量阈值 1.9TB
    local balance_threshold=700     # 账户余额阈值 700 元

    # 查询当前资源包剩余容量
    local query_result
    local page_num=1
    local remaining_amount=0
    local remaining_https_request=0

    while true; do
        query_result=$(aliyun --profile "${profile:-}" bssopenapi QueryResourcePackageInstances --ProductCode dcdn --PageNum "$page_num" --PageSize 100) || {
            [[ -n "$show_message" ]] && echo -e "[CDN] \033[0;31m查询资源包失败\033[0m"
            return 1
        }

        # 直接处理当前页的数据
        remaining_amount="$(
            echo "$remaining_amount + $(
                echo "$query_result" | jq -r '.Data.Instances.Instance[] | select(.RemainingAmount != "0" and .RemainingAmountUnit != "次") | if .RemainingAmountUnit == "GB" then (. | .RemainingAmount | tonumber) / 1024 elif .RemainingAmountUnit == "TB" then (. | .RemainingAmount | tonumber) else 0 end' | awk '{s+=$1} END {printf "%.3f", s}' 2>/dev/null || echo "-1"
            )" | bc -l
        )"
        remaining_https_request="$(
            echo "$remaining_https_request + $(
                echo "$query_result" | jq -r '.Data.Instances.Instance[] | select(.RemainingAmount != "0" and .RemainingAmountUnit == "次") | .RemainingAmount' | awk '{s+=$1} END {printf "%.0f", s}' 2>/dev/null || echo "0"
            )" | bc -l
        )"

        # 如果当前页的结果数量小于 100，说明没有更多页了
        if [[ $(echo "$query_result" | jq '.Data.Instances.Instance | length') -lt 100 ]]; then
            break
        fi

        ((page_num++))
    done

    if [[ -n "$show_message" ]]; then
        local https_color_code="\033[0;31m" # 默认红色
        if ((remaining_https_request >= 20000000)); then
            https_color_code="\033[0;32m" # 大于2000万次时显示绿色
        fi
        echo -e "[CDN] 剩余HTTPS请求次数: ${https_color_code}$(
            echo "$remaining_https_request" | awk '{
            if ($1 >= 100000000) {
                printf "%.6f亿", $1/100000000
            } else if ($1 >= 10000000) {
                printf "%.4f千万", $1/10000000
            } else if ($1 >= 10000) {
                printf "%.2f万", $1/10000
            } else {
                printf "%d", $1
            }
        }'
        )次\033[0m"
    fi

    # 检查是否获取到有效的剩余容量值
    if [ "$remaining_amount" = "-1" ]; then
        if [[ -n "$show_message" ]]; then
            echo -e "[CDN] \033[0;31m无法获取资源包剩余容量信息\033[0m"
        fi
        return 1
    fi

    # 显示剩余容量信息并判断是否需要购买
    if [[ -n "$show_message" ]]; then
        local traffic_color_code="\033[0;31m" # 默认红色
        if (($(echo "$remaining_amount > $remaining_threshold" | bc -l))); then
            traffic_color_code="\033[0;32m" # 充足时显示绿色
        fi
        echo -e "[CDN] 剩余下行流量: ${traffic_color_code}${remaining_amount:-0}TB\033[0m"
    fi

    # 如果剩余容量充足，则跳过购买
    if (($(echo "$remaining_amount > $remaining_threshold" | bc -l))); then
        return 0
    fi

    # 查询账户可用余额
    local available_balance
    available_balance="$(
        aliyun --profile "${profile:-}" bssopenapi QueryAccountBalance |
            jq -r '.Data.AvailableAmount' |
            awk '{gsub(/,/,""); print int($0)}'
    )"

    # 检查账户余额是否充足
    if ((available_balance < (balance_threshold + package_unit_price))); then
        echo -e "[CDN] \033[0;31m账户余额 $available_balance 元不足，无法购买资源包。\033[0m"
        return 1
    fi

    # 根据账户余额计算可购买的资源包规格
    local package_size
    for size in 200 50 10 5 1; do
        local special_discount=$((size == 200 ? 7870 : 0)) # 200TB 包有特殊优惠
        if ((available_balance > balance_threshold + package_unit_price * size - special_discount)); then
            package_size=$((package_unit_size * size))
            break
        fi
    done

    # 执行购买操作
    log_result "${profile:-}" "$region" "cdn" "pay" "当前剩余: ${remaining_amount:-0}TB，准备购买 $((package_size / package_unit_size))TB 资源包..."
    local result
    result=$(aliyun --profile "${profile:-}" bssopenapi CreateResourcePackage \
        --ProductCode dcdn \
        --PackageType FPT_dcdnpaybag_deadlineAcc_1541405199 \
        --Duration 1 \
        --PricingCycle Year \
        --Specification "$package_size")

    log_result "${profile:-}" "$region" "cdn" "pay" "$result"
}
