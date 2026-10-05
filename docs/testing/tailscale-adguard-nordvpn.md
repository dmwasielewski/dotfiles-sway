# Tailscale / AdGuard / NordVPN interoperability test plan

Status: **planned; the four-case matrix has not been executed**.
Prepared: 2026-10-06. Run on the Fedora Sway Atomic host, not inside a container.

## Objective and baseline

Determine which Internet, tailnet and home-LAN services remain reachable with
Tailscale running and each combination of AdGuard for Linux and NordVPN.
AdGuard here is the filtering proxy, not AdGuard VPN.

Observed before testing: Tailscale Running; no exit node; accept-routes false;
Tailscale DNS enabled; NordVPN disconnected (NordLynx, firewall enabled,
kill switch disabled); AdGuard proxy stopped. These are a dated snapshot, not
fresh-install defaults or evidence that coexistence works.

Keep Tailscale, exit-node choice, subnet-route acceptance, NordVPN firewall,
kill switch and DNS configuration unchanged throughout the first matrix.
Do not apply allowlist, DNS or routing fixes mid-case. Record a failure first;
any proposed fix needs its own repeated test. Do not disable the NordVPN
firewall as an automatic workaround.

## Targets to agree before the run

Keep real addresses, account details and logs outside this public repository,
for example under ~/.local/state/tailscale-coexistence/ (directory mode 700).
Use these aliases in published results:

| Alias | Purpose | Required target details |
|---|---|---|
| Internet | Public HTTPS + public DNS | A stable public website and hostname |
| Egress | Identify the Internet path | Public-IP check compared locally; publish only ISP/NordVPN |
| Peer | Online Tailscale device | Its Tailscale IP and MagicDNS name |
| Peer-service | Real application over Tailscale | An existing HTTPS panel or SSH endpoint |
| LAN-service | Direct local network access | Existing NAS/router/panel/file service by LAN IP |
| Routed-service | Home subnet via Tailscale router | Advertised/approved subnet and existing service |
| Phone | Android Tailscale peer | Online and Tailscale connected during each case |
| Files | Intended NAS file workflow, if required | Existing SMB/SFTP share; read-only listing/opening |

At planning time one Linux peer was online; the Android peer was offline.
Offline/unavailable peers are **NOT TESTED**, not blocked by VPN.
User-confirmed scope: the whole NAS, Proxmox host and all of its VMs/LXCs.
Local homelab notes include an authoritative LXC resource inventory dated
2026-09-29 listing 20 containers. The older Tailscale project note is a draft
setup guide, not proof of current routes or an approved access policy. VM names,
current endpoints and intended protocols still need live inventory confirmation.
Neither the peer hostname nor its presence proves that it is a subnet router.

### Full NAS / Proxmox coverage

Before changing either laptop toggle, use the existing authenticated Proxmox
UI or authorized read-only API/SSH access to collect the current host, VM and
LXC inventory. Do not guess from the list of Tailscale peers: most guests may
use a shared subnet router without having their own Tailscale client.
Confirm NAS repository/Forgejo documentation through existing authorized access
if available; no current NAS-hosted repository was read during planning.

The local 2026-09-29 inventory identifies these service roles:

| Role | Intended read-only validation |
|---|---|
| Proxmox VE host | Admin login, guest list, existing console access if needed |
| Proxmox Backup Server | Dashboard / backup catalogue, no backup or restore jobs |
| NAS / Samba | List the intended share and open an existing small file |
| Tailscale gateway | Peer connectivity, advertised and approved subnets, forwarding |
| AdGuard Home | Existing admin dashboard and intended home-DNS resolution |
| Authentik | Existing login/SSO flow |
| Nginx Proxy Manager | Existing management access and configured proxy hostname paths |
| Paperless-ngx | Dashboard / existing document view |
| Stirling PDF | Load interface without uploading or transforming files |
| Home Assistant | Dashboard without operating devices |
| Immich | Dashboard / existing thumbnail or photo |
| n8n | Dashboard without executing workflows |
| Jellyfin | Dashboard / existing media access if required |
| Forgejo | Existing repository listing/read-only documentation access |
| Beszel | Dashboard / existing monitoring data |
| Uptime Kuma | Dashboard / existing service status |
| Ollama | Existing read-only health/model listing; no model pulls or generation |
| Semaphore | Dashboard without executing jobs |
| JDownloader 2 | Existing interface without starting downloads |
| PostgreSQL | Intended existing authenticated client path, only if laptop access is required |
| SearXNG | Existing web interface / normal query if required |
| Every additional live VM/LXC | Existing intended application, dashboard or SSH path |

The list is a planning inventory, not a claim that every service is running or
configured. Validate live before testing. A stopped guest is NOT TESTED (stopped),
not a VPN failure; do not start it automatically. Database/back-end services
need not be directly exposed to the laptop just to mark the test complete:
record INTENTIONALLY RESTRICTED where that is the intended access policy.

For **every guest and intended service**, create an individual result row with
an anonymized alias, IP-vs-name access, direct-LAN-vs-subnet path, baseline
availability and results A/B/C/D/A2. One successful dashboard does not stand
in for all NAS workloads. Keep the real inventory/mapping in private local
notes, not this public repository.

Verify the actual subnet-router design separately: gateway forwarding,
advertised/approved prefixes, tailnet access policy, client route acceptance,
and return path. Do not enable broad access or advertise extra subnets based
only on this plan. If the design requires route acceptance on Fedora, make it
a separately documented configuration prerequisite and then repeat the full
matrix with that prerequisite held constant.

A direct LAN target is relevant only while connected to that LAN. To prove
remote home access, repeat the relevant tests on a genuinely external network
(e.g. a phone hotspot); same-Wi-Fi success does not prove remote access.
With accept-routes false, a service reachable only through advertised subnet
routes is not expected to work. Record NOT CONFIGURED, then plan a separate,
explicitly configured subnet-routing run if that access is wanted.

## Test sequence

Record initial statuses and restore the initial AdGuard/NordVPN connection
state at the end, including on interruption. Execute one transition at a time;
check the actual status and wait for network/DNS stabilization before probing.
A command exit code or tray icon alone is not proof of service availability.

| Case | AdGuard | NordVPN | Transition from previous case |
|---|---|---|---|
| A | OFF | OFF | Confirm baseline; stop/disconnect only if needed |
| B | ON | OFF | Start AdGuard; confirm active |
| C | OFF | ON | Stop AdGuard and confirm; connect NordVPN and confirm |
| D | ON | ON | Start AdGuard with NordVPN still connected |
| A2 | OFF | OFF | Stop AdGuard; disconnect NordVPN; repeat baseline |

Use `adguard-cli start`, `adguard-cli stop`, `nordvpn connect`, and
`nordvpn disconnect` for the planned transitions. Confirm with
`adguard-cli status` and `nordvpn status`. If activation/login is needed, pause
the dependent test instead of reporting that case as tested.
Record the chosen NordVPN country/server privately and keep it consistent.
Do not turn Tailscale off to make another case pass.

## Identical checks in every case

1. Record `tailscale version`, `tailscale status`, `nordvpn status`,
   `nordvpn settings`, `adguard-cli status`, `resolvectl status`,
   `ip -brief addr`, `ip rule`, and `ip route show table all` privately.
2. Public DNS: `resolvectl query example.com`; Internet HTTPS:
   `curl --connect-timeout 5 --max-time 15 -I https://example.com`.
   Record the HTTP result; distinguish DNS failure from TLS/connection failure.
3. Check public egress with the same trusted IP-check service in every case.
   Compare addresses privately. Report only ISP vs NordVPN, not the actual IP.
4. For the online peer, run both a Tailscale diagnostic and a real application:
   `tailscale ping --c=3 --timeout=5s --until-direct=false <peer-tailscale-ip>`;
   `ping -c 3 -W 3 <peer-tailscale-ip>`; then open the intended existing
   panel or SSH connection by IP. An ICMP failure alone is inconclusive.
   Tailscale diagnostic ping can succeed while normal service traffic is blocked.
