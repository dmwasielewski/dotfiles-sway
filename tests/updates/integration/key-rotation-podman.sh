#!/bin/bash
# Real-tools check of scripts/container-key-refresh.sh in a throwaway podman
# container (no network keyservers, no live keyring touched). It reproduces the
# 2026-11-08 Warp case with a key made on the spot:
#   1. primary P + signing subkey S1; the container trusts that old certificate
#   2. vendor adds S2 and signs a package with it -> NOKEY in the container
#   3. the refresh must import the updated P, verify the package, update the
#      repo's gpgkey file — and must REFUSE a certificate with a different primary.
# Run on the host:  bash tests/updates/integration/key-rotation-podman.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
IMAGE="${IMAGE:-$(podman images --format '{{.Repository}}:{{.Tag}}' | grep -m1 'fedora-toolbox')}"
[[ -n "$IMAGE" ]] || { echo "no local fedora image"; exit 1; }
podman run --rm -i -v "$DIR/scripts:/repo:ro,Z" "$IMAGE" bash -s <<'IN'
set -uo pipefail
dnf -y -q install rpm-build rpm-sign >/dev/null 2>&1
export GNUPGHOME=/root/g; mkdir -p -m700 $GNUPGHOME; cd /root
gpg --batch --passphrase '' --quick-gen-key 'Vendor <v@example.test>' rsa3072 cert never
P=$(gpg --list-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
gpg --batch --passphrase '' --quick-add-key $P rsa3072 sign never
gpg --armor --export $P > old.asc                       # what the container has
gpg --batch --passphrase '' --quick-add-key $P rsa3072 sign never
S2=$(gpg --list-keys --with-colons $P | awk -F: '/^fpr/{f=$10} END{print f}')
gpg --armor --export $P > new.asc                       # what the key server has
mkdir -p rpmbuild/SPECS; cat > rpmbuild/SPECS/t.spec <<S
Name: vendor-tool
Version: 1
Release: 1
Summary: t
License: MIT
BuildArch: noarch
%description
t
%files
S
rpmbuild -bb --quiet rpmbuild/SPECS/t.spec >/dev/null 2>&1
RPM=$(ls rpmbuild/RPMS/noarch/*.rpm)
rpmsign --define "_gpg_name ${S2}!" --addsign "$RPM" >/dev/null 2>&1
# Container state on the day: old certificate imported, stale local key file.
rpmkeys --import old.asc
install -m644 old.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-vendor
printf '[vendor]\nname=v\nbaseurl=file:///nonexistent\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-vendor\n' > /etc/yum.repos.d/vendor.repo
# A second repo whose key file is a BUNDLE (vendor cert + another): must stay untouched.
GNUPGHOME=/root/o; mkdir -p -m700 $GNUPGHOME
gpg --batch --passphrase '' --quick-gen-key 'Other <o@example.test>' rsa3072 sign never 2>/dev/null
gpg --armor --export > other.asc; export GNUPGHOME=/root/g
cat old.asc other.asc > /etc/pki/rpm-gpg/RPM-GPG-KEY-bundle
printf '[bundle]\nname=b\nbaseurl=file:///nonexistent\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-bundle\n' > /etc/yum.repos.d/bundle.repo
BUNDLE_SUM=$(sha256sum /etc/pki/rpm-gpg/RPM-GPG-KEY-bundle)
fail=0; ok() { echo "  ok: $*"; }; bad() { echo "  FAIL: $*"; fail=1; }
[[ "$(rpmkeys -Kv "$RPM" 2>&1)" == *NOKEY* ]] && ok "package starts NOKEY (rotation reproduced)" || bad "setup did not reproduce NOKEY"
# A stranger's certificate offered at the same URL must be refused.
GNUPGHOME=/root/x; mkdir -p -m700 $GNUPGHOME
gpg --batch --passphrase '' --quick-gen-key 'Evil <e@example.test>' rsa3072 sign never 2>/dev/null
gpg --armor --export > evil.asc; export GNUPGHOME=/root/g
mkdir -p ks; cp evil.asc "ks/${P^^}"
KEY_SOURCES="file:///root/ks/{FPR}" bash /repo/container-key-refresh.sh "$RPM"; rc=$?
[[ $rc -eq 1 ]] && ok "unrelated certificate refused (rc=1)" || bad "unrelated certificate rc=$rc"
[[ "$(rpmkeys -Kv "$RPM" 2>&1)" == *NOKEY* ]] && ok "live keyring untouched after refusal" || bad "keyring changed"
# The genuine updated certificate must fix it.
cp new.asc "ks/${P^^}"
KEY_SOURCES="file:///root/ks/{FPR}" bash /repo/container-key-refresh.sh "$RPM"; rc=$?
[[ $rc -eq 0 ]] && ok "rotated subkey refreshed (rc=0)" || bad "refresh rc=$rc"
[[ "$(rpmkeys -K "$RPM" 2>&1)" == *"signatures OK"* ]] && ok "package verifies after refresh" || bad "package still fails"
gpg --show-keys --with-colons /etc/pki/rpm-gpg/RPM-GPG-KEY-vendor | grep -qi "$S2" && ok "repo gpgkey file updated" || bad "gpgkey file stale"
ls /etc/pki/rpm-gpg/RPM-GPG-KEY-vendor.bak-* >/dev/null && ok "old key file kept as backup" || bad "no backup"
[[ "$(sha256sum /etc/pki/rpm-gpg/RPM-GPG-KEY-bundle)" == "$BUNDLE_SUM" ]] && ok "multi-cert bundle key file left untouched" || bad "bundle file was rewritten"
# A package that is fine is not a missing-key failure.
KEY_SOURCES="file:///root/ks/{FPR}" bash /repo/container-key-refresh.sh "$RPM"; rc=$?
[[ $rc -eq 3 ]] && ok "already-valid package -> rc=3 (nothing to refresh)" || bad "valid package rc=$rc"
exit $fail
IN
