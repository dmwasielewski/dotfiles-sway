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

## NordVPN

**Status:** ✅ current (2026-05-30) — `rpm-ostree upgrade --check` reports no updates for the layered `nordvpn` package.
**Note:** A stale `NORDVPN_REPO` failure (from 2026-05-29 when the repo was unreachable) lingers in the shared install-state file and shows up in setup summaries. The repo is reachable again; re-run `bash ~/dotfiles-sway/scripts/setup-nordvpn.sh` to clear it.

---

## System updates (rpm-ostree)

**Status:** ✅ current (2026-05-30) — booted `44.20260530.0`; `rpm-ostree upgrade --check` → "No updates available".
**When new updates appear:** `rpm-ostree upgrade` then `systemctl reboot`.

---

## Flatpak updates

**Status:** ✅ triggered (running) — Mesa, Mesa Codecs, KDE runtime updates available
**Command:** `flatpak update --user -y`

---

## yazi — terminal file manager

**Status:** ✅ installed (2026-06-03, yazi 26.5.6). yazi is **not** in Fedora's repos, so it is installed user-local from its GitHub release by `scripts/setup-yazi.sh` (→ `~/.local/opt/yazi-<ver>`, symlinked to `~/.local/bin/{yazi,ya}`) — no root, no reboot. Hooked into `setup.sh`. Previews: images via foot sixel; video via `ffmpegthumbnailer` (in `packages.sh`); PDF via `poppler-utils` (already in Fedora base). Note: there is no flatpak for yazi — it's a TUI/CLI tool, and flatpak targets sandboxed GUI apps.

**Why:** Primary, keyboard-driven file manager for Sway — fast, low-footprint, reuses ripgrep/fd/fzf. Thunar stays as the GUI fallback for drag-and-drop into other GUI apps and device/network mounting.

**Open:** optional Sway keybind (`Mod+…` → `foot -e yazi`) — not yet bound (avoid shortcut conflicts; decide key first). Optional shell hook to `cd` into yazi's last dir on exit.
