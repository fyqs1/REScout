#include "NetworkHelpers.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <resolv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>

/* Minimal Darwin routing constants / structs (iOS SDK omits net/route.h). */
#ifndef RTF_GATEWAY
#define RTF_GATEWAY 0x2
#endif
#ifndef NET_RT_FLAGS
#define NET_RT_FLAGS 2
#endif
#ifndef RTAX_MAX
#define RTAX_MAX 8
#endif
#ifndef RTAX_DST
#define RTAX_DST 0
#endif
#ifndef RTAX_GATEWAY
#define RTAX_GATEWAY 1
#endif

struct dov_rt_metrics {
    unsigned int rmx_locks;
    unsigned int rmx_mtu;
    unsigned int rmx_hopcount;
    int          rmx_expire;
    unsigned int rmx_recvpipe;
    unsigned int rmx_sendpipe;
    unsigned int rmx_ssthresh;
    unsigned int rmx_rtt;
    unsigned int rmx_rttvar;
    unsigned int rmx_pksent;
    unsigned int rmx_filler[4];
};

struct dov_rt_msghdr {
    unsigned short      rtm_msglen;
    unsigned char       rtm_version;
    unsigned char       rtm_type;
    unsigned short      rtm_index;
    int                 rtm_flags;
    int                 rtm_addrs;
    pid_t               rtm_pid;
    int                 rtm_seq;
    int                 rtm_errno;
    int                 rtm_use;
    unsigned int        rtm_inits;
    struct dov_rt_metrics rtm_rmx;
};

int DOVCopyDNSServers(char *out, int outLen) {
    if (!out || outLen <= 0) return 0;
    out[0] = '\0';

    res_state res = calloc(1, sizeof(*res));
    if (!res) return 0;
    if (res_ninit(res) != 0) {
        free(res);
        return 0;
    }

    char buf[INET_ADDRSTRLEN];
    int first = 1;
    for (int i = 0; i < res->nscount; i++) {
        memset(buf, 0, sizeof(buf));
        inet_ntop(AF_INET, &res->nsaddr_list[i].sin_addr, buf, sizeof(buf));
        if (buf[0] == '\0' || strcmp(buf, "0.0.0.0") == 0) continue;
        if (!first) {
            strncat(out, ", ", (size_t)outLen - strlen(out) - 1);
        }
        strncat(out, buf, (size_t)outLen - strlen(out) - 1);
        first = 0;
    }

    res_ndestroy(res);
    free(res);
    return (int)strlen(out);
}

int DOVCopyDefaultGateway(char *out, int outLen) {
    if (!out || outLen <= 0) return 0;
    out[0] = '\0';

    int mib[] = { CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY };
    size_t len = 0;
    if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0 || len == 0) {
        return 0;
    }

    char *buf = malloc(len);
    if (!buf) return 0;
    if (sysctl(mib, 6, buf, &len, NULL, 0) != 0) {
        free(buf);
        return 0;
    }

    char *limit = buf + len;
    char *next = buf;
    int found = 0;

    while (next + sizeof(struct dov_rt_msghdr) <= limit) {
        struct dov_rt_msghdr *rtm = (struct dov_rt_msghdr *)next;
        if (rtm->rtm_msglen == 0) break;

        char *addrPtr = (char *)(rtm + 1);
        struct sockaddr *dst = NULL;
        struct sockaddr *gateway = NULL;

        for (int i = 0; i < RTAX_MAX; i++) {
            if ((rtm->rtm_addrs & (1 << i)) == 0) continue;
            if (addrPtr + sizeof(struct sockaddr) > next + rtm->rtm_msglen) break;
            struct sockaddr *sa = (struct sockaddr *)addrPtr;
            unsigned saLen = sa->sa_len ? sa->sa_len : sizeof(struct sockaddr);
            if (saLen < sizeof(struct sockaddr)) saLen = sizeof(struct sockaddr);
            if (i == RTAX_DST) dst = sa;
            if (i == RTAX_GATEWAY) gateway = sa;
            addrPtr += saLen;
        }

        if (dst && gateway &&
            dst->sa_family == AF_INET && gateway->sa_family == AF_INET) {
            struct sockaddr_in *d = (struct sockaddr_in *)dst;
            struct sockaddr_in *g = (struct sockaddr_in *)gateway;
            if (d->sin_addr.s_addr == INADDR_ANY && g->sin_addr.s_addr != INADDR_ANY) {
                if (inet_ntop(AF_INET, &g->sin_addr, out, outLen)) {
                    found = 1;
                    break;
                }
            }
        }

        next += rtm->rtm_msglen;
    }

    free(buf);
    return found;
}
