#!/system/bin/sh
SKIPUNZIP=1

language="zh"

init_language() {
    locale=""
    for _prop in persist.sys.locale ro.product.locale ro.product.locale.language persist.sys.language; do
        locale=$(getprop "$_prop" 2>/dev/null)
        [ -n "$locale" ] && break
    done
    [ -n "$locale" ] || locale="zh"

    case "$locale" in
        *[Ee][Nn]*|[Uu][Ss]*|[Uu][Kk]*|[Cc][Aa]*|[Aa][Uu]*|[Nn][Zz]*) language="en" ;;
    esac
}

pick() {
    if [ "$language" = "en" ]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

ui_msg() {
    ui_print "$(pick "$1" "$2")"
}

ui_error() {
    abort "$(pick "$1" "$2")"
}

ensure_dir() {
    [ -d "$1" ] || mkdir -p "$1"
}

extract_quiet() {
    unzip -o "$ZIPFILE" "$1" -d "$2" >/dev/null 2>&1
}

extract_or_abort() {
    extract_quiet "$1" "$2" || ui_error "$3" "$4"
}

extract_many() {
    _dest="$1"
    shift
    for _item in "$@"; do
        extract_quiet "$_item" "$_dest"
    done
}

indent_of() {
    printf '%s' "$1" | sed 's/[^[:space:]].*$//' | tr -d '\n' | wc -c
}

is_root_key_line() {
    printf '%s\n' "$1" | grep -qE '^[^[:space:]#][^:]*:'
}

is_dns_key_line() {
    _key="$1"
    _line="$2"
    _indent="$3"
    [ "$_indent" -eq 2 ] &&
        printf '%s\n' "$_line" | grep -qE "^[[:space:]][[:space:]]${_key}:[[:space:]]*"
}

detect_raw_group() {
    for g in net_raw network inet rawip; do
        if grep -q "^$g:" /etc/group 2>/dev/null; then
            echo "$g"
            return 0
        fi
    done
    echo "root"
}

AGH_DIR="/data/adb/agh"
AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
PROXY_SCRIPT="$AGH_DIR/scripts/ProxyConfig.sh"
BIN_DIR="$AGH_DIR/bin"
SCRIPT_DIR="$AGH_DIR/scripts"
AGH_YAML="$BIN_DIR/AdGuardHome.yaml"
FILTER_CACHE_DIR="$BIN_DIR/data/filters"

BOX_MODULE_DIR="/data/adb/modules/box_for_root"
BOX_CONFIG_DIR="/data/adb/box"
BOX_MIHOMO_CONFIG="$BOX_CONFIG_DIR/mihomo/config.yaml"
BOX_SINGBOX_CONFIG="$BOX_CONFIG_DIR/sing-box/config.json"

TMPDIR="${TMPDIR:-/tmp}"
ensure_dir "$TMPDIR"

BACKUP_DIR="/data/adb/modules/adg_installation_module"
USER_RULES_BAK="$BACKUP_DIR/user_rules.yaml.bak"
WHITELIST_BAK="$BACKUP_DIR/whitelist_filters.yaml.bak"
FILTERS_BAK="$BACKUP_DIR/filters.yaml.bak"
FALLBACK_DNS_BAK="$BACKUP_DIR/fallback_dns.yaml.bak"
BOOTSTRAP_DNS_BAK="$BACKUP_DIR/bootstrap_dns.yaml.bak"
UPSTREAM_DNS_BAK="$BACKUP_DIR/upstream_dns.yaml.bak"
UPSTREAM_DNS_FILE_BAK="$BACKUP_DIR/upstream_dns_file.yaml.bak"

init_language

cleanup_old_backups() {
    [ -d "$BACKUP_DIR" ] || return 0
    
    for _bak in "$USER_RULES_BAK" "$WHITELIST_BAK" "$FILTERS_BAK" \
                "$FALLBACK_DNS_BAK" "$BOOTSTRAP_DNS_BAK" "$UPSTREAM_DNS_BAK" "$UPSTREAM_DNS_FILE_BAK"; do
        [ -f "$_bak" ] && rm -f "$_bak"
    done
    
    [ -d "$BACKUP_DIR/filters" ] && rm -rf "$BACKUP_DIR/filters"
    
    return 0
}

backup_top_block() {
    _yaml="$1"
    _keyword="$2"
    _output="$3"

    [ -f "$_yaml" ] || return 0

    _start=$(grep -nE "^${_keyword}:[[:space:]]*(\\[\\])?[[:space:]]*$" "$_yaml" 2>/dev/null | head -n 1 | cut -d: -f1)
    [ -n "$_start" ] || return 0

    ensure_dir "$BACKUP_DIR"
    sed -n "${_start},\$p" "$_yaml" | sed -n '1p;2,$ {/^[^[:space:]#][^:]*:/q;p}' > "$_output"
    [ -s "$_output" ] || rm -f "$_output"
    return 0
}

backup_dns_subblock() {
    _yaml="$1"
    _key="$2"
    _out="$3"

    [ -f "$_yaml" ] || return 0
    ensure_dir "$BACKUP_DIR"

    _in_dns=false
    _in_target=false
    _target_indent=0
    : > "$_out"

    while IFS= read -r _line || [ -n "$_line" ]; do
        _indent=$(indent_of "$_line")

        if [ "$_in_dns" = false ] && printf '%s\n' "$_line" | grep -qE "^dns:[[:space:]]*$"; then
            _in_dns=true
            continue
        fi

        [ "$_in_dns" = false ] && continue

        if [ "$_indent" -eq 0 ] && printf '%s\n' "$_line" | grep -qE "^[a-zA-Z_]"; then
            [ -s "$_out" ] || rm -f "$_out"
            return 0
        fi

        if [ "$_in_target" = false ] && is_dns_key_line "$_key" "$_line" "$_indent"; then
            _in_target=true
            _target_indent=$_indent
            printf '%s\n' "$_line" >> "$_out"
            continue
        fi

        if [ "$_in_target" = true ]; then
            if [ "$_indent" -le "$_target_indent" ] && [ "$_indent" -ge 2 ]; then
                [ -s "$_out" ] || rm -f "$_out"
                return 0
            fi
            printf '%s\n' "$_line" >> "$_out"
        fi
    done < "$_yaml"

    [ -s "$_out" ] || rm -f "$_out"
    return 0
}

backup_all_configs() {
    [ -f "$AGH_YAML" ] || return 0

    for _entry in \
        "user_rules|$USER_RULES_BAK|top" \
        "whitelist_filters|$WHITELIST_BAK|top" \
        "filters|$FILTERS_BAK|top" \
        "upstream_dns|$UPSTREAM_DNS_BAK|dns" \
        "bootstrap_dns|$BOOTSTRAP_DNS_BAK|dns" \
        "fallback_dns|$FALLBACK_DNS_BAK|dns" \
        "upstream_dns_file|$UPSTREAM_DNS_FILE_BAK|dns"
    do
        _key=${_entry%%|*}
        _rest=${_entry#*|}
        _bak=${_rest%%|*}
        _type=${_rest##*|}

        case "$_type" in
            top) backup_top_block "$AGH_YAML" "$_key" "$_bak" ;;
            dns) backup_dns_subblock "$AGH_YAML" "$_key" "$_bak" ;;
        esac
    done

    ui_msg "- Backed up all config blocks" "- 已备份所有配置块"
    return 0
}

backup_filter_files() {
    [ -d "$FILTER_CACHE_DIR" ] || return 0
    ensure_dir "$BACKUP_DIR/filters"

    for _bak in "$FILTERS_BAK" "$WHITELIST_BAK"; do
        [ -f "$_bak" ] || continue
        for _id in $(grep -E '^[[:space:]]*id:[[:space:]]*[0-9]+' "$_bak" 2>/dev/null | sed 's/.*id:[[:space:]]*//'); do
            [ -f "$FILTER_CACHE_DIR/${_id}.txt" ] && cp -f "$FILTER_CACHE_DIR/${_id}.txt" "$BACKUP_DIR/filters/"
        done
    done

    if [ -d "$BACKUP_DIR/filters" ] && [ "$(ls -A "$BACKUP_DIR/filters" 2>/dev/null)" ]; then
        ui_msg "- Backed up filter cache files" "- 已备份过滤器缓存文件"
    fi
    return 0
}

merge_top_block() {
    _yaml="$1"
    _key="$2"
    _bak="$3"

    [ -f "$_yaml" ] || return 0
    [ -s "$_bak" ] || return 0

    _tmp="${_yaml}.tmp"
    : > "$_tmp"
    _skip=false
    _replaced=false

    while IFS= read -r _ln || [ -n "$_ln" ]; do
        if [ "$_skip" = true ]; then
            if is_root_key_line "$_ln"; then
                _skip=false
            else
                continue
            fi
        fi

        if [ "$_replaced" = false ] &&
           printf '%s\n' "$_ln" | grep -qE "^${_key}:[[:space:]]*(\\[\\])?[[:space:]]*$"; then
            cat "$_bak" >> "$_tmp"
            _replaced=true
            _skip=true
            continue
        fi

        printf '%s\n' "$_ln" >> "$_tmp"
    done < "$_yaml"

    [ "$_replaced" = false ] && cat "$_bak" >> "$_tmp"
    mv "$_tmp" "$_yaml"
    return 0
}

merge_dns_list_block() {
    _yaml="$1"
    _key="$2"
    _bak="$3"

    [ -f "$_yaml" ] || return 0
    [ -s "$_bak" ] || return 0

    _tmp="${_yaml}.tmp"
    : > "$_tmp"
    _in_dns=false
    _skip=false
    _replaced=false

    while IFS= read -r _ln || [ -n "$_ln" ]; do
        _ind=$(indent_of "$_ln")

        if [ "$_in_dns" = false ]; then
            printf '%s\n' "$_ln" >> "$_tmp"
            if printf '%s\n' "$_ln" | grep -qE '^dns:[[:space:]]*$'; then
                _in_dns=true
            fi
            continue
        fi

        if [ "$_skip" = true ]; then
            if { [ "$_ind" -eq 2 ] && printf '%s\n' "$_ln" | grep -qE '^[[:space:]][[:space:]][a-z_][a-z0-9_]*:[[:space:]]*'; } ||
               { [ "$_ind" -eq 0 ] && is_root_key_line "$_ln"; }; then
                _skip=false
                [ "$_ind" -eq 0 ] && _in_dns=false
            else
                continue
            fi
        fi

        if [ "$_replaced" = false ] && is_dns_key_line "$_key" "$_ln" "$_ind"; then
            cat "$_bak" >> "$_tmp"
            _replaced=true
            _skip=true
            continue
        fi

        if [ "$_ind" -eq 0 ] && is_root_key_line "$_ln"; then
            if [ "$_replaced" = false ]; then
                cat "$_bak" >> "$_tmp"
                _replaced=true
            fi
            _in_dns=false
            printf '%s\n' "$_ln" >> "$_tmp"
            continue
        fi

        printf '%s\n' "$_ln" >> "$_tmp"
    done < "$_yaml"

    if [ "$_in_dns" = true ] && [ "$_replaced" = false ]; then
        cat "$_bak" >> "$_tmp"
    fi

    mv "$_tmp" "$_yaml"
    return 0
}

replace_dns_scalar() {
    _yaml="$1"
    _key="$2"
    _bak="$3"

    [ -f "$_yaml" ] || return 0
    [ -s "$_bak" ] || return 0

    _val=$(head -n 1 "$_bak" 2>/dev/null)
    [ -n "$_val" ] || return 0

    _tmp="${_yaml}.tmp"
    : > "$_tmp"
    _in_dns=false
    _done=false

    while IFS= read -r _ln || [ -n "$_ln" ]; do
        _ind=$(indent_of "$_ln")

        if [ "$_in_dns" = false ] && printf '%s\n' "$_ln" | grep -qE "^dns:[[:space:]]*$"; then
            _in_dns=true
            printf '%s\n' "$_ln" >> "$_tmp"
            continue
        fi

        if [ "$_in_dns" = true ] &&
           [ "$_done" = false ] &&
           is_dns_key_line "$_key" "$_ln" "$_ind"; then
            printf '%s\n' "$_val" >> "$_tmp"
            _done=true
            continue
        fi

        if [ "$_in_dns" = true ] &&
           [ "$_ind" -eq 0 ] &&
           printf '%s\n' "$_ln" | grep -qE "^[a-zA-Z_]"; then
            if [ "$_done" = false ]; then
                printf '%s\n' "$_val" >> "$_tmp"
                _done=true
            fi
            _in_dns=false
        fi

        printf '%s\n' "$_ln" >> "$_tmp"
    done < "$_yaml"

    [ "$_in_dns" = true ] && [ "$_done" = false ] && printf '%s\n' "$_val" >> "$_tmp"
    mv "$_tmp" "$_yaml"
    return 0
}

merge_all_configs() {
    [ -f "$AGH_YAML" ] || return 0

    for _entry in \
        "user_rules|$USER_RULES_BAK|top" \
        "whitelist_filters|$WHITELIST_BAK|top" \
        "filters|$FILTERS_BAK|top" \
        "upstream_dns|$UPSTREAM_DNS_BAK|dns_list" \
        "bootstrap_dns|$BOOTSTRAP_DNS_BAK|dns_list" \
        "fallback_dns|$FALLBACK_DNS_BAK|dns_list" \
        "upstream_dns_file|$UPSTREAM_DNS_FILE_BAK|dns_scalar"
    do
        _key=${_entry%%|*}
        _rest=${_entry#*|}
        _bak=${_rest%%|*}
        _type=${_rest##*|}

        case "$_type" in
            top) merge_top_block "$AGH_YAML" "$_key" "$_bak" ;;
            dns_list) merge_dns_list_block "$AGH_YAML" "$_key" "$_bak" ;;
            dns_scalar) replace_dns_scalar "$AGH_YAML" "$_key" "$_bak" ;;
        esac
    done

    ui_msg "- Restored and merged previous config blocks" "- 已恢复并合并旧配置块"
    return 0
}

