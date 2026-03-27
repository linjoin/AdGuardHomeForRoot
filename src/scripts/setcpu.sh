#!/system/bin/sh

PID_FILE="/data/adb/agh/bin/agh.pid"
MODULE_PROP="/data/adb/modules/AdGuardHome/module.prop"
CPU_MASK="F"  
CGROUP_CPUS="0-3"
TASKSET_CMD="/system/bin/taskset"
[ ! -x "$TASKSET_CMD" ] && TASKSET_CMD="taskset"

[ "$(id -u)" -ne 0 ] && exit 1
[ ! -f "$PID_FILE" ] && exit 1

PID=$(cat "$PID_FILE" 2>/dev/null)
[ -z "$PID" ] || ! [ "$PID" -gt 0 ] 2>/dev/null && exit 1
! [ -d "/proc/$PID" ] && exit 1

BIND_FAILED=0

lock_cpu() {
    local target=$1
    $TASKSET_CMD -p "$CPU_MASK" "$target" >/dev/null 2>&1
    [ -f "/proc/$target/cpuset" ] && echo "$CGROUP_CPUS" > "/proc/$target/cpuset" 2>/dev/null
}

CGROUP="/dev/cpuset/agh"
mkdir -p "$CGROUP" 2>/dev/null
echo "$CGROUP_CPUS" > "$CGROUP/cpus" 2>/dev/null
echo "0" > "$CGROUP/mems" 2>/dev/null
echo "$PID" > "$CGROUP/cgroup.procs" 2>/dev/null

lock_cpu "$PID"
for task in /proc/$PID/task/[0-9]*; do
    [ -d "$task" ] || continue
    lock_cpu "$(basename "$task")"
done

sleep 0.2
for task in /proc/$PID/task/[0-9]*; do
    [ -d "$task" ] || continue
    mask=$($TASKSET_CMD -p "$(basename "$task")" 2>/dev/null | tail -1 | awk '{print $NF}')
    [ "$((0x$mask))" -ne "$((0x$CPU_MASK))" ] && BIND_FAILED=1
done

[ $BIND_FAILED -eq 1 ] && [ -f "$MODULE_PROP" ] && \
    sed -i 's/^description=.*/description=🌳拦截启用成功 🪵绑定线程失败/' "$MODULE_PROP"

exit $BIND_FAILED