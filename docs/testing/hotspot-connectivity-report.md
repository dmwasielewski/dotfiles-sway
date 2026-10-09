# Phone hotspot: Tailscale, NordVPN, AdGuard and OneDrive

Measured on 2026-10-09, approximately 22:02–22:10 Europe/London. The user
connected Fedora through a phone hotspot with NordVPN and AdGuard enabled.
No VPN, DNS profile, firewall setting or existing user file was changed.
Only uniquely named 76-byte connectivity-test files were created for the
OneDrive transfer tests; their cleanup is recorded below.

## Results and evidence

| Check | Method | Result | What it establishes |
|---|---|---|---|
| External network | Compare Wi-Fi IPv4 with the home subnet | Outside home | Access does not rely on being on home Wi-Fi |
| Home route | `ip route get` for Proxmox | tailscale0, table 52 | Home traffic selects Tailscale |
| Peer reachability | Tailscale diagnostic ping and ordinary ICMP ping | PASS | Both transport and ordinary peer packets work |
| Peer service port | Open a TCP socket to the peer SSH port | PASS | TCP handshake succeeds; not an authenticated SSH login |
| Proxmox panel port | Open a TCP socket to port 8006 | PASS | The panel service is reachable |
| Proxmox TLS | Normal curl HTTPS request, without insecure flags | Certificate validation failed | Trusted/authenticated panel remains repair 3 |
| Tailscale name | Resolve actual peer FQDN through system resolver | PASS | MagicDNS is usable |
| Internet | HTTPS request to example.com | HTTP 200 | Public HTTPS remains usable |
| NordVPN route | `ip route get` for a public IPv4 | nordlynx, table 205 | Ordinary Internet traffic selects the VPN |
| NordVPN egress | NordVPN's public IP-insights endpoint | protected=true, GB/Manchester | Provider identifies the outgoing connection as protected |
| AdGuard DNS filtering | Explicit advertising-domain A query | REFUSED; log says blocked with filter ID/rule | Actual local DNS filtering, not merely an active process |
| AdGuard HTTP filtering | Advertising URL through local HTTP proxy | 500 Request Blocked; log records matching rule | Actual HTTP ad blocking |
| OneDrive mount | findmnt and availability indicator | fuse.onedriver mounted; account connected | Mount and authenticated Microsoft Graph account access work |
| OneDrive upload | Create own test file through the mounted folder; query Graph for its size | PASS | Data reaches the cloud through the actual Onedriver mount |
| OneDrive download | Download that cloud item through its signed HTTPS download URL; compare bytes | PASS | Cloud contains exactly the test payload; not a local-cache-only read |

NordVPN's API initially resolved to 0.0.0.0 through the current DNS path.
The single diagnostic request used curl's DNS-over-HTTPS option, with normal
TLS verification. This changed no persistent DNS setting. The source of that
API-domain DNS answer was not established. The VPN server's tunnel endpoint
and public egress addresses differed; those are different roles, so inequality
alone is not evidence of failure.

## Routes and ports: distinguish the application from its tunnel

A port identifies a service at an address. A tunnel wraps an application's
packets inside another connection. The application's port and the tunnel's
outer transport port can therefore be different.

| Traffic | Application protocol/port | Measured path / outer transport | Reason |
|---|---|---|---|
| Proxmox panel | HTTPS, TCP 8006 | tailscale0 → encrypted Tailscale → NAS subnet router → Proxmox | Accepted, approved home-subnet route |
| Peer SSH | TCP 22 | tailscale0 → encrypted Tailscale → peer | Peer IPv4 exception and preserved transport connection mark |
| Peer ping | ICMP; no TCP/UDP port | tailscale0 → Tailscale | ICMP is a separate network protocol |
| Tailscale transport in this check | Encapsulates the above packets | DERP London/lhr relay, TCP 443; bypasses NordVPN | Direct transport was not selected for the observed replies |
| Tailscale direct transport | UDP 41641 local listener observed | Available for direct attempts; not the measured data path here | Tailscale's direct WireGuard transport uses UDP |
| Ordinary HTTPS, including OneDrive | TCP 443 | nordlynx → encrypted NordLynx/UDP → NordVPN → website/Microsoft | Public Internet follows NordVPN routing |
| MagicDNS | UDP/TCP 53 to Quad100 | Local Tailscale resolver; exempt from AdGuard redirect | Tailnet names must remain with Tailscale's resolver |
| Ordinary DNS | Initially UDP/TCP 53 | AdGuard interception → configured NextDNS over HTTPS/TCP 443 | AdGuard checks its filters and forwards allowed queries to its upstream |
| Explicit local AdGuard HTTP proxy | TCP 3129 on localhost | Local filtering component; Internet-bound traffic still follows NordVPN | This is a local proxy, not a third remote VPN tunnel |
| Local SOCKS proxy | TCP 1081 on localhost | Listening; not used by the explicit HTTP ad-block test | Separate local proxy interface |

