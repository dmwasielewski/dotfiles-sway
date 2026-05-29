# Backlog — dotfiles-sway

Items to implement, fix, or automate. Ordered by priority.

---

## Waybar — Update notification module

**Status:** ✅ DONE

Icon-only Waybar indicator + interactive foot menu for Flatpak / containers / Fedora OS updates.

**Files:**
- `scripts/lib-updates.sh` — shared detection logic (single source of truth). All names discovered dynamically (`distrobox list`, `toolbox list`, `flatpak remote-ls`, `rpm-ostree`). No hardcoding.
- `scripts/updates-waybar.sh` — indicator: icon `⬆`, 3 CSS severity classes, multiline tooltip. Caches JSON 1h.
- `scripts/updates-do.sh` — tiny launcher → foot → updates-menu.
- `scripts/updates-menu.sh` — interactive menu (loop, returns after each action).
- `waybar/config` — `custom/updates` module (interval 60, signal 8).
- `waybar/style.css` — `.warning` (amber), `.critical` (red); uptodate hidden via empty text.
- `sway/config` — floating rule `system-updates` 900×640.

**Severity logic:** critical = OS update pending (reboot); warning = Flatpak/stale containers; uptodate = hidden.

**Menu (order by update frequency):** 1) Flatpak  2) Containers  3) Fedora OS  4) Everything (apps→containers→OS, continue-on-error + results summary, no `--force`)  5) Show update list (scrollable `less`, returns to menu)  q) Cancel.

**Last-updated dates:** OS from `rpm-ostree status --json` timestamp; Flatpak/containers from our own `~/.cache/update-last-*` files written after each successful update.

**Known limitation:** `rpm-ostree upgrade --check` fails when the NordVPN rpm repo is unreachable (no network/VPN), so OS shows "up to date" until the repo is reachable again. Degrades gracefully (no crash).

**Performance:** indicator caches JSON for 1h; OS check runs ONCE per invocation (parsed from captured text, not re-run per field).

---

## NordVPN update to latest version

**Status:** ready — NordVPN 4.6.0 is outdated
**What:** NordVPN showed "A new version of NordVPN is available!" at every command.
**Command:**
```bash
bash ~/dotfiles-sway/scripts/setup-nordvpn.sh
```
Or update the setup script to handle upgrades automatically.

---

## System updates (rpm-ostree)

**Status:** ready — run when convenient (requires reboot)
**What:** `rpm-ostree upgrade` — checks and installs host system updates.
After install: `systemctl reboot`

---

## Flatpak updates

**Status:** ✅ triggered (running) — Mesa, Mesa Codecs, KDE runtime updates available
**Command:** `flatpak update --user -y`
