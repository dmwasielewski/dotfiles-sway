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
