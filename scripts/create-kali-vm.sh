#!/usr/bin/env bash
# Create the Kali Linux lab VM.
#
# The guest lands on the same libvirt network as the other guests, because the
# point of this machine is to be a *separate host* that can reach the Windows
# guest — a container shares the host's network identity and cannot play that
# part. The install itself is interactive: this is a machine to live in, not an
# orchestrator run to validate unattended, so there is no preseed to maintain.
set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
info()  { echo -e "${BLUE}==>${NC} $*"; }
ok()    { echo -e "${GREEN}  ✓${NC} $*"; }
warn()  { echo -e "${YELLOW}  !${NC} $*" >&2; }
die()   { echo -e "${RED}  ✗${NC} $*" >&2; exit 1; }

VIRSH=(virsh --connect qemu:///system)

VM_NAME="${VM_NAME:-kali}"
VM_CPUS="${VM_CPUS:-2}"
VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_DISK_GB="${VM_DISK_GB:-40}"
ISO_SEARCH_DIR="${ISO_SEARCH_DIR:-$HOME/Downloads}"
ISO_GLOB="${ISO_GLOB:-kali-linux-*-installer-amd64.iso}"

# A network install can run for an hour; the host suspending mid-way killed an
# earlier run after it had been going for 17 hours. Hold sleep off for the
# duration, the same way the Fedora guest script does.
if [[ -z "${VM_INHIBITED:-}" ]] && command -v systemd-inhibit >/dev/null 2>&1; then
    export VM_INHIBITED=1
    exec systemd-inhibit --what=sleep:idle --mode=block \
         --who="create-kali-vm" --why="Kali guest install in progress" \
         "$0" "$@"
fi

# ---------------------------------------------------------------- discovery --

# The network to attach to is not a constant: it is wherever the guests this
# machine is supposed to reach already live. Pick the network used by most
# defined domains, so the lab stays on one segment even if that segment is
# renamed or replaced.
discover_network() {
    local d nets count
    nets="$(for d in $("${VIRSH[@]}" list --all --name 2>/dev/null); do
                [[ -n "$d" ]] || continue
                "${VIRSH[@]}" domiflist "$d" 2>/dev/null |
                    awk 'NR>2 && $2=="network" && $3!="" {print $3}'
            done | sort -u)"
    count="$(grep -c . <<< "$nets" || true)"
    # One network among the existing guests is an answer. Several is not: which
    # segment this guest belongs on decides whether it can reach the machine it
    # is meant to reach, and that is not something to settle by a tie-break.
    if [[ "$count" == "1" ]]; then printf '%s' "$nets"; return 0; fi
    return 1
}

# Which guest sits on which network — printed when the choice has to be made.
network_map() {
    local d
    for d in $("${VIRSH[@]}" list --all --name 2>/dev/null); do
        [[ -n "$d" ]] || continue
        "${VIRSH[@]}" domiflist "$d" 2>/dev/null |
            awk -v D="$d" 'NR>2 && $2=="network" && $3!="" {printf "      %-22s %s\n", D, $3}'
    done
}

# Where a pool actually stores its files, read at run time.
pool_path() {
    "${VIRSH[@]}" pool-dumpxml "$1" 2>/dev/null |
        sed -n 's|.*<path>\(.*\)</path>.*|\1|p' | head -1
}

# The guest's disk goes wherever the existing guests' disks go; the ISO goes to
# a pool meant for boot media if one exists, otherwise alongside the disk.
discover_disk_pool() {
    local p
    local p vols
    for p in $("${VIRSH[@]}" pool-list --name 2>/dev/null); do
        [[ -n "$p" ]] || continue
        # Collect first, then match: `grep -q` in a pipeline exits early, the
        # upstream process dies of SIGPIPE, and pipefail reports the whole
        # pipeline as failed even though the match succeeded.
        vols="$("${VIRSH[@]}" vol-list "$p" 2>/dev/null || true)"
        case "$vols" in *.qcow2*) printf '%s' "$p"; return 0 ;; esac
    done
    return 1
}

discover_iso_pool() {
    local p path
    for p in $("${VIRSH[@]}" pool-list --name 2>/dev/null); do
        [[ -n "$p" ]] || continue
        path="$(pool_path "$p")"
        [[ "$path" == */boot ]] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

# Newest installer image in the search directory, by version order rather than
# by a name written down here.
discover_iso() {
    local f
    f="$(find "$ISO_SEARCH_DIR" -maxdepth 1 -type f -name "$ISO_GLOB" 2>/dev/null |
             sort -V | tail -1)"
    [[ -n "$f" ]] && { printf '%s' "$f"; return 0; }
    return 1
}

