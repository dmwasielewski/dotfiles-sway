## Telegram Desktop

- Install source: user Flatpak `org.telegram.desktop` from Flathub. The upstream
  [Telegram Desktop website](https://desktop.telegram.org/) links to Flatpak.
- `setup.sh` installs it through `install_flatpak_app`, covering both manual
  bootstrap and orchestrator P1. Existing installations are skipped; failed
  downloads are collected and reported without abandoning other applications.
- `scripts/verify.sh` checks the installed application and prints the repair
  command if missing. This check covers installation, not login or messaging.
- Launch **Telegram Desktop** from the application menu, or run:

  ```bash
  flatpak run org.telegram.desktop
  ```

- First login requires the user's Telegram account and interactive approval.
  Session data under `~/.var/app/org.telegram.desktop/` is private and must stay
  outside Git. A fresh laptop installs the app automatically but needs login.
- Updates use the existing Flatpak updater. No rpm-ostree package, host reboot,
  dedicated workspace, login autostart, or custom launcher is required.

### Validation on 2026-10-18

Telegram Desktop 7.3.1 was installed from Flathub as a user Flatpak on the Fedora
Sway Atomic laptop. `flatpak ps` showed the running app; Sway's window tree showed
`app_id=org.telegram.desktop`, title `Telegram`, and native Wayland `xdg_shell`.
This confirms installation and window creation. Account login, messages, calls,
notifications and microphone/speaker operation were not tested.

The launch printed an OpenAL PipeWire connection error, while the application
still created its window. Do not infer working or broken call audio from window
creation alone; verify audio during an actual user-authorized call before
changing audio configuration or Flatpak permissions.

### Checks and repair

```bash
flatpak info --user org.telegram.desktop
flatpak install -y --user flathub org.telegram.desktop
bash ~/dotfiles-sway/scripts/verify.sh
```

For future AI changes, keep `setup.sh`, the Flatpak map in `scripts/verify.sh`,
`README.md`, `CLAUDE.md` and this document consistent. Preserve the existing
non-blocking installation policy and distinguish installation checks from
account-dependent tests. Never copy Telegram account/session files into this repo.
