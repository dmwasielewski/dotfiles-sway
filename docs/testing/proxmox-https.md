# Proxmox HTTPS client setup

On 2026-10-09 the CA fingerprint supplied from an authenticated root SSH
session matched the supplied public CA certificate. The server certificate
already covered its DNS name; its IP SAN covered an old address. No server
certificate replacement, proxy restart, firewall or VPN change was required.

The opt-in installer trusts the pinned CA in Fedora's system trust store and
adds one marked hostname mapping to `/etc/hosts`. Use the certificate's DNS
name when opening port 8006. An IP URL still fails identity verification.
Trusting this CA allows certificates it signs; keep its private key on Proxmox.

## Restore on a replacement Fedora machine

Restore these files from private backup before `bootstrap.sh`/`orchestrate.sh`:
`~/.config/dotfiles/proxmox-client.json` and the adjacent public CA PEM.
Keep both files mode 600. Example policy (replace all values):

```json
{"hostname":"pve.example.home","address":"192.168.50.10","ca_file":"proxmox-root-ca.pem","sha256":"AUTHENTICATED_SHA256_FINGERPRINT"}
```

Obtain the pin on the authenticated Proxmox host using:

```bash
openssl x509 -in /etc/pve/pve-root-ca.pem -noout -subject -dates -fingerprint -sha256
```

Never trust a CA obtained only through an unverified HTTPS connection.
Neither real addresses nor the cluster certificate belong in this public repo.
The installer validates the pin, validity, hostname and private IPv4 address,
preserves unrelated hosts entries, refuses conflicting mappings/different
anchors, and rolls back its writes if extraction fails. Without a policy it
changes nothing. P0 runs it during normal administrator authentication;
manual setup requires `sudo -v` before running the helper. No passwordless
execution of this repository's Python script is granted.

```bash
sudo -v
bash ~/dotfiles-sway/scripts/setup-proxmox-client.sh
curl --max-time 15 -o /dev/null -w 'HTTPS=%{http_code} TLS=%{ssl_verify_result}\n' https://YOUR_CERTIFICATE_HOSTNAME:8006/
```

`verify.sh` checks local configuration independently of home availability.
An HTTPS test verifies trust and identity; it does not prove a panel login.
Restart the browser if it cached the old certificate error. Browser-specific
trust handling must be checked separately if a warning persists.

To remove this integration, remove only the `dotfiles-proxmox-client` block
from `/etc/hosts` and `/etc/pki/ca-trust/source/anchors/dotfiles-proxmox-ca.pem`,
then run `sudo update-ca-trust extract`. Preserve unrelated entries/anchors.
The private policy must also be removed to prevent automatic restoration.

## Validation on 2026-10-09

- Normal hostname HTTPS: HTTP 200, TLS verification result 0, with no custom CA
  option, resolver override or insecure flag.
- Hostname resolution matched the intended private address; routing selected
  `tailscale0` table 52. NordVPN remained connected and AdGuard filtering ON;
  both compatibility services remained active.
- Six isolated tests passed: hosts preservation/idempotence, conflict rejection,
  malformed-block rejection, private-key rejection, invalid-policy rejection
  and trust-extraction rollback. Setup and orchestrator regression suites passed.
- Shell syntax and ShellCheck (`-x`, existing SC2016/SC2088 exclusions) passed.
  Full system verification: 197 passed, 0 failed, 0 pending, 1 warning.
- Browser UI and authenticated panel login were not checked by this automated
  test. Full NAS/guest application coverage remains repair 4.
