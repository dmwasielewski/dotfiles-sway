# Tailscale coexistence: four sequential repairs

Approved order: 1 → 2 → 3 → 4. Complete and evaluate one repair before changing
the next variable. Baseline: [measured results](tailscale-adguard-nordvpn-results.md).

## 1. NordVPN: peer and home LAN reachability

Status: IMPLEMENTED AND VALIDATED for the tested IPv4 peer and Proxmox port
with the persistent transport service enabled on 2026-10-09. Earlier regression
and external-network experiments are preserved below as historical evidence.
Full guest/remote coverage belongs to repair 4. AdGuard stays OFF while isolating this problem.
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

Status: IMPLEMENTED AND VALIDATED for the tested DNS/filtering targets. See the
2026-10-09 final matrix below; authenticated/full guest coverage is still pending.

AdGuard's AGCLI NAT chain redirects UDP/TCP port 53 before its LAN exclusions.
Direct fresh queries to Tailscale's local Quad100 resolver timed out. Changing
bootstrap/fallback DNS and bypassing tailscaled did not help and were reverted.
Two destination-specific port-53 RETURN rules restored direct DNS; removing
those rules reproduced the failure. Cached application lookups are not rollback
proof. NordVPN also requires the individual Quad100 /32 in the private policy.

The root-owned `adguard-tailscale-dns.service` maintains only two tagged rules
at the start of AGCLI, rebuilding them when AdGuard recreates the chain and
removing them when Tailscale's interface disappears or the service stops.
It leaves other DNS destinations, filter settings and account configuration
unchanged. Rule reconciliation can take one second after startup/rebuild.

`scripts/setup-adguard-tailscale-dns.sh` installs protected copies under
`/etc/dotfiles` and enables the service once both CLIs exist. The orchestrator
copies these during its authenticated phase, then uses only the exact protected
installer command during provisioning. Never grant passwordless execution of
a script from a user-writable repository. Post-reboot/manual installation:

```bash
sudo -v
bash ~/dotfiles-sway/scripts/setup-tailscale.sh
bash ~/dotfiles-sway/scripts/setup-adguard-tailscale-dns.sh
```

Restore the private NordVPN policy from backup, including the Quad100 host
exception, before applying it while disconnected. Missing policy is not an
automatic broad VPN exclusion. `verify.sh` checks root ownership, deployed
file equality and enabled/active service; those checks do not prove traffic.

### Follow-up matrix, 2026-10-06

Fresh UDP and TCP Quad100 queries, uncached system queries, application DNS,
and public HTTPS passed in A (both OFF), B (AdGuard only), C (NordVPN only),
D (both ON), and restored A. A temporary random-domain DNS rewrite returned
0.0.0.0 only in B/D, proving AdGuard still intercepted/filtering other DNS.
The original filter file was restored byte-for-byte. AdGuard and NordVPN ended
OFF. OneDrive account metadata was also reachable in the repeated C probe;
file transfers were not tested.

An explicit stop, two-second wait, start cycle passed fresh DNS and filtering
again, exercising chain recreation. Native `adguard-cli restart` returned zero
but reported an unknown startup error and left the proxy OFF. Its cause is not
yet established; do not treat a zero exit code as successful restart. Use the
verified stop/wait/start sequence and check status while this remains open.

Peer TCP passed A/B/restored A but timed out C/D; a separate fresh C connection
also failed normal/diagnostic peer ping. The configured allowlist still passes
its policy check. Proxmox-port TCP initially failed even in A/B/restored A. Live route inspection
then revealed Fedora was on an external Wi-Fi network with accept-routes OFF.
The NAS router itself could reach Proxmox. Enabling the already approved subnet
route restored Proxmox-port TCP in A/B/restored A; C/D still failed both peer
and Proxmox TCP. This external-network matrix must not be confused with the
earlier successful local-home tests. These failures prevent
claiming completed NAS coexistence or proceeding with a trusted panel test.

