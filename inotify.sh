. /data/adb/agh/settings.conf

readonly EVENTS=$1
readonly MONITOR_DIR=$2
readonly MONITOR_FILE=$3

if [ "${MONITOR_FILE}" = "disable" ]; then
  if [ "${EVENTS}" = "d" ]; then
    $SCRIPT_DIR/tool.sh start
  elif [ "${EVENTS}" = "n" ]; then
    $SCRIPT_DIR/tool.sh stop
  fi
fi
