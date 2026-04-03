#!/system/bin/sh

AGH_DIR="/data/adb/agh"
AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
PID_FILE="$AGH_DIR/bin/agh.pid"

stop_pid_if_running() {
    [ -f "$PID_FILE" ] || return 0

    _pid="$(tr -cd '0-9' < "$PID_FILE" 2>/dev/null)"
    [ -n "$_pid" ] || return 0
    kill -0 "$_pid" 2>/dev/null || return 0

    kill "$_pid" 2>/dev/null
    sleep 2
    kill -9 "$_pid" 2>/dev/null
}

cleanup_nat_chain() {
    _cmd="$1"
    _chain="$2"

    "$_cmd" -t nat -D OUTPUT -j "$_chain" 2>/dev/null
    "$_cmd" -t nat -F "$_chain" 2>/dev/null
    "$_cmd" -t nat -X "$_chain" 2>/dev/null
}

cleanup_filter_chain() {
    _cmd="$1"
    _chain="$2"

    "$_cmd" -t filter -D OUTPUT -j "$_chain" 2>/dev/null
    "$_cmd" -t filter -F "$_chain" 2>/dev/null
    "$_cmd" -t filter -X "$_chain" 2>/dev/null
}

unlock_dir() {
    [ -e "$1" ] || return 0
    find "$1" 2>/dev/null -exec chattr -i {} \; 2>/dev/null
}

stop_pid_if_running
pkill -9 AdGuardHome 2>/dev/null

cleanup_nat_chain iptables ADGUARD_REDIRECT_DNS
cleanup_nat_chain ip6tables ADGUARD_REDIRECT_DNS
cleanup_nat_chain ip6tables ADGUARD_REDIRECT_DNS6
cleanup_filter_chain ip6tables ADGUARD_BLOCK_DNS

unlock_dir "$AGH_DIR"
unlock_dir "$AGH_MODULE_DIR"

rm -rf "$AGH_DIR" "$AGH_MODULE_DIR"