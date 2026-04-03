#!/system/bin/sh

AGH_DIR="/data/adb/agh"
AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
LOG="$AGH_DIR/debug.log"
AGH_BIN="$AGH_DIR/bin/AdGuardHome"
AGH_YAML="$AGH_DIR/bin/AdGuardHome.yaml"
PID_FILE="$AGH_DIR/bin/agh.pid"
BIN_LOG="$AGH_DIR/bin.log"
INOTIFY_LOG="$AGH_DIR/inotifyd_bug.log"
SETTINGS_CONF="$AGH_DIR/settings.conf"
SYSTEM_HOSTS="/system/etc/hosts"
TEST_PUBLIC_IPS="114.114.114.114 223.5.5.5 180.76.76.76 8.8.8.8"
TEST_DOMAINS="www.baidu.com www.qq.com www.163.com"

[ -d "$AGH_DIR" ] || mkdir -p "$AGH_DIR" 2>/dev/null

section() {
    echo "== $1 =="
}

subsection() {
    echo "--- $1 ---"
}

blank() {
    echo
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

is_number() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

file_size() {
    stat -c%s "$1" 2>/dev/null || echo "unknown"
}

file_mtime() {
    stat -c%y "$1" 2>/dev/null || echo "unknown"
}

first_reachable() {
    for _target in "$@"; do
        if ping -c 1 -W 2 "$_target" >/dev/null 2>&1; then
            echo "$_target"
            return 0
        fi
    done
    return 1
}

show_port_listeners() {
    _port="$1"
    if has_cmd netstat; then
        netstat -tlnp 2>/dev/null | grep ":$_port" || echo "No listener on port $_port"
    elif has_cmd ss; then
        ss -tlnp 2>/dev/null | grep ":$_port" || echo "No listener on port $_port"
    else
        echo "netstat/ss not available"
    fi
}

show_port53_all_listeners() {
    if has_cmd netstat; then
        netstat -tulnp 2>/dev/null | grep ':53' || echo "No listener on port 53"
    elif has_cmd ss; then
        ss -tulnp 2>/dev/null | grep ':53' || echo "No listener on port 53"
    else
        echo "netstat/ss not available"
    fi
}

agh_processes() {
    ps -A 2>/dev/null | grep -i adguardhome | grep -v grep
}

agh_process_count() {
    agh_processes | wc -l | tr -d ' '
}

show_db_size() {
    [ -f "$1" ] || return 0
    echo "$(basename "$1") size: $(file_size "$1") bytes"
}

scan_named_modules() {
    _label="$1"
    _empty_msg="$2"
    shift 2

    _found=0
    for _name in "$@"; do
        if [ -d "/data/adb/modules/$_name" ] || [ -d "/data/adb/modules_update/$_name" ]; then
            _found=1
            echo "WARNING: $_label: $_name"
            if [ -f "/data/adb/modules/$_name/module.prop" ]; then
                grep -E 'name|version' "/data/adb/modules/$_name/module.prop" 2>/dev/null | head -3
            fi
        fi
    done

    [ "$_found" -eq 0 ] && echo "$_empty_msg"
}

dump_attrs_tree() {
    _dir="$1"
    _missing_msg="$2"

    echo "=== $_dir ==="
    if [ ! -d "$_dir" ]; then
        echo "ERROR: $_missing_msg"
        echo
        return 0
    fi

    if has_cmd lsattr; then
        _dir_attrs=$(lsattr -d "$_dir" 2>/dev/null)
    else
        _dir_attrs="lsattr not available"
    fi

    echo "Directory: $_dir_attrs $(stat -c '%a %U:%G' "$_dir" 2>/dev/null)"
    echo
    echo "All files:"

    find "$_dir" 2>/dev/null | while IFS= read -r _f; do
        if has_cmd lsattr; then
            _attrs=$(lsattr "$_f" 2>/dev/null | awk '{print $1}')
        else
            _attrs="N/A"
        fi

        _perms=$(stat -c '%a %U:%G %n' "$_f" 2>/dev/null)
        case "$_attrs" in
            *i*) echo "[i] $_attrs $_perms" ;;
            *) echo "[-] $_attrs $_perms" ;;
        esac
    done
    echo
}

