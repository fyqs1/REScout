#import "ProcessInventory.h"
#import <sys/sysctl.h>
#import <sys/param.h>
#import <limits.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>
#import <dlfcn.h>

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN)
#endif

typedef int (*dov_proc_pidpath_fn)(int, void *, uint32_t);

static dov_proc_pidpath_fn dov_proc_pidpath_sym(void) {
    static dov_proc_pidpath_fn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (dov_proc_pidpath_fn)dlsym(RTLD_DEFAULT, "proc_pidpath");
    });
    return fn;
}

static NSString *dov_proc_path(pid_t pid) {
    dov_proc_pidpath_fn fn = dov_proc_pidpath_sym();
    if (!fn) return @"";
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    memset(pathbuf, 0, sizeof(pathbuf));
    int ret = fn(pid, pathbuf, sizeof(pathbuf));
    if (ret <= 0) return @"";
    return [[NSString stringWithUTF8String:pathbuf] ?: @"" stringByResolvingSymlinksInPath];
}

static NSString *dov_bundle_id_from_path(NSString *path) {
    if (path.length == 0) return @"";
    NSString *cursor = path;
    for (int i = 0; i < 6; i++) {
        if ([cursor.pathExtension.lowercaseString isEqualToString:@"app"]) {
            NSString *plist = [cursor stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
            NSString *bid = info[@"CFBundleIdentifier"];
            if ([bid isKindOfClass:[NSString class]]) return bid;
            return @"";
        }
        NSString *parent = [cursor stringByDeletingLastPathComponent];
        if ([parent isEqualToString:cursor] || parent.length == 0) break;
        cursor = parent;
    }
    return @"";
}

static NSString *dov_display_name(NSString *path, NSString *bundleID, NSString *comm) {
    if (path.length) {
        NSString *cursor = path;
        for (int i = 0; i < 6; i++) {
            if ([cursor.pathExtension.lowercaseString isEqualToString:@"app"]) {
                NSString *plist = [cursor stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
                NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
                if ([name isKindOfClass:[NSString class]] && name.length) return name;
                return cursor.lastPathComponent.stringByDeletingPathExtension;
            }
            NSString *parent = [cursor stringByDeletingLastPathComponent];
            if ([parent isEqualToString:cursor] || parent.length == 0) break;
            cursor = parent;
        }
        return path.lastPathComponent;
    }
    if (bundleID.length) return bundleID;
    return comm.length ? comm : @"?";
}

NSArray<NSDictionary *> *DOVCopyRunningApplications(void) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0 || size == 0) {
        return @[];
    }

    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) return @[];
    if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
        free(procs);
        return @[];
    }

    int count = (int)(size / sizeof(struct kinfo_proc));
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seenPID = [NSMutableSet set];
    uid_t myuid = getuid();

    for (int i = 0; i < count; i++) {
        struct kinfo_proc kp = procs[i];
        pid_t pid = kp.kp_proc.p_pid;
        if (pid <= 0) continue;
        if ([seenPID containsObject:@(pid)]) continue;

        NSString *path = dov_proc_path(pid);
        char namebuf[MAXCOMLEN + 1];
        memset(namebuf, 0, sizeof(namebuf));
        memcpy(namebuf, kp.kp_proc.p_comm, MAXCOMLEN);
        NSString *comm = [NSString stringWithUTF8String:namebuf] ?: @"";

        // Only the main app binary: .../Foo.app/Foo (not Frameworks / helpers under .app).
        NSRange appSlash = [path rangeOfString:@".app/" options:NSCaseInsensitiveSearch];
        if (appSlash.location == NSNotFound) continue;
        NSString *afterApp = [path substringFromIndex:NSMaxRange(appSlash)];
        if (afterApp.length == 0 || [afterApp containsString:@"/"]) continue;
        if ([path.lowercaseString containsString:@".appex/"] ||
            [path containsString:@"/PlugIns/"]) {
            continue;
        }

        NSString *bundleID = dov_bundle_id_from_path(path);
        NSString *name = dov_display_name(path, bundleID, comm);
        BOOL isApple = [bundleID hasPrefix:@"com.apple."] ||
            [path containsString:@"/System/"] ||
            [path containsString:@"/CoreServices/"] ||
            [path hasPrefix:@"/usr/"];
        if ([path containsString:@"/var/containers/Bundle/Application/"] ||
            [path containsString:@"/private/var/containers/Bundle/Application/"]) {
            isApple = [bundleID hasPrefix:@"com.apple."];
        }

        [seenPID addObject:@(pid)];
        [out addObject:@{
            @"pid": @(pid),
            @"name": name ?: @"?",
            @"path": path ?: @"",
            @"bundleID": bundleID ?: @"",
            @"isApple": @(isApple),
            @"uid": @(kp.kp_eproc.e_ucred.cr_uid),
            @"isCurrentUser": @(kp.kp_eproc.e_ucred.cr_uid == myuid)
        }];
    }

    free(procs);

    // One row per bundle ID (keep lowest pid). Nameless leftovers stay as-is.
    NSMutableDictionary<NSString *, NSDictionary *> *byBundle = [NSMutableDictionary dictionary];
    NSMutableArray *noBundle = [NSMutableArray array];
    for (NSDictionary *item in out) {
        NSString *bid = item[@"bundleID"];
        if (![bid isKindOfClass:[NSString class]] || bid.length == 0) {
            [noBundle addObject:item];
            continue;
        }
        NSDictionary *prev = byBundle[bid];
        if (!prev || [item[@"pid"] compare:prev[@"pid"]] == NSOrderedAscending) {
            byBundle[bid] = item;
        }
    }
    NSMutableArray *deduped = [NSMutableArray arrayWithArray:byBundle.allValues];
    [deduped addObjectsFromArray:noBundle];

    [deduped sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *na = a[@"name"] ?: @"";
        NSString *nb = b[@"name"] ?: @"";
        NSComparisonResult r = [na localizedCaseInsensitiveCompare:nb];
        if (r != NSOrderedSame) return r;
        return [a[@"pid"] compare:b[@"pid"]];
    }];
    return deduped;
}
