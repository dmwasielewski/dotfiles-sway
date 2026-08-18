#!/bin/bash
# create-fedora-sway-vm.sh — disposable Fedora Sway Atomic VM for install validation
# Uses the official Fedora Everything installer ISO and an injected kickstart file
# to automate the Atomic Sway install. After first boot it drives the install over
# SSH — by default the ORCHESTRATOR path, because that is the one backlog #5 needs
# proven: does systemd-linger resume phase 2 after the reboot without anyone
# logging in? bootstrap.sh cannot answer that question; it never enables
# dotfiles-phase2.service, it only runs setup.sh + packages.sh and stops.

set -euo pipefail

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/create-fedora-sway-vm.sh"

VM_NAME="${VM_NAME:-fedora-sway-test}"
VM_RAM_MB="${VM_RAM_MB:-8192}"
VM_VCPUS="${VM_VCPUS:-4}"
VM_DISK_GB="${VM_DISK_GB:-40}"
VM_HOSTNAME="${VM_HOSTNAME:-fedora-sway-test}"
# orchestrator = clone + orchestrate.sh run (P0..P1, reboot, P2..P3 via linger)
# bootstrap    = clone + setup.sh + packages.sh, stops before the reboot
# none         = provision the VM only
VM_INSTALL_MODE="${VM_INSTALL_MODE:-orchestrator}"
# Back-compat: callers that set VM_BOOTSTRAP=0 meant "install nothing".
[[ "${VM_BOOTSTRAP:-1}" == "0" ]] && VM_INSTALL_MODE="none"
VM_USER="${VM_USER:-damian}"
VM_ISO="${VM_ISO:-$HOME/Downloads/Fedora-Everything-netinst-x86_64-44-1.7.iso}"
VM_CHECKSUM="${VM_CHECKSUM:-$HOME/Downloads/Fedora-Everything-44-1.7-x86_64-CHECKSUM}"
VM_ISO_URL="${VM_ISO_URL:-https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-44-1.7.iso}"
VM_CHECKSUM_URL="${VM_CHECKSUM_URL:-https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/Fedora-Everything-44-1.7-x86_64-CHECKSUM}"
VM_OSTREE_MIRRORLIST="${VM_OSTREE_MIRRORLIST:-https://ostree.fedoraproject.org/mirrorlist}"
VM_OSTREE_URL="${VM_OSTREE_URL:-}"
VM_STAGE_DIR="${VM_STAGE_DIR:-/tmp/dotfiles-sway-libvirt}"
VM_STAGE_ISO="$VM_STAGE_DIR/$(basename "$VM_ISO")"
KS_TEMPLATE="$DOTFILES/kickstarts/fedora-sway-atomic.ks"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${RED}✗ missing command: $1${NC}"
        exit 1
    }
}

