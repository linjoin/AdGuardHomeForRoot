#!/system/bin/sh

PID_FILE="/data/adb/agh/bin/agh.pid"
MODULE_PROP="/data/adb/modules/AdGuardHome/module.prop"
CPU_MASK="7"
CGROUP_CPUS="0-2"
CGROUP_DIR="/dev/cpuset/agh"

TASKSET_CMD="/system/bin/taskset"
[ -x "$TASKSET_CMD" ] || TASKSET_CMD="taskset"

language="${language:-zh}"

read_pid() {
    tr -cd '0-9' < "$PID_FILE" 2>/dev/null
}

is_valid_pid() {
    _pid="$1"
    [ -n "$_pid" ] || return 1
    [ "$_pid" -gt 0 ] 2>/dev/null || return 1
    [ -d "/proc/$_pid" ]
}

lock_cpu() {
    _target="$1"
    "$TASKSET_CMD" -p "$CPU_MASK" "$_target" >/dev/null 2>&1
    [ -f "/proc/$_target/cpuset" ] && echo "$CGROUP_CPUS" > "/proc/$_target/cpuset" 2>/dev/null
}

setup_cgroup() {
    mkdir -p "$CGROUP_DIR" 2>/dev/null
    echo "$CGROUP_CPUS" > "$CGROUP_DIR/cpus" 2>/dev/null
    echo "0" > "$CGROUP_DIR/mems" 2>/dev/null
    echo "$PID" > "$CGROUP_DIR/cgroup.procs" 2>/dev/null
}

bind_all_tasks() {
    _pid="$1"

    lock_cpu "$_pid"
    for task in /proc/"$_pid"/task/[0-9]*; do
        [ -d "$task" ] || continue
        lock_cpu "${task##*/}"
    done
}

verify_binding() {
    _pid="$1"

    sleep 0.2
    for task in /proc/"$_pid"/task/[0-9]*; do
        [ -d "$task" ] || continue

        _tid="${task##*/}"
        _mask=$("$TASKSET_CMD" -p "$_tid" 2>/dev/null | tail -1 | awk '{print $NF}')

        [ -n "$_mask" ] || return 1
        [ "$((0x$_mask))" -eq "$((0x$CPU_MASK))" ] || return 1
    done

    return 0
}

update_bind_failed_desc() {
    [ -f "$MODULE_PROP" ] || return 0

    if [ "$language" = "en" ]; then
        _desc="AdGuardHome For Root AutoOpt Running - PID:$PID - CPU Binding Failed"
    else
        _desc="AdGuardHome For Root AutoOpt 运行中 - PID:$PID - CPU核心绑定失败"
    fi

    sed -i "s/^description=.*/description=$_desc/" "$MODULE_PROP"
}

[ "$(id -u)" -eq 0 ] || exit 1
[ -f "$PID_FILE" ] || exit 1

PID="$(read_pid)"
is_valid_pid "$PID" || exit 1

setup_cgroup
bind_all_tasks "$PID"

if verify_binding "$PID"; then
    exit 0
fi

update_bind_failed_desc
exit 1