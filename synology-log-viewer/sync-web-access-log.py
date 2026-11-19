#!/usr/bin/env python3
"""Parsea access logs de Nginx en Synology y escribe recent.json (con geo IP)."""

from __future__ import print_function

import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    from urllib.request import Request, urlopen
except ImportError:
    from urllib2 import Request, urlopen  # type: ignore

DATA_DIR = Path(os.environ.get("DATA_DIR", "/volume1/@appdata/familia-accesos"))
OUT_FILE = Path(os.environ.get("OUT_FILE", str(DATA_DIR / "recent.json")))
WEB_OUT = Path(
    os.environ.get(
        "WEB_OUT",
        "/volume1/web/familia/accesos/data/recent.json",
    )
)
GEO_CACHE = Path(os.environ.get("GEO_CACHE", str(DATA_DIR / "geo-cache.json")))
MAX_LINES = int(os.environ.get("MAX_LINES", "800"))
FILTER = os.environ.get("FILTER", "")  # vacío = todo
GEO_ENABLED = os.environ.get("GEO_ENABLED", "1") != "0"

CANDIDATES = [
    "/var/log/nginx/access.log",
    "/var/log/nginx/webstation_access.log",
]

LINE_RE = re.compile(
    r'^(?P<ip>\S+) \S+ \S+ \[(?P<time>[^\]]+)\] '
    r'"(?P<method>[A-Z]+) (?P<path>\S+)(?P<proto> [^"]*)?" '
    r'(?P<status>\d{3}) (?P<size>\S+) '
    r'"(?P<ref>[^"]*)" "(?P<ua>[^"]*)"'
)

# 19/Nov/2026:18:51:17 +1100
TIME_RE = re.compile(
    r"^(?P<d>\d{2})/(?P<mon>[A-Za-z]{3})/(?P<y>\d{4}):"
    r"(?P<h>\d{2}):(?P<mi>\d{2}):(?P<s>\d{2})\s*(?P<tz>[+-]\d{4})?"
)
MON = {
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
}


def find_logs():
    found = []
    seen = set()
    for p in CANDIDATES:
        if os.path.isfile(p) and p not in seen:
            found.append(p)
            seen.add(p)
    nginx_dir = Path("/var/log/nginx")
    if nginx_dir.is_dir():
        for p in sorted(nginx_dir.glob("*access*")):
            sp = str(p)
            if sp not in seen and p.is_file():
                found.append(sp)
                seen.add(sp)
    for root in ("/var/log", "/volume1/@appdata/WebStation"):
        rp = Path(root)
        if not rp.is_dir():
            continue
        try:
            for p in rp.rglob("*access*.log"):
                sp = str(p)
                if sp not in seen and p.is_file() and p.stat().st_size > 0:
                    found.append(sp)
                    seen.add(sp)
        except Exception:
            pass
    return found


def tail_lines(path, n):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            block = 8192
            data = b""
            while size > 0 and data.count(b"\n") <= n:
                step = min(block, size)
                size -= step
                f.seek(size)
                data = f.read(step) + data
            lines = data.splitlines()[-n:]
            return [ln.decode("utf-8", "replace") for ln in lines]
    except Exception as ex:
        print("WARN no se pudo leer %s: %s" % (path, ex), file=sys.stderr)
        return []


def parse_time_epoch(timestr):
    if not timestr:
        return 0
    m = TIME_RE.match(timestr.strip())
    if not m:
        return 0
    try:
        mon = MON.get(m.group("mon"), 1)
        dt = datetime(
            int(m.group("y")),
            mon,
            int(m.group("d")),
            int(m.group("h")),
            int(m.group("mi")),
            int(m.group("s")),
        )
        # naive local-ish; enough for sorting
        return int(dt.timestamp())
    except Exception:
        return 0


def parse_line(line):
    m = LINE_RE.match(line.strip())
    if not m:
        parts = line.split()
        if len(parts) < 7:
            return None
        ip = parts[0]
        method, path, status = "-", "-", "-"
        ref, ua, t = "-", "-", "-"
        qm = re.search(r'"([A-Z]+) ([^"]+)"', line)
        if qm:
            req = qm.group(0).strip('"').split()
            if len(req) >= 2:
                method, path = req[0], req[1]
        sm = re.search(r'" (\d{3}) ', line)
        if sm:
            status = sm.group(1)
        tm = re.search(r"\[([^\]]+)\]", line)
        if tm:
            t = tm.group(1)
        return {
            "ip": ip,
            "time": t,
            "ts": parse_time_epoch(t),
            "method": method,
            "path": path,
            "status": status,
            "referer": ref,
            "ua": ua,
        }
    t = m.group("time")
    return {
        "ip": m.group("ip"),
        "time": t,
        "ts": parse_time_epoch(t),
        "method": m.group("method"),
        "path": m.group("path"),
        "status": m.group("status"),
        "referer": m.group("ref"),
        "ua": m.group("ua"),
    }


def is_private_ip(ip):
    if not ip or ip == "-":
        return True
    if ip.startswith("127.") or ip == "::1":
        return True
    if ip.startswith("10."):
        return True
    if ip.startswith("192.168."):
        return True
    if ip.startswith("169.254."):
        return True
    m = re.match(r"^172\.(\d+)\.", ip)
    if m and 16 <= int(m.group(1)) <= 31:
        return True
    return False


def load_geo_cache():
    if GEO_CACHE.is_file():
        try:
            with GEO_CACHE.open("r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                return data
        except Exception:
            pass
    return {}


def save_geo_cache(cache):
    try:
        GEO_CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = str(GEO_CACHE) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, indent=2)
        os.replace(tmp, str(GEO_CACHE))
    except Exception as ex:
        print("WARN geo-cache: %s" % ex, file=sys.stderr)


