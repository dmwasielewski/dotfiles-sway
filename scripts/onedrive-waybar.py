#!/usr/bin/python3
"""Read-only OneDrive availability indicator; never logs or refreshes tokens."""
import html
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import urllib.error
import urllib.request


def mounted(path):
    target = os.path.realpath(path)
    for row in Path("/proc/self/mountinfo").read_text().splitlines():
        left, right = row.split(" - ", 1)
        location = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), left.split()[4])
        if location == target and right.split()[0] == "fuse.onedriver":
            return True
    return False


def probe(token):
    request = urllib.request.Request(
        "https://graph.microsoft.com/v1.0/me/drive/root?$select=id",
        headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(request, timeout=4) as response:
            if json.load(response).get("id"):
                return "connected", "Połączenie z kontem Microsoft działa"
            return "warning", "Microsoft zwrócił nieoczekiwaną odpowiedź"
    except urllib.error.HTTPError as error:
        error.close()
        if error.code in (401, 403):
            return "warning", "Sprawdź logowanie w Onedriver (token lub uprawnienia)"
        return "warning", "Błąd usługi Microsoft: HTTP " + str(error.code)
    except (urllib.error.URLError, TimeoutError, OSError):
        return "offline", "Brak dostępu do Microsoft (sieć, DNS lub usługa)"
    except (ValueError, TypeError):
        return "warning", "Nie można potwierdzić dostępu do konta"


def status(home):
    mount = home / "OneDrive"
    if not mounted(mount):
        return "disconnected", "Folder ~/OneDrive nie jest podłączony"
    # Cache keys use the original mount path, which can include /home symlinks.
    # Match the canonical path, without selecting another account's token.
    cache = Path(os.environ.get("XDG_CACHE_HOME", str(home / ".cache"))) / "onedriver"
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(home / ".config"))) / "onedriver/config.yml"
    if config.exists():
        for line in config.read_text().splitlines():
            if line.startswith("cacheDir:"):
                value = line.split(":", 1)[1].strip().strip("\"'")
                if value:
                    cache = Path(os.path.expanduser(value))
    for authfile in cache.glob("*/auth_tokens.json"):
        escaped = authfile.parent.name
        decoded = "/" + re.sub(r"\\x([0-9a-fA-F]{2})", lambda m: chr(int(m[1], 16)), escaped.replace("-", "/"))
        if os.path.realpath(decoded) != os.path.realpath(mount):
            continue
        auth = json.loads(authfile.read_text())
        token = auth.get("access_token")
        if token:
            return probe(token)
    return "warning", "Folder podłączony; nie znaleziono tokenu do sprawdzenia konta"


def open_launcher():
    # Focus the existing GUI instead of starting duplicate windows.
    tree = json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree"]))
    def find(node):
        if "onedriver" in (node.get("app_id") or "").lower():
            return node["id"]
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            match = find(child)
            if match:
                return match
    window = find(tree)
    if window:
        subprocess.run(["swaymsg", f"[con_id={window}] focus"], check=True)
    else:
        subprocess.Popen([str(Path.home() / ".local/bin/onedriver-launcher")],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "open":
        open_launcher()
        return
    def deadline(signum, frame):
        raise TimeoutError()
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(6)
    try:
        state, message = status(Path.home())
    except TimeoutError:
        state, message = "offline", "Microsoft nie odpowiada w ciągu 6 sekund"
    except Exception:
        # Do not expose exceptions containing account data or authorization headers.
        state, message = "warning", "Nie można sprawdzić stanu OneDrive"
    finally:
        signal.alarm(0)
    tooltip = message + "\n~/OneDrive • kontrola co 30 s\nKliknij: ustawienia Onedriver\nTo dostępność konta, nie potwierdzenie wysłania plików."
    print(json.dumps({"text": "☁", "class": state, "tooltip": html.escape(tooltip)}, ensure_ascii=True))


if __name__ == "__main__":
    main()
