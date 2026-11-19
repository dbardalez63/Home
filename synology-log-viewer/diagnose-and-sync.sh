#!/bin/sh
# Diagnostico + regeneracion del JSON de accesos.
# Uso: sudo sh diagnose-and-sync.sh

set -eu

echo "=== Python ==="
command -v python3 || true
python3 --version 2>&1 || true

echo ""
echo "=== Logs nginx (lista) ==="
ls -la /var/log/nginx/ 2>/dev/null || echo "sin /var/log/nginx"

echo ""
echo "=== Ultimas lineas access.log ==="
if [ -f /var/log/nginx/access.log ]; then
  wc -l /var/log/nginx/access.log
  tail -n 15 /var/log/nginx/access.log
else
  echo "NO EXISTE /var/log/nginx/access.log"
fi

echo ""
echo "=== Buscar otros *access*.log ==="
find /var/log /volume1/@appdata/WebStation -type f -name '*access*.log' 2>/dev/null | head -30

echo ""
echo "=== Instalar/actualizar sync Python ==="
APP_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
cp -f "$APP_DIR/sync-web-access-log.py" /usr/local/bin/familia-sync-web-access-log.py
chmod 755 /usr/local/bin/familia-sync-web-access-log.py

cat > /usr/local/bin/familia-sync-web-access-log.sh <<'EOF'
#!/bin/sh
export DATA_DIR="/volume1/@appdata/familia-accesos"
export FILTER=""
export MAX_LINES="800"
exec python3 /usr/local/bin/familia-sync-web-access-log.py
EOF
chmod 755 /usr/local/bin/familia-sync-web-access-log.sh

echo ""
echo "=== Ejecutar sync ==="
/usr/local/bin/familia-sync-web-access-log.sh

echo ""
echo "=== Resultado JSON ==="
ls -la /volume1/@appdata/familia-accesos/recent.json
python3 - <<'PY'
import json
p="/volume1/@appdata/familia-accesos/recent.json"
with open(p,encoding="utf-8") as f:
    d=json.load(f)
print("generated:", d.get("generated"))
print("source:", d.get("source"))
print("entries:", len(d.get("entries") or []))
print("sources:", d.get("sources"))
if d.get("entries"):
    e=d["entries"][-1]
    print("ultima:", e.get("time"), e.get("ip"), e.get("status"), e.get("path"))
PY
