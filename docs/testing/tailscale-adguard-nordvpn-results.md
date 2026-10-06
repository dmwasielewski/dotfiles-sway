# Tailscale / AdGuard / NordVPN access results

Date: 2026-10-06 (Europe/London).
Status: **four combinations tested for available targets; full NAS/VM/LXC
application coverage remains incomplete**.

The table below records the ORIGINAL baseline. Later repair 1 restored the
tested peer IPv4 and local Proxmox-port access with NordVPN; see the
[sequential repair record](tailscale-repair-plan.md). DNS and certificate trust
remain pending. The original matrix does not describe the updated policy.

## Scope and method

Tests ran on the Fedora Sway Atomic host while connected to the home LAN.
Tailscale 1.102.5 was Running, without an exit node or subnet-route acceptance.
The online Linux Tailscale peer advertised the current home subnet, but this
laptop was not accepting it. No routing, firewall, allowlist, kill-switch,
exit-node or DNS preference was changed for these tests.

AdGuard was the Linux filtering proxy, with system-wide automatic filtering
reported enabled in B/D. NordVPN used NordLynx with its existing firewall
configuration. NordVPN stayed on the same connection for C/D within each run;
the retry used a new automatic connection. Public egress changed while NordVPN
was connected and returned to the original address after disconnection. Real
addresses, account identities, server names and complete logs are kept private.

Each case checked actual toggle states before and after probing. The initial
standalone AdGuard attempt did not remain active across the execution boundary;
that attempt was discarded. The valid matrix started AdGuard and probed within
one continuous command lifetime. No general claim about AdGuard startup failure
is derived from that discarded attempt.

The same tests were performed in A (neither), B (AdGuard), C (NordVPN), D (both),
then A2 (restored baseline). Failed C/D connectivity probes and the B MagicDNS
lookup were repeated separately after stabilization. A2 restored baseline
Internet, peer connectivity and name resolution. Both optional services were
returned to their initial OFF/disconnected state; Tailscale remained enabled.

## Observed results

| Check | A: neither | B: AdGuard | C: NordVPN | D: both | A2: restored |
|---|---|---|---|---|---|
| Public hostname lookup (example.com) | PASS | PASS | PASS | PASS | PASS |
| Public HTTPS (example.com) | HTTP 200 | HTTP 200 | HTTP 200 | HTTP 200 | HTTP 200 |
| Public egress vs baseline | Original | Original | Changed with NordVPN | Same as C | Original |
| Tailscale client state | Running | Running | Running | Running | Running |
| Diagnostic ping to online peer by Tailscale IP | PASS | PASS | No reply | No reply | PASS |
| Normal ICMP ping to peer IP | PASS | PASS | No reply | No reply | PASS |
| TCP connection to peer SSH port | PASS | PASS | Timeout | Timeout | PASS |
| Peer MagicDNS name via system resolver | PASS | Timeout | Timeout | Timeout | PASS |
| TCP connection to Proxmox panel port | PASS | PASS | Timeout | Timeout | PASS |
| HTTPS certificate verification for Proxmox by LAN IP | Certificate error | Certificate error | Connection timeout | Connection timeout | Certificate error |
| OneDrive account metadata availability (supplemental run) | PASS | PASS | PASS | PASS | PASS |
| Authenticated Proxmox UI / guest inventory | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED |
| Each guest application / NAS file share | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED | NOT TESTED |
| Remote home-subnet access through Tailscale | NOT CONFIGURED | NOT CONFIGURED | NOT CONFIGURED | NOT CONFIGURED | NOT CONFIGURED |
| AdGuard blocks a known unwanted request | N/A | NOT TESTED | N/A | NOT TESTED | N/A |

Public lookup success includes the system resolver's normal caching behavior;
it is not proof of a fresh upstream query or of all DNS names working.
The HTTPS request used normal certificate validation. Proxmox's certificate
error is distinct from network failure: the port was reachable in A/B/A2, but
curl did not trust/validate the presented certificate for that IP. Validation
was not disabled to obtain a successful HTTP result.

The SSH port check proves TCP reachability, not an authenticated SSH session.
Existing key-based login attempts to Proxmox using the two known/plausible
local account names were rejected. No password guessing or credential changes
were performed. The phone was offline and was not used as a test endpoint.

## What this means for daily use

- **Neither enabled:** tested Internet and peer IP/MagicDNS access work; the
  local Proxmox panel port is reachable. Application login remains a separate test.
- **AdGuard alone:** tested Internet and peer access by IP work; peer MagicDNS
  lookup times out. An IP path working does not mean internal hostnames work.
- **NordVPN alone:** tested Internet works through the changed egress, but the
  tested Tailscale peer and local Proxmox port time out. Tailscale still reports
  Running, so its enabled tray/client state does not prove usable access.
- **Both enabled:** the tested Internet works, but the same tailnet/local-Proxmox
  access failures occur. This combination is not validated for homelab access.

These observations do not isolate whether the NordVPN failures are caused by
firewall rules, policy routing or another interaction. AdGuard correlates with
the MagicDNS timeout, but the exact resolver interaction is not yet identified.
No firewall protection was disabled, no broad allowlist was installed, and no
configuration remedy has been verified or added to the installer.

## OneDrive follow-up

The user observed a lost OneDrive connection during the earlier network tests.
After restoring the baseline, the drive remained mounted and the existing
Waybar helper reported connected. A separate continuous A/B/C/D/A2 run then
checked the helper twice in each case, with 32 seconds between checks. Both
checks reported connected in every case, including NordVPN alone and both
programs together. Toggle states were checked before and after each case.

The helper makes an authenticated read-only Microsoft Graph drive-root metadata
request using the existing account token. No token was printed or refreshed,
and no cloud file was created or changed. These results establish account
metadata reachability at the times tested, not completed uploads, full file
synchronization or the rendered tray icon state. The reported outage was not
reproduced; a brief interruption during network switching remains a hypothesis,
not an established cause. Do not describe OneDrive as consistently blocked by
NordVPN on the basis of the earlier observation.

## Remaining work and required access

The user wants the **entire NAS, Proxmox and every VM/LXC**. Local homelab notes
contain a dated inventory of 20 LXCs; those notes do not establish the current
application addresses, credentials, guest state or intended access policies.
To finish, obtain the correct existing SSH account/key or an authenticated
read-only Proxmox session and the NAS-hosted Forgejo documentation address.
Use the live guest/service inventory to add a separate A/B/C/D/A2 result row
for every intended application and file share; do not infer fleet coverage
from the gateway or Proxmox-port checks above.

Also pending: application-level access by peer name/IP, inbound Fedora services,
actual AdGuard filtering, TLS validation for intended Proxmox hostname, and
remote access on an external network. The subnet-router prerequisite must be
agreed and documented before enabling route acceptance; testing on the same
home Wi-Fi does not validate remote access.

Next diagnostic work should isolate DNS and NordVPN routing/firewall one
variable at a time. Test any proposed narrow exception or DNS remedy against
all four cases, then update automation only if that remedy is verified and
matches the intended access policy.

[Original test plan](tailscale-adguard-nordvpn.md)
