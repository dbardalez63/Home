<?php
declare(strict_types=1);

session_start();

$configFile = __DIR__ . '/config.php';
if (!is_file($configFile)) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Falta config.php. Copia config.sample.php a config.php y define una contraseña.";
    exit;
}

/** @var array{password:string,session_ttl:int,data_file:string} $config */
$config = require $configFile;
$dataFile = $config['data_file'] ?? (__DIR__ . '/data/recent.json');
$ttl = (int)($config['session_ttl'] ?? 28800);
$password = (string)($config['password'] ?? '');

if ($password === '' || $password === 'CambiaEstaClave') {
    $mustChangePassword = true;
} else {
    $mustChangePassword = false;
}

$logout = isset($_GET['logout']);
if ($logout) {
    $_SESSION = [];
    session_destroy();
    header('Location: index.php');
    exit;
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['password'])) {
    if ($mustChangePassword) {
        $error = 'Cambia la contraseña en config.php antes de entrar.';
    } elseif (hash_equals($password, (string)$_POST['password'])) {
        $_SESSION['log_viewer_ok'] = time();
        header('Location: index.php');
        exit;
    } else {
        $error = 'Contraseña incorrecta.';
    }
}

$authed = isset($_SESSION['log_viewer_ok'])
    && is_int($_SESSION['log_viewer_ok'])
    && (time() - $_SESSION['log_viewer_ok'] < $ttl);

if ($authed) {
    $_SESSION['log_viewer_ok'] = time();
}