NordVPN was using NordLynx/UDP. The exact remote UDP tunnel port was not
measured in this report; no unobserved port number is asserted. The local
AdGuard automatic-interception/DNS listeners also use dynamic ports; the
stable client-facing proxy ports above were observed directly.

Tailscale's observed DERP relay uses TCP 443. UDP 41641 is its normal direct
peer transport listener. These are distinct from the inner SSH/Proxmox ports.
Reference: [Tailscale firewall ports](https://tailscale.com/docs/reference/faq/firewall-ports).
The cloud download used the signed URL returned by Graph, without sending the
Graph bearer token to the download host. Reference:
[Microsoft Graph download](https://learn.microsoft.com/en-us/graph/api/driveitem-get-content?view=graph-rest-1.0).

## Why the three products can coexist

Fedora accepts the home-subnet route advertised by its NAS Tailscale router.
The private NordVPN policy allows the intended LAN, individual peer and
Quad100 resolver. It does not exempt the whole Internet or the whole CGNAT
range. Account access policy/route approval remains in the Tailscale console.

The protected NordVPN compatibility service adds only one tagged output rule:
match Tailscale's reserved underlay packet mark, preserve that packet mark,
and set the connection mark accepted by NordVPN's own firewall. This allows
both directions of Tailscale transport without disabling NordVPN's firewall.
A route lookup with Tailscale's mark selected the phone Wi-Fi path; the same
public destination without the mark selected nordlynx. The rule is kept ahead
of vendor rules and restored when NordVPN recreates its chain.

The protected AdGuard compatibility service exempts only Quad100 UDP/TCP 53
from AdGuard's DNS redirection. Other DNS still goes through filtering, as
confirmed by the blocked advertising request. It restores its tagged rules
when AdGuard recreates its NAT chain. No broad firewall disable was used.

AdGuard's app configuration includes browsers, bypasses apps matching `*vpn*`,
and uses `bypass_https` for the remaining apps. Therefore this report does not
claim that OneDrive HTTPS content is decrypted/ad-filtered: its connection is
forwarded and its DNS can be filtered. HTTPS requests to Graph appear as TLS
traffic in the current AdGuard log. DNS and HTTP tests establish the scopes
actually checked, not every browser page or every HTTPS app.

## OneDrive cleanup and limits

The first immediate delete through the mounted folder returned locally, but
Graph still reported the own test item after 25 seconds. The item was safely
identified by its unique name and exact test contents, then removed with an
authenticated Graph DELETE (HTTP 204); its cloud path subsequently returned
not found. Only this test item was targeted. Upload and cloud-content read
had already passed; the deletion result must not be hidden behind a connected
status indicator.

A second test waited 15 seconds after the confirmed upload/content read before
unlinking through the mounted folder. Upload, byte-for-byte cloud download,
local deletion and cloud deletion all passed. No Graph cleanup was needed for
this second file. The difference suggests timing matters, but does not prove
the cause of the first failure. Both own test items were cleaned up.

This proves the tested small-file operation, not large transfers, every
account, all browser filtering, IPv6 or all NAS VM/LXC services. Full guest
inventory/application logins/file shares and Proxmox certificate trust remain
open. The user's VPN and AdGuard connections were preserved. Private endpoint
addresses, tokens, signed URLs and raw logs are outside the public repository.

## Subsequent Proxmox HTTPS repair

After the measurements above, authenticated CA verification and the correct
DNS identity resolved the Proxmox TLS error. Normal hostname HTTPS returned
HTTP 200 with TLS verification result 0 while both programs stayed ON.
See [Proxmox client trust setup and validation](proxmox-https.md).
