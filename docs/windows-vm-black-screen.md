# Windows black screen after saved-state restore

## Incident and evidence (2026-10-16)

`win11edu-damian` resumed after a Fedora restart with a black display in its
virt-manager console on workspace 6. This incident is separate from the earlier
SPICE handoff between virt-viewer and virt-manager. The current launcher uses
virt-manager for the personal console and reuses its per-domain window.

Observed before recovery:

- libvirt reported `running (restored)`; SPICE had an active display channel.
- QEMU's own screenshot was entirely black, so the problem was present before
  the image reached the viewer. Reopening a window alone was not a sufficient fix.
- Repeated Guest Agent queries returned exactly the same Windows time,
  `18:11:29`, while some commands and processes still responded.
- Shift, Ctrl+Alt+Delete and Win+Ctrl+Shift+B did not restore the display.
- Normal shutdown through Guest Agent and ACPI did not complete.
- Windows VBS (Virtualization-Based Security) was running: Device Guard status 2,
  with security services 1 and 2. This uses a nested Hyper-V hypervisor inside KVM.
- The domain enabled the Hyper-V synthetic timer (`stimer`) without direct mode.

The strongest hypothesis is a synthetic-timer/nested-Hyper-V incompatibility
when restoring saved state. QEMU documents that nested Hyper-V needs
[`hv-stimer-direct`](https://www.qemu.org/docs/master/system/i386/hyperv.html).
No failure memory dump or controlled comparison with the old timer setting was
captured. Therefore the exact blocked thread and the causal link are not proven.
The changed configuration passed the tested recovery and restore sequence.

## Applied correction

The only persistent VM configuration change was:

```xml
<features>
  <!-- Other existing features remain in place. -->
  <hyperv mode='custom'>
    <!-- Other existing Hyper-V settings remain in place. -->
    <stimer state='on'>
      <direct state='on'/>
    </stimer>
  </hyperv>
</features>
```

This is an excerpt to merge into the existing domain XML, not a replacement
for its entire features section. Preserve identity, CPU topology, RAM, disks,
network, firmware, TPM, security settings and workspace routing.

Before changing a future guest, save its inactive XML in a visible Downloads
folder. Shut Windows down fully, ensure that no managed-save state from the old
virtual hardware is pending, edit through `virsh --connect qemu:///system edit
VM_NAME`, and start the guest normally. A guest reboot alone does not recreate
QEMU with changed virtual CPU features. Do not silently discard a managed save:
it can contain unsaved work. Obtain approval before interrupting the user's work
or force-stopping an unresponsive guest.

For this incident, the user approved the change and restart. Normal shutdown
failed; the stuck VM was then force-stopped and cold-started. That recovery step
is not an instruction to make forced shutdown the normal workflow.

## What was verified

- The proposed XML passed `virt-xml-validate` before application.
- Cold boot reached the Windows login screen and desktop.
- A subsequent `virsh managedsave` followed by `virsh start`, both through
  `qemu:///system`, restored the desktop successfully.
- Guest time advanced after restore, rather than remaining frozen.
- The actual virt-manager window displayed the desktop on workspace 6.
- Inactive domain XML retained `stimer/direct state='on'`.

One manual save/restore cycle passed. A complete Fedora shutdown/reboot with
this correction has **not yet been tested**. Check that on the next planned
host restart; a visible window or a successful agent ping alone is insufficient.

## Read-only diagnosis if it returns

First record whether the guest was started cold or restored. Compare the actual
viewer image with a QEMU screenshot, and sample guest time more than once:

```bash
virsh --connect qemu:///system domstate win11edu-damian --reason
virsh --connect qemu:///system qemu-monitor-command win11edu-damian '{"execute":"query-spice"}'
virsh --connect qemu:///system screenshot win11edu-damian /tmp/win11edu-damian-screen.png
virsh --connect qemu:///system qemu-agent-command win11edu-damian '{"execute":"guest-get-time"}'
# Repeat after several seconds and compare the values.
virsh --connect qemu:///system qemu-agent-command win11edu-damian '{"execute":"guest-get-time"}'
virsh --connect qemu:///system dumpxml --inactive win11edu-damian
journalctl -u libvirtd -u libvirt-guests --since '-30 minutes'
journalctl -k --since '-30 minutes'
```

Do not publish screenshots or raw guest logs without reviewing personal data.
Inside Windows, inspect System and Application events and the current video
controller status. Query VBS with PowerShell:

```powershell
Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard |
    Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning
Get-CimInstance Win32_VideoController |
    Select-Object Name, Status, ConfigManagerErrorCode, DriverVersion
```

Event interpretation from this investigation:

- QXL reported OK with device error code 0 after recovery; the sampled recent
  System warnings/errors contained no Display 4101 or bugcheck 1001. That does
  not prove graphics never stalled during the original incident.
- Kernel-Power 41 and EventLog 6008 followed the forced stop. They record the
  unclean shutdown; they do not identify the original cause.
- An earlier disk I/O retry (153) was recorded, without a demonstrated link to
  this freeze. Do not treat it alone as proof of physical disk failure.
- Windows Time was Manual and stopped. This prevented the attempted Guest Agent
  time synchronization, but does not by itself explain a frozen system clock.
  Its service policy was not changed.

## Prevention and scope

Keep direct mode enabled when this synthetic timer is used by a nested Hyper-V
Windows guest. Check VBS/Hyper-V state when preparing or restoring future
Windows templates, and validate both cold boot and managed-save restoration.
Keep the single virt-manager console workflow for workspace 6. Continue normal
host shutdown with the existing managed-save service and allow it to finish.
Do not modify the guest automatically from the login launcher or hide repeated
failures with a forced-restart loop.

The audit found `stimer` enabled without direct mode in `win10edu`,
`win10edu-cyber`, `win11edu` and `win11edu-cyber`. Those guests were not changed
or started for this investigation. Their current VBS state and susceptibility
were not verified; do not describe them as already fixed or definitely broken.

Private evidence, original/proposed/applied domain XML and rollback notes are
in `~/Downloads/Instalatory/Windows-VM/Win11edu-Damian-Black-Screen/`.
Keep those machine-specific files outside public Git. To roll back, fully stop
the guest and use its original domain XML with `virsh --connect qemu:///system
define`; avoid applying XML incompatible with a pending saved state.
