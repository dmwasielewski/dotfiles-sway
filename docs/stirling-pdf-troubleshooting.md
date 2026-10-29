# Stirling PDF desktop: Sway clipboard and self-hosted connections

## Verified findings on Fedora Sway Atomic (2026-10-14)

The official desktop v3.1.0 renders its UI through WebKitGTK, and uses Tauri's
HTTP plugin for Connect to Server. The system route and curl do not prove that
the desktop client is accepted by the server.

### Clipboard SIGSEGV

WebKitGTK 2.54.1 receives unavailable GTK targets as a NULL array and a count of
-1. `ClipboardGtk3.cpp::formats` converts this signed count into a span length
and crashes. The native probe reproduced NULL/-1; the compatibility shim returns
NULL/0 for this case. It leaves normal target arrays and callback data unchanged.

`scripts/setup-stirling-runtime.sh` builds the small compatibility library from
`scripts/native/stirling-clipboard.c`. The launcher prepends that library to
LD_PRELOAD only for Stirling PDF. It does not replace any system library, change
clipboard contents, disable the WebKit sandbox, or alter TLS checks. XWayland
alone did not resolve all crashes. The launcher still defaults to XWayland;
`STIRLING_GDK_BACKEND=wayland` permits a future native-backend retest.

`setup-stirling-pdf.sh` invokes the runtime setup. A fresh installation without
gcc reports a pending build. `packages.sh` layers gcc and glibc-devel and P2
retries the runtime setup after reboot. Verify with:

```bash
bash ~/dotfiles-sway/scripts/setup-stirling-runtime.sh
bash ~/dotfiles-sway/tests/stirling-pdf/test-clipboard.sh
bash ~/dotfiles-sway/tests/stirling-pdf/test-launcher.sh
```

Restart the application and test actual copy/paste after changes.

### Private HTTPS certificate trust

Use the full private DNS URL, including `https://`. Obtain the private root CA
through an authenticated source or independently verified fingerprint. A Firefox
certificate exception does not add system-wide CA trust. On Fedora Atomic:

```bash
sudo install -m 0644 /path/to/verified-root-ca.pem /etc/pki/ca-trust/source/anchors/home-lab-ca.pem
sudo update-ca-trust extract
curl --fail https://pdf.example.internal/api/v1/info/status
```

The launcher defaults `SSL_CERT_FILE` to Fedora's complete CA bundle when no
explicit value is provided. Restart the app after updating trust. Never download
an arbitrary presented CA and trust it without authenticating it first.

### “Internet works but this specific server is unreachable” can mean CORS

In the verified case, the actual Tauri HTTP client received HTTP 403 and the body
`Invalid CORS request`. TLS succeeded and the request reached the server. A
comparison of origins returned:

| Origin | Observed status before correction |
|---|---|
| No Origin (curl) | 200, JSON status UP |
| The server's own HTTPS origin | 200 |
| `http://tauri.localhost` (Windows desktop origin) | 200 |
| `tauri://localhost` (observed Linux desktop origin) | 403, Invalid CORS request |
| `https://tauri.localhost` | 403, Invalid CORS request |

Preserve the server's existing allowed-origin list and add the required desktop
origin `tauri://localhost`. Stirling configuration uses `system.corsAllowedOrigins`
(or `SYSTEM_CORSALLOWEDORIGINS` when supplied through environment variables).
Check which source is authoritative in the actual server deployment before
editing. Back up that source, restart only the affected Stirling backend, and
verify both origin-specific HTTP status and desktop login. Keep CORS scoped to
known origins; do not replace it with `*` or remove certificate validation.

The server correction and desktop authentication must be verified separately;
local clipboard stability is not a successful server connection.

## Logs and manual recovery

Desktop log: `~/.local/share/stirling.pdf.dev/logs/Stirling PDF.log`.
Bundled local backend logs: `~/.config/Stirling-PDF/logs/`.
Installation state/log: `~/.dotfiles-install-state` and `~/.dotfiles-install.log`.

The desktop supports a per-user `~/.config/Stirling-PDF/stirling-provisioning.json`
with `serverUrl` and `lockConnectionMode`. This selects the intended server;
it does not fix CORS, authenticate an account, or establish processing success.
Back up `~/.local/share/stirling.pdf.dev/connection.json` before changing it.

## Server correction verified

After explicit user approval, the missing `tauri://localhost` origin was appended
to the existing Compose environment list. The Compose file was backed up and
validated, and only the Stirling PDF service was recreated. An origin-specific
request changed from HTTP 403 / `Invalid CORS request` to HTTP 200 with JSON
status `UP`. Existing web and Windows desktop origins remained allowed.

The short HTTP 502 interval during restart ended when the backend was ready.
The user confirmed that Connect to Server works and reaches the server login
screen after the correction. Account authentication and a remote PDF operation
remain separate user checks. The Linux, Windows and existing web origins all
returned HTTP 200; an unrelated HTTPS origin remained rejected with HTTP 403.

## Missing watched-folder warning (2026-10-15)

The local desktop backend repeatedly logged `Not monitoring any directories;
attempting to re-register root paths.` every five seconds because its expected
`~/.config/Stirling-PDF/pipeline/watchedFolders` directory was absent. Creating
that empty application directory let FileMonitor register it on its next cycle,
without a restart. Runtime setup and the launcher now ensure the directory exists.
This restores the missing watch root rather than suppressing log messages; it
does not watch Downloads or other user document folders.

Historical failed logins must be distinguished from the later successful login.
An older updater connection error was also followed by a fresh successful HTTP
200 check of the official update manifest; it did not justify changing network
or certificate settings.
