# Host hardware

Measured on 2026-10-29 from the running system (no values copied from spec
sheets). Re-measure with the commands at the bottom before relying on a number.

## Machine

| Item | Value |
|---|---|
| Model | ASUS Vivobook 15X OLED, **M1503QA** (AMD Ryzen 5000 series) |
| Board | ASUSTeK M1503QA |
| CPU | AMD Ryzen 5 5600H with Radeon Graphics — 6 cores / 12 threads, AMD-V (KVM) |
| GPU | AMD Radeon Vega (Cezanne, integrated) `1002:1638` — VA-API via mesa/amdgpu, no extra driver |
| RAM | 40 442 044 kB reported (≈ 38.6 GiB usable) + 8 GiB zram swap |
| Storage | WD_BLACK SN850X 2000 GB NVMe (1.8 TiB) |
| Display | internal eDP-1, 1920×1080 @ 60 Hz (highest mode the panel reports) |
| Wi-Fi | Intel Wi-Fi 6E AX210 `8086:2725` (Typhoon Peak) |
| Bluetooth | `hci0` present |
| Audio | AMD Ryzen HD Audio + Audio Coprocessor; HDMI/DP audio |
| Webcam | USB2.0 HD UVC WebCam |

## Firmware

| Item | Value |
|---|---|
| BIOS | American Megatrends **M1503QA.312**, build date 2025-05-07 |
| Latest on ASUS support | **312**, released 2025-06-24 ("AMD security update") — **up to date** as of 2026-10-29 |
| SSD firmware | 620361WD |
| UEFI dbx | 20250902 |

**BIOS updates are not delivered through fwupd for this model.** `fwupdmgr
get-updates` shows nothing because ASUS does not publish M1503QA system firmware
on LVFS; "no updates" there says nothing about the BIOS. The source of truth is
the ASUS support page:
<https://www.asus.com/me-en/supportonly/m1503qa/helpdesk_bios/>.
On Fedora, update with the **EZ Flash** package (not the Windows installer): copy
it to a FAT32 USB stick and run EZ Flash from the BIOS setup, on AC power.
fwupd does handle the SN850X SSD and the Secure Boot certificates/dbx.

## Battery

| Item | Value |
|---|---|
| Design capacity | 70.0 Wh |
| Current full charge | 37.0 Wh — **≈ 53 % of design** |
| Cycle count | 117 |

The battery holds about half its original charge. Worth re-measuring now and
then; replacement is a hardware decision, not something this repo automates.

Why it wore so fast at only 117 cycles: the laptop runs on AC almost all the
time and the charge limit is **100 %** (`charge_control_end_threshold = 100`);
upower's history since 2026-10-22 is 100 % "fully-charged" in every entry.
Lithium cells age fastest held full and warm. The firmware reports only
`ASUS Battery` / `ASUSTeK`, no part number or serial.

**Charge limit:** click the Waybar battery icon to switch between 80 % (battery
care, default) and 100 % (full charge before a day away from the charger) — see
README *Battery charge limit*. Installed by `scripts/setup-battery-charge-limit.sh`.
Decision 2026-10-29 (Damian): the current battery will be replaced anyway; the
80 % default protects the replacement from ageing the same way.

What happens above the limit on AC depends on the firmware's state, measured
2026-10-29 with the limit at 80 %:
- Battery at 100 %, charger never unplugged after setting the limit:
  `energy_now` stayed at 37 018 000 µWh for a full minute (`Not charging`, brief
  `Discharging` blips < 1 W moved nothing).
- After unplugging (down to 94 %) and plugging back in: `status=Discharging` at
  ~8–9 W **with AC online** — the firmware ran the laptop from the battery,
  94→92 % within minutes, to bring it down to the 80 % limit; then the charger
  takes over.

So do not promise either behaviour; the tooltip shows which is happening
("running on battery down to the 80% limit"). This ASUS exposes no
`charge_behaviour` (no software-controlled force-discharge) — only
`charge_control_end_threshold`.

ASUS's MyASUS FAQ 1032726 says above the limit on AC the battery "may simply
maintain its current charge level rather than actively discharging" — "may":
the measurement above shows this unit sometimes does discharge. Also **the firmware resets the limit to 100 % at every
start-up** (boot, restart, BIOS setup) until the OS re-applies it. Here that
re-apply is the `status` self-heal run by Waybar right after login, so between
power-on and login the battery may charge past 80 %, exactly as on Windows.
<https://www.asus.com/support/faq/1032726/>

**Replacement part** (per sellers, not ASUS — read the label under the bottom
cover before ordering): **C31N2105**, alt. part 0B200-04140000, 70 Wh, 11.61 V,
3-cell. **C31N2105-1 is a different part** (different screw holes) — not
interchangeable. UK prices seen 2026-10-29: compatible replacements about
£51–55; a genuine ASUS 0B200-04140000 from an ASUS reseller about €149, but that
listing is the -1 variant. Replace immediately if the battery swells (raised
touchpad or bulging bottom cover).

## How to re-measure

```bash
cat /sys/class/dmi/id/{sys_vendor,product_name,board_name,bios_version,bios_date}
grep -m1 'model name' /proc/cpuinfo; nproc; grep MemTotal /proc/meminfo
lsblk -d -o NAME,MODEL,SIZE,TRAN
lspci -nn | grep -iE 'vga|network|audio'
cat /sys/class/power_supply/BAT0/{energy_full_design,energy_full,cycle_count}
fwupdmgr get-devices          # firmware versions fwupd can see
fwupdmgr get-updates          # updates fwupd can install (never the ASUS BIOS)
```
