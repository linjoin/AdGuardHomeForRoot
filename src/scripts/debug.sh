#!/system/bin/sh

AGH_DIR="/data/adb/agh"
AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
LOG="$AGH_DIR/debug.log"

{
  echo "==== AdGuardHome Debug Log ===="
  date
  echo

  echo "== System Info =="
  echo "Android: $(getprop ro.build.version.release)"
  echo "Device: $(getprop ro.product.model)"
  echo "Arch: $(uname -m)"
  echo

  echo "== Root Method =="
  if [ -d "/data/adb/magisk" ]; then
    echo "Magisk"
  elif [ -d "/data/adb/ksu" ]; then
    echo "KernelSU"
  elif [ -d "/data/adb/ap" ]; then
    echo "APatch"
  else
    echo "Unknown"
  fi
  echo

  echo "== SELinux Status =="
  getenforce 2>/dev/null || echo "getenforce not available"
  ls -l /sys/fs/selinux/enforce 2>/dev/null || echo "Cannot check SELinux enforce file"
  echo

  echo "== Module Status =="
  if [ -f "$AGH_MODULE_DIR/module.prop" ]; then
    cat "$AGH_MODULE_DIR/module.prop"
  else
    echo "ERROR: Module not found!"
  fi
  echo

  echo "== Module Immutable Attributes =="
  lsattr -d "$AGH_MODULE_DIR" 2>/dev/null || echo "WARNING: Cannot check module dir attributes"
  echo

  echo "== Binary Check =="
  if [ -f "$AGH_DIR/bin/AdGuardHome" ]; then
    ls -l "$AGH_DIR/bin/AdGuardHome"
    "$AGH_DIR/bin/AdGuardHome" --version 2>&1 | head -1
    if [ -x "$AGH_DIR/bin/AdGuardHome" ]; then
      echo "Binary is executable"
    else
      echo "ERROR: Binary not executable!"
    fi
  else
    echo "ERROR: AdGuardHome binary not found!"
  fi
  echo

  echo "== Config Files Check =="
  for file in "bin/AdGuardHome.yaml" "settings.conf"; do
    if [ -f "$AGH_DIR/$file" ]; then
      echo "OK: $file exists"
    else
      echo "ERROR: $file missing!"
    fi
  done
  echo

  echo "== YAML Syntax Pre-check =="
  if [ -f "$AGH_DIR/bin/AdGuardHome.yaml" ]; then
    if grep -q $'\t' "$AGH_DIR/bin/AdGuardHome.yaml"; then
      echo "ERROR: Found TAB characters in YAML (line numbers):"
      grep -n $'\t' "$AGH_DIR/bin/AdGuardHome.yaml" | head -3
    else
      echo "OK: No TAB characters"
    fi
    if grep -q ' $' "$AGH_DIR/bin/AdGuardHome.yaml"; then
      echo "WARNING: Found trailing spaces in YAML"
    fi
    spaces=$(grep -E '^[ ]+' "$AGH_DIR/bin/AdGuardHome.yaml" | head -20 | wc -l)
    tabs=$(grep -E '^	' "$AGH_DIR/bin/AdGuardHome.yaml" | head -20 | wc -l)
    if [ "$spaces" -gt 0 ] && [ "$tabs" -gt 0 ]; then
      echo "ERROR: Mixed spaces and tabs for indentation!"
    fi
  else
    echo "SKIP: YAML file not found"
  fi
  echo

  echo "== Config Syntax Check =="
  if [ -f "$AGH_DIR/bin/AdGuardHome" ] && [ -f "$AGH_DIR/bin/AdGuardHome.yaml" ]; then
    "$AGH_DIR/bin/AdGuardHome" --check-config -c "$AGH_DIR/bin/AdGuardHome.yaml" 2>&1 || echo "ERROR: Config syntax invalid!"
  else
    echo "SKIP: Cannot check config - files missing"
  fi
  echo

  echo "== Process Status =="
  PID=$(cat "$AGH_DIR/bin/agh.pid" 2>/dev/null)
  if [ -n "$PID" ]; then
    if ps -p "$PID" >/dev/null 2>&1; then
      echo "Process running (PID: $PID)"
      ps -p "$PID" -o pid,ppid,cmd 2>/dev/null
    else
      echo "ERROR: PID file exists ($PID) but process not running!"
      echo "Stale PID file detected - should be removed"
    fi
  else
    echo "No PID file found"
  fi
  echo "All AdGuardHome processes:"
  ps -A | grep -i adguardhome | grep -v grep || echo "No processes found"
  echo "Process count: $(ps -A | grep -i adguardhome | grep -v grep | wc -l)"
  echo

  echo "== Duplicate Instance Check =="
  AGH_COUNT=$(ps -A | grep -i adguardhome | grep -v grep | wc -l)
  if [ "$AGH_COUNT" -gt 1 ]; then
    echo "WARNING: Multiple AdGuardHome instances detected ($AGH_COUNT)!"
    echo "This can cause port conflicts and crash loops"
    ps -A | grep -i adguardhome | grep -v grep
  elif [ "$AGH_COUNT" -eq 1 ]; then
    echo "OK: Single instance running"
  else
    echo "No instances running"
  fi
  echo

  echo "== Service Status =="
  ps | grep service.sh | grep -v grep && echo "service.sh running" || echo "service.sh not running"
  echo

  echo "== Port Conflict Check =="
  echo "Port 53 listeners (may conflict with AGH):"
  if command -v netstat >/dev/null 2>&1; then
    netstat -tlnp 2>/dev/null | grep ':53' || echo "No listener on port 53"
  elif command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | grep ':53' || echo "No listener on port 53"
  else
    echo "netstat/ss not available"
  fi
  echo "Port 3000 listeners (AGH Web UI):"
  if command -v netstat >/dev/null 2>&1; then
    netstat -tlnp 2>/dev/null | grep ':3000' || echo "No listener on port 3000"
  elif command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | grep ':3000' || echo "No listener on port 3000"
  fi
  echo

  echo "== Potential DNS Conflict Services =="
  for service in dnsmasq systemd-resolved bind9 named; do
    if pgrep -x "$service" >/dev/null 2>&1; then
      echo "WARNING: $service is running (may conflict with port 53)"
    fi
  done
  echo

  echo "== Private DNS (DoH/DoT) Check =="
  PRIVATE_DNS=$(settings get global private_dns_mode 2>/dev/null)
  PRIVATE_DNS_HOST=$(settings get global private_dns_specifier 2>/dev/null)
  echo "Private DNS mode: ${PRIVATE_DNS:-not set}"
  if [ -n "$PRIVATE_DNS_HOST" ]; then
    echo "Private DNS hostname: $PRIVATE_DNS_HOST"
  fi
  if [ "$PRIVATE_DNS" = "hostname" ] && [ -n "$PRIVATE_DNS_HOST" ]; then
    echo "WARNING: Private DNS is ENABLED - this bypasses AdGuardHome!"
  elif [ "$PRIVATE_DNS" = "off" ] || [ -z "$PRIVATE_DNS" ]; then
    echo "OK: Private DNS is disabled"
  fi
  echo

  echo "== DoH Hardcoded Check =="
  if [ -f "/product/etc/resolv.conf" ] || [ -f "/system/etc/resolv.conf" ]; then
    echo "System resolv.conf found:"
    cat /product/etc/resolv.conf 2>/dev/null | grep -E 'nameserver|options' | head -5
    cat /system/etc/resolv.conf 2>/dev/null | grep -E 'nameserver|options' | head -5
  fi
  if getprop | grep -qiE 'doh|dot|dns.*https|dns.*tls'; then
    echo "WARNING: Found DoH/DoT related properties:"
    getprop | grep -iE 'doh|dot|dns.*https|dns.*tls' | head -5
  fi
  echo

  echo "== Database Integrity Check =="
  if [ -f "$AGH_DIR/bin/data/querylog.json" ]; then
    QUERYLOG_SIZE=$(stat -c%s "$AGH_DIR/bin/data/querylog.json" 2>/dev/null || stat -f%z "$AGH_DIR/bin/data/querylog.json" 2>/dev/null)
    echo "querylog.json size: ${QUERYLOG_SIZE:-unknown} bytes"
    if [ -n "$QUERYLOG_SIZE" ] && [ "$QUERYLOG_SIZE" -gt 104857600 ]; then
      echo "WARNING: querylog.json is very large (>100MB), may cause performance issues"
    fi
    if head -1 "$AGH_DIR/bin/data/querylog.json" | grep -q '{'; then
      echo "OK: querylog.json appears to be valid JSON"
    else
      echo "WARNING: querylog.json may be corrupted (not valid JSON start)"
    fi
    tail -5 "$AGH_DIR/bin/data/querylog.json" | grep -q '}' || echo "WARNING: querylog.json may be truncated"
  else
    echo "querylog.json not found (may be normal if logging disabled)"
  fi
  
  if [ -f "$AGH_DIR/bin/data/stats.db" ]; then
    STATS_SIZE=$(stat -c%s "$AGH_DIR/bin/data/stats.db" 2>/dev/null || stat -f%z "$AGH_DIR/bin/data/stats.db" 2>/dev/null)
    echo "stats.db size: ${STATS_SIZE:-unknown} bytes"
  fi
  
  if [ -f "$AGH_DIR/bin/data/sessions.db" ]; then
    SESSION_SIZE=$(stat -c%s "$AGH_DIR/bin/data/sessions.db" 2>/dev/null || stat -f%z "$AGH_DIR/bin/data/sessions.db" 2>/dev/null)
    echo "sessions.db size: ${SESSION_SIZE:-unknown} bytes"
  fi
  echo

  echo "== Firewall Modules Check =="
  FIREWALL_MODULES=""
  for fw_mod in "afwall" "firewall" "iptables" "netguard" "droidwall" "afwallplus"; do
    if [ -d "/data/adb/modules/$fw_mod" ] || [ -d "/data/adb/modules_update/$fw_mod" ]; then
      FIREWALL_MODULES="$FIREWALL_MODULES $fw_mod"
      echo "WARNING: Firewall module detected: $fw_mod"
      if [ -f "/data/adb/modules/$fw_mod/module.prop" ]; then
        grep -E 'name|version' "/data/adb/modules/$fw_mod/module.prop" 2>/dev/null | head -3
      fi
    fi
  done
  if [ -z "$FIREWALL_MODULES" ]; then
    echo "OK: No known firewall modules detected"
  fi
  echo

  echo "== iptables Rules Check =="
  echo "All iptables chains (filter):"
  iptables -L -n 2>/dev/null | grep -E 'Chain|DROP|REJECT|AdGuard|agh' | head -20 || echo "Cannot list iptables rules"
  echo
  echo "NAT table DNS rules:"
  iptables -t nat -L -n 2>/dev/null | grep -E '53|dns|DNS' | head -10 || echo "No DNS-related NAT rules"
  echo

  echo "== Hosts Module/Modification Check =="
  HOSTS_MODULES=""
  for module_dir in /data/adb/modules/*/; do
    if [ -d "$module_dir" ] && [ -f "${module_dir}system/etc/hosts" ]; then
      mod_id=$(basename "$module_dir")
      HOSTS_MODULES="$HOSTS_MODULES $mod_id"
      echo "WARNING: Module '$mod_id' contains system/etc/hosts (will override system hosts)"
      lines=$(wc -l < "${module_dir}system/etc/hosts" 2>/dev/null)
      [ -n "$lines" ] && echo "  Hosts entries: $lines lines"
    fi
  done
  if [ -z "$HOSTS_MODULES" ]; then
    echo "OK: No module found with custom system/etc/hosts"
  fi
  if [ -d "/data/adb/magisk" ]; then
    if grep -r 'magisk.*--hosts' /data/adb/modules/*/post-fs-data.sh 2>/dev/null | grep -q .; then
      echo "WARNING: At least one module executes 'magisk --hosts' (enables system-wide hosts redirection)"
    fi
  fi
  if [ -d "/data/adb/modules/hosts" ]; then
    echo "NOTE: A module named 'hosts' exists, but check if it actually contains system/etc/hosts"
    if [ -f "/data/adb/modules/hosts/system/etc/hosts" ]; then
      echo "  Module 'hosts' contains system/etc/hosts, will override system hosts"
      lines=$(wc -l < "/data/adb/modules/hosts/system/etc/hosts" 2>/dev/null)
      echo "  Hosts entries: $lines lines"
    fi
  fi
  SYSTEM_HOSTS="/system/etc/hosts"
  if [ -L "$SYSTEM_HOSTS" ]; then
    echo "WARNING: /system/etc/hosts is a symlink!"
    ls -l "$SYSTEM_HOSTS"
  fi
  echo "System hosts file size:"
  wc -l "$SYSTEM_HOSTS" 2>/dev/null || echo "Cannot read system hosts"
  if grep -qE '127\.0\.0\.1|0\.0\.0\.0' "$SYSTEM_HOSTS" 2>/dev/null | head -1; then
    echo "WARNING: System hosts file contains redirect entries (may conflict with AGH)"
    grep -cE '127\.0\.0\.1|0\.0\.0\.0' "$SYSTEM_HOSTS" 2>/dev/null || echo "Cannot count hosts entries"
  fi
  echo

  echo "== All Installed Modules List =="
  echo "Scanning /data/adb/modules/ ..."
  MODULE_COUNT=0
  for module_dir in /data/adb/modules/*/; do
    if [ -d "$module_dir" ]; then
      MODULE_COUNT=$((MODULE_COUNT + 1))
      prop_file="${module_dir}module.prop"
      mod_name=""
      mod_id=""
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
    fi
  done
  echo "Total modules found: $MODULE_COUNT"
  echo

  echo "== Log Analysis (last 50 lines) =="
  if [ -f "$AGH_DIR/bin.log" ]; then
    echo "Error keywords from bin.log:"
    tail -n 50 "$AGH_DIR/bin.log" 2>/dev/null | grep -iE 'error|fail|fatal|cannot|unable|permission|denied|address already in use|bind:|parse|yaml|config|database|corrupt|disk full|no space' | tail -10
    echo
    echo "Last 10 lines:"
    tail -n 10 "$AGH_DIR/bin.log"
  else
    echo "No bin.log found"
  fi
  echo

  echo "== Permission Check =="
  echo "AGH_DIR permissions:"
  ls -ld "$AGH_DIR" 2>/dev/null || echo "Cannot access $AGH_DIR"
  echo
  echo "Binary permissions:"
  ls -l "$AGH_DIR/bin/" 2>/dev/null | head -5
  echo
  echo "Data directory permissions:"
  ls -ld "$AGH_DIR/bin/data" 2>/dev/null || echo "data directory not found"
  echo

  echo "== Immutable Attributes & Permissions - All Files =="
  echo
  echo "=== /data/adb/modules/AdGuardHome/ ==="
  if [ -d "$AGH_MODULE_DIR" ]; then
    echo "Directory: $(lsattr -d "$AGH_MODULE_DIR" 2>/dev/null) $(stat -c '%a %U:%G' "$AGH_MODULE_DIR" 2>/dev/null)"
    echo
    echo "All files:"
    find "$AGH_MODULE_DIR" -print0 2>/dev/null | while IFS= read -r -d '' f; do
      attrs=$(lsattr "$f" 2>/dev/null | awk '{print $1}')
      perms=$(stat -c '%a %U:%G %n' "$f" 2>/dev/null)
      if echo "$attrs" | grep -q 'i'; then
        echo "[i] $attrs $perms"
      else
        echo "[-] $attrs $perms"
      fi
    done
  else
    echo "ERROR: Module directory not found!"
  fi
  echo
  
  echo "=== /data/adb/agh/ ==="
  if [ -d "$AGH_DIR" ]; then
    echo "Directory: $(lsattr -d "$AGH_DIR" 2>/dev/null) $(stat -c '%a %U:%G' "$AGH_DIR" 2>/dev/null)"
    echo
    echo "All files:"
    find "$AGH_DIR" -print0 2>/dev/null | while IFS= read -r -d '' f; do
      attrs=$(lsattr "$f" 2>/dev/null | awk '{print $1}')
      perms=$(stat -c '%a %U:%G %n' "$f" 2>/dev/null)
      if echo "$attrs" | grep -q 'i'; then
        echo "[i] $attrs $perms"
      else
        echo "[-] $attrs $perms"
      fi
    done
  else
    echo "ERROR: AGH directory not found!"
  fi
  echo

  echo "== iptables DNS Redirection =="
  iptables -t nat -L -n 2>/dev/null | grep -E 'REDIRECT.*53|dpt:53' | head -5 || echo "No DNS redirection rules or nat table unavailable"
  echo

  echo "== Settings =="
  cat "$AGH_DIR/settings.conf" 2>/dev/null || echo "settings.conf not found"
  echo

  echo "== Network Interface Check =="
  ip addr | grep -E 'inet ' | head -5
  echo

  echo "== Potential Interference Factors =="
  echo

  echo "--- System DNS settings (basic) ---"
  getprop net.dns1 2>/dev/null && echo "net.dns1: $(getprop net.dns1)" || echo "net.dns1: not set"
  getprop net.dns2 2>/dev/null && echo "net.dns2: $(getprop net.dns2)" || echo "net.dns2: not set"
  echo

  echo "--- Other DNS related services ---"
  echo "All processes listening on port 53 (TCP/UDP):"
  if command -v netstat >/dev/null 2>&1; then
    netstat -tulnp 2>/dev/null | grep ':53' || echo "No listener on port 53"
  elif command -v ss >/dev/null 2>&1; then
    ss -tulnp 2>/dev/null | grep ':53' || echo "No listener on port 53"
  else
    echo "netstat/ss not available"
  fi
  echo

  echo "--- Kernel network parameters ---"
  if [ -f /proc/sys/net/ipv4/ip_forward ]; then
    echo "IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"
  fi
  if [ -f /proc/sys/net/ipv4/conf/all/forwarding ]; then
    echo "IPv4 forwarding (all): $(cat /proc/sys/net/ipv4/conf/all/forwarding)"
  fi
  echo

  echo "--- SELinux denials (last 20) ---"
  if command -v dmesg >/dev/null 2>&1; then
    dmesg | grep -iE 'avc.*denied' | tail -20 || echo "No recent SELinux denials"
  else
    echo "dmesg not available"
  fi
  echo

  echo "--- Process limits ---"
  echo "ulimit -n: $(ulimit -n 2>/dev/null || echo 'unknown')"
  echo "Current open files for AGH process:"
  if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
    ls -1 /proc/$PID/fd 2>/dev/null | wc -l
  else
    echo "AGH not running or PID unknown"
  fi
  echo

  echo "--- Shared library dependencies ---"
  if [ -f "$AGH_DIR/bin/AdGuardHome" ]; then
    echo "Required libraries:"
    readelf -d "$AGH_DIR/bin/AdGuardHome" 2>/dev/null | grep NEEDED || echo "readelf not available, skipping"
  fi
  echo

  echo "--- TZ / timezone ---"
  date
  getprop persist.sys.timezone 2>/dev/null && echo "Timezone: $(getprop persist.sys.timezone)"
  echo

  echo "--- Custom DNS module detection ---"
  DNS_MODULES=""
  for dns_mod in "dnsmasq" "pdnsd" "stubby" "unbound" "dnscrypt" "simple_dns"; do
    if [ -d "/data/adb/modules/$dns_mod" ] || [ -d "/data/adb/modules_update/$dns_mod" ]; then
      DNS_MODULES="$DNS_MODULES $dns_mod"
      echo "WARNING: DNS-related module detected: $dns_mod"
    fi
  done
  [ -z "$DNS_MODULES" ] && echo "No conflicting DNS modules detected"
  echo

  echo "--- Magisk/KernelSU details ---"
  if [ -d "/data/adb/magisk" ]; then
    if command -v magisk >/dev/null 2>&1; then
      echo "Magisk version: $(magisk -c 2>/dev/null)"
    fi
  elif [ -d "/data/adb/ksu" ]; then
    if [ -f "/data/adb/ksu/version" ]; then
      echo "KernelSU version: $(cat /data/adb/ksu/version 2>/dev/null)"
    fi
  fi
  echo

  echo "--- Zygisk/Denylist status ---"
  if [ -f "/data/adb/magisk/util_functions.sh" ]; then
    echo "Magisk Denylist: $(magisk --denylist 2>/dev/null || echo 'not available')"
  fi
  echo "AGH process is likely running as root; check if it's on Magisk denylist:"
  magisk --denylist ls 2>/dev/null | grep -i adguard || echo "Not on denylist (or magisk command not available)"
  echo

  echo "--- Additional system properties (network/dns related) ---"
  getprop | grep -E 'net\.|dns' | grep -v 'gsm' | head -10
  echo

  echo "=== End of Additional Checks ==="
  echo

} >"$LOG" 2>&1

echo "Debug info collected in $LOG"