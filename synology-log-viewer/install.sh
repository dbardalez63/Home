#!/bin/sh
# Instala el visor de accesos en el Synology.
#
# Uso (SSH como admin):
#   sudo sh install.sh /volume1/web/familia

set -eu

WEB_ROOT="${1:-/volume1/web/familia}"
APP_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
DEST="${WEB_ROOT}/accesos"
DATA_DIR="${DATA_DIR:-/volume1/@appdata/familia-accesos}"
SCRIPT_DIR="/usr/local/bin"
SYNC_NAME="familia-sync-web-access-log.sh"
SRC_SYNC="${APP_DIR}/sync-web-access-log.sh"

echo "==> Destino web: $DEST"
echo "==> Datos privados: $DATA_DIR"

mkdir -p "$DEST" "$DATA_DIR"
cp -f "$APP_DIR/www/index.cgi" "$DEST/index.cgi"
chmod 755 "$DEST/index.cgi"
# PHP en Synology suele fallar por open_basedir con @appdata; el visor real es CGI.
if [ -f "$DEST/index.php" ]; then
  mv -f "$DEST/index.php" "$DEST/index.php.bak"
  echo "==> index.php renombrado a index.php.bak (usar index.cgi)"
fi
cp -f "$APP_DIR/www/config.sample.php" "$DEST/config.sample.php" 2>/dev/null || true

# Redirige la carpeta al CGI (no depende de PHP)
cat > "$DEST/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="es"><head>
<meta charset="utf-8"/>
<meta http-equiv="refresh" content="0; url=index.cgi"/>
<title>Accesos</title>
</head><body><a href="index.cgi">Abrir visor de accesos</a></body></html>
EOF

if [ ! -f "$DEST/config.json" ]; then
  cat > "$DEST/config.json" <<EOF
{
  "password": "CambiaEstaClave",
  "session_ttl": 28800,
  "data_file": "${DATA_DIR}/recent.json",
  "secret": "cambia-este-secreto-$(date +%s)"
}
EOF
  echo "==> Creado $DEST/config.json (CAMBIA LA CONTRASEÑA)"
else
  echo "==> Se conserva $DEST/config.json existente"
fi

# Mantener config.php solo si ya existía; el visor principal es index.cgi
if [ ! -f "$DEST/config.php" ]; then
  cat > "$DEST/config.php" <<EOF
<?php
return [
    'password' => 'CambiaEstaClave',
    'session_ttl' => 28800,
    'data_file' => '${DATA_DIR}/recent.json',
];
EOF
fi

# Parser Python (mas fiable en Synology) + wrapper
cp -f "$SRC_SYNC" "${SCRIPT_DIR}/familia-sync-web-access-log.real.sh"
chmod 755 "${SCRIPT_DIR}/familia-sync-web-access-log.real.sh"
cp -f "$APP_DIR/sync-web-access-log.py" "${SCRIPT_DIR}/familia-sync-web-access-log.py"
chmod 755 "${SCRIPT_DIR}/familia-sync-web-access-log.py"

cat > "${SCRIPT_DIR}/${SYNC_NAME}" <<EOF
#!/bin/sh
export DATA_DIR="${DATA_DIR}"
export FILTER="\${FILTER-}"
export MAX_LINES="\${MAX_LINES:-800}"
if command -v python3 >/dev/null 2>&1; then
  exec python3 "${SCRIPT_DIR}/familia-sync-web-access-log.py"
fi
exec "${SCRIPT_DIR}/familia-sync-web-access-log.real.sh" "${WEB_ROOT}"
EOF
chmod 755 "${SCRIPT_DIR}/${SYNC_NAME}"

"${SCRIPT_DIR}/${SYNC_NAME}" || true

# Evita listar data si alguien la crea bajo el web root
mkdir -p "$DEST/data"
cat > "$DEST/data/index.html" <<'EOF'
<!DOCTYPE html><title>Forbidden</title><p>Forbidden</p>
EOF

echo ""
echo "=== Instalacion lista ==="
echo "Visor principal: index.cgi (no necesita PHP)."
echo "1) Cambia la contraseña:"
echo "     sudo tee ${DEST}/config.json >/dev/null << 'EOF'"
echo "{"
echo "  \"password\": \"TuClaveSegura\","
echo "  \"session_ttl\": 28800,"
echo "  \"data_file\": \"${DATA_DIR}/recent.json\","
echo "  \"secret\": \"otro-secreto-largo\""
echo "}"
echo "EOF"
echo "2) DSM -> Programador de tareas -> root -> cada 1-5 min:"
echo "     ${SCRIPT_DIR}/${SYNC_NAME}"
echo "3) Abre:"
echo "     http://192.168.2.3/familia/accesos/"
echo "     http://192.168.2.3/familia/accesos/index.cgi"
echo ""
echo "No dejes la clave por defecto si el puerto esta abierto a Internet."