Validation: six isolated DNS-helper tests passed, setup/orchestrator suites
passed, shell checks passed, and systemd unit validation passed. Full system verification: 194 passed, 0 failed, 0 pending, 1 warning; live traffic limitations above
remain regardless of configuration verification.

## 3. Proxmox: HTTPS identity and trust

Status: QUEUED. Presented certificate identity was inspected: its DNS SANs
include the intended PVE hostname, but its IP SAN contains an old LAN address
rather than the current address. Validity has not expired. A reachable port
is not a trusted/authenticated panel. The existing Fedora SSH key was rejected
by Proxmox; authenticated host access remains needed to obtain the intended
CA and reconcile the certificate/hostname safely. Do not automatically trust
a CA retrieved through an unverified HTTPS session.
Obtain the intended hostname and inspect its certificate chain.
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

### Reproducible subnet-route preference

`setup-tailscale.sh` reads the optional private file
`~/.config/dotfiles/tailscale-accept-routes`: exactly `true` or `false`.
Missing file preserves current settings; invalid content aborts. The current
installation uses `true`. Restore this mode-600 file alongside the NordVPN
policy from private backup before installing a replacement machine.
`verify.sh` compares it with the live RouteAll preference. Approval and access
policy remain in the Tailscale admin console; accepting routes does not select
an exit node or prove every guest service is accessible.

## Architecture alternatives