escape_sed() {
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

get_vm_ip() {
    virsh --connect qemu:///system domifaddr "$VM_NAME" --source lease 2>/dev/null | \
        awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n1 || true
}

wait_for_ip() {
    local ip=""
    local attempt
    for attempt in $(seq 1 90); do
        ip="$(get_vm_ip)"
        if [[ -n "$ip" ]]; then
            printf '%s' "$ip"
            return 0
        fi
        sleep 10
    done
    return 1
}

# 90 minutes by default, not 30. The Fedora Atomic install pulls ~72k ostree
# objects (~2 GB) before it even writes a bootloader: on 2026-08-18 that was only
# 96% done at the 32-minute mark, so the old 30-minute ceiling aborted a healthy
# install and reported "SSH did not become ready" as if the guest were broken.
# A ceiling tuned below the thing it is waiting for is not a timeout, it is a
# false negative.
SSH_WAIT_SECONDS="${SSH_WAIT_SECONDS:-5400}"

wait_for_ssh() {
    local attempt
    local state
    local ip
    local tries=$(( SSH_WAIT_SECONDS / 5 ))

    for attempt in $(seq 1 "$tries"); do
        # Say what is happening every 5 minutes: a silent half-hour is
        # indistinguishable from a hang, which is why the last run looked stuck.
        if (( attempt % 60 == 0 )); then
            echo -e "${CYAN}==> still waiting for SSH ($(( attempt * 5 / 60 )) min of $(( SSH_WAIT_SECONDS / 60 )); guest is installing)${NC}"
        fi

        state="$(virsh --connect qemu:///system domstate "$VM_NAME" 2>/dev/null || true)"
        if [[ "$state" == "shut off" ]]; then
            echo -e "${CYAN}==> VM is shut off after install; starting installed system...${NC}"
            virsh --connect qemu:///system start "$VM_NAME" >/dev/null
            sleep 10
        fi

        ip="$(get_vm_ip)"
        if [[ -n "$ip" ]]; then
            VM_IP="$ip"
            if ssh -i "$SSH_PRIVKEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
                "$VM_USER@$VM_IP" 'true' >/dev/null 2>&1; then
                return 0
            fi
        fi

        sleep 5
    done

    return 1
}

require_cmd virsh
require_cmd virt-install
require_cmd curl
require_cmd ssh
require_cmd awk
require_cmd sed
require_cmd sha256sum

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   Fedora Sway Atomic VM — provision      ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

if [[ ! -f "$KS_TEMPLATE" ]]; then
    echo -e "${RED}✗ Kickstart template missing: $KS_TEMPLATE${NC}"
    exit 1
fi

if [[ -f "$HOME/.ssh/id_ed25519.pub" && -f "$HOME/.ssh/id_ed25519" ]]; then
    SSH_PUBKEY_FILE="$HOME/.ssh/id_ed25519.pub"
    SSH_PRIVKEY_FILE="$HOME/.ssh/id_ed25519"
elif [[ -f "$HOME/.ssh/id_rsa.pub" && -f "$HOME/.ssh/id_rsa" ]]; then
    SSH_PUBKEY_FILE="$HOME/.ssh/id_rsa.pub"
    SSH_PRIVKEY_FILE="$HOME/.ssh/id_rsa"
else
    echo -e "${RED}✗ No matching SSH keypair found in ~/.ssh (need a public/private key for VM login)${NC}"
    exit 1
fi

SSH_PUBKEY="$(<"$SSH_PUBKEY_FILE")"
SSH_PUBKEY_ESCAPED="$(escape_sed "$SSH_PUBKEY")"

if [[ -z "$VM_OSTREE_URL" ]]; then
    echo -e "${CYAN}==> Resolving Fedora ostree mirror...${NC}"
    VM_OSTREE_URL="$(curl -fsSL "$VM_OSTREE_MIRRORLIST" | awk 'NF {print; exit}')"
fi

if [[ -z "$VM_OSTREE_URL" ]]; then
    echo -e "${RED}✗ Could not resolve Fedora ostree mirror from $VM_OSTREE_MIRRORLIST${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Fedora ostree URL: $VM_OSTREE_URL${NC}"
VM_OSTREE_URL_ESCAPED="$(escape_sed "$VM_OSTREE_URL")"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
KS_FILE="$WORKDIR/fedora-sway-atomic.ks"
sed \
    -e "s|__HOST_SSH_PUBKEY__|$SSH_PUBKEY_ESCAPED|g" \
    -e "s|__OSTREE_URL__|$VM_OSTREE_URL_ESCAPED|g" \
    "$KS_TEMPLATE" > "$KS_FILE"

# The checksum comes first: it is what decides whether an existing ISO is usable.
if [[ -s "$VM_CHECKSUM" ]]; then
    echo -e "${GREEN}✓ checksum already present: $VM_CHECKSUM${NC}"
else
    echo -e "${CYAN}==> Downloading Fedora Everything checksum...${NC}"
    mkdir -p "$(dirname "$VM_CHECKSUM")"
    curl -fL --retry 3 "$VM_CHECKSUM_URL" -o "$VM_CHECKSUM"
fi

iso_is_valid() {
    [[ -s "$VM_ISO" ]] || return 1
    ( cd "$(dirname "$VM_ISO")" && sha256sum --ignore-missing --status -c "$(basename "$VM_CHECKSUM")" )
}

# `[[ -f ]]` is not "the ISO is usable": an interrupted curl leaves a truncated
# file behind, and the old check announced "✓ ISO already present" for a 179 MB
# fragment of a 700 MB image (observed 2026-08-15 after a cancelled download).
# The run then died at the verification step with a bare checksum error and no
# hint that the cure is to delete the fragment — and every rerun failed the same
# way. Validate what is on disk, and re-fetch what does not validate.
if iso_is_valid; then
    echo -e "${GREEN}✓ ISO already present and verified: $VM_ISO${NC}"
else
    if [[ -e "$VM_ISO" ]]; then
        echo -e "${YELLOW}==> Existing ISO fails its checksum ($(du -h "$VM_ISO" | cut -f1)) — re-downloading${NC}"
        rm -f "$VM_ISO"
    fi
    echo -e "${CYAN}==> Downloading Fedora Everything ISO (~700 MB)...${NC}"
    mkdir -p "$(dirname "$VM_ISO")"
    # -C - resumes a partial transfer instead of restarting from zero.
    curl -fL --retry 3 -C - "$VM_ISO_URL" -o "$VM_ISO"

    echo -e "${CYAN}==> Verifying ISO checksum...${NC}"
    if ! iso_is_valid; then
        echo -e "${RED}✗ The downloaded ISO does not match its published checksum.${NC}" >&2
        echo -e "${YELLOW}  Delete it and retry:  rm -f $VM_ISO${NC}" >&2
        exit 1
    fi
fi
echo -e "${GREEN}✓ ISO checksum verified${NC}"

echo -e "${CYAN}==> Staging ISO for libvirt...${NC}"
install -D -m 0644 "$VM_ISO" "$VM_STAGE_ISO"

# An existing VM is a resume, not an error. This run takes over an hour and the
# install phase alone is ~40 minutes; making a timeout or an interrupted run cost
# that time again is why the previous attempt had to be thrown away. Set
# VM_RECREATE=1 to force a clean rebuild.
if virsh --connect qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1; then
    if [[ "${VM_RECREATE:-0}" == "1" ]]; then
        echo -e "${YELLOW}==> VM_RECREATE=1 — destroying the existing $VM_NAME${NC}"
        virsh --connect qemu:///system destroy "$VM_NAME" >/dev/null 2>&1 || true
        virsh --connect qemu:///system undefine "$VM_NAME" --nvram >/dev/null 2>&1 || true
    else
        echo -e "${CYAN}==> $VM_NAME already exists — resuming instead of rebuilding${NC}"
        echo -e "${CYAN}    (VM_RECREATE=1 forces a clean rebuild)${NC}"
        if [[ "$(virsh --connect qemu:///system domstate "$VM_NAME" 2>/dev/null)" != "running" ]]; then
            echo -e "${CYAN}==> starting it${NC}"
            virsh --connect qemu:///system start "$VM_NAME" >/dev/null
        fi
        SKIP_PROVISION=1
    fi
fi

if [[ "${SKIP_PROVISION:-0}" != "1" ]]; then
echo -e "${CYAN}==> Launching virt-install...${NC}"
virt-install --connect qemu:///system \
    --name "$VM_NAME" \
    --memory "$VM_RAM_MB" \
    --vcpus "$VM_VCPUS" \
    --cpu host-passthrough \
    --machine q35 \
    --boot uefi \
    --os-variant fedora-unknown \
    --network network=default,model=virtio \
    --disk size="$VM_DISK_GB",format=qcow2,bus=virtio \
    --graphics spice \
    --video qxl \
    --location "$VM_STAGE_ISO" \
    --initrd-inject "$KS_FILE" \
    --extra-args "inst.ks=file:/$(basename "$KS_FILE") inst.ksstrict" \
    --noautoconsole

fi   # SKIP_PROVISION

echo -e "${CYAN}==> Waiting for VM to obtain an IP address...${NC}"
VM_IP="$(wait_for_ip)" || {
    echo -e "${RED}✗ VM did not report an IP address in time${NC}"
    exit 1
}
echo -e "${GREEN}✓ VM IP: $VM_IP${NC}"

echo -e "${CYAN}==> Waiting for SSH...${NC}"
if wait_for_ssh; then
    echo -e "${GREEN}✓ SSH ready: $VM_IP${NC}"
else
    echo -e "${RED}✗ SSH did not become ready${NC}"
    exit 1
fi

vm_ssh() {   # run a command in the guest; caller decides how to treat failure
    ssh -i "$SSH_PRIVKEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
        "$VM_USER@$VM_IP" "$@"
}

case "$VM_INSTALL_MODE" in
    orchestrator)
        echo -e "${CYAN}==> Running the orchestrator inside the VM (P0..P1, then reboot)...${NC}"
        echo -e "${YELLOW}    packages.sh downloads ~420 MB for the ChatGPT app; a long pause here is${NC}"
        echo -e "${YELLOW}    the download, not a hang.${NC}"
        # P1 ends in `sudo systemctl reboot`, so this ssh ALWAYS dies — dropped
        # connection or non-zero exit. Under `set -euo pipefail` that would abort
        # the script exactly at the moment of interest, so the failure is accepted
        # here and the real verdict comes from the state file after the reboot.
        vm_ssh 'bash -lc "
            set -e
            if [[ -d ~/dotfiles-sway/.git ]]; then git -C ~/dotfiles-sway pull --ff-only
            else git clone https://github.com/dmwasielewski/dotfiles-sway.git ~/dotfiles-sway
            fi
            git -C ~/dotfiles-sway submodule update --init --recursive
            bash ~/dotfiles-sway/orchestrate.sh run
        "' || echo -e "${YELLOW}==> SSH ended (expected: phase 1 reboots the guest).${NC}"

        echo -e "${CYAN}==> Waiting for the guest to come back...${NC}"
        if ! wait_for_ssh; then
            echo -e "${RED}✗ Guest did not return after the phase-1 reboot${NC}"
            exit 1
        fi

        # THE question behind backlog #5: did linger resume phase 2 with nobody
        # logged in? Read the state file rather than trusting that it looks alive.
        echo -e "${CYAN}==> Checking whether phase 2 resumed on its own...${NC}"
        for _ in $(seq 1 60); do
            vm_ssh 'grep -q "^INSTALL_COMPLETE=" ~/.dotfiles-install-state 2>/dev/null' && break
            sleep 20
        done
        echo ""
        vm_ssh 'systemctl --user status dotfiles-phase2.service --no-pager 2>&1 | head -12' || true
        echo ""
        if vm_ssh 'grep -q "^INSTALL_COMPLETE=" ~/.dotfiles-install-state 2>/dev/null'; then
            echo -e "${GREEN}✓ Phase 2 resumed after the reboot and the install completed${NC}"
            echo -e "${GREEN}  systemd-linger works — backlog #5 answered.${NC}"
        else
            echo -e "${RED}✗ Phase 2 did NOT complete after the reboot${NC}"
            echo -e "${YELLOW}  This is the documented risk. Fall back to a Sway-session trigger${NC}"
            echo -e "${YELLOW}  (exec orchestrate.sh resume) and record it in setup-orchestrator-service.sh.${NC}"
            vm_ssh 'cat ~/.dotfiles-install-state' || true
        fi
        ;;
    bootstrap)
        echo -e "${CYAN}==> Running bootstrap.sh inside the VM (classic path)...${NC}"
        vm_ssh 'bash -lc "curl -fsSL https://raw.githubusercontent.com/dmwasielewski/dotfiles-sway/main/bootstrap.sh | bash"'
        echo ""
        echo -e "${GREEN}✓ Bootstrap completed inside the VM${NC}"
        echo -e "${YELLOW}Note: bootstrap stops after Phase 1 and asks for a reboot. That is expected.${NC}"
        echo -e "${YELLOW}It does NOT exercise the orchestrator — use VM_INSTALL_MODE=orchestrator for that.${NC}"
        ;;
    none)
        echo -e "${YELLOW}Install skipped (VM_INSTALL_MODE=none)${NC}"
        ;;
    *)
        echo -e "${RED}Unknown VM_INSTALL_MODE: $VM_INSTALL_MODE${NC}" >&2
        exit 2
        ;;
esac

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} VM provisioning complete${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " VM: ${CYAN}$VM_NAME${NC}"
echo -e " IP: ${CYAN}$VM_IP${NC}"
echo -e " SSH: ${CYAN}ssh -i $SSH_PRIVKEY_FILE $VM_USER@$VM_IP${NC}"
echo -e " ISO: ${CYAN}$VM_ISO${NC}"
echo ""