# osinfo has no Kali entry — Kali rolling tracks Debian testing. Pick from what
# is actually installed instead of naming a variant that may not exist.
discover_os_variant() {
    local v list
    command -v osinfo-query >/dev/null 2>&1 || return 1
    # One read, then match against it — see the note in discover_disk_pool about
    # `grep -q` inside a pipeline under pipefail.
    list="$(osinfo-query os -f short-id 2>/dev/null | tr -d ' ' || true)"
    for v in debiantesting debianunstable; do
        if grep -qx "$v" <<< "$list"; then printf '%s' "$v"; return 0; fi
    done
    # Fall back to the highest numbered Debian this host knows about.
    v="$(grep -E '^debian[0-9]+$' <<< "$list" | sort -V | tail -1 || true)"
    [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
    return 1
}

verify_iso() {                       # $1 = iso path
    local iso="$1" dir base sums
    dir="$(dirname "$iso")"; base="$(basename "$iso")"
    sums="$(find "$dir" -maxdepth 1 -type f -name 'SHA256SUMS*' 2>/dev/null | head -1)"
    if [[ -z "$sums" ]]; then
        warn "no SHA256SUMS file beside the image — cannot verify $base"
        return 0
    fi
    grep -q " $base\$" "$sums" || { warn "$base is not listed in $(basename "$sums")"; return 0; }
    info "Verifying $base against $(basename "$sums")"
    ( cd "$dir" && grep " $base\$" "$sums" | sha256sum -c - >/dev/null ) \
        || die "checksum mismatch for $base — do not install from this image"
    ok "checksum matches"
}

# ------------------------------------------------------------------- checks --

command -v virt-install >/dev/null 2>&1 || die "virt-install is not available"
"${VIRSH[@]}" version >/dev/null 2>&1 || die "cannot reach libvirt at qemu:///system"

ISO="$(discover_iso)" || die "no image matching '$ISO_GLOB' in $ISO_SEARCH_DIR
    Download one from https://cdimage.kali.org/current/ first."
ok "image: $ISO ($(du -h "$ISO" | cut -f1))"
verify_iso "$ISO"

if [[ -n "${VM_NETWORK:-}" ]]; then
    NETWORK="$VM_NETWORK"
else
    NETWORK="$(discover_network)" || die "the existing guests are not on one network, so this one cannot be placed automatically.
    This guest has to share a network with whatever it is meant to reach.
$(network_map)
    Re-run with the network named, e.g.  VM_NETWORK=<name> $0"
fi
DISK_POOL="${VM_POOL:-$(discover_disk_pool)}" || die "could not find a storage pool holding guest disks; set VM_POOL"
ISO_POOL="${VM_ISO_POOL:-$(discover_iso_pool || printf '%s' "$DISK_POOL")}"
OS_VARIANT="${VM_OS_VARIANT:-$(discover_os_variant)}" || die "could not determine an --os-variant; set VM_OS_VARIANT"

DISK_VOL="$VM_NAME.qcow2"
ISO_VOL="$(basename "$ISO")"

info "Plan"
printf '    %-14s %s\n' name "$VM_NAME" cpus "$VM_CPUS" "ram (MiB)" "$VM_RAM_MB" \
       "disk (GiB)" "$VM_DISK_GB" network "$NETWORK" "disk pool" "$DISK_POOL" \
       "iso pool" "$ISO_POOL" os-variant "$OS_VARIANT"
echo "    network $NETWORK is where $(for d in $("${VIRSH[@]}" list --all --name 2>/dev/null); do
        [[ -n "$d" ]] && "${VIRSH[@]}" domiflist "$d" 2>/dev/null |
            awk -v D="$d" 'NR>2 && $3=="'"$NETWORK"'" {print D}'; done | paste -sd', ' -) already live"

# An existing domain is not overwritten silently: that is how 139 GiB of
# orphaned disks accumulated here once. Recreating removes the disk too.
if "${VIRSH[@]}" dominfo "$VM_NAME" >/dev/null 2>&1; then
    if [[ "${VM_RECREATE:-0}" == "1" ]]; then
        info "Removing the existing '$VM_NAME' domain and its disk"
        "${VIRSH[@]}" destroy "$VM_NAME" >/dev/null 2>&1 || true
        "${VIRSH[@]}" undefine "$VM_NAME" --nvram >/dev/null 2>&1 ||
            "${VIRSH[@]}" undefine "$VM_NAME" >/dev/null 2>&1 || true
        if "${VIRSH[@]}" vol-delete --pool "$DISK_POOL" "$DISK_VOL" >/dev/null 2>&1; then
            ok "deleted $DISK_VOL"
        else
            warn "no $DISK_VOL to delete"
        fi
    else
        die "domain '$VM_NAME' already exists.
    Open it in virt-manager, or set VM_RECREATE=1 to rebuild it from scratch
    (that deletes its disk)."
    fi
