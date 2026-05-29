// context_util.h  (전체 교체)
#ifndef CONTEXT_UTIL_H
#define CONTEXT_UTIL_H

#include <stdio.h>
#include <stdlib.h>
#include <iio.h>

// WSL/Windows 공통: IP 고정으로만 붙는다. (기본 192.168.2.1)
static inline struct iio_context* create_ctx_safe(void) {
    struct iio_context *ctx = NULL;
    const char *remote = getenv("IIOD_REMOTE");
    if (!remote || !remote[0]) remote = "192.168.2.1";

    ctx = iio_create_network_context(remote);
    if (!ctx) {
        fprintf(stderr, "ERROR: Failed to create IIO network context to %s\n", remote);
        return NULL;
    }
    return ctx;
}

// 스캔은 WSL에서 의미 없으므로 “0”만 깔끔히 출력하고 끝
static inline void print_scan_results_safe(void) {
    printf("\n        Number of available Contexts: 0\n");
}

#endif

