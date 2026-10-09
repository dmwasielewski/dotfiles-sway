# Fedora Sway Atomic: reproducible homelab connectivity

## Implemented configuration

| Component | Fresh-install integration | What was verified |
|---|---|---|
| Tailscale | Host package in `packages.sh`; daemon, Waybar tray and session autostart in `setup-tailscale.sh`; optional subnet-route preference | Home peer and Proxmox reached from a phone hotspot |
| NordVPN coexistence | Private allowlist policy; protected transport helper seeded in P0 and enabled in P2 | Home traffic through Tailscale; public egress through NordVPN |
| AdGuard coexistence | Protected DNS helper seeded in P0 and enabled in P2; narrowly preserves Tailscale Quad100 DNS | MagicDNS and actual DNS/HTTP filtering with both programs ON |
| Proxmox HTTPS | Pinned private CA and hostname mapping installed during authenticated P0; idempotent manual `setup.sh` integration | Normal HTTPS returned 200 with TLS verification result 0 |
| OneDrive | Existing Onedriver setup and login | Real upload, byte-identical download and delayed deletion with both programs ON |

See the [hotspot measurements](hotspot-connectivity-report.md),
[Proxmox HTTPS details](proxmox-https.md) and [remaining repair plan](tailscale-repair-plan.md).
Immediate OneDrive deletion was not confirmed in the first test; delayed deletion
passed. Do not interpret these results as full NAS/VM/application coverage.

## Private configuration required on a new machine

GitHub contains the installer and documentation. Machine-specific configuration
is restored privately; account logins remain separate steps. Keep these files
in a directory named `config/dotfiles` inside the encrypted USB vault:

```text
config/dotfiles/
  nordvpn-homelab.json
  tailscale-accept-routes
  proxmox-client.json
  proxmox-root-ca.pem
```

The CA filename must match `ca_file` in the Proxmox policy. The Proxmox pin must
be obtained through an authenticated server session. Restore the actual files
from private backup rather than using example addresses. Keep files mode 600.
Do not commit them, tokens or private keys to public Git.

`install-from-usb.sh` harvests the unlocked vault into private staging. Before
any routing setup, P0's `restore-homelab-config.py` validates these specific
files and restores them into `${XDG_CONFIG_HOME:-~/.config}/dotfiles`.
It rejects invalid policy, unverified CA, symlinks and conflicting destination
files; it preserves unrelated configuration. No staged files means no changes.
The main vault manifest still applies account/API secrets in P2. Do not add
these networking files to a late P2 manifest that overwrites the P0 result.

With the prepared encrypted USB attached, use the existing launcher:

```bash
bash ~/dotfiles-sway/scripts/install-from-usb.sh
```

For the manual `bootstrap.sh` path, restore these files directly into
`~/.config/dotfiles` before bootstrap and authenticate with `sudo -v`.
Bootstrap invokes `setup.sh`, which applies Proxmox client trust. After reboot,
follow the existing README steps to configure Tailscale and both compatibility
services. The USB orchestrator runs these steps automatically in P2.

Tailscale login, approved subnet-router routes/access policy on the home side,
NordVPN login, AdGuard activation and OneDrive login are prerequisites that
cannot be replaced by workstation configuration. After NordVPN login, rerun
`setup-nordvpn.sh` to apply the private allowlist before connecting.
Use the DNS hostname covered by Proxmox's certificate to open its panel.

## Verification and remaining work

Run `bash ~/dotfiles-sway/scripts/verify.sh`. Local policy/service checks do
not require the home server to be online. Separately test the intended home
services from outside home with AdGuard and NordVPN enabled, and verify normal
HTTPS without insecure options. Browser login and every NAS/VM/LXC service
remain distinct from the already verified routing, TCP and HTTPS checks.
A complete fresh-install VM/USB run of this new restore step has not yet been
performed; isolated restore tests and the live existing workstation were tested.

Validation on 2026-10-09: seven isolated restore/order tests passed. An isolated
fresh destination restored all four actual private configuration files,
including the authenticated Proxmox CA, with byte-for-byte equality. Setup and
orchestrator suites passed, shell checks passed, and full workstation
verification returned 197 passed, 0 failed, 0 pending and 1 warning.