append_unique_filter_item() {
    [ -n "$_filter_item_buf" ] || return 0

    _dup=false
    _item_id=$(printf '%s\n' "$_filter_item_buf" | sed -n 's/^[[:space:]]*id:[[:space:]]*//p' | head -n 1 | tr -d ' ')
    _item_url=$(printf '%s\n' "$_filter_item_buf" | sed -n 's/^[[:space:]]*url:[[:space:]]*//p' | head -n 1 | tr -d ' ')

    if [ -n "$_item_id" ]; then
        case " $_seen_filter_ids " in
            *" $_item_id "*) _dup=true ;;
            *) _seen_filter_ids="$_seen_filter_ids $_item_id" ;;
        esac
    fi

    if [ "$_dup" = false ] && [ -n "$_item_url" ]; then
        case " $_seen_filter_urls " in
            *" $_item_url "*) _dup=true ;;
            *) _seen_filter_urls="$_seen_filter_urls $_item_url" ;;
        esac
    fi

    if [ "$_dup" = false ]; then
        printf '%s\n' "$_filter_item_buf" >> "$_filter_items_tmp"
        _filter_kept_any=true
    fi

    _filter_item_buf=""
    return 0
}

flush_filter_block() {
    [ -n "$_current_filter_key" ] || return 0

    append_unique_filter_item

    if [ "$_filter_kept_any" = true ]; then
        printf '%s:\n' "$_current_filter_key" >> "$_filter_tmp"
        cat "$_filter_items_tmp" >> "$_filter_tmp"
    else
        printf '%s: []\n' "$_current_filter_key" >> "$_filter_tmp"
    fi

    : > "$_filter_items_tmp"
    _current_filter_key=""
    _filter_item_buf=""
    _filter_kept_any=false
    return 0
}

dedup_filter_blocks() {
    _yaml="$1"

    [ -f "$_yaml" ] || return 0

    _filter_tmp="${_yaml}.tmp"
    _filter_items_tmp="$TMPDIR/filter_items.$$"
    : > "$_filter_tmp"
    : > "$_filter_items_tmp"

    _in_filter_block=false
    _current_filter_key=""
    _filter_item_buf=""
    _filter_kept_any=false
    _seen_filter_ids=""
    _seen_filter_urls=""

    while IFS= read -r _ln || [ -n "$_ln" ]; do
        if [ "$_in_filter_block" = false ]; then
            if printf '%s\n' "$_ln" | grep -qE '^(filters|whitelist_filters):[[:space:]]*(\[\])?[[:space:]]*$'; then
                _in_filter_block=true
                _current_filter_key=$(printf '%s' "$_ln" | sed 's/:.*$//')
                : > "$_filter_items_tmp"
                _filter_item_buf=""
                _filter_kept_any=false
                continue
            fi

            printf '%s\n' "$_ln" >> "$_filter_tmp"
            continue
        fi

        if is_root_key_line "$_ln"; then
            flush_filter_block
            _in_filter_block=false

            if printf '%s\n' "$_ln" | grep -qE '^(filters|whitelist_filters):[[:space:]]*(\[\])?[[:space:]]*$'; then
                _in_filter_block=true
                _current_filter_key=$(printf '%s' "$_ln" | sed 's/:.*$//')
                : > "$_filter_items_tmp"
                _filter_item_buf=""
                _filter_kept_any=false
                continue
            fi

            printf '%s\n' "$_ln" >> "$_filter_tmp"
            continue
        fi

        if printf '%s\n' "$_ln" | grep -qE '^[[:space:]]*-'; then
            append_unique_filter_item
            _filter_item_buf="$_ln"
            continue
        fi

        if [ -n "$_filter_item_buf" ]; then
            _filter_item_buf="${_filter_item_buf}
${_ln}"
        fi
    done < "$_yaml"

    [ "$_in_filter_block" = true ] && flush_filter_block

    mv "$_filter_tmp" "$_yaml"
    rm -f "$_filter_items_tmp"
    return 0
}

