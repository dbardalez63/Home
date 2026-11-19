#!/bin/sh
# Copia/parsea las ultimas lineas del access.log de Nginx a un JSON
# legible por el visor web. Ejecutar como root (Programador de tareas DSM).
#
# Uso:
#   WEB_ROOT=/volume1/web/familia ./sync-web-access-log.sh
#   ./sync-web-access-log.sh /volume1/web/familia

set -eu

WEB_ROOT="${1:-${WEB_ROOT:-/volume1/web/familia}}"
# Preferir DATA_DIR privado (fuera del Document Root). Si no, caer a WEB_ROOT/accesos/data
if [ -n "${DATA_DIR:-}" ]; then
  OUT_DIR="$DATA_DIR"
elif [ -n "${OUT_DIR:-}" ]; then
  :
else
  OUT_DIR="${WEB_ROOT}/accesos/data"
fi
OUT_FILE="${OUT_FILE:-${OUT_DIR}/recent.json}"
LOG_FILE="${LOG_FILE:-/var/log/nginx/access.log}"
MAX_LINES="${MAX_LINES:-400}"
# Por defecto: todo el access.log (pon FILTER='familia|arbol' para limitar)
FILTER="${FILTER-}"

if [ ! -r "$LOG_FILE" ]; then
  echo "No se puede leer $LOG_FILE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
chmod 755 "$OUT_DIR" 2>/dev/null || true

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Ultimas N lineas; filtro opcional
if [ -n "$FILTER" ]; then
  tail -n "$MAX_LINES" "$LOG_FILE" | grep -E "$FILTER" | tail -n "$MAX_LINES" > "$TMP" || true
else
  tail -n "$MAX_LINES" "$LOG_FILE" > "$TMP"
fi

# Genera JSON (awk portable en Synology BusyBox/ash)
awk -v generated="$(date '+%Y-%m-%dT%H:%M:%S%z')" '
BEGIN {
  print "{"
  print "  \"generated\": \"" generated "\","
  print "  \"source\": \"/var/log/nginx/access.log\","
  print "  \"entries\": ["
  first = 1
}
{
  # Formato típico Nginx combined
  # IP - - [date] "METHOD PATH PROTO" STATUS SIZE "REF" "UA"
  ip = $1
  # fecha entre corchetes
  date = ""
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^\[/) {
      date = $i
      gsub(/^\[/, "", date)
      # puede ser [19/Nov/2026:16:51:42
      if ($(i+1) ~ /\]$/) {
        date = date " " $(i+1)
        gsub(/\]$/, "", date)
      } else {
        gsub(/\]$/, "", date)
      }
      break
    }
  }

  req = ""
  ua = ""
  ref = ""
  status = "-"
  # Extrae "METHOD PATH PROTO"
  if (match($0, /"[A-Z]+ [^"]*"/)) {
    req = substr($0, RSTART + 1, RLENGTH - 2)
  }
  # status: número después del request
  rest = $0
  if (match(rest, /" [0-9]{3} /)) {
    status = substr(rest, RSTART + 2, 3)
  }
  # referer y user-agent: dos strings entre comillas al final
  n = split($0, parts, "\"")
  # parts: 1 before first quote, 2 request, 3 between, 4 referer, 5 between, 6 ua, ...
  if (n >= 6) {
    ref = parts[4]
    ua = parts[6]
  } else if (n >= 4) {
    ref = parts[4]
  }

  method = "-"
  path = "-"
  split(req, rp, " ")
  if (length(rp) >= 2) {
    method = rp[1]
    path = rp[2]
  }

  gsub(/\\/, "\\\\", ip)
  gsub(/"/, "\\\"", ip)
  gsub(/\\/, "\\\\", date)
  gsub(/"/, "\\\"", date)
  gsub(/\\/, "\\\\", method)
  gsub(/"/, "\\\"", method)
  gsub(/\\/, "\\\\", path)
  gsub(/"/, "\\\"", path)
  gsub(/\\/, "\\\\", status)
  gsub(/"/, "\\\"", status)
  gsub(/\\/, "\\\\", ref)
  gsub(/"/, "\\\"", ref)
  gsub(/\\/, "\\\\", ua)
  gsub(/"/, "\\\"", ua)

  if (!first) print ","
  first = 0
  printf "    {\"ip\": \"%s\", \"time\": \"%s\", \"method\": \"%s\", \"path\": \"%s\", \"status\": \"%s\", \"referer\": \"%s\", \"ua\": \"%s\"}", \
    ip, date, method, path, status, ref, ua
}
END {
  print ""
  print "  ]"
  print "}"
}
' "$TMP" > "${OUT_FILE}.tmp"

mv "${OUT_FILE}.tmp" "$OUT_FILE"
chmod 644 "$OUT_FILE"
chown http:http "$OUT_FILE" 2>/dev/null || chown nobody:nobody "$OUT_FILE" 2>/dev/null || true

COUNT="$(grep -c '"ip"' "$OUT_FILE" 2>/dev/null || echo 0)"
echo "OK: $COUNT entradas -> $OUT_FILE"
