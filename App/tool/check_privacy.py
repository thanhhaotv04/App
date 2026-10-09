#!/usr/bin/env python3
"""Check publication and Android backup boundaries without printing private data."""

from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
android = root / "App/android/app/src/main"
attr = "{http://schemas.android.com/apk/res/android}"
app = ET.parse(android / "AndroidManifest.xml").getroot().find("application")
assert app.get(attr + "allowBackup") == "false", "Android backup must be disabled"
assert app.get(attr + "fullBackupContent") == "@xml/backup_rules"
assert app.get(attr + "dataExtractionRules") == "@xml/data_extraction_rules"

required = {"root", "file", "database", "sharedpref", "external"}
legacy = ET.parse(android / "res/xml/backup_rules.xml").getroot()
modern = ET.parse(android / "res/xml/data_extraction_rules.xml").getroot()
for policy in [legacy, modern.find("cloud-backup"), modern.find("device-transfer")]:
    excluded = {item.get("domain") for item in policy.findall("exclude")
                if item.get("path") == "."}
    assert required <= excluded, "Backup/transfer must exclude app data"

tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
for name in tracked:
    if not name:
        continue
    path = Path(name)
    assert path.name not in {"secrets.h", "qr_assets_private.h", "key.properties", "local.properties"}, name
    assert not path.name.startswith(".env") or path.name == ".env.example", name
    assert path.suffix not in {".jks", ".keystore", ".pem", ".key"}, name

qr = (root / "Firmware/include/qr_assets.h").read_text()
assert '__has_include("qr_assets_private.h")' in qr
for name in ["BANK", "PROFILE"]:
    assert re.search(rf"{name}_QR_SIZE\s*=\s*0;", qr), "Public QR default must be empty"
    assert re.search(rf"{name}_QR_BITS\[\].*?=\s*\{{0\}};", qr)
subprocess.run(["git", "check-ignore", "--no-index", "-q",
                "Firmware/include/qr_assets_private.h"], cwd=root, check=True)

firmware = (root / "Firmware/src/main.cpp").read_text()
for log in re.findall(r"Serial\.(?:printf|print|println)\(.*?;", firmware, re.S):
    assert not re.search(r"popupTitle|popupBody|navigationStreet|wifiSsid|wifiPassword|pairingPin|localIP|SSID\(", log), \
        "Serial logs must not include private values"
assert not re.search(r'drawCentered\("\d{9,}"', firmware), "Payment caption must stay private"
print("PASS: private files, empty public QR defaults, serial logs and Android backup/transfer boundaries")