dedup_user_rules() {
    _yaml="$1"
    _key="$2"

    [ -f "$_yaml" ] || return 0

    _tmp="${_yaml}.tmp"
    : > "$_tmp"
    
    _in_block=false
    _seen=""

    while IFS= read -r _ln || [ -n "$_ln" ]; do
        if [ "$_in_block" = false ]; then
            if printf '%s\n' "$_ln" | grep -qE "^${_key}:[[:space:]]*(\\[\\])?[[:space:]]*$"; then
                _in_block=true
                printf '%s\n' "$_ln" >> "$_tmp"
                continue
            fi
            printf '%s\n' "$_ln" >> "$_tmp"
            continue
        fi

        if is_root_key_line "$_ln"; then
            _in_block=false
            printf '%s\n' "$_ln" >> "$_tmp"
            continue
        fi

        _hash=$(printf '%s' "$_ln" | tr -d '[:space:]')
        case "$_seen" in
            *"|$_hash|"*) continue ;;
            *) 
                _seen="${_seen}|${_hash}|"
                printf '%s\n' "$_ln" >> "$_tmp"
                ;;
        esac
    done < "$_yaml"

    mv "$_tmp" "$_yaml"
    return 0
}

dedup_dns_list() {
    _yaml="$1"
    _key="$2"

    [ -f "$_yaml" ] || return 0

    _tmp="${_yaml}.tmp"
    : > "$_tmp"
    
    _in_dns=false
    _in_block=false
    _seen=""

    while IFS= read -r _ln || [ -n "$_ln" ]; do
        _indent=$(indent_of "$_ln")

        if [ "$_in_dns" = false ] && printf '%s\n' "$_ln" | grep -qE "^dns:[[:space:]]*$"; then
            _in_dns=true
            printf '%s\n' "$_ln" >> "$_tmp"
            continue
        fi

        if [ "$_in_dns" = true ] && [ "$_in_block" = false ] && is_dns_key_line "$_key" "$_ln" "$_indent"; then
            _in_block=true
            printf '%s\n' "$_ln" >> "$_tmp"
            continue
        fi

        if [ "$_in_block" = true ]; then
            if [ "$_indent" -eq 2 ] && printf '%s\n' "$_ln" | grep -qE "^[[:space:]][[:space:]][a-z_]"; then
                _in_block=false
                printf '%s\n' "$_ln" >> "$_tmp"
                continue
            elif [ "$_indent" -eq 0 ] && printf '%s\n' "$_ln" | grep -qE "^[a-zA-Z_]"; then
                _in_block=false
                _in_dns=false
                printf '%s\n' "$_ln" >> "$_tmp"
                continue
            fi
            
            _hash=$(printf '%s' "$_ln" | tr -d '[:space:]')
            case "$_seen" in
                *"|$_hash|"*) ;;
                *) 
                    _seen="${_seen}|${_hash}|"
                    printf '%s\n' "$_ln" >> "$_tmp"
                    ;;
            esac
            continue
        fi

        printf '%s\n' "$_ln" >> "$_tmp"
    done < "$_yaml"

    mv "$_tmp" "$_yaml"
    return 0
}

