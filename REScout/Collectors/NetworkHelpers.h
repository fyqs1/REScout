#include <stddef.h>

/// Comma-separated IPv4 DNS servers into `out`. Returns bytes written.
int DOVCopyDNSServers(char *out, int outLen);

/// Default IPv4 gateway into `out`. Returns 1 on success.
int DOVCopyDefaultGateway(char *out, int outLen);
