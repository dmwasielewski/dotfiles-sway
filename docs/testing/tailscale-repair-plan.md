# Tailscale coexistence: four sequential repairs

Approved order: 1 → 2 → 3 → 4. Complete and evaluate one repair before changing
the next variable. Baseline: [measured results](tailscale-adguard-nordvpn-results.md).

## 1. NordVPN: peer and home LAN reachability

Status: IMPLEMENTED AND VALIDATED for the tested IPv4 peer and local Proxmox
port. Full guest/remote coverage belongs to repair 4. AdGuard stays OFF while isolating this problem.
Capture settings and existing exceptions. With one NordVPN connection kept up,
reproduce the failures, then try an IPv4 /32 exception for the tested Tailscale
peer. Test and remove it to confirm reversal. Separately test an exception for
the intended home LAN target; expand only to the required home subnet if the
approved policy requires all NAS services. Keep firewall and routing enabled.
Preserve existing exceptions and restore initial connection state on exit.
Pass criteria: peer ping/SSH-port TCP and Proxmox-port TCP work with NordVPN,
public HTTPS remains usable and public egress stays on NordVPN. MagicDNS is
recorded separately; do not conflate repair 1 with repair 2. Only verified
exceptions enter opt-in automation, with private addresses outside Git.

### First controlled experiment (2026-10-06)

The targets were briefly unavailable before testing, then baseline TCP access
was confirmed again. Each experiment kept AdGuard OFF, the same NordVPN
connection up, firewall/routing enabled and verified working public HTTPS.

| Exception configuration | Peer SSH-port TCP | Proxmox-port TCP |
|---|---|---|
| NordVPN disconnected, no exceptions | PASS | PASS |
| NordVPN connected, no exceptions | Timeout | Timeout |
| Peer IPv4 /32 only | Timeout | Timeout |
| Remove peer exception | Timeout | Timeout |
| Intended home LAN subnet only | Timeout | PASS |
| Remove LAN exception | Timeout | Timeout |
| Peer /32 plus home LAN | Timeout | PASS |
| Disconnect and remove test exceptions | PASS | PASS |

A second connection tested the local Tailscale IPv4 /32 alongside the peer /32;
that did not restore peer TCP. Adding the home LAN exception again restored
Proxmox-port TCP. A diagnostic `tailscale ping` then returned direct replies,
but ordinary peer TCP still timed out. Diagnostic transport success is not
proof of usable application traffic. This second run did not establish a
successful Tailscale remedy.

All temporary exceptions were removed and NordVPN was disconnected after the
tests. Existing settings were preserved. No unresolved rule was added to the
installer. The verified LAN exception is a candidate component of repair 1,
not a completed repair or proof of remote/all-guest access. NordVPN's official local diagnostics subsequently provided the live firewall
rules without administrator authentication. They contain an output allowlist
rule that sets NordVPN's packet mark. A short controlled Tailscale capture
recorded outgoing TCP SYNs, without a corresponding peer TCP reply; route
lookups before/after the NordVPN mark still selected tailscale0. This does not
prove the marking rule is the cause.

The temporary mark-preservation test ran after administrator authentication.
It did not establish any benefit: peer TCP worked before insertion and after
removal. Its initial peer baseline was unavailable. No custom nftables rule is
retained or automated.

### Persistent configuration and final verification

A subsequent normal-user run confirmed peer and Proxmox TCP with both standard
exceptions. Removing the peer exception broke peer TCP while Proxmox remained
reachable; restoring it restored peer TCP. The exceptions were then configured
BEFORE connecting. Two fresh NordVPN connections passed peer/Proxmox TCP and
diagnostic ping. Public HTTPS stayed HTTP 200, egress differed from baseline,
and firewall/routing stayed enabled. Earlier mid-connection trials were
inconsistent; their transient cause remains unproven. Use the verified workflow:
apply/check exceptions while disconnected, then connect.

The installed-policy test passed normal peer ICMP, peer SSH-port TCP, Proxmox
port TCP, public HTTPS and OneDrive account metadata access. Peer MagicDNS
still timed out (repair 2). Proxmox certificate validation still failed (repair 3).
These results do not prove authenticated services, IPv6 or remote access.

`scripts/nordvpn-homelab.py apply|check` reads the private JSON file
`~/.config/dotfiles/nordvpn-homelab.json` (or `DOTFILES_NORDVPN_POLICY`).
`setup-nordvpn.sh` applies it when ready; `verify.sh` checks retained exceptions.
Missing policy leaves all existing exceptions unchanged. Example schema only:
`{"subnets": ["192.168.50.0/24", "100.80.20.30/32"]}`.
Only explicit RFC1918 LAN networks and individual Tailscale IPv4 hosts (/32)
are accepted. No public/default route or whole-CGNAT exception is added.
Existing exceptions are preserved; newly added rules are rolled back on error.
Removing an entry from the file does not automatically remove a NordVPN rule.

Keep the real file mode 600 and restore it from private backup BEFORE setup on
a replacement machine. GitHub stores automation, not private addresses.
After manual NordVPN account login, rerun setup if policy application was pending.

Validation: all isolated setup tests passed, including five policy tests;
shell syntax checks passed; ShellCheck passed with existing SC2016/SC2088
exclusions. Full system verification: 192 passed, 0 failed, 0 pending, 1 warning.

Private endpoint addresses and full logs stay outside Git.

## 2. AdGuard: Tailscale MagicDNS

Status: QUEUED. Inspect system resolver ownership and compare direct Tailscale
DNS queries with application/system queries. Test domain-specific DNS forwarding
or a narrow exclusion compatible with the installed AdGuard version.
Pass criteria: the real peer name resolves with AdGuard alone and both programs,
peer access works, and a known filtering test still passes. Preserve repair 1.

## 3. Proxmox: HTTPS identity and trust

Status: QUEUED. Obtain the intended hostname and inspect its certificate chain.
Use the proper hostname/certificate or install the intended private CA trust.
Pass criteria: normal HTTPS validation succeeds without insecure flags, and the
intended authenticated panel works. Requires working existing login access.

## 4. Entire NAS over Tailscale outside home

Status: QUEUED. Obtain the live Proxmox/Forgejo inventory and existing access.
Verify subnet-router advertisement, approval, access policy and routing before
accepting the intended route. Validate each VM/LXC application and file share
from an external network in A/B/C/D plus restored baseline.
Pass criteria: explicit results for every intended service; no inference from
one peer or one reachable port. Document any intentionally restricted access.

For each repair: record before/after/rollback evidence, update installation and
verification where applicable, publish complete related changes, and preserve
private addresses/credentials outside the public repository. A failed experiment
is rolled back and recorded; it is never described as a completed repair.
