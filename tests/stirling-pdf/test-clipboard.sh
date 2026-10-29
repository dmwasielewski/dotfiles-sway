#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/fake.c" <<'C'
#include <stddef.h>
typedef void (*Callback)(void *, void **, int, void *);
int mode;
void gtk_clipboard_request_targets(void *clip, Callback cb, void *data) {
    void *targets[] = {(void *)42};
    cb(clip, mode == 2 ? targets : NULL, mode == 0 ? -1 : 1, data);
}
C
cat > "$tmp/main.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
extern int mode;
extern void gtk_clipboard_request_targets(void *, void (*)(void *, void **, int, void *), void *);
static void received(void *clip, void **targets, int count, void *data) {
    if (clip != (void *)9 || data != (void *)7) exit(3);
    if (mode < 2 && count != 0) { fprintf(stderr, "FAIL: empty targets count=%d\n", count); exit(1); }
    if (mode == 2 && (count != 1 || targets[0] != (void *)42)) exit(2);
}
int main(void) {
    for (mode=0; mode<3; mode++) gtk_clipboard_request_targets((void *)9, received, (void *)7);
    puts("PASS: negative/NULL clipboard targets normalized; valid targets and callback context preserved");
}
C
gcc -shared -fPIC "$tmp/fake.c" -o "$tmp/libfake.so"
gcc "$tmp/main.c" -L"$tmp" -lfake -Wl,-rpath,"$tmp" -o "$tmp/test"
if [[ -f "$repo/scripts/native/stirling-clipboard.c" ]]; then
    gcc -Wall -Wextra -Werror -shared -fPIC "$repo/scripts/native/stirling-clipboard.c" -ldl -o "$tmp/shim.so"
    LD_PRELOAD="$tmp/shim.so" "$tmp/test"
else
    "$tmp/test"
fi
