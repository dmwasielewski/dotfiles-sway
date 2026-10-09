# Jellyfin playback: external-network diagnostics — 2026-10-09

The user tried Jellyfin in Firefox on Fedora while connected through the phone
hotspot, with NordVPN and AdGuard enabled. The selected movie did not start
and remained loading. Endpoints, movie IDs and account data are excluded here.
No configuration, firewall rule, playback setting or service state was changed.

## Observations

| Check | Result |
|---|---|
| Route to the Jellyfin LAN address | `tailscale0`, table 52 |
| Tailscale gateway transport | DERP relay in London; four diagnostic pings 84–97 ms; no direct connection established |
| Ordinary gateway ICMP | 9/10 replies; mean 704 ms, range 528–840 ms |
| Jellyfin host ICMP | 5/6 replies; mean 885 ms, range 621–1125 ms |
| Public server info and web index | HTTP 200; approximately 6 seconds per request in the initial sample |
| Public playback bitrate endpoint without credentials | HTTP 401; not a media-playback failure |
| Public 520,778-byte frontend file, sample 1 | 12.573 s; 0.331 Mb/s including request startup |
| Same frontend file, sample 2 | 11.482 s; 0.363 Mb/s including request startup |
| Same frontend file, sample 3 | 10.826 s; 0.385 Mb/s including request startup |
| Different 741,608-byte frontend file | 17.137 s; 0.346 Mb/s including request startup |

The file tests downloaded only public frontend JavaScript into memory, without
media access, authentication or playback. No local film copy was created.
These are end-to-end HTTP averages for a small application file, not a sustained
large-stream benchmark or measurement of either ISP's maximum line speed.
Packet-loss percentages come from very small samples and are preliminary.

`tailscale netcheck` reported UDP false and no IPv4 mapping in this combined
configuration. This does not establish whether the restriction is caused by
NordVPN, its firewall, the hotspot/carrier, the home network or another layer.
A public-Internet comparison download failed with HTTP error; it provides no
usable Internet-speed measurement and is not evidence of a DNS/filter cause.

## Assessment and next diagnosis

The measured home-service path is slow and has variable latency. It can explain
long loading and insufficient streaming throughput, but does not prove the
underlying Internet subscription is slow or that networking is the only issue.
DERP is generally slower than direct transport, but its presence alone is not
proof that it caused this particular throughput result.
See [Tailscale connection types](https://tailscale.com/docs/reference/connection-types).

Next compare the same file under a controlled change of one variable, retaining
and restoring initial service state. Diagnose direct UDP connectivity separately
on both ends before changing routers or persistent firewall rules. Obtain a
sustained transfer test when authenticated access is available. Compare the
result with the affected stream's actual bitrate, and inspect the active
Jellyfin playback/transcoding details and ffmpeg logs to distinguish network
starvation from codec, transcoding or server-storage failure.
See [Jellyfin transcoding](https://jellyfin.org/docs/general/post-install/transcoding/)
and [playback troubleshooting](https://jellyfin.org/docs/general/administration/troubleshooting.html/).

No new remedy is added to the installer on the basis of these measurements.
The existing Tailscale/NordVPN/AdGuard compatibility configuration is retained.

## User-disconnected NordVPN comparison — 23:14–23:15 BST

The user disconnected NordVPN; diagnostics confirmed `Disconnected`. AdGuard
remained running with automatic filtering enabled. No service was toggled by
the diagnostic process. The same public 520,778-byte file and request options
were used, with three successful HTTP 200 samples:

| Sample | Seconds | End-to-end Mb/s |
|---|---|---|
| 1 | 2.821 | 1.477 |
| 2 | 2.659 | 1.567 |
| 3 | 2.646 | 1.575 |

Jellyfin ICMP received 8/8 replies, mean 80.181 ms (59.291–124.667 ms).
Compared with the earlier run, frontend delivery was approximately four times
faster and host latency substantially lower. This sequential comparison is
evidence of improvement after disconnecting NordVPN, not proof of the precise
packet/filter bottleneck; hotspot load and time changed between runs.

Tailscale still used London DERP: three diagnostic pings returned 61, 108 and
69 ms, and no direct connection was established. `netcheck` still reported
UDP false and no IPv4 mapping. Therefore NordVPN is not established as the
sole cause of relay use. Public Internet routing now selected the hotspot
interface; Jellyfin still selected `tailscale0` table 52. The exact underlay
route of earlier existing relay sockets was not proven by a mark-only lookup.

Tailscale also reported a coordination-server network-map delay (2m6s) and
marked the local device offline, while the tested data path still worked.
This control-plane health warning requires a separate follow-up if persistent.
The comparison did not authenticate to Jellyfin or establish film playback,
actual stream bitrate, sustained capacity or transcoding state. NordVPN remains
in the user's disconnected state. No performance remedy was automated.
