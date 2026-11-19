#!/usr/bin/env python3
# Visor de accesos para Synology Web Station (fcgiwrap/CGI).
# No requiere PHP.

import cgi
import hashlib
import hmac
import json
import os
import sys
import time
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.parse import parse_qs

BASE = Path(__file__).resolve().parent
CONFIG_PATH = BASE / "config.json"
DEFAULT_DATA = Path("/volume1/@appdata/familia-accesos/recent.json")
SECRET_FALLBACK = "familia-accesos-change-me"
TTL = 28800


def load_config():
    cfg = {
        "password": "CambiaEstaClave",
        "session_ttl": TTL,
        "data_file": str(DEFAULT_DATA),
        "secret": SECRET_FALLBACK,
    }
    if CONFIG_PATH.is_file():
        try:
            with CONFIG_PATH.open("r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                cfg.update(data)
        except Exception:
            pass
    return cfg


def header(status="200 OK", content_type="text/html; charset=utf-8", extra=None):
    sys.stdout.write("Status: %s\r\n" % status)
    sys.stdout.write("Content-Type: %s\r\n" % content_type)
    sys.stdout.write("Cache-Control: no-store\r\n")
    if extra:
        for k, v in extra:
            sys.stdout.write("%s: %s\r\n" % (k, v))
    sys.stdout.write("\r\n")


def html_escape(s):
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def token_for(password, secret, now=None):
    now = int(now or time.time())
    # round to TTL window start for stability? better absolute expiry in payload
    exp = now + TTL
    payload = "%s:%s" % (exp, hashlib.sha256(password.encode("utf-8")).hexdigest()[:16])
    sig = hmac.new(secret.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    return "%s.%s" % (payload, sig)


def token_ok(token, password, secret, ttl):
    try:
        payload, sig = token.rsplit(".", 1)
        expect = hmac.new(secret.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expect, sig):
            return False
        exp_s, pwd_part = payload.split(":", 1)
        if int(exp_s) < int(time.time()):
            return False
        want = hashlib.sha256(password.encode("utf-8")).hexdigest()[:16]
        return hmac.compare_digest(pwd_part, want)
    except Exception:
        return False


def read_body():
    method = os.environ.get("REQUEST_METHOD", "GET").upper()
    if method != "POST":
        return {}
    try:
        length = int(os.environ.get("CONTENT_LENGTH") or "0")
    except ValueError:
        length = 0
    raw = sys.stdin.read(length) if length > 0 else ""
    return {k: (v[0] if v else "") for k, v in parse_qs(raw, keep_blank_values=True).items()}


def get_cookie_token():
    raw = os.environ.get("HTTP_COOKIE", "")
    c = SimpleCookie()
    try:
        c.load(raw)
    except Exception:
        return ""
    if "fa_auth" in c:
        return c["fa_auth"].value
    return ""


def page_login(error="", must_change=False):
    err = ('<p class="error">%s</p>' % html_escape(error)) if error else ""
    warn = (
        '<p class="warn">Edita config.json y cambia la contraseña por defecto.</p>'
        if must_change
        else ""
    )
    return """<!DOCTYPE html>
<html lang="es"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="robots" content="noindex,nofollow"/>
<title>Accesos web — Synology</title>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;700&family=Outfit:wght@600;700&display=swap" rel="stylesheet"/>
<style>
:root{--ink:#0f2744;--muted:#5b6b7c;--accent:#0d9f9f;--sky:#3b82f6;--err:#dc2626;--warn:#d97706}
body{margin:0;min-height:100vh;font-family:Manrope,Segoe UI,sans-serif;color:var(--ink);
background:radial-gradient(ellipse 70%% 50%% at 0%% 0%%,rgba(59,130,246,.16),transparent 55%%),
radial-gradient(ellipse 60%% 45%% at 100%% 0%%,rgba(13,159,159,.18),transparent 50%%),
linear-gradient(165deg,#eef7ff,#e8fbf7 50%%,#f5f8fc)}
.card{max-width:24rem;margin:12vh auto;background:rgba(255,255,255,.85);border-radius:1.1rem;padding:1.2rem;
border:1px solid rgba(15,39,68,.07);box-shadow:0 10px 28px rgba(15,39,68,.06)}
h1{font-family:Outfit,sans-serif;margin:0 0 .35rem;font-size:1.6rem}
.sub{color:var(--muted);margin:0 0 1rem}
label{display:grid;gap:.35rem;font-size:.72rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--accent)}
input{border:1px solid rgba(15,39,68,.12);border-radius:.8rem;padding:.7rem .85rem;font:inherit;font-weight:600}
.btn{margin-top:1rem;border:0;border-radius:.8rem;padding:.65rem 1rem;font:inherit;font-weight:700;cursor:pointer;
background:linear-gradient(135deg,var(--accent),var(--sky));color:#fff}
.error{color:var(--err)}.warn{color:var(--warn)}
</style></head><body>
<div class="card">
<h1>Accesos web</h1>
<p class="sub">Visor de visitas del sitio en este Synology.</p>
%s%s
<form method="post">
<label>Contraseña<input type="password" name="password" required autofocus/></label>
<button class="btn" type="submit">Entrar</button>
</form>
</div></body></html>""" % (
        warn,
        err,
    )


def page_app():
    return """<!DOCTYPE html>
<html lang="es"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="robots" content="noindex,nofollow"/>
<title>Accesos web — Synology</title>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;700&family=Outfit:wght@600;700&display=swap" rel="stylesheet"/>
<style>
:root{--ink:#0f2744;--muted:#5b6b7c;--accent:#0d9f9f;--sky:#3b82f6;--ok:#059669;--err:#dc2626}
*{box-sizing:border-box}
body{margin:0;font-family:Manrope,Segoe UI,sans-serif;color:var(--ink);
background:radial-gradient(ellipse 70% 50% at 0% 0%,rgba(59,130,246,.16),transparent 55%),
linear-gradient(165deg,#eef7ff,#e8fbf7 50%,#f5f8fc)}
.wrap{max-width:1100px;margin:0 auto;padding:1.25rem 1rem 2.5rem}
h1{font-family:Outfit,sans-serif;margin:0;font-size:clamp(1.5rem,3vw,2rem)}
.sub{color:var(--muted);margin:.35rem 0 1rem}
.toolbar{display:flex;flex-wrap:wrap;gap:.6rem;align-items:center;margin-bottom:.9rem}
.grow{flex:1;min-width:12rem}
input[type=search]{width:100%;border:1px solid rgba(15,39,68,.12);border-radius:.8rem;padding:.65rem .85rem;font:inherit;font-weight:600}
.btn{border:1px solid rgba(15,39,68,.1);background:#fff;border-radius:.8rem;padding:.55rem .9rem;font:inherit;font-weight:700;cursor:pointer;text-decoration:none;color:var(--ink)}
.card{background:rgba(255,255,255,.82);border-radius:1.1rem;overflow:auto;border:1px solid rgba(15,39,68,.07)}
table{width:100%;border-collapse:collapse;font-size:.86rem}
th,td{text-align:left;padding:.55rem .45rem;border-bottom:1px solid rgba(15,39,68,.06);vertical-align:top}
th{font-size:.7rem;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}
.pill{background:#fff;border:1px solid rgba(15,39,68,.08);border-radius:.7rem;padding:.35rem .7rem;font-size:.8rem;font-weight:700}
.stats{display:flex;flex-wrap:wrap;gap:.5rem;margin-bottom:.9rem}
.meta{color:var(--muted);font-size:.82rem}
.st-2{color:var(--ok);font-weight:700}.st-4,.st-5{color:var(--err);font-weight:700}
.path{font-weight:600;word-break:break-all}.ua{color:var(--muted);font-size:.78rem}
.empty{text-align:center;color:var(--muted);padding:1.5rem}
@media(max-width:800px){.hide-sm{display:none}}
</style></head><body>
<div class="wrap">
<div style="display:flex;justify-content:space-between;gap:1rem;flex-wrap:wrap;align-items:flex-start">
<div><h1>Accesos web</h1><p class="sub">Registros de Nginx</p></div>
<a class="btn" href="?logout=1">Salir</a>
</div>
<div class="toolbar">
<div class="grow"><input type="search" id="q" placeholder="Filtrar por IP, ruta, estado..."/></div>
<button type="button" class="btn" id="refresh">Actualizar</button>
<label style="font-size:.85rem;color:var(--muted)"><input type="checkbox" id="auto" checked/> Auto 15s</label>
</div>
<div class="stats" id="stats"></div>
<p class="meta" id="meta">Cargando...</p>
<div class="card"><table>
<thead><tr><th>Hora</th><th>IP</th><th>Estado</th><th>Ruta</th><th class="hide-sm">Origen</th><th class="hide-sm">Navegador</th></tr></thead>
<tbody id="rows"><tr><td colspan="6" class="empty">Cargando...</td></tr></tbody>
</table></div>
</div>
<script>
const rowsEl=document.getElementById('rows'), metaEl=document.getElementById('meta'), statsEl=document.getElementById('stats'), qEl=document.getElementById('q');
let entries=[], timer=null;
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
function shortUa(ua){if(!ua||ua==='-')return '—';if(/Mobile|Android|iPhone/i.test(ua))return 'Móvil';if(/Chrome/i.test(ua))return 'Chrome';if(/Firefox/i.test(ua))return 'Firefox';if(/Safari/i.test(ua))return 'Safari';if(/curl|bot|spider|crawler/i.test(ua))return 'Bot/script';return ua.slice(0,40)}
function render(){
  const q=(qEl.value||'').trim().toLowerCase();
  const filtered=!q?entries:entries.filter(e=>[e.ip,e.path,e.status,e.referer,e.ua,e.time,e.method].join(' ').toLowerCase().includes(q));
  const ok=filtered.filter(e=>String(e.status).startsWith('2')).length;
  const notFound=filtered.filter(e=>e.status==='404').length;
  const ips=new Set(filtered.map(e=>e.ip)).size;
  statsEl.innerHTML=`<span class="pill">${filtered.length} visitas</span><span class="pill">${ips} IPs</span><span class="pill">${ok} OK</span><span class="pill">${notFound} 404</span>`;
  if(!filtered.length){rowsEl.innerHTML='<tr><td colspan="6" class="empty">Sin coincidencias</td></tr>';return}
  const list=filtered.slice().reverse();
  rowsEl.innerHTML=list.map(e=>{
    const st=String(e.status||'')[0];
    return `<tr><td>${esc(e.time||'—')}</td><td><strong>${esc(e.ip||'—')}</strong></td><td class="st-${st}">${esc(e.status||'—')}</td><td class="path">${esc((e.method||'')+' '+(e.path||''))}</td><td class="hide-sm">${esc(e.referer&&e.referer!=='-'?e.referer:'—')}</td><td class="hide-sm ua" title="${esc(e.ua||'')}">${esc(shortUa(e.ua))}</td></tr>`;
  }).join('');
}
async function load(){
  try{
    const res=await fetch('?json=1',{cache:'no-store'});
    if(res.status===401){location.reload();return}
    const data=await res.json();
    entries=Array.isArray(data.entries)?data.entries:[];
    let msg=data.error?data.error:('Actualizado: '+(data.generated||'—')+' · '+(data.source||'nginx'));
    if(!(data.entries||[]).length){
      const src=(data.sources||[]).map(s=>s.path+' ('+s.tailed+' leidas, '+s.parsed+' ok)').join(' | ');
      msg += src ? (' · vacio: '+src) : ' · sin entradas (log vacio o ruta distinta)';
    }
    metaEl.textContent=msg;
    render();
  }catch(err){metaEl.textContent='No se pudo cargar: '+err}
}
function arm(){if(timer)clearInterval(timer);timer=null;if(document.getElementById('auto').checked)timer=setInterval(load,15000)}
qEl.addEventListener('input',render);
document.getElementById('refresh').addEventListener('click',load);
document.getElementById('auto').addEventListener('change',arm);
load();arm();
</script>
</body></html>"""


def main():
    cfg = load_config()
    password = str(cfg.get("password") or "")
    secret = str(cfg.get("secret") or SECRET_FALLBACK)
    ttl = int(cfg.get("session_ttl") or TTL)
    data_file = Path(str(cfg.get("data_file") or DEFAULT_DATA))
    must_change = password in ("", "CambiaEstaClave")

    qs = parse_qs(os.environ.get("QUERY_STRING", ""))
    if "logout" in qs:
        header("302 Found", extra=[("Set-Cookie", "fa_auth=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"), ("Location", "index.cgi")])
        return

    form = read_body()
    if os.environ.get("REQUEST_METHOD", "GET").upper() == "POST" and "password" in form:
        if must_change:
            header()
            sys.stdout.write(page_login("Cambia la contraseña en config.json antes de entrar.", True))
            return
        if hmac.compare_digest(form.get("password", ""), password):
            tok = token_for(password, secret)
            header(
                "302 Found",
                extra=[
                    ("Set-Cookie", "fa_auth=%s; Path=/; Max-Age=%s; HttpOnly; SameSite=Lax" % (tok, ttl)),
                    ("Location", "index.cgi"),
                ],
            )
            return
        header()
        sys.stdout.write(page_login("Contraseña incorrecta.", must_change))
        return

    authed = token_ok(get_cookie_token(), password, secret, ttl)
    if not authed:
        header()
        sys.stdout.write(page_login(must_change=must_change))
        return

    if "json" in qs:
        header(content_type="application/json; charset=utf-8")
        if not data_file.is_file():
            sys.stdout.write(
                json.dumps(
                    {
                        "generated": None,
                        "error": "Aun no hay datos. Ejecuta /usr/local/bin/familia-sync-web-access-log.sh",
                        "entries": [],
                    },
                    ensure_ascii=False,
                )
            )
            return
        try:
            with data_file.open("r", encoding="utf-8") as f:
                sys.stdout.write(f.read())
        except Exception as ex:
            sys.stdout.write(json.dumps({"generated": None, "error": str(ex), "entries": []}, ensure_ascii=False))
        return

    header()
    sys.stdout.write(page_app())


if __name__ == "__main__":
    try:
        main()
    except Exception as ex:
        header("500 Internal Server Error", "text/plain; charset=utf-8")
        sys.stdout.write("Error del visor: %s\n" % ex)
