until [ $(getprop init.svc.bootanim) = "stopped" ]; do
 sleep 12
done

VALIDATION_FILE="/data/adb/modules/AdGuardHome/Validation"
MODULE_PROP="/data/adb/modules/AdGuardHome/module.prop"
BOX_SINGBOX="/data/adb/box/sing-box/config.json"
BOX_MIHOMO="/data/adb/box/mihomo/config.yaml"
MODULE_SINGBOX="/data/adb/modules/AdGuardHome/box/sing-box/config.json"
MODULE_MIHOMO="/data/adb/modules/AdGuardHome/box/mihomo/config.yaml"

START_TOOL=false

if [ -f "$VALIDATION_FILE" ]; then
 VALIDATION_CONTENT=$(cat "$VALIDATION_FILE" 2>/dev/null)
 
 if [ "$VALIDATION_CONTENT" = "X7kL9pQ2rM5vN3jH8fD1" ]; then
   REPLACE_SUCCESS=true
   
   if [ -f "$MODULE_SINGBOX" ] && [ -f "$BOX_SINGBOX" ]; then
     if ! diff -q "$MODULE_SINGBOX" "$BOX_SINGBOX" >/dev/null 2>&1; then
       REPLACE_SUCCESS=false
     fi
   fi
   
   if [ -f "$MODULE_MIHOMO" ] && [ -f "$BOX_MIHOMO" ]; then
     if ! diff -q "$MODULE_MIHOMO" "$BOX_MIHOMO" >/dev/null 2>&1; then
       REPLACE_SUCCESS=false
     fi
   fi
   
   if [ "$REPLACE_SUCCESS" = true ]; then
     START_TOOL=true
   else
     if [ -f "$MODULE_PROP" ]; then
       sed -i 's/^description=.*/description=[⚠️ box配置未成功替换，模块未启动，强行启动请点击执行 Box config not replaced, module not started, click to force start] AdGuardHome for Root/' "$MODULE_PROP"
     fi
   fi
 fi
else
 START_TOOL=true
fi

if [ "$START_TOOL" = true ]; then
 /data/adb/agh/scripts/tool.sh start
fi

inotifyd /data/adb/agh/scripts/inotify.sh /data/adb/modules/AdGuardHome:d,n &