For browser-only Nord traffic, the official NordVPN extension is a browser
proxy. Keep the system NordVPN tunnel disconnected and exclude the intended
NAS/Proxmox addresses in the extension. Tailscale routes home services; other
applications use their normal Internet path. This does not provide NordVPN
protection for SSH, OneDrive or other non-browser applications.
References: [NordVPN extension](https://nordvpn.com/features/proxy-extension/),
[website exclusions](https://support.nordvpn.com/hc/en-us/articles/20321703651985-How-to-use-the-Exclude-from-VPN-Split-Tunneling-feature-on-the-NordVPN-extension).

For system-wide Nord traffic, Linux's documented allowlist selects subnets/ports,
not individual applications. Our external-network tests show the static address
exceptions alone are insufficient. A temporary output rule accepting Tailscale's
underlay packet mark alone did not help. Adding NordVPN's connection mark while
preserving Tailscale's packet mark restored peer and Proxmox TCP, with public
HTTPS still working and firewall/routing enabled. After removing the rule,
already established transport continued to work, so that result is not proof
of successful rollback for fresh transport. The experimental rule was removed;
The experimental rules were removed before the persistent service was activated
on 2026-10-09 with explicit user approval. A further controlled run
restarted tailscaled in each phase: baseline failed both targets; the rule
restored both; removing the rule and restarting tailscaled reproduced both
failures. Public HTTPS passed throughout. Simply reconnecting NordVPN was
insufficient to clear the already established Tailscale transport's connection
mark; do not confuse that with a successful rollback experiment.

The prepared `nordvpn-tailscale-transport.service` maintains one tagged rule in
NordVPN's output chain. It matches only the reserved Tailscale underlay mark,
preserves the packet mark, and sets the connection mark read from NordVPN's
own allow rule. It refuses an unknown vendor mark layout. It does not disable
the firewall, change VPN connection/account settings or add public address
exceptions. Like the DNS service, its runtime files live under root-owned
`/etc/dotfiles`; provisioning permits only the exact protected installer.
The service reconciles chain rebuilds once per second and removes only its own
rule when Tailscale disappears or it stops. Existing conntrack state can outlive
rule removal; stopping the service is not immediate revocation of established
transport. Automatic approval review initially rejected activation of the persistent
firewall change; the user explicitly approved it on 2026-10-09 and the protected
installer enabled the service. Four isolated tests
and systemd unit validation passed. End-to-end service validation passed as recorded below. NordVPN has not documented
this custom marking workaround as a supported integration.
Reference: [NordVPN Linux allowlist](https://support.nordvpn.com/hc/en-us/articles/19618692366865-What-is-Split-Tunneling-and-how-to-use-it-with-NordVPN).

## Final enabled-service matrix — 2026-10-09

Both protected compatibility services are enabled/active. Fedora was on its
home Wi-Fi during this run; the earlier external-network temporary-rule proof
is separate evidence. Do not claim this run revalidated an external network.

| Variant | Fresh Tailscale DNS UDP/TCP/system | Peer SSH-port TCP | Proxmox port TCP | Public HTTPS | AdGuard control filter |
|---|---|---|---|---|---|
| A: both OFF | PASS | PASS | PASS | PASS | Inactive |
| B: AdGuard only | PASS | PASS | PASS | PASS | PASS |
| B: stop/wait/start | PASS | PASS | PASS | PASS | PASS |
| C: NordVPN only | PASS | PASS | PASS | PASS | Inactive |
| D: both ON | PASS | PASS | PASS | PASS | PASS |
| Restored A | PASS | PASS | PASS | PASS | Inactive |

The temporary filter file was restored byte-for-byte. AdGuard ended OFF and
NordVPN disconnected; Tailscale and the two compatibility services remain ON.
Native AdGuard restart limitation remains documented above. Tests cover IPv4,
DNS, filtering and transport/ports, not authenticated panel/file transfers or
every VM/LXC. Proxmox HTTPS trust and full NAS inventory/access remain repairs
3 and 4. Private endpoints, policies and raw logs remain outside Git.

Full system verification: 196 passed, 0 failed, 0 pending, 1 warning. Setup and
orchestrator suites, helper tests, shell checks and systemd unit validation
passed. Automatic installation deploys protected helpers in authenticated P0,
enables services in P2, restores optional private route/allowlist preferences,
and checks deployed file equality, root ownership and service state.

A second fresh NordVPN connection passed diagnostic/ordinary peer ping, peer
and Proxmox TCP, MagicDNS and public HTTPS. Public egress differed from the
disconnected baseline. OneDrive account metadata reported connected; actual
file transfers were not tested. Proxmox TLS validation still failed as expected
for repair 3. Both VPN/firewall routing settings remain enabled.

## External phone-hotspot verification — 2026-10-09

The user moved Fedora to a phone hotspot and enabled AdGuard and NordVPN.
Checks confirmed the Wi-Fi IPv4 address was outside the home subnet. Both
compatibility services were active. No service was toggled, no filter/config
was changed, and the user's connected state was preserved.

- Home traffic selected tailscale0; the peer replied to diagnostic and ordinary
  ping, its SSH port accepted TCP, and the Proxmox panel port accepted TCP.
- The peer's MagicDNS name resolved and public HTTPS returned HTTP 200.
- Public Internet routing selected nordlynx. NordVPN's own IP-insights endpoint
  reported `protected: true`, United Kingdom / Manchester. The server's tunnel
  endpoint address differed from the public egress address; that difference
  alone is not evidence of a VPN failure.
- An explicit DNS query for the advertising test domain was blocked. AdGuard's
  current access log recorded the exact query as `blocked`, with a filter ID
  and matching rule. Its local HTTP proxy separately returned `500 Request
  Blocked` for the advertising URL, also with a matching blocking rule in the
  log. These are actual DNS/HTTP filtering checks, not merely process status.
- The usual DNS path initially returned 0.0.0.0 for NordVPN's diagnostic API.
  The single diagnostic HTTPS request used curl's DNS-over-HTTPS option to
  reach that endpoint with normal TLS verification; no persistent DNS setting
  changed. The source of that API-domain answer was not established.

Result: tested Tailscale/home access, NordVPN Internet egress and AdGuard
DNS/HTTP filtering work together outside home. Proxmox normal TLS validation
still failed; this does not validate a trusted/authenticated panel. Full live
VM/LXC inventory, application logins and file transfers remain pending.
Private addresses and raw logs remain outside the public repository.