def lookup_geo_batch(ips):
    """Usa ip-api.com (gratis, sin clave). Máx 100 por lote."""
    results = {}
    if not ips:
        return results
    # lotes de 100
    for i in range(0, len(ips), 100):
        chunk = ips[i : i + 100]
        body = json.dumps(chunk).encode("utf-8")
        url = "http://ip-api.com/batch?fields=status,message,country,countryCode,regionName,city,query"
        try:
            req = Request(url, data=body, headers={"Content-Type": "application/json"})
            with urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode("utf-8", "replace"))
            if not isinstance(data, list):
                continue
            for item in data:
                if not isinstance(item, dict):
                    continue
                q = item.get("query") or ""
                if item.get("status") == "success":
                    city = item.get("city") or ""
                    region = item.get("regionName") or ""
                    country = item.get("country") or ""
                    code = item.get("countryCode") or ""
                    parts = [p for p in (city, region, country) if p]
                    label = ", ".join(parts) if parts else (country or "Desconocido")
                    if code and country and code not in label:
                        label = "%s (%s)" % (label, code)
                    results[q] = {
                        "country": country,
                        "countryCode": code,
                        "region": region,
                        "city": city,
                        "label": label,
                    }
                else:
                    results[q] = {
                        "country": "",
                        "countryCode": "",
                        "region": "",
                        "city": "",
                        "label": "No disponible",
                    }
        except Exception as ex:
            print("WARN geo lookup: %s" % ex, file=sys.stderr)
            for ip in chunk:
                results.setdefault(
                    ip,
                    {
                        "country": "",
                        "countryCode": "",
                        "region": "",
                        "city": "",
                        "label": "Geo no disponible",
                    },
                )
        # respeta limite gratuito
        if i + 100 < len(ips):
            time.sleep(1.2)
    return results


def enrich_geo(entries):
    cache = load_geo_cache()
    private_label = {
        "country": "LAN",
        "countryCode": "LAN",
        "region": "",
        "city": "",
        "label": "Red local (LAN)",
    }
    need = []
    for e in entries:
        ip = e.get("ip") or ""
        if is_private_ip(ip):
            e["geo"] = private_label
            continue
        if ip in cache and isinstance(cache[ip], dict) and cache[ip].get("label"):
            e["geo"] = cache[ip]
            continue
        if ip and ip not in need:
            need.append(ip)

    if GEO_ENABLED and need:
        print("Geo lookup: %s IPs nuevas" % len(need))
        fresh = lookup_geo_batch(need)
        cache.update(fresh)
        save_geo_cache(cache)
        for e in entries:
            ip = e.get("ip") or ""
            if "geo" in e:
                continue
            e["geo"] = cache.get(
                ip,
                {
                    "country": "",
                    "countryCode": "",
                    "region": "",
                    "city": "",
                    "label": "—",
                },
            )
    else:
        for e in entries:
            if "geo" in e:
                continue
            ip = e.get("ip") or ""
            e["geo"] = cache.get(
                ip,
                {
                    "country": "",
                    "countryCode": "",
                    "region": "",
                    "city": "",
                    "label": "—",
                },
            )
    return entries


def write_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = str(path) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    os.replace(tmp, str(path))
    try:
        os.chmod(str(path), 0o644)
    except Exception:
        pass


def main():
    logs = find_logs()
    print("Logs encontrados:")
    for p in logs:
        try:
            sz = os.path.getsize(p)
        except OSError:
            sz = -1
        print("  - %s (%s bytes)" % (p, sz))

    entries = []
    sources = []
    filt = FILTER.strip()
    for path in logs:
        lines = tail_lines(path, MAX_LINES)
        kept = 0
        for line in lines:
            if not line.strip():
                continue
            if filt and not re.search(filt, line):
                continue
            row = parse_line(line)
            if not row:
                continue
            row["log"] = path
            entries.append(row)
            kept += 1
        sources.append({"path": path, "parsed": kept, "tailed": len(lines)})
        print("  %s -> %s lineas, %s parseadas" % (path, len(lines), kept))

    # Más recientes primero
    entries.sort(key=lambda e: (e.get("ts") or 0, e.get("time") or ""), reverse=True)
    entries = entries[:MAX_LINES]
    entries = enrich_geo(entries)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated": datetime.now().strftime("%Y-%m-%dT%H:%M:%S%z"),
        "source": ", ".join(logs) if logs else "(ninguno)",
        "sources": sources,
        "filter": filt,
        "order": "newest_first",
        "entries": entries,
    }

    write_json(OUT_FILE, payload)
    try:
        write_json(WEB_OUT, payload)
        print("OK: %s entradas -> %s" % (len(payload["entries"]), OUT_FILE))
        print("OK: copia web -> %s" % WEB_OUT)
    except Exception as ex:
        print("OK: %s entradas -> %s" % (len(payload["entries"]), OUT_FILE))
        print("WARN no se pudo escribir copia web %s: %s" % (WEB_OUT, ex), file=sys.stderr)

    if not logs:
        print("ERROR: no hay access.log legibles. Revisa permisos/sudo.", file=sys.stderr)
        return 1
    if not payload["entries"]:
        print("AVISO: 0 entradas. El log puede estar vacio o en otra ruta.", file=sys.stderr)
    elif payload["entries"]:
        e0 = payload["entries"][0]
        print(
            "Primera (mas reciente): %s %s %s | %s"
            % (e0.get("time"), e0.get("ip"), (e0.get("geo") or {}).get("label"), e0.get("path"))
        )
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