5. Resolve the peer's MagicDNS name with `resolvectl query <peer-dns-name>`
   and repeat the same application check by name. IP works/name fails points
   toward DNS; it does not prove the exact cause.
6. Open the LAN-service and Routed-service separately by IP and, if used, name.
   Check intended file access with a read-only directory listing/opening of an
   existing small file. Do not create, upload or modify remote data.
7. If inbound access to Fedora is required, repeat an existing intended service
   from another online tailnet device. Laptop-to-peer success proves only that
   direction. Do not enable a new SSH server solely for this test.
8. Check AdGuard functionality through its activity/filtering view and an
   agreed known blocked test domain. A running process or successful curl does
   not prove browser filtering works; curl may bypass the relevant filtering path.
9. Record tray state and actual browser/application behavior. Note direct vs
   DERP from Tailscale diagnostics; DERP success still means access works.
   Repeat a failed probe once after stabilization, retaining both outcomes.

Use authenticated applications/browser sessions where needed; do not put
credentials into curl command arguments or public test logs. For an HTTPS panel
by IP, certificate mismatch is a separate result from network failure; do not
silently disable TLS certificate validation to obtain a green result.

## Results matrix

Do not replace PLANNED with PASS based on expected behavior.

| Access / behavior | A: neither | B: AdGuard | C: NordVPN | D: both | A2: restored |
|---|---|---|---|---|---|
| Public DNS | PLANNED | PLANNED | PLANNED | PLANNED | PLANNED |
| Internet HTTPS | PLANNED | PLANNED | PLANNED | PLANNED | PLANNED |
| Internet egress ISP/NordVPN | PLANNED | PLANNED | PLANNED | PLANNED | PLANNED |
| Tailscale diagnostic IP ping | PLANNED | PLANNED | PLANNED | PLANNED | PLANNED |
| Real peer service by IP | PLANNED | PLANNED | PLANNED | PLANNED | PLANNED |
| MagicDNS + same service by name | PLANNED | PLANNED | PLANNED | PLANNED | PLANNED |
| Proxmox host/admin | Inventory pending | Inventory pending | Inventory pending | Inventory pending | Inventory pending |
| Each VM/LXC intended service (separate rows) | Inventory pending | Inventory pending | Inventory pending | Inventory pending | Inventory pending |
| NAS/home LAN direct | Inventory pending | Inventory pending | Inventory pending | Inventory pending | Inventory pending |
| Home LAN through subnet router | NOT CONFIGURED | NOT CONFIGURED | NOT CONFIGURED | NOT CONFIGURED | NOT CONFIGURED |
| Phone access | Offline at planning | Offline at planning | Offline at planning | Offline at planning | Offline at planning |
| NAS file access | Inventory pending | Inventory pending | Inventory pending | Inventory pending | Inventory pending |
| Inbound intended Fedora service | Inventory pending | Inventory pending | Inventory pending | Inventory pending | Inventory pending |
| AdGuard filtering | N/A | PLANNED | N/A | PLANNED | N/A |

Verdicts: PASS, FAIL, INTERMITTENT, NOT TESTED, NOT CONFIGURED, N/A.
Every FAIL should name the failing operation and concise error, not an inferred
cause. Track system/application versions, date, local vs external network, and
sanitized evidence. Keep private URLs, peer identities, IPs, tokens, account
names and complete logs out of Git. Commit only this sanitized summary.

## Completion and automation follow-up

The deliverable after execution is a plain statement for each case: Internet
path, available tailnet services, available LAN/subnet services, DNS behavior,
and whether AdGuard filtering works. Include untested targets explicitly.
The first baseline must be reproducible in A2. Investigate any mismatch before
attributing it to a particular VPN or filter.

Only confirmed remedies should be added to install automation. Each remedy
must pass the full matrix again, preserve the user's intended NordVPN protection,
and be reflected in setup scripts, verify.sh, README.md and CLAUDE.md together.
Planning this test does not change any running VPN, filtering or routing setting.
A complete fresh-install VM test remains a separate validation activity.

References:
- https://tailscale.com/docs/reference/faq/other-vpns
- `tailscale ping --help` (installed client explains diagnostic vs normal traffic)