dedup_all_lists() {
    [ -f "$AGH_YAML" ] || return 0

    dedup_filter_blocks "$AGH_YAML"
    dedup_user_rules "$AGH_YAML" "user_rules"
    dedup_dns_list "$AGH_YAML" "upstream_dns"
    dedup_dns_list "$AGH_YAML" "bootstrap_dns"
    dedup_dns_list "$AGH_YAML" "fallback_dns"

    ui_msg "- Cleaned config entries" "- 已清理配置项"
    return 0
}

restore_filter_files() {
    [ -d "$BACKUP_DIR/filters" ] || return 0
    ensure_dir "$FILTER_CACHE_DIR"

    for _id in $(grep -E '^[[:space:]]*id:[[:space:]]*[0-9]+' "$AGH_YAML" 2>/dev/null | sed 's/.*id:[[:space:]]*//'); do
        [ -f "$BACKUP_DIR/filters/${_id}.txt" ] && cp -f "$BACKUP_DIR/filters/${_id}.txt" "$FILTER_CACHE_DIR/"
    done

    ui_msg "- Restored filter cache files" "- 已恢复过滤器缓存文件"
    return 0
}

remove_immutable_recursive() {
    _target="$1"
    [ -e "$_target" ] || return 0

    chattr -i -R "$_target" 2>/dev/null
    find "$_target" -exec chattr -i {} \; 2>/dev/null
    find "$_target" -type d -exec chmod 755 {} \; 2>/dev/null
    return 0
}

disable_system_dns() {
    ui_msg "- Disabling system DNS to avoid conflicts" "- 正在关闭系统DNS以避免冲突"

    settings put global private_dns_mode off 2>/dev/null
    settings put global wifi_use_static_ip 0 2>/dev/null

    if [ -f /system/build.prop ]; then
        for _prop in ro.net.dns1 ro.net.dns2 net.dns1 net.dns2 persist.sys.dns1 persist.sys.dns2; do
            resetprop "$_prop" "" 2>/dev/null
        done
    fi

    ui_msg "- System DNS disabled" "- 系统DNS已关闭"
}

install_ksu_webui() {
    [ -n "$MAGISK_VER" ] || return 0
    [ -z "$KSU" ] || return 0
    [ -z "$APATCH" ] || return 0

    ui_msg "- Installing KsuWebUI" "- 正在安装KsuWebUI"

    _tmp_apk="/data/local/tmp/KsuWebUI_1.0.apk"
    unzip -p "$ZIPFILE" "apk/KsuWebUI_1.0.apk" > "$_tmp_apk" 2>/dev/null || {
        rm -f "$_tmp_apk"
        ui_msg "- KsuWebUI.apk not found" "- 未找到KsuWebUI.apk"
        return 0
    }

    [ -s "$_tmp_apk" ] || {
        rm -f "$_tmp_apk"
        ui_msg "- KsuWebUI.apk extraction failed" "- KsuWebUI.apk解压失败"
        return 0
    }

    chmod 644 "$_tmp_apk" 2>/dev/null
    if pm install -r "$_tmp_apk" 2>/dev/null; then
        rm -f "$_tmp_apk"
        ui_msg "- KsuWebUI installed successfully" "- KsuWebUI安装成功"
    else
        rm -f "$_tmp_apk"
        ui_msg "- Failed to install KsuWebUI" "- KsuWebUI安装失败"
    fi
}

