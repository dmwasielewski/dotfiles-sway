#version=F44
text
lang en_US.UTF-8
keyboard gb
timezone Europe/London --utc
network --bootproto=dhcp --device=link --activate --hostname=fedora-sway-test
rootpw --lock
user --name=damian --groups=wheel --plaintext --password=damian
sshkey --username=damian "__HOST_SSH_PUBKEY__"
services --enabled=sshd
firewall --enabled --service=ssh
zerombr
clearpart --all --initlabel
bootloader --timeout=1
autopart --type=btrfs
ostreesetup --osname=fedora --remote=fedora --url=__OSTREE_URL__ --ref=fedora/44/x86_64/sericea --nogpg
reboot

%post --log=/root/ks-post.log
cat >/etc/sudoers.d/10-wheel-nopasswd <<'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/10-wheel-nopasswd
echo "Fedora Sway Atomic VM install complete" >/etc/motd
%end
