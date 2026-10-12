# Selectable VM network modes

The laptop keeps four distinct libvirt networks, ordered by readable names:

| Name | Subnet | Host access | Public Internet |
|---|---|---|---|
| `01-Host-Internet` | `192.168.170.0/24` | Yes | Yes |
| `02-Host-NoInternet` | `192.168.171.0/24` | Yes | No |
| `03-Lab-NoHost-Internet` | `192.168.172.0/24` | DHCP/DNS only | Yes |
| `04-Lab-NoHost-NoInternet` | `192.168.173.0/24` | DHCP/DNS only | No |

Bridges remain `virbr170` through `virbr173`. All modes provide DHCP and local
DNS, with `.1` as gateway/DNS, pool `.100`–`.200`, and the local domain `lab.test`.
The laptop reserves `.10` for Kali and `.20` for Windows cyber by NIC MAC.
These are DHCP reservations, not guest static IP configuration. Offline DNS
resolves local names only. Same-network guests can communicate, subject to their
firewalls. Names do not enforce policy; the libvirt XML and nftables rules do.
Modes 02 and 03 restrict different destinations, rather than forming a strict
security hierarchy. NoHost does not disable clipboard or other guest integration.

## Installation and restore

`setup-kvm.sh` reuses/creates `01-Host-Internet`; it no longer creates the redundant
`dotfiles-nat` network. On a fresh system it selects the first free /24 from
170, 174, 175 and 176 to avoid conflicts, including nested validation guests.
The VM validation script uses that network by default. The other three modes
and their firewall are restored from the laptop's visible configuration bundle:
`~/Downloads/Laboratorium-cyber/sieci-do-przelaczania`.
The bundle's root-run installer installs the firewall before starting networks
and refuses to overwrite existing names. Do not copy laptop MAC reservations
blindly to a different machine. Package-provided `default` may exist on a fresh
system; it was removed on this laptop only after checking no VM used it.

On 2026-10-11, four networks were renamed, all five shut-off VM definitions were
updated, and unused `default`, `dotfiles-nat`, `cyber-lab` networks were removed.
Backup XML is in `backup-before-network-renaming-*` in the visible bundle.
The same subnet, bridge, DNS, DHCP and firewall settings were preserved.
`vm-network-modes.service` remains enabled/active. Legacy virbr77 firewall rules
are inert because the old bridge no longer exists. Host restart and guest traffic
were not retested for this naming-only migration.

## Using virt-manager

Shut down the VM, open hardware details, select its NIC, choose **Network source**,
and apply. Start the guest with automatic IPv4/DNS enabled. To connect Kali and
Windows for an exercise, select the same network on both. Pause does not shut down
the guest. `virsh --connect qemu:///system net-list --all` lists current modes.

## Host shutdown and managed guest save

`setup-kvm.sh` runs `setup-vm-state.sh` to install `libvirt/libvirt-guests` under
`/etc/sysconfig` and enable/start `libvirt-guests.service`. On host shutdown,
libvirt saves running persistent guests' RAM and device state with managedsave,
then stops their QEMU processes. Saved guests are not automatically resumed by
the boot service (`ON_BOOT=ignore`). The Sway personal Windows launcher invokes
`virsh start`, which restores its managed state. Other guests resume on demand.
`SYNC_TIME=1` asks guest agents to synchronize guest time when service-based
restoration is used; the personal launcher uses normal libvirt start.

This is different from Pause: a managed save persists RAM on disk under
`/var/lib/libvirt/qemu/save`. Allow space roughly proportional to active guest
RAM. Leave save files intact. Closing a viewer does not stop a guest. Normal
host shutdown must finish; cutting power or holding the power button cannot be
protected by this service. This is not a backup or a snapshot rollback point.
Do not restart/stop libvirt-guests as a harmless configuration reload: its stop
action saves running guests. The installer uses enable --now without restart.
Installer steps record shared state/log output; verification checks the policy
and service. No host reboot is required to enable the shutdown hook.

Validated on 2026-10-12: service enabled/active, policy matches the repository,
and manual managedsave stopped win11edu-damian with a retained save image.
Normal virsh start restored that state, and the Windows guest agent responded.
The VM was left running. Full verification: 201 passed, 0 failed, 1 warning.
An actual host shutdown/reboot was not performed during this validation.