fi

if [[ "${VM_DRY_RUN:-0}" == "1" ]]; then
    info "Dry run — stopping before anything is written"
    exit 0
fi

# ------------------------------------------------------------------- upload --

# The image cannot be booted from $HOME: that directory is mode 700, so the
# qemu user cannot traverse it whatever the SELinux labels say. Push it into
# the pool through libvirt, which needs no sudo.
if "${VIRSH[@]}" vol-info --pool "$ISO_POOL" "$ISO_VOL" >/dev/null 2>&1; then
    ok "image already in pool $ISO_POOL"
else
    info "Copying the image into pool $ISO_POOL (needs no sudo — libvirt does the write)"
    "${VIRSH[@]}" vol-create-as "$ISO_POOL" "$ISO_VOL" "$(stat -c %s "$ISO")" --format raw >/dev/null \
        || die "could not create the volume $ISO_VOL in $ISO_POOL"
    "${VIRSH[@]}" vol-upload --pool "$ISO_POOL" "$ISO_VOL" "$ISO" \
        || { "${VIRSH[@]}" vol-delete --pool "$ISO_POOL" "$ISO_VOL" >/dev/null 2>&1; die "upload of $ISO_VOL failed"; }
    ok "uploaded $ISO_VOL"
fi

if ! "${VIRSH[@]}" vol-info --pool "$DISK_POOL" "$DISK_VOL" >/dev/null 2>&1; then
    info "Creating the ${VM_DISK_GB}G disk"
    "${VIRSH[@]}" vol-create-as "$DISK_POOL" "$DISK_VOL" "${VM_DISK_GB}G" --format qcow2 >/dev/null \
        || die "could not create $DISK_VOL in $DISK_POOL"
    ok "created $DISK_VOL"
fi

# ------------------------------------------------------------------ install --

VIRT_INSTALL_ARGS=(
    --connect qemu:///system
    --name "$VM_NAME"
    --vcpus "$VM_CPUS"
    --memory "$VM_RAM_MB"
    --os-variant "$OS_VARIANT"
    --disk "vol=$DISK_POOL/$DISK_VOL,bus=virtio"
    --disk "vol=$ISO_POOL/$ISO_VOL,device=cdrom"
    # virt-install refuses to run without an explicit install method, and a
    # cdrom passed as --disk is not one. --boot states it, and also fixes the
    # order: installer first, then the disk it installs onto. (Note that
    # --print-xml skips this check, so it cannot catch the omission.)
    --boot "cdrom,hd"
    --network "network=$NETWORK,model=virtio"
    --graphics spice
    --video qxl
    --sound none
    --noautoconsole
)

# VM_DRY_RUN stops before any write. VM_PRINT_XML goes as far as the domain
# definition and prints it instead of creating it — useful for checking the
# arguments once the volumes exist.
if [[ "${VM_PRINT_XML:-0}" == "1" ]]; then
    info "Printing the domain XML instead of creating the domain"
    virt-install "${VIRT_INSTALL_ARGS[@]}" --print-xml
    exit 0
fi

info "Creating the domain"
virt-install "${VIRT_INSTALL_ARGS[@]}"

# The installer menu gives about one second before it starts speech synthesis
# on its own, and this guest has no sound card, so it then sits forever probing
# for one. Tapping a key stops that countdown; DOWN followed by UP leaves the
# highlighted entry where it was.
info "Stopping the installer's speech-synthesis countdown"
for _ in $(seq 1 40); do
    "${VIRSH[@]}" send-key "$VM_NAME" --codeset linux KEY_DOWN >/dev/null 2>&1 || true
    "${VIRSH[@]}" send-key "$VM_NAME" --codeset linux KEY_UP   >/dev/null 2>&1 || true
    sleep 0.5
done

ok "domain '$VM_NAME' created, sitting at the installer menu"
cat <<EOF

  The installer is now running. Drive it yourself:

    virt-manager                     # '$VM_NAME' appears beside the other guests
    virt-viewer --connect qemu:///system $VM_NAME

  After the install finishes, detach the installer image so the guest stops
  booting from it:

    virsh --connect qemu:///system change-media $VM_NAME sda --eject --config

  The guest sits on '$NETWORK' with the other guests, so it can reach them as a
  separate host. Its traffic leaves through this host, which is worth
  remembering when a VPN is up.
EOF
