#version=F44
# Disposable VALIDATION VM for dotfiles-sway (driven by scripts/create-fedora-sway-vm.sh).
# This is NOT a general-purpose installer: it targets a single virtio disk (vda)
# on an isolated, host-only libvirt NAT and is reachable only by the SSH public
# key injected at provision time. Review disk selection and the sudo policy below
# before ever reusing this on physical or multi-disk hardware.
text
lang en_US.UTF-8
keyboard gb
timezone Europe/London --utc
network --bootproto=dhcp --device=link --activate --hostname=fedora-sway-test
# No password login anywhere: root is locked and the unprivileged account has no
# password — access is exclusively via the SSH key injected by the provisioning
# script. This removes the previous trivial plaintext password.
rootpw --lock
user --name=damian --groups=wheel
sshkey --username=damian "__HOST_SSH_PUBKEY__"
services --enabled=sshd
firewall --enabled --service=ssh
# Constrain destructive partitioning to the VM's single virtio disk, so this file
# can never erase additional disks if it is ever run on multi-disk hardware.
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
bootloader --timeout=1
autopart --type=btrfs
ostreesetup --osname=fedora --remote=fedora --url=__OSTREE_URL__ --ref=fedora/44/x86_64/sericea --nogpg
reboot

%post --log=/root/ks-post.log
# Passwordless sudo is required because bootstrap.sh runs unattended over SSH with
# no TTY to type a sudo password. This is acceptable ONLY because this is a
# disposable test VM on an isolated host-only NAT reachable by SSH key alone.
# A persistent/real install must scope this to the provisioning commands and drop
# the rule once provisioning finishes — tracked in BACKLOG.md (item 1, orchestrator).
cat >/etc/sudoers.d/10-wheel-nopasswd <<'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/10-wheel-nopasswd
echo "Fedora Sway Atomic disposable test VM — install complete" >/etc/motd
%end