$wantsJson = isset($_GET['json']);
if ($authed && $wantsJson) {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    if (!is_readable($dataFile)) {
        echo json_encode([
            'generated' => null,
            'error' => 'Aun no hay datos. Ejecuta sync-web-access-log.sh o el Programador de tareas.',
            'entries' => [],
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
    readfile($dataFile);
    exit;
}

function h(?string $s): string
{
    return htmlspecialchars((string)$s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="robots" content="noindex,nofollow" />
  <title>Accesos web — Synology</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;700&family=Outfit:wght@600;700&display=swap" rel="stylesheet" />
  <style>
    :root {
      --ink: #0f2744;
      --muted: #5b6b7c;
      --accent: #0d9f9f;
      --sky: #3b82f6;
      --ok: #059669;
      --warn: #d97706;
      --err: #dc2626;
      --bg: #eef7ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Manrope", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(ellipse 70% 50% at 0% 0%, rgba(59,130,246,.16), transparent 55%),
        radial-gradient(ellipse 60% 45% at 100% 0%, rgba(13,159,159,.18), transparent 50%),
        linear-gradient(165deg, #eef7ff, #e8fbf7 50%, #f5f8fc);
    }
    .wrap { max-width: 1100px; margin: 0 auto; padding: 1.25rem 1rem 2.5rem; }
    h1 {
      margin: 0;
      font-family: "Outfit", sans-serif;
      font-size: clamp(1.5rem, 3vw, 2rem);
      letter-spacing: -.02em;
    }
    .sub { color: var(--muted); margin: .35rem 0 1rem; font-size: .92rem; }
    .card {
      background: rgba(255,255,255,.82);
      border: 1px solid rgba(15,39,68,.07);
      border-radius: 1.1rem;
      padding: 1.1rem 1.2rem;
      box-shadow: 0 10px 28px rgba(15,39,68,.06);
      backdrop-filter: blur(10px);
    }
    .login { max-width: 24rem; margin: 12vh auto 0; }
    label { display: grid; gap: .35rem; font-size: .75rem; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; color: var(--accent); }
    input[type=password], input[type=search] {
      width: 100%;
      border: 1px solid rgba(15,39,68,.12);
      border-radius: .8rem;
      padding: .7rem .85rem;
      font: inherit;
      font-weight: 600;
    }
    .btn {
      border: 0;
      border-radius: .8rem;
      padding: .65rem 1rem;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
      background: linear-gradient(135deg, var(--accent), var(--sky));
      color: #fff;
      box-shadow: 0 6px 16px rgba(13,159,159,.28);
    }
    .btn.ghost {
      background: #fff;
      color: var(--ink);
      border: 1px solid rgba(15,39,68,.1);
      box-shadow: none;
    }
    .error { color: var(--err); font-size: .9rem; margin: .75rem 0 0; }
    .warn { color: var(--warn); font-size: .9rem; margin: .75rem 0 0; }
    .toolbar {
      display: flex; flex-wrap: wrap; gap: .6rem; align-items: center;
      margin-bottom: .9rem;
    }
    .toolbar .grow { flex: 1; min-width: 12rem; }
    .meta { color: var(--muted); font-size: .82rem; }
    .stats { display: flex; flex-wrap: wrap; gap: .5rem; margin-bottom: .9rem; }
    .pill {
      background: #fff;
      border: 1px solid rgba(15,39,68,.08);
      border-radius: .7rem;
      padding: .35rem .7rem;
      font-size: .8rem;
      font-weight: 700;
    }
    table { width: 100%; border-collapse: collapse; font-size: .86rem; }
    th, td { text-align: left; padding: .55rem .45rem; border-bottom: 1px solid rgba(15,39,68,.06); vertical-align: top; }
    th { font-size: .7rem; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); }
    tr:hover td { background: rgba(13,159,159,.05); }
    .st { font-weight: 700; }
    .st-2 { color: var(--ok); }
    .st-3 { color: var(--sky); }
    .st-4, .st-5 { color: var(--err); }
    .path { font-weight: 600; word-break: break-all; }
    .ua { color: var(--muted); font-size: .78rem; max-width: 18rem; }
    .empty { color: var(--muted); padding: 1.5rem 0; text-align: center; }
    @media (max-width: 800px) {
      .hide-sm { display: none; }
    }
  </style>
</head>
<body>
  <div class="wrap">
<?php if (!$authed): ?>
    <div class="card login">
      <h1>Accesos web</h1>
      <p class="sub">Visor de visitas del sitio en este Synology.</p>
      <?php if ($mustChangePassword): ?>
        <p class="warn">Edita <code>config.php</code> y cambia la contraseña por defecto.</p>
      <?php endif; ?>
      <form method="post" autocomplete="current-password">
        <label>Contraseña
          <input type="password" name="password" required autofocus />
        </label>
        <p style="margin:1rem 0 0">
          <button class="btn" type="submit">Entrar</button>
        </p>
        <?php if ($error): ?><p class="error"><?= h($error) ?></p><?php endif; ?>
      </form>
    </div>
<?php else: ?>
    <div style="display:flex;justify-content:space-between;gap:1rem;align-items:flex-start;flex-wrap:wrap;margin-bottom:.5rem">
      <div>
        <h1>Accesos web</h1>
        <p class="sub">Registros de Nginx · se actualiza solo</p>
      </div>
      <a class="btn ghost" href="?logout=1">Salir</a>
    </div>

    <div class="toolbar">
      <div class="grow">
        <input type="search" id="q" placeholder="Filtrar por IP, ruta, estado..." />
      </div>
      <button type="button" class="btn ghost" id="refresh">Actualizar</button>
      <label style="display:flex;align-items:center;gap:.4rem;text-transform:none;letter-spacing:0;font-size:.85rem;color:var(--muted)">
        <input type="checkbox" id="auto" checked /> Auto 15s
      </label>
    </div>

    <div class="stats" id="stats"></div>
    <p class="meta" id="meta">Cargando...</p>

    <div class="card" style="padding:0;overflow:auto">
      <table>
        <thead>
          <tr>
            <th>Hora</th>
            <th>IP</th>
            <th>Estado</th>
            <th>Ruta</th>
            <th class="hide-sm">Origen</th>
            <th class="hide-sm">Navegador</th>
          </tr>
        </thead>
        <tbody id="rows">
          <tr><td colspan="6" class="empty">Cargando...</td></tr>
        </tbody>
      </table>
    </div>
  </div>
  <script>
    const rowsEl = document.getElementById('rows');
    const metaEl = document.getElementById('meta');
    const statsEl = document.getElementById('stats');
    const qEl = document.getElementById('q');
    let entries = [];
    let timer = null;

    function statusClass(s) {
      const n = String(s || '')[0];
      return 'st st-' + (n || '0');
    }

    function shortUa(ua) {
      if (!ua || ua === '-') return '—';
      if (/Mobile|Android|iPhone/i.test(ua)) return 'Móvil';
      if (/Chrome/i.test(ua)) return 'Chrome';
      if (/Firefox/i.test(ua)) return 'Firefox';
      if (/Safari/i.test(ua)) return 'Safari';
      if (/curl|bot|spider|crawler/i.test(ua)) return 'Bot/script';
      return ua.slice(0, 40);
    }

    function render() {
      const q = (qEl.value || '').trim().toLowerCase();
      const filtered = !q ? entries : entries.filter(e =>
        [e.ip, e.path, e.status, e.referer, e.ua, e.time, e.method]
          .join(' ').toLowerCase().includes(q)
      );

      const ok = filtered.filter(e => String(e.status).startsWith('2')).length;
      const notFound = filtered.filter(e => e.status === '404').length;
      const ips = new Set(filtered.map(e => e.ip)).size;

      statsEl.innerHTML = `
        <span class="pill">${filtered.length} visitas</span>
        <span class="pill">${ips} IPs</span>
        <span class="pill">${ok} OK</span>
        <span class="pill">${notFound} 404</span>`;

      if (!filtered.length) {
        rowsEl.innerHTML = '<tr><td colspan="6" class="empty">Sin coincidencias</td></tr>';
        return;
      }

      // Más recientes primero
      const list = filtered.slice().reverse();
      rowsEl.innerHTML = list.map(e => `
        <tr>
          <td>${escapeHtml(e.time || '—')}</td>
          <td><strong>${escapeHtml(e.ip || '—')}</strong></td>
          <td class="${statusClass(e.status)}">${escapeHtml(e.status || '—')}</td>
          <td class="path">${escapeHtml((e.method || '') + ' ' + (e.path || ''))}</td>
          <td class="hide-sm">${escapeHtml(e.referer && e.referer !== '-' ? e.referer : '—')}</td>
          <td class="hide-sm ua" title="${escapeHtml(e.ua || '')}">${escapeHtml(shortUa(e.ua))}</td>
        </tr>`).join('');
    }

    function escapeHtml(s) {
      return String(s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;')
        .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    async function load() {
      try {
        const res = await fetch('index.php?json=1', { cache: 'no-store' });
        if (res.status === 401 || res.redirected) {
          location.reload();
          return;
        }
        const data = await res.json();
        entries = Array.isArray(data.entries) ? data.entries : [];
        metaEl.textContent = data.error
          ? data.error
          : ('Actualizado: ' + (data.generated || '—') + ' · fuente ' + (data.source || 'nginx'));
        render();
      } catch (err) {
        metaEl.textContent = 'No se pudo cargar el log: ' + err;
      }
    }

    function armTimer() {
      if (timer) clearInterval(timer);
      timer = null;
      if (document.getElementById('auto').checked) {
        timer = setInterval(load, 15000);
      }
    }

    qEl.addEventListener('input', render);
    document.getElementById('refresh').addEventListener('click', load);
    document.getElementById('auto').addEventListener('change', armTimer);
    load();
    armTimer();
  </script>
<?php endif; ?>
</body>
</html>