collect_debug_info() {
    echo "==== AdGuardHome Debug Log ===="
    date
    blank

    section "System Info"
    echo "Android: $(getprop ro.build.version.release 2>/dev/null)"
    echo "Device: $(getprop ro.product.model 2>/dev/null)"
    echo "Arch: $(uname -m 2>/dev/null)"
    blank

    section "Network Connectivity Check"
    NETWORK_OK=0
    reachable_ip=$(first_reachable $TEST_PUBLIC_IPS)
    if [ -n "$reachable_ip" ]; then
        echo " Public network connectivity: OK (can reach $reachable_ip)"
        NETWORK_OK=1
    else
        echo " Public network connectivity: FAILED"
    fi
    blank

    section "Domain Name Resolution Check"
    DNS_OK=0
    reachable_domain=$(first_reachable $TEST_DOMAINS)
    if [ -n "$reachable_domain" ]; then
        echo " Domain name resolution: OK (can resolve $reachable_domain)"
        DNS_OK=1
    else
        echo " Domain name resolution: FAILED"
    fi
    blank

    if [ "$NETWORK_OK" -eq 1 ] && [ "$DNS_OK" -eq 1 ]; then
        echo " Final: Network is available and working properly"
    elif [ "$NETWORK_OK" -eq 1 ] && [ "$DNS_OK" -eq 0 ]; then
        echo " Final: Network connected but DNS failed"
    else
        echo " Final: Network unavailable"
    fi
    blank

    section "Root Method"
    if [ -d "/data/adb/magisk" ]; then
        echo "Magisk"
    elif [ -d "/data/adb/ksu" ]; then
        echo "KernelSU"
    elif [ -d "/data/adb/ap" ]; then
        echo "APatch"
    else
        echo "Unknown"
    fi
    blank

    section "SELinux Status"
    getenforce 2>/dev/null || echo "getenforce not available"
    ls -l /sys/fs/selinux/enforce 2>/dev/null || echo "Cannot check SELinux"
    blank

    section "Module Status"
    if [ -f "$AGH_MODULE_DIR/module.prop" ]; then
        cat "$AGH_MODULE_DIR/module.prop"
    else
        echo "ERROR: Module not found!"
    fi
    blank

    section "Module Immutable Attributes"
    if has_cmd lsattr; then
        lsattr -d "$AGH_MODULE_DIR" 2>/dev/null || echo "WARNING: Cannot check module dir attributes"
    else
        echo "WARNING: lsattr not available"
    fi
    blank

    section "Binary Check"
    if [ -f "$AGH_BIN" ]; then
        ls -l "$AGH_BIN"
        "$AGH_BIN" --version 2>&1 | head -1
        if [ -x "$AGH_BIN" ]; then
            echo "Binary is executable"
        else
            echo "ERROR: Binary not executable!"
        fi
    else
        echo "ERROR: AdGuardHome binary not found!"
    fi
    blank

    section "Config Files Check"
    for file in "bin/AdGuardHome.yaml" "settings.conf"; do
        if [ -f "$AGH_DIR/$file" ]; then
            echo "OK: $file exists"
        else
            echo "ERROR: $file missing!"
        fi
    done
    blank

    section "YAML Syntax Pre-check"
    if [ -f "$AGH_YAML" ]; then
        TAB_CHAR=$(printf '\t')

        if grep -q "$TAB_CHAR" "$AGH_YAML"; then
            echo "ERROR: Found TAB characters in YAML"
            grep -n "$TAB_CHAR" "$AGH_YAML" | head -3
        else
            echo "OK: No TAB characters"
        fi

        if grep -q ' $' "$AGH_YAML"; then
            echo "WARNING: Found trailing spaces in YAML"
        fi

        spaces=$(grep -E '^[ ]+' "$AGH_YAML" 2>/dev/null | head -20 | wc -l | tr -d ' ')
        tabs=$(grep "^$TAB_CHAR" "$AGH_YAML" 2>/dev/null | head -20 | wc -l | tr -d ' ')

        if [ "$spaces" -gt 0 ] && [ "$tabs" -gt 0 ]; then
            echo "ERROR: Mixed spaces and tabs!"
        fi
    else
        echo "SKIP: YAML file not found"
    fi
    blank

    section "Config Syntax Check"
    if [ -f "$AGH_BIN" ] && [ -f "$AGH_YAML" ]; then
        "$AGH_BIN" --check-config -c "$AGH_YAML" 2>&1 || echo "ERROR: Config syntax invalid!"
    else
        echo "SKIP: Cannot check config"
    fi
    blank

    section "Process Status"
    PID=$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')
    if [ -n "$PID" ]; then
        if ps -p "$PID" >/dev/null 2>&1; then
            echo "Process running (PID: $PID)"
            ps -p "$PID" -o pid,ppid,cmd 2>/dev/null
        else
            echo "ERROR: PID file exists but process not running"
        fi
    else
        echo "No PID file found"
    fi

    echo "All AdGuardHome processes:"
    if ! agh_processes; then
        echo "No processes found"
    fi

    AGH_COUNT=$(agh_process_count)
    echo "Process count: $AGH_COUNT"
    blank

    section "Duplicate Instance Check"
    if [ "$AGH_COUNT" -gt 1 ]; then
        echo "WARNING: Multiple instances detected ($AGH_COUNT)!"
        agh_processes
    elif [ "$AGH_COUNT" -eq 1 ]; then
        echo "OK: Single instance running"
    else
        echo "No instances running"
    fi
    blank

    section "Service Status"
    ps | grep service.sh | grep -v grep && echo "service.sh running" || echo "service.sh not running"
    blank

    section "Port Conflict Check"
    echo "Port 53 listeners:"
    show_port_listeners 53
    echo "Port 3000 listeners:"
    show_port_listeners 3000
    blank

    section "Potential DNS Conflict Services"
    _svc_found=0
    for service in dnsmasq systemd-resolved bind9 named; do
        if pgrep -x "$service" >/dev/null 2>&1; then
            _svc_found=1
            echo "WARNING: $service is running"
        fi
    done
    [ "$_svc_found" -eq 0 ] && echo "No known DNS conflict services detected"
    blank

    section "Private DNS (DoH/DoT) Check"
    PRIVATE_DNS=$(settings get global private_dns_mode 2>/dev/null)
    PRIVATE_DNS_HOST=$(settings get global private_dns_specifier 2>/dev/null)
    echo "Private DNS mode: ${PRIVATE_DNS:-not set}"
    if [ -n "$PRIVATE_DNS_HOST" ]; then
        echo "Private DNS hostname: $PRIVATE_DNS_HOST"
    fi
    if [ "$PRIVATE_DNS" = "hostname" ] && [ -n "$PRIVATE_DNS_HOST" ]; then
        echo "WARNING: Private DNS is ENABLED"
    elif [ "$PRIVATE_DNS" = "off" ] || [ -z "$PRIVATE_DNS" ]; then
        echo "OK: Private DNS is disabled"
    fi
    blank

    section "DoH Hardcoded Check"
    if [ -f "/product/etc/resolv.conf" ] || [ -f "/system/etc/resolv.conf" ]; then
        echo "System resolv.conf found:"
        grep -E 'nameserver|options' /product/etc/resolv.conf 2>/dev/null | head -5
        grep -E 'nameserver|options' /system/etc/resolv.conf 2>/dev/null | head -5
    fi
    if getprop | grep -qiE 'doh|dot|dns.*https|dns.*tls'; then
        echo "WARNING: Found DoH/DoT related properties:"
        getprop | grep -iE 'doh|dot|dns.*https|dns.*tls' | head -5
    fi
    blank

    section "Database Integrity Check"
    if [ -f "$AGH_DIR/bin/data/querylog.json" ]; then
        QUERYLOG_SIZE=$(file_size "$AGH_DIR/bin/data/querylog.json")
        echo "querylog.json size: ${QUERYLOG_SIZE} bytes"

        if is_number "$QUERYLOG_SIZE" && [ "$QUERYLOG_SIZE" -gt 104857600 ]; then
            echo "WARNING: querylog.json very large"
        fi

        if head -1 "$AGH_DIR/bin/data/querylog.json" | grep -q '{'; then
            echo "OK: querylog.json appears valid"
        else
            echo "WARNING: querylog.json may be corrupted"
        fi

        tail -5 "$AGH_DIR/bin/data/querylog.json" | grep -q '}' || echo "WARNING: querylog.json may be truncated"
    else
        echo "querylog.json not found"
    fi

    show_db_size "$AGH_DIR/bin/data/stats.db"
    show_db_size "$AGH_DIR/bin/data/sessions.db"
    blank

    section "Firewall Modules Check"
    scan_named_modules \
        "Firewall module detected" \
        "OK: No known firewall modules detected" \
        afwall firewall iptables netguard droidwall afwallplus
    blank

    section "iptables Rules Check"
    echo "All iptables chains (filter):"
    iptables -L -n 2>/dev/null | grep -E 'Chain|DROP|REJECT|AdGuard|agh' | head -20 || echo "Cannot list iptables rules"
    echo
    echo "NAT table DNS rules:"
    iptables -t nat -L -n 2>/dev/null | grep -E '53|dns|DNS' | head -10 || echo "No DNS-related NAT rules"
    blank

    section "Hosts Module/Modification Check"
    HOSTS_MODULES_FOUND=0
    for module_dir in /data/adb/modules/*; do
        [ -d "$module_dir" ] || continue
        if [ -f "$module_dir/system/etc/hosts" ]; then
            HOSTS_MODULES_FOUND=1
            mod_id=$(basename "$module_dir")
            echo "WARNING: Module '$mod_id' contains system/etc/hosts"
            lines=$(wc -l < "$module_dir/system/etc/hosts" 2>/dev/null)
            [ -n "$lines" ] && echo "  Hosts entries: $lines lines"
        fi
    done
    [ "$HOSTS_MODULES_FOUND" -eq 0 ] && echo "OK: No module found with custom system/etc/hosts"

    if [ -d "/data/adb/magisk" ] && grep -r 'magisk.*--hosts' /data/adb/modules/*/post-fs-data.sh 2>/dev/null | grep -q .; then
        echo "WARNING: At least one module executes 'magisk --hosts'"
    fi

    if [ -d "/data/adb/modules/hosts" ]; then
        echo "NOTE: Module 'hosts' exists"
        if [ -f "/data/adb/modules/hosts/system/etc/hosts" ]; then
            echo "  Module 'hosts' overrides system hosts"
            lines=$(wc -l < "/data/adb/modules/hosts/system/etc/hosts" 2>/dev/null)
            echo "  Hosts entries: $lines lines"
        fi
    fi

    if [ -L "$SYSTEM_HOSTS" ]; then
        echo "WARNING: /system/etc/hosts is a symlink!"
        ls -l "$SYSTEM_HOSTS"
    fi

    echo "System hosts file size:"
    wc -l "$SYSTEM_HOSTS" 2>/dev/null || echo "Cannot read system hosts"

    if grep -qE '127\.0\.0\.1|0\.0\.0\.0' "$SYSTEM_HOSTS" 2>/dev/null; then
        echo "WARNING: System hosts contains redirect entries"
        grep -cE '127\.0\.0\.1|0\.0\.0\.0' "$SYSTEM_HOSTS" 2>/dev/null || echo "Cannot count entries"
    fi
    blank

    section "All Installed Modules List"
    echo "Scanning /data/adb/modules/ ..."
    MODULE_COUNT=0
    for module_dir in /data/adb/modules/*; do
        [ -d "$module_dir" ] || continue
        MODULE_COUNT=$((MODULE_COUNT + 1))
        prop_file="$module_dir/module.prop"
        mod_id=""
        mod_name=""
        mod_desc=""

        if [ -f "$prop_file" ]; then
            mod_id=$(grep -E '^id=' "$prop_file" 2>/dev/null | head -1 | cut -d'=' -f2-)
            mod_name=$(grep -E '^name=' "$prop_file" 2>/dev/null | head -1 | cut -d'=' -f2-)
            mod_desc=$(grep -E '^description=' "$prop_file" 2>/dev/null | head -1 | cut -d'=' -f2-)
        fi

        mod_basename=$(basename "$module_dir")
        echo "[$MODULE_COUNT] Directory: $mod_basename"
        echo "    ID: ${mod_id:-N/A}"
        echo "    Name: ${mod_name:-N/A}"
        echo "    Description: ${mod_desc:-N/A}"
        echo
    done
    echo "Total modules found: $MODULE_COUNT"
    blank

    section "Log Analysis (last 50 lines)"
    if [ -f "$BIN_LOG" ]; then
        echo "Error keywords from bin.log:"
        tail -n 50 "$BIN_LOG" 2>/dev/null | grep -iE 'error|fail|fatal|cannot|unable|permission|denied|address already in use|bind|parse|yaml|config|database|corrupt|disk full' | tail -10
        echo
        echo "Last 10 lines:"
        tail -n 10 "$BIN_LOG"
    else
        echo "No bin.log found"
    fi
    blank

    section "inotifyd_bug.log Check"
    if [ -f "$INOTIFY_LOG" ]; then
        echo "File: $INOTIFY_LOG"
        echo "Size: $(file_size "$INOTIFY_LOG") bytes"
        echo "Last modified: $(file_mtime "$INOTIFY_LOG")"
        echo
        echo "Last 20 error entries:"
        tail -n 20 "$INOTIFY_LOG" 2>/dev/null
        echo
        echo "Error count by type:"
        echo "  Unlock failures: $(grep -c "解除.*失败" "$INOTIFY_LOG" 2>/dev/null)"
        echo "  Lock failures: $(grep -c "恢复.*失败" "$INOTIFY_LOG" 2>/dev/null)"
        echo "  Stop failures: $(grep -c "tool.sh stop.*失败" "$INOTIFY_LOG" 2>/dev/null)"
        echo "  Start failures: $(grep -c "tool.sh start.*失败" "$INOTIFY_LOG" 2>/dev/null)"
    else
        echo "No inotifyd_bug.log found"
    fi
    blank

    section "Permission Check"
    echo "AGH_DIR permissions:"
    ls -ld "$AGH_DIR" 2>/dev/null || echo "Cannot access $AGH_DIR"
    echo
    echo "Binary permissions:"
    ls -l "$AGH_DIR/bin/" 2>/dev/null | head -5
    echo
    echo "Data directory permissions:"
    ls -ld "$AGH_DIR/bin/data" 2>/dev/null || echo "data directory not found"
    blank

    section "Immutable Attributes & Permissions - All Files"
    echo
    dump_attrs_tree "$AGH_MODULE_DIR" "Module directory not found!"
    dump_attrs_tree "$AGH_DIR" "AGH directory not found!"

    section "iptables DNS Redirection"
    iptables -t nat -L -n 2>/dev/null | grep -E 'REDIRECT.*53|dpt:53' | head -5 || echo "No DNS redirection rules"
    blank

    section "Settings"
    cat "$SETTINGS_CONF" 2>/dev/null || echo "settings.conf not found"
    blank

    section "Network Interface Check"
    ip addr | grep -E 'inet ' | head -5
    blank

    section "Potential Interference Factors"
    blank

    subsection "System DNS settings (basic)"
    dns1=$(getprop net.dns1 2>/dev/null)
    dns2=$(getprop net.dns2 2>/dev/null)
    [ -n "$dns1" ] && echo "net.dns1: $dns1" || echo "net.dns1: not set"
    [ -n "$dns2" ] && echo "net.dns2: $dns2" || echo "net.dns2: not set"
    blank

    subsection "Other DNS related services"
    echo "All processes listening on port 53 (TCP/UDP):"
    show_port53_all_listeners
    blank

    subsection "Kernel network parameters"
    if [ -f /proc/sys/net/ipv4/ip_forward ]; then
        echo "IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"
    fi
    if [ -f /proc/sys/net/ipv4/conf/all/forwarding ]; then
        echo "IPv4 forwarding (all): $(cat /proc/sys/net/ipv4/conf/all/forwarding)"
    fi
    blank

    subsection "SELinux denials (last 20)"
    if has_cmd dmesg; then
        dmesg | grep -iE 'avc.*denied' | tail -20 || echo "No recent SELinux denials"
    else
        echo "dmesg not available"
    fi
    blank

    subsection "Process limits"
    echo "ulimit -n: $(ulimit -n 2>/dev/null || echo unknown)"
    echo "Current open files for AGH process:"
    if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        ls -1 "/proc/$PID/fd" 2>/dev/null | wc -l
    else
        echo "AGH not running or PID unknown"
    fi
    blank

    subsection "Shared library dependencies"
    if [ -f "$AGH_BIN" ]; then
        echo "Required libraries:"
        readelf -d "$AGH_BIN" 2>/dev/null | grep NEEDED || echo "readelf not available"
    fi
    blank

    subsection "TZ / timezone"
    date
    timezone=$(getprop persist.sys.timezone 2>/dev/null)
    [ -n "$timezone" ] && echo "Timezone: $timezone"
    blank

    subsection "Custom DNS module detection"
    scan_named_modules \
        "DNS-related module detected" \
        "No conflicting DNS modules detected" \
        dnsmasq pdnsd stubby unbound dnscrypt simple_dns
    blank

    subsection "Magisk/KernelSU details"
    if [ -d "/data/adb/magisk" ]; then
        if has_cmd magisk; then
            echo "Magisk version: $(magisk -c 2>/dev/null)"
        fi
    elif [ -d "/data/adb/ksu" ]; then
        if [ -f "/data/adb/ksu/version" ]; then
            echo "KernelSU version: $(cat /data/adb/ksu/version 2>/dev/null)"
        fi
    fi
    blank

    subsection "Zygisk/Denylist status"
    if has_cmd magisk; then
        echo "Magisk Denylist: $(magisk --denylist 2>/dev/null || echo 'not available')"
        echo "AGH on Magisk denylist:"
        magisk --denylist ls 2>/dev/null | grep -i adguard || echo "Not on denylist"
    else
        echo "Magisk Denylist: not available"
        echo "AGH on Magisk denylist:"
        echo "magisk command not available"
    fi
    blank

    subsection "Additional system properties (network/dns related)"
    getprop | grep -E 'net\.|dns' | grep -v 'gsm' | head -10
    blank

    echo "=== End of Additional Checks ==="
    blank
}

collect_debug_info > "$LOG" 2>&1

echo "Debug info collected in $LOG"