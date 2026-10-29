# Home network application policy

The opt-in user service `home-network.service` pauses AdGuard, NordVPN and
Tailscale on arrival at home. It records their previous enabled/connected state
and restores only previously enabled apps when a non-home physical connection
becomes active. It never logs out, resets vendor preferences, edits DNS servers,
changes firewall rules, or stops the vendor daemons. Existing DNS/transport
compatibility services remain installed and reconcile their own rules.

## Detection and manual overrides

Private configuration: `~/.config/dotfiles/home-network.json` (mode 600).
Wi-Fi is matched by actual SSID and NetworkManager key-management setting,
not by profile name, laptop hardware address or old connection UUID. The same
secured Wi-Fi therefore matches on a fresh laptop once its connection is set up.
SSID/security is a convenience selector, not proof of network identity.
No Wi-Fi password is exported by this feature.

```json
{
  "wifi": [{"ssid": "YOUR-HOME-WIFI", "security": "sae"}],
  "ethernet_uuids": []
}
```

Enroll while connected to home Wi-Fi (never run enrollment on public Wi-Fi):

```bash
python3 ~/dotfiles-sway/scripts/home-network.py enroll-wifi
bash ~/dotfiles-sway/scripts/setup-home-network.sh
```

Ethernet profiles are opt-in through `ethernet_uuids`. Do not automatically trust
all wired connections. Their UUID is local: re-enroll a new laptop's wired
profile or deliberately restore its NetworkManager profile from private backup.
An empty list means home detection currently covers Wi-Fi only. If Wi-Fi and
Ethernet are both active, any configured home connection selects home mode.

The service reads active NetworkManager connections every five seconds. Three
consecutive readings select a transition (about 10–15 seconds). Disconnected,
virtual bridge and VPN-only states do not count as leaving home; suspend and
brief reconnects therefore preserve overrides. Switching between home APs does
not retrigger the rule. While staying home, manually starting any app is allowed
and does not trigger another automatic stop. Restarting the monitor during the
same boot also preserves overrides; rebooting at home applies home mode again.

On departure only the saved enabled apps are started. Apps that were off remain
untouched, including any app manually enabled while home. If all three were off
before arrival, departure does not turn them on. This is not an always-on VPN or
a guarantee of protection before an outside network starts carrying traffic.

## Automatic installation and private USB backup

`setup.sh` installs/enables the opt-in unit without starting it before packages
are ready. Orchestrator P2 starts it after Tailscale, NordVPN and compatibility
setup. Without private policy, installation is a no-op. Account sign-in and
AdGuard activation remain separate prerequisites.

The encrypted USB vault must contain `config/dotfiles/home-network.json`.
P0 restores this validated file before dependent setup, preserving mode 600 and
rejecting conflicting files. Never commit personal policy or Wi-Fi credentials.
Changing laptop UUID does not break the Wi-Fi rule. The new laptop must still
be connected to Wi-Fi; this feature does not provision Wi-Fi passwords.

To save the current rule, plug in the vault USB and use a host terminal:

```bash
cd ~/dotfiles-sway
bash scripts/vault/vault unlock
source scripts/vault/lib-vault.sh
vault_is_unlocked && install -Dm600 \
  ~/.config/dotfiles/home-network.json \
  "$VAULT_MOUNT/config/dotfiles/home-network.json"
cmp ~/.config/dotfiles/home-network.json "$VAULT_MOUNT/config/dotfiles/home-network.json"
bash scripts/vault/vault lock
```

Do not write into the vault path unless it is actually mounted. Code integration
alone does not mean the currently unplugged USB has been updated. Refresh any
separate encrypted vault backup after changing its contents. Application restore
state in `~/.local/state/dotfiles/home-network.json` is machine-specific and must
not be copied to a new laptop.

## Checks, recovery and removal

```bash
python3 ~/dotfiles-sway/scripts/home-network.py status
journalctl --user -u home-network.service -n 40
bash ~/dotfiles-sway/scripts/verify.sh --profile phase1
```

Commands have timeouts, state is saved atomically, and simultaneous monitor runs
are locked out. Unknown app status cancels the transition before changes. A
failed change attempts to restore the previous state and stops the monitor for
inspection. An interrupted transaction retains a recovery marker: the next
explicit restart restores its snapshot and stops; inspect before restarting
again. Failed recovery retains the marker. There is no endless enforcement loop.
Transient NetworkManager read failures do not change apps and are retried.

To pause automation without changing app states:

```bash
systemctl --user disable --now home-network.service
```

To resume after resolving an error:

```bash
systemctl --user restart home-network.service
```

Live checks on 2026-10-15: home Wi-Fi detected; app states initially off; manual
AdGuard and Tailscale enables survived the monitor; a separate live arrival
transition stopped both; both restored off after tests;
NAS HTTPS returned 200 and local DNS/routing used Wi-Fi. NordVPN connection and
physical departure to another network have not been tested live. Automated tests
cover all three apps, home/away/offline transitions, retained manual overrides,
reboot behavior, rollback, and portable private-policy restoration.