disable_iptables_in_conf() {
    _conf_file="$1"
    [ -f "$_conf_file" ] || return 0

    ui_msg "- Auto-disabling iptables" "- 自动关闭iptables以避免冲突"

    sed -i 's/^[#[:space:]]*enable_iptables=.*/enable_iptables=false/' "$_conf_file"
    if ! grep -q "^enable_iptables=false" "$_conf_file"; then
        if grep -q "enable_iptables" "$_conf_file"; then
            sed -i 's/^enable_iptables.*/enable_iptables=false/' "$_conf_file"
        else
            sed -i '1i enable_iptables=false' "$_conf_file"
        fi
    fi

    ui_msg "- iptables disabled" "- iptables已关闭"
}

stop_agh_processes() {
    for _proc in NoAdsService ProxyConfig AdGuardHome; do
        pkill -9 "$_proc" 2>/dev/null
    done

    agh_pid=$(pidof AdGuardHome 2>/dev/null)
    if [ -n "$agh_pid" ]; then
        kill -9 "$agh_pid" 2>/dev/null
        sleep 1
    fi
}

cleanup_old_proxy_install() {
    [ -f "$PROXY_SCRIPT" ] || return 0

    ui_msg "- Old AGH detected, backing up and cleaning up" "- 检测到旧版AGH，正在备份并清理"
    
    cleanup_old_backups
    backup_all_configs
    backup_filter_files
    
    _proxy_backup_done=true
    
    stop_agh_processes

    [ -f "$PROXY_SCRIPT" ] && "$PROXY_SCRIPT" --clean 2>/dev/null

    remove_immutable_recursive "$AGH_DIR"
    remove_immutable_recursive "$AGH_MODULE_DIR"
    [ -d "$AGH_DIR" ] && rm -rf "$AGH_DIR"

    ui_msg "- Old AGH removed" "- 旧版AGH已清理完成"
    return 0
}

remove_existing_agh_dir() {
    [ -d "$AGH_DIR" ] || return 0

    ui_msg "- Removing old directory and leftovers" "- 正在移除旧目录和残留文件"
    remove_immutable_recursive "$AGH_DIR"
    rm -rf "$AGH_DIR"

    [ -d "$AGH_DIR" ] && ui_error "- Failed to remove old directory" "- 旧目录删除失败"
    ui_msg "- Old directory removed" "- 旧目录已删除"
    return 0
}

handle_box_module() {
    [ -d "$BOX_MODULE_DIR" ] || return 0

    ui_msg "- Detected box_for_root module" "- 检测到 box_for_root 模块"
    ui_msg "- Only supports box_for_root" "- 仅支持 box_for_root 模块"
    ui_msg "- Vol Up=Replace, Vol Down=Keep, 10s=Keep" "- 音量上键=替换配置，音量下键=保留配置，10秒无操作默认保留"

    REPLACE_BOX=false
    START_TIME=$(date +%s)
    
    while true; do
        NOW_TIME=$(date +%s)
        if [ $((NOW_TIME - START_TIME)) -gt 9 ]; then
            ui_msg "- No key pressed, keeping config" "- 无操作，保留现有配置"
            break
        fi
        
        timeout 1 getevent -lc 1 2>/dev/null | grep -q "KEY_VOLUMEUP" && {
            ui_msg "- User selected replace config" "- 用户选择替换配置"
            REPLACE_BOX=true
            break
        }
        
        timeout 1 getevent -lc 1 2>/dev/null | grep -q "KEY_VOLUMEDOWN" && {
            ui_msg "- User selected keep config" "- 用户选择保留配置"
            break
        }
    done

    [ "$REPLACE_BOX" = true ] || return 0

    ui_msg "- Replacing box configuration" "- 正在替换 box 配置"

    MIHOMO_EXTRACTED=false
    SINGBOX_EXTRACTED=false

    if extract_quiet "box/mihomo/config.yaml" "$TMPDIR" && [ -f "$TMPDIR/box/mihomo/config.yaml" ]; then
        [ -f "$BOX_MIHOMO_CONFIG" ] && cp "$BOX_MIHOMO_CONFIG" "$BOX_MIHOMO_CONFIG.bak.$(date +%s)"
        ensure_dir "$BOX_CONFIG_DIR/mihomo"
        mv "$TMPDIR/box/mihomo/config.yaml" "$BOX_MIHOMO_CONFIG"
        ui_msg "- Extracted mihomo/config.yaml" "- 已解压 mihomo 配置"
        MIHOMO_EXTRACTED=true
    else
        ui_msg "- mihomo/config.yaml not found in module" "- 模块内未找到 mihomo 配置"
    fi

    if extract_quiet "box/sing-box/config.json" "$TMPDIR" && [ -f "$TMPDIR/box/sing-box/config.json" ]; then
        [ -f "$BOX_SINGBOX_CONFIG" ] && cp "$BOX_SINGBOX_CONFIG" "$BOX_SINGBOX_CONFIG.bak.$(date +%s)"
        ensure_dir "$BOX_CONFIG_DIR/sing-box"
        mv "$TMPDIR/box/sing-box/config.json" "$BOX_SINGBOX_CONFIG"
        ui_msg "- Extracted sing-box/config.json" "- 已解压 sing-box 配置"
        SINGBOX_EXTRACTED=true
    else
        ui_msg "- sing-box/config.json not found in module" "- 模块内未找到 sing-box 配置"
    fi

    if [ "$MIHOMO_EXTRACTED" = true ] || [ "$SINGBOX_EXTRACTED" = true ]; then
        ui_msg "========================================" "========================================"
        ui_msg "IMPORTANT: Please update your subscription URL" "重要：请修改为您的订阅链接"
        ui_msg "Supported: mihomo, sing-box" "支持：mihomo, sing-box"

        [ "$MIHOMO_EXTRACTED" = true ] && ui_msg "Edit: $BOX_MIHOMO_CONFIG" "编辑：$BOX_MIHOMO_CONFIG"
        [ "$SINGBOX_EXTRACTED" = true ] && ui_msg "Edit: $BOX_SINGBOX_CONFIG" "编辑：$BOX_SINGBOX_CONFIG"

        ui_msg "========================================" "========================================"
        ui_msg "- Press Vol Down to continue, 10s auto continue" "- 按音量下继续，10秒后自动继续"
        
        START_TIME=$(date +%s)
        while true; do
            NOW_TIME=$(date +%s)
            if [ $((NOW_TIME - START_TIME)) -gt 9 ]; then
                break
            fi
            timeout 1 getevent -lc 1 2>/dev/null | grep -q "KEY_VOLUMEDOWN" && break
        done
    else
        ui_msg "- No config extracted" "- 未解压任何配置文件"
    fi

    return 0
}

