#!/system/bin/sh

abort_verify() {
  ui_print "*********************************************************"
  ui_print "! $1"
  ui_print "! This zip may be corrupted, please try downloading again"
  abort    "*********************************************************"
}

command -v sha256sum >/dev/null 2>&1 || abort_verify "sha256sum not found"

[ -n "${ZIPFILE:-}" ] || abort_verify "ZIPFILE is not set"
[ -f "$ZIPFILE" ] || abort_verify "File not found: $ZIPFILE"

verify_file_in_zip() {
  local zipfile="$1"
  local file="$2"
  local hashfile="$file.sha256"

  local tmpdir="${TMPDIR:-/data/local/tmp}/verify_$$"
  mkdir -p "$tmpdir"

  unzip -o "$zipfile" "$file" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; abort_verify "$file not found in zip"; }
  unzip -o "$zipfile" "$hashfile" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; abort_verify "$hashfile not found in zip"; }

  local file_path="$tmpdir/$file"
  local hash_path="$tmpdir/$hashfile"

  [ -f "$file_path" ] || { rm -rf "$tmpdir"; abort_verify "$file extraction failed"; }
  [ -f "$hash_path" ] || { rm -rf "$tmpdir"; abort_verify "$hashfile extraction failed"; }

  (echo "$(cat "$hash_path" | tr -d '
')  $file_path" | sha256sum -c -s -) || { rm -rf "$tmpdir"; abort_verify "Failed to verify $file"; }

  rm -rf "$tmpdir"
  ui_print "- Verified: $file"
}

verify_file_in_zip "$ZIPFILE" "customize.sh"
verify_file_in_zip "$ZIPFILE" "module.prop"
verify_file_in_zip "$ZIPFILE" "service.sh"
verify_file_in_zip "$ZIPFILE" "verify.sh"

return 0 2>/dev/null || exit 0
