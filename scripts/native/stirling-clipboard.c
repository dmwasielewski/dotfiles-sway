/* App-scoped workaround for WebKitGTK ClipboardGtk3.cpp::formats.
 * GTK reports unavailable targets as NULL/-1. WebKitGTK 2.54.1 converts
 * the signed count to a span length and dereferences an invalid array.
 * Normalize unavailable results to empty, preserving valid clipboard data.
 * This interposes only the GTK3 target callback, not TLS or paste contents.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
typedef void (*TargetsCallback)(void *, void **, int, void *);
typedef void (*RequestTargets)(void *, TargetsCallback, void *);
struct Request { TargetsCallback callback; void *data; };
static void received(void *clipboard, void **targets, int count, void *opaque)
{
    struct Request *request = opaque;
    TargetsCallback callback = request->callback;
    void *data = request->data;
    free(request);
    if (!targets || count < 0) { targets = NULL; count = 0; }
    callback(clipboard, targets, count, data);
}
void gtk_clipboard_request_targets(void *clipboard, TargetsCallback callback, void *data)
{
    RequestTargets original = (RequestTargets)dlsym(RTLD_NEXT, "gtk_clipboard_request_targets");
    struct Request *request = malloc(sizeof(*request));
    if (!original || !request) {
        free(request);
        callback(clipboard, NULL, 0, data);
        return;
    }
    request->callback = callback;
    request->data = data;
    original(clipboard, received, request);
}
