#!/usr/bin/env python3
"""Toqdas cihaz tanı özeti.

Telefondan (ve isterse saatten) plist çekip tek ekranda şu soruları yanıtlar:

- Dijital anahtar sabit mi, onarım kaydı kaldı mı?
- BLE oturumları ne kadar sürüyor, sinyal ne durumda?
- Saat eşitlemesi gönderiliyor mu, complication taze mi?

Kullanım:
    python3 Scripts/tani-ozet.py
    python3 Scripts/tani-ozet.py --no-watch
    python3 Scripts/tani-ozet.py --plist ~/Desktop/iphone.plist --no-pull
    python3 Scripts/tani-ozet.py --device <UDID> --outdir ~/Desktop/tani

Yalnız standart kütüphane kullanır. Eksik veri "—" olarak gösterilir;
bilinmeyen değer asla 0'a çevrilmez.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

REF_EPOCH = 978307200  # 2001-01-01 UTC, BLE tanı zaman damgaları
PHONE_UDID = "00008150-001E425622F8C01C"
WATCH_UDID = "00008310-001515AE0ED9A01E"
PHONE_BUNDLE = "com.toqdas.ios.dev"
WATCH_GROUP = "group.com.toqdas.ios"
STALE_AFTER = 3600


def dt(unix: float | None) -> str:
    if unix is None:
        return "—"
    return datetime.fromtimestamp(unix).strftime("%d.%m %H:%M")


def dt_ref(seconds: float | None) -> str:
    if seconds is None:
        return "—"
    return dt(REF_EPOCH + seconds)


def load_json(value):
    if value is None:
        return None
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return None


def pull(device: str, source: str, domain: str, identifier: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "xcrun", "devicectl", "device", "copy", "from",
        "--device", device,
        "--source", source,
        "--domain-type", domain,
        "--domain-identifier", identifier,
        "--destination", str(dest),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        lines = result.stderr.strip().splitlines()
        detail = lines[-1].strip() if lines else "bilinmeyen hata"
        print(f"  ! çekilemedi: {source} · {detail[:120]}")
        return False
    return True


def section(title: str) -> None:
    print()
    print(title)


def main() -> int:
    parser = argparse.ArgumentParser(description="Toqdas cihaz tanı özeti")
    parser.add_argument("--device", default=PHONE_UDID, help="iPhone UDID")
    parser.add_argument("--watch-device", default=WATCH_UDID, help="Apple Watch UDID")
    parser.add_argument("--no-watch", action="store_true", help="saat bölümünü atla")
    parser.add_argument("--plist", type=Path, help="çekmek yerine var olan iPhone plist'i oku")
    parser.add_argument("--no-pull", action="store_true", help="hiçbir şey çekme; --plist kullan")
    parser.add_argument("--outdir", type=Path,
                        default=Path.home() / "Desktop" / "toqdas-analiz" / "tani",
                        help="çekilen plist'lerin klasörü")
    args = parser.parse_args()

    if args.no_pull and not args.plist:
        print("--no-pull için --plist gerekli", file=sys.stderr)
        return 2

    outdir: Path = args.outdir
    phone_plist = args.plist
    watch_group = outdir / "watch-group.plist"

    if not args.no_pull:
        print("Cihazlardan okunuyor…")
        phone_dest = outdir / "iphone.plist"
        if pull(args.device, f"/Library/Preferences/{PHONE_BUNDLE}.plist",
                "appDataContainer", PHONE_BUNDLE, phone_dest):
            phone_plist = phone_dest
        if not args.no_watch:
            pull(args.watch_device, f"/Library/Preferences/{WATCH_GROUP}.plist",
                 "appGroupDataContainer", WATCH_GROUP, watch_group)

    if not phone_plist or not phone_plist.exists():
        print("iPhone plist yok; --plist ile yol ver veya cihaz bağlantısını kontrol et", file=sys.stderr)
        return 1

    import plistlib
    with phone_plist.open("rb") as handle:
        phone = plistlib.load(handle)

    vin = phone.get("toqdas.selectedVin") or ""
    vin_short = vin[-6:] if vin else "—"
    now = datetime.now().timestamp()

    print()
    print(f"TOQDAS TANI ÖZETİ · {datetime.now().strftime('%d.%m.%Y %H:%M')}")
    print(f"VIN …{vin_short} · kaynak: {phone_plist}")

    warnings: list[str] = []

    # --- Dijital anahtar -------------------------------------------------
    section("DİJİTAL ANAHTAR")
    key_fp = phone.get(f"toqdas.ble.keyFingerprint.{vin}")
    cert_fp = phone.get(f"toqdas.ble.certFingerprint.{vin}")
    provenance = load_json(phone.get(f"toqdas.cert.provenance.{vin}")) or {}
    repair = load_json(phone.get(f"toqdas.pairing.repair.{vin}"))
    accessibility = phone.get("toqdas.key.accessibility.v1") or {}

    print(f"  parmak izi     : {key_fp or '—'}")
    if provenance:
        print(f"  sertifika      : {cert_fp or '—'} · {provenance.get('source', '—')} · {dt(provenance.get('at'))}")
    else:
        print(f"  sertifika      : {cert_fp or '—'} · kaynak —")
    if repair:
        print(f"  onarım kaydı   : VAR · {repair.get('reason', '—')} · {dt(repair.get('detectedAt'))}")
        warnings.append("onarım kaydı duruyor (araçta 'Yeniden eşleştir' sonrası temizlenmeli)")
    else:
        print("  onarım kaydı   : yok")
    if accessibility:
        status = accessibility.get("status")
        mark = "✓" if status == 0 else "!"
        print(f"  anahtar erişimi: {mark} status={status} · {dt(accessibility.get('at'))}")
        if status not in (None, 0):
            warnings.append(f"anahtar erişim durumu status={status}")
    else:
        print("  anahtar erişimi: —")

    history = load_json(phone.get("toqdas.key.history.v1")) or []
    section("ANAHTAR GEÇMİŞİ (son 8)")
    if not history:
        print("  —")
    for event in history[-8:]:
        print(f"  {dt(event.get('at'))}  {str(event.get('kind', '—')):<14} {event.get('detail', '')}")
    fingerprints = set()
    for event in history:
        if event.get("kind") != "confirmed":
            continue
        match = re.search(r"[0-9a-f]{8}", str(event.get("detail", "")))
        if match:
            fingerprints.add(match.group(0))
    if len(fingerprints) > 1:
        warnings.append(f"anahtar parmak izi değişmiş: {', '.join(sorted(fingerprints))}")

    # --- BLE oturumları --------------------------------------------------
    sessions = load_json(phone.get("toqdas.ble.session.v1")) or []
    section("BLE OTURUM KALİTESİ (son 8)")
    if not sessions:
        print("  —")
    for session in sessions[-8:]:
        rssi = "—"
        if session.get("minRSSI") is not None:
            rssi = f"{session.get('minRSSI')}/{session.get('averageRSSI', '—')}/{session.get('maxRSSI')} dBm"
        duration = session.get("duration")
        seconds = f"{duration:.0f} sn" if isinstance(duration, (int, float)) else "—"
        print(f"  {dt(session.get('startedAt'))}  {seconds:>7}  {rssi:<22} {session.get('endReason', '—')}")

    # --- Sinyal / bağlantı olayları -------------------------------------
    diagnostics = load_json(phone.get("toqdas.ble.diagnostics.v1")) or []
    cutoff = now - 24 * 3600
    recent = [e for e in diagnostics if REF_EPOCH + (e.get("timestamp") or 0) >= cutoff]
    rssi_values = []
    for event in recent:
        match = re.search(r"RSSI\s*(-?\d+)", event.get("message", ""))
        if match:
            rssi_values.append(int(match.group(1)))
    failures = Counter()
    for event in recent:
        match = re.match(r"failure_kind\s*·\s*(\w+)\s*·\s*(.*)", event.get("message", ""))
        if match:
            failures[f"{match.group(1)} ({match.group(2)[:40]})"] += 1

    section("SİNYAL (son 24 saat)")
    if rssi_values:
        weak = sum(1 for value in rssi_values if value < -85)
        print(f"  RSSI: {len(rssi_values)} örnek · ort {sum(rssi_values) / len(rssi_values):.0f} · "
              f"min {min(rssi_values)} · maks {max(rssi_values)} · "
              f"zayıf %{round(100 * weak / len(rssi_values))}")
    else:
        print("  RSSI: —")
    if failures:
        for reason, count in failures.most_common(6):
            print(f"  kopma: {count:>2} × {reason}")
    else:
        print("  kopma: —")

    repair_events = Counter()
    for event in recent:
        match = re.match(r"(repair_\w+|key_fingerprint|key_unavailable)", event.get("message", ""))
        if match:
            repair_events[match.group(1)] += 1
    if repair_events:
        print("  anahtar/onarım: " + " · ".join(f"{k} {v}" for k, v in repair_events.most_common()))
        if repair_events.get("repair_restored") and not repair_events.get("repair_cleared"):
            warnings.append("son 24 saatte onarım kaydı yeniden oluşmuş; temizleme yok")

    # --- Saat ------------------------------------------------------------
    section("SAAT")
    sync = phone.get("toqdas.watch.sync.v1") or {}
    if sync:
        installed = "✓" if sync.get("installed") else "✗"
        paired = "✓" if sync.get("paired") else "✗"
        print(f"  eşitleme       : {sync.get('outcome', '—')} · kurulu {installed} · eşleşmiş {paired} · "
              f"erişilebilir {'✓' if sync.get('reachable') else '✗'} · {dt(sync.get('at'))}")
        if sync.get("outcome") != "sent":
            warnings.append(f"saat eşitlemesi gönderilemiyor: {sync.get('outcome')}")
    else:
        print("  eşitleme       : — (uygulama bir kez öne gelmeli)")

    complication_updated = None
    if not args.no_watch and watch_group.exists():
        with watch_group.open("rb") as handle:
            watch = plistlib.load(handle)
        snapshot = load_json(watch.get("toqdas.watch.complication.snapshot.v1")) or {}
        complication_updated = snapshot.get("updatedAt")
    if complication_updated:
        age = now - complication_updated
        fresh = age <= STALE_AFTER
        print(f"  complication   : {dt(complication_updated)} · "
              f"{'güncel' if fresh else 'ESKİ'} ({age / 60:.0f} dk)")
        if not fresh:
            warnings.append("complication verisi 1 saatten eski")
    else:
        print("  complication   : —")

    # --- Sonuç -----------------------------------------------------------
    section("DİKKAT")
    if warnings:
        for warning in warnings:
            print(f"  • {warning}")
    else:
        print("  • belirgin sorun yok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
