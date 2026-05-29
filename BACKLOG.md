# Backlog — dotfiles-sway

Items to implement, fix, or automate. Ordered by priority.

---

## Waybar — Update notification module

**Status:** ✅ DONE
**Priority:** high — user wants click-to-update from Waybar

**Reference:** https://github.com/ccuqme/swarofi-updater — only existing Fedora Sway Atomic + Waybar update applet (needs adaptation for this setup)

**Architecture (3 components):**

1. **`scripts/updates-check.sh`** — systemd timer script, writes cache file `~/.cache/waybar-update-count`
   - Checks: `flatpak remote-ls --user --updates | wc -l` (user flatpaks only, NOT system)
   - Checks: `rpm-ostree upgrade --check` (slow 5-30s — runs in background timer, NOT inline)
   - Writes count + tooltip to `~/.cache/waybar-update-count`

2. **`scripts/updates-waybar.sh`** — Waybar polling script (reads cache, instant)
   - JSON output: `{"text":"⬆ 3","class":"updates","tooltip":"OS: 1 | Flatpak: 2"}`
   - Empty text when 0 updates (hides module in Waybar)
   - Signal 8 triggers immediate re-read

3. **`scripts/updates-do.sh`** — click handler (foot terminal)
   - Shows: `rpm-ostree status`, available updates list
   - Asks: "Apply all updates? [y/N]"
   - Runs: `rpm-ostree upgrade` + `flatpak update --user -y`
   - Offers reboot after OS update
   - After done: sends `pkill -SIGRTMIN+8 waybar` to force refresh

4. **`~/.config/systemd/user/check-updates.timer`** — runs every 1h
   - Calls `scripts/updates-check.sh` in background
   - Avoids blocking Waybar during slow network checks

5. **`waybar/config`** — add module:
   ```json
   "custom/updates": {
       "exec": "$HOME/.local/bin/updates-waybar",
       "return-type": "json",
       "interval": 60,
       "signal": 8,
       "on-click": "$HOME/.local/bin/updates-do"
   }
   ```
   Add `"custom/updates"` to `modules-right` before `"clock"`.

6. **`waybar/style.css`** — add CSS class `.updates` (amber colour when updates pending)

**NordVPN updates:** covered automatically via `rpm-ostree upgrade` (NordVPN is rpm-ostree layered package).

**Performance note:** NEVER use `rpm-ostree upgrade --check` at short Waybar intervals — it's 5-30s network call. Always use systemd timer → cache file pattern.

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