extract_module_files() {
    ui_msg "- Extracting module files, please wait" "- 正在解压模块文件，请稍候"
    extract_many "$MODPATH" action.sh module.prop service.sh uninstall.sh "webroot/*" "box/*"
    return 0
}

extract_agh_files() {
    ui_msg "- Creating directories" "- 正在创建目录"
    ensure_dir "$AGH_DIR"
    ensure_dir "$BIN_DIR"
    ensure_dir "$SCRIPT_DIR"

    ui_msg "- Extracting script files" "- 正在解压脚本文件"
    extract_or_abort "scripts/*" "$AGH_DIR" "- Failed to extract scripts" "- 脚本解压失败"

    ui_msg "- Extracting AdGuardHome binary" "- 正在解压 AdGuardHome 主程序"
    extract_or_abort "bin/*" "$AGH_DIR" "- Failed to extract binaries" "- 主程序解压失败"

    ui_msg "- Extracting default configs" "- 正在解压默认配置文件"
    extract_or_abort "AdGuardHome.yaml" "$BIN_DIR" "- Failed to extract AdGuardHome.yaml" "- 主配置解压失败"
    extract_or_abort "settings.conf" "$AGH_DIR" "- Failed to extract settings.conf" "- 设置文件解压失败"

    return 0
}

set_final_permissions() {
    RAW_GROUP=$(detect_raw_group)

    ui_msg "- Setting permissions (group: $RAW_GROUP)" "- 正在设置权限（组：$RAW_GROUP）"

    chmod +x "$BIN_DIR/AdGuardHome"
    chown root:$RAW_GROUP "$BIN_DIR/AdGuardHome" 2>/dev/null || chown root:root "$BIN_DIR/AdGuardHome"
    chmod +x "$SCRIPT_DIR"/*.sh "$MODPATH"/*.sh 2>/dev/null

    return 0
}

validate_agh_config() {
    _yaml="$1"
    _binary="$BIN_DIR/AdGuardHome"
    
    [ -f "$_yaml" ] || return 1
    [ -x "$_binary" ] || return 0
    
    if "$_binary" --check-config -c "$_yaml" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

finalize_and_validate() {
    [ -f "$AGH_YAML" ] || return 0

    ui_msg "- Validating configuration..." "- 正在校验配置..."

    [ -x "$BIN_DIR/AdGuardHome" ] || ui_error "- AdGuardHome binary is not executable" "- AdGuardHome 可执行权限异常"

    if ! validate_agh_config "$AGH_YAML"; then
        [ -f "$AGH_YAML.premerge" ] && mv -f "$AGH_YAML.premerge" "$AGH_YAML"
        ui_error "- AGH configuration validation failed" "- AGH 配置校验失败"
    fi

    rm -f "$AGH_YAML.premerge" 2>/dev/null
    ui_msg "- Configuration validation passed" "- 配置校验通过"
    return 0
}

finish_install() {
    ui_msg "- Installation completed, please reboot to apply" "- 安装完成，请重启设备生效"
    ui_msg "- Thank you for using" "- 感谢使用"
    sleep 0.5
    am start -d "coolmarket://u/37906923" >/dev/null 2>&1 &
    return 0
}

_proxy_backup_done=false

remove_immutable_recursive "$AGH_DIR"
remove_immutable_recursive "$AGH_MODULE_DIR"

cleanup_old_proxy_install

if [ -d "$AGH_MODULE_DIR" ]; then
    ui_msg "- Removing immutable attributes" "- 正在解除目录不可变属性"
    remove_immutable_recursive "$AGH_MODULE_DIR"
fi

ui_msg "- Installing AdGuardHome For Root AutoOpt" "- 正在安装 AdGuardHome For Root AutoOpt"

MERGE_CONFIG=false

if [ -d "$AGH_DIR" ] || [ "$_proxy_backup_done" = true ]; then
    ui_msg "- Found old version, stopping all AdGuardHome processes..." "- 发现旧版模块，正在停止所有 AdGuardHome 进程..."
    stop_agh_processes
    
    ui_msg "========================================" "========================================"
    ui_msg "The following configurations can be backed up:" "以下配置项支持备份合并："
    ui_msg "  - User rules (user_rules)" "  - 用户自定义规则 (user_rules)"
    ui_msg "  - Whitelist filters (whitelist_filters)" "  - 白名单过滤器 (whitelist_filters)"
    ui_msg "  - Blocklist filters (filters)" "  - 黑名单过滤器 (filters)"
    ui_msg "  - Upstream DNS servers (upstream_dns)" "  - 上游DNS服务器 (upstream_dns)"
    ui_msg "  - Bootstrap DNS (bootstrap_dns)" "  - 引导DNS (bootstrap_dns)"
    ui_msg "  - Fallback DNS (fallback_dns)" "  - 备用DNS服务器 (fallback_dns)"
    ui_msg "  - Upstream DNS file (upstream_dns_file)" "  - 上游DNS文件路径 (upstream_dns_file)"
    ui_msg "" ""
    ui_msg "Note: selecting merge keeps your old filters/user_rules/DNS blocks." "注意：选择合并会优先保留您旧的 filters/user_rules/DNS 配置块。"
    ui_msg "If you want new module default filters, select NO merge." "如果您想使用模块新的默认过滤器，请选择不合并。"
    ui_msg "" ""
    ui_msg "If you have NOT modified these configs," "如果您未修改过以上配置，"
    ui_msg "it is recommended to select NO merge." "建议选择不合并。"
    ui_msg "========================================" "========================================"
    ui_msg ""
    
    ui_msg "- Do you want to merge the old configuration?" "- 是否合并原来的配置文件？"
    ui_msg "- (Volume Up = Yes/Merge, Volume Down = No/Keep Default, 10s no input = No)" "- （音量上键 = 合并, 音量下键 = 不合并，10秒无操作 = 不合并）"
    
    START_TIME=$(date +%s)
    while true; do
        NOW_TIME=$(date +%s)
        if [ $((NOW_TIME - START_TIME)) -gt 9 ]; then
            ui_msg "- No input after 10 seconds, using module default config." "- 10秒无输入，使用模块默认配置。"
            break
        fi
        
        timeout 1 getevent -lc 1 2>/dev/null | grep -q "KEY_VOLUMEUP" && {
            ui_msg "- User chose to merge configuration..." "- 用户选择合并配置..."
            MERGE_CONFIG=true
            break
        }
        
        timeout 1 getevent -lc 1 2>/dev/null | grep -q "KEY_VOLUMEDOWN" && {
            ui_msg "- User chose not to merge configuration..." "- 用户选择不合并配置..."
            break
        }
    done
    
    if [ "$MERGE_CONFIG" = true ]; then
        if [ "$_proxy_backup_done" = false ]; then
            cleanup_old_backups
            backup_all_configs
            backup_filter_files
        fi
    fi
    
    remove_existing_agh_dir
else
    ui_msg "- First time installation, extracting files..." "- 第一次安装，正在解压文件..."
    mkdir -p "$AGH_DIR" "$BIN_DIR" "$SCRIPT_DIR"
fi

handle_box_module
extract_module_files
extract_agh_files

[ -d "$BOX_CONFIG_DIR" ] && disable_iptables_in_conf "$AGH_DIR/settings.conf"

if [ "$MERGE_CONFIG" = true ]; then
    ui_msg "- Merging configuration, this may take a while..." "- 正在合并配置，可能需要一些时间..."
    rm -f "$AGH_YAML.premerge" 2>/dev/null
    cp -f "$AGH_YAML" "$AGH_YAML.premerge" || ui_error "- Failed to create pre-merge snapshot" "- 创建合并前快照失败"
    merge_all_configs
    dedup_all_lists
    restore_filter_files
fi

set_final_permissions
finalize_and_validate

disable_system_dns
install_ksu_webui
finish_install
