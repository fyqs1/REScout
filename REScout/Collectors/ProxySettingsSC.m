#import "ProxySettingsSC.h"
#import <dlfcn.h>

typedef const void *DOVSCPreferencesRef;

typedef DOVSCPreferencesRef (*DOVSCPreferencesCreateFn)(CFAllocatorRef, CFStringRef, CFStringRef);
typedef Boolean (*DOVSCPreferencesLockFn)(DOVSCPreferencesRef, Boolean);
typedef Boolean (*DOVSCPreferencesUnlockFn)(DOVSCPreferencesRef);
typedef CFPropertyListRef (*DOVSCPreferencesGetValueFn)(DOVSCPreferencesRef, CFStringRef);
typedef Boolean (*DOVSCPreferencesSetValueFn)(DOVSCPreferencesRef, CFStringRef, CFPropertyListRef);
typedef Boolean (*DOVSCPreferencesCommitFn)(DOVSCPreferencesRef);
typedef Boolean (*DOVSCPreferencesApplyFn)(DOVSCPreferencesRef);
typedef void (*DOVCFReleaseFn)(CFTypeRef);

static void *dov_sc_handle(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
    });
    return handle;
}

NSString *DOVApplyNetworkServiceProxies(NSDictionary<NSString *, NSDictionary *> *serviceProxies,
                                        BOOL enabled) {
#pragma unused(enabled)
    if (serviceProxies.count == 0) {
        return @"no services";
    }

    void *handle = dov_sc_handle();
    if (!handle) {
        return @"SystemConfiguration dlopen failed";
    }

    DOVSCPreferencesCreateFn createFn = (DOVSCPreferencesCreateFn)dlsym(handle, "SCPreferencesCreate");
    DOVSCPreferencesLockFn lockFn = (DOVSCPreferencesLockFn)dlsym(handle, "SCPreferencesLock");
    DOVSCPreferencesUnlockFn unlockFn = (DOVSCPreferencesUnlockFn)dlsym(handle, "SCPreferencesUnlock");
    DOVSCPreferencesGetValueFn getFn = (DOVSCPreferencesGetValueFn)dlsym(handle, "SCPreferencesGetValue");
    DOVSCPreferencesSetValueFn setFn = (DOVSCPreferencesSetValueFn)dlsym(handle, "SCPreferencesSetValue");
    DOVSCPreferencesCommitFn commitFn = (DOVSCPreferencesCommitFn)dlsym(handle, "SCPreferencesCommitChanges");
    DOVSCPreferencesApplyFn applyFn = (DOVSCPreferencesApplyFn)dlsym(handle, "SCPreferencesApplyChanges");

    if (!createFn || !lockFn || !unlockFn || !getFn || !setFn || !commitFn || !applyFn) {
        return @"SCPreferences symbols missing";
    }

    DOVSCPreferencesRef prefs = createFn(kCFAllocatorDefault, CFSTR("REScout"), NULL);
    if (!prefs) {
        return @"SCPreferencesCreate failed";
    }

    if (!lockFn(prefs, true)) {
        CFRelease((CFTypeRef)prefs);
        return @"SCPreferencesLock failed";
    }

    NSString *error = nil;
    @try {
        CFPropertyListRef raw = getFn(prefs, CFSTR("NetworkServices"));
        NSMutableDictionary *networkServices = nil;
        if (raw && CFGetTypeID(raw) == CFDictionaryGetTypeID()) {
            networkServices = [(__bridge NSDictionary *)raw mutableCopy];
        }
        if (![networkServices isKindOfClass:[NSMutableDictionary class]]) {
            error = @"NetworkServices missing in SCPreferences";
        } else {
            [serviceProxies enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, NSDictionary *proxies, BOOL *stop) {
#pragma unused(stop)
                NSMutableDictionary *svc = nil;
                id existing = networkServices[uuid];
                if ([existing isKindOfClass:[NSDictionary class]]) {
                    svc = [existing mutableCopy];
                } else {
                    svc = [NSMutableDictionary dictionary];
                }
                svc[@"Proxies"] = [proxies mutableCopy] ?: [NSMutableDictionary dictionary];
                networkServices[uuid] = svc;
            }];

            if (!setFn(prefs, CFSTR("NetworkServices"), (__bridge CFDictionaryRef)networkServices)) {
                error = @"SCPreferencesSetValue failed";
            } else if (!commitFn(prefs)) {
                error = @"SCPreferencesCommitChanges failed";
            } else if (!applyFn(prefs)) {
                error = @"SCPreferencesApplyChanges failed";
            }
        }
    } @finally {
        unlockFn(prefs);
        CFRelease((CFTypeRef)prefs);
    }

    return error;
}
