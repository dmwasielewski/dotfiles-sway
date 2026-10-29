# Selectable VM network modes

The laptop keeps four distinct libvirt networks, ordered by readable names:

| Name | Subnet | Host access | Public Internet |
|---|---|---|---|
| `01-Host-Internet` | `192.168.101.0/24` | Yes | Yes |
| `02-Host-NoInternet` | `192.168.102.0/24` | Yes | No |
| `03-Lab-NoHost-Internet` | `192.168.103.0/24` | DHCP/DNS only | Yes |
| `04-Lab-NoHost-NoInternet` | `192.168.104.0/24` | DHCP/DNS only | No |

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
101, 105, 106 and 107 to avoid conflicts, including nested validation guests.
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
then stops their QEMU processes. The boot service resumes guests recorded as running at shutdown
(`ON_BOOT=start`). VMs that were already shut off are not started by this policy.
The Sway personal Windows launcher reuses an already running guest.
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

For the separate 2026-10-16 Windows frozen-clock/black-display incident and its
Hyper-V timer correction, see [Windows saved-state troubleshooting](windows-vm-black-screen.md).
That correction passed one manual managed-save restore; full host reboot remains
unverified. Network policy and VM workspace routing were not changed by it.

## Subnet numbering (2026-10-16)

The four laptop subnets now use 101, 102, 103 and 104 to match menu prefixes 01–04. Bridge names remain virbr170–virbr173. Network UUIDs and VM network selections are preserved. DNS records, DHCP ranges/reservations and the NoHost firewall DNS exceptions use the new addresses. Backups and traffic-test reports are in the visible network bundle. This does not move any VM between network modes. Shut-off guests obtain their new addresses at the next boot; a saved running guest may need DHCP renewal.


### Host-wide restart and poweroff policy (2026-10-25)

The same system `libvirt-guests.service` stop action runs during ordinary
`reboot`, `systemctl reboot`, `systemctl poweroff`, desktop power-menu actions,
and the updater reboot. It targets persistent QEMU/KVM guests on
`qemu:///system`, not VirtualBox or session-scoped libvirt instances.
`ON_SHUTDOWN=suspend` means managed save to disk, not merely pausing RAM.
The installed unit has `TimeoutStopSec=0` (infinite), so normal system shutdown
waits for its save operation rather than terminating it on the default timer.
`ON_BOOT=start` restores the guests recorded by this service at shutdown.

This is not a guarantee that a failed managed save aborts system shutdown:
systemd can continue shutdown after a stop-action failure. Disk-full, unsupported
passthrough, forced reboot and power loss remain failure conditions. Do not
advertise the hook as a fail-closed reboot interlock. Verify free disk space and
review `journalctl -u libvirt-guests -b -1` after the first normal reboot.
No real reboot/poweroff or guest interruption was performed for this change.


### Reproduction on a fresh Fedora Sway Atomic installation

The automatic path is `orchestrate.sh` phase P2 → `scripts/setup-kvm.sh` →
`scripts/setup-vm-state.sh` → `/etc/sysconfig/libvirt-guests`. The installer
preserves the first pre-existing configuration as
`/etc/sysconfig/libvirt-guests.before-dotfiles`, installs the versioned policy,
and enables/starts the service without restarting it. Its shared state records
`KVM_GUEST_STATE_SAVE=done`. A failure propagates to P2 rather than silently
finishing installation. `scripts/verify.sh` checks service enablement, active
state and byte-for-byte policy agreement.

Verified on 2026-10-25 after interactive sudo: installed policy matched the
repository (`ON_BOOT=start`, `ON_SHUTDOWN=suspend`, `PERSISTENT_ONLY=true`),
service enabled/active, stop timeout infinite, installer step done. Personal
Windows remained running; other defined guests were shut off. No host reboot
was performed, so automatic boot-time restoration remains end-to-end untested.
