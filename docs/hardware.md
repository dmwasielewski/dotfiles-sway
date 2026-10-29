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
