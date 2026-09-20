#import "AppInventory.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdio.h>
#import <objc/runtime.h>
#import <objc/message.h>

static id dov_safePerform(id target, SEL sel) {
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [target performSelector:sel];
#pragma clang diagnostic pop
}

static id dov_safePerform1(id target, SEL sel, id arg) {
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [target performSelector:sel withObject:arg];
#pragma clang diagnostic pop
}

static NSString *dov_stringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value path];
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    if (value) return [value description];
    return @"";
}

static NSString *dov_normalizePath(NSString *path) {
    if (path.length == 0) return @"";
    NSString *resolved = [path stringByResolvingSymlinksInPath] ?: path;
    if ([resolved hasPrefix:@"/private/var/"]) {
        return [@"/var/" stringByAppendingString:[resolved substringFromIndex:12]];
    }
    return resolved;
}

/// Device evidence (iOS 16 / Dopamine): Apple apps also live under
/// /var/containers/Bundle/Application — path alone cannot mean "user".
/// Prefer bundle-id + system roots, then container third-party, then LS type.
static NSString *dov_classifyRole(NSString *appType, NSString *bundlePath, NSString *bundleID) {
    NSString *bid = bundleID ?: @"";
    NSString *path = dov_normalizePath(bundlePath ?: @"");
    NSString *type = (appType ?: @"").lowercaseString;

    if ([bid hasPrefix:@"com.apple."]) {
        return @"system";
    }

    if ([path hasPrefix:@"/Applications/"] ||
        [path hasPrefix:@"/System/"] ||
        [path containsString:@"/System/Library/"] ||
        [path containsString:@"/Library/Application Support/"] ||
        [path containsString:@"/CoreServices/"]) {
        return @"system";
    }

    if ([path containsString:@"/var/jb/Applications"] ||
        [path containsString:@"/private/var/jb/Applications"]) {
        return @"user";
    }

    BOOL inUserContainer =
        [path containsString:@"/var/containers/Bundle/Application/"] ||
        [path containsString:@"/private/var/containers/Bundle/Application/"];
    if (inUserContainer) {
        return @"user";
    }

    if ([type isEqualToString:@"user"]) return @"user";
    if ([type isEqualToString:@"system"] || [type isEqualToString:@"internal"]) return @"system";

    return @"user";
}

/// Rebuild MCM Data-container index. Never reuse Bundle UUID for Data paths.
static NSDictionary<NSString *, NSString *> *dov_buildDataContainerIndex(void) {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSArray *roots = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
        @"/var/containers/Data/Application"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in roots) {
        NSArray *uuids = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *uuid in uuids) {
            NSString *dir = [root stringByAppendingPathComponent:uuid];
            NSString *meta = [dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:meta];
            NSString *owner = plist[@"MCMMetadataIdentifier"];
            if (![owner isKindOfClass:[NSString class]] || owner.length == 0) continue;
            if (map[owner]) continue;
            map[owner] = dir;
        }
    }
    return [map copy];
}

static NSDictionary<NSString *, NSString *> *g_dovDataIndex = nil;

static NSString *dov_lookupDataByBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return @"";
    if (!g_dovDataIndex) {
        g_dovDataIndex = dov_buildDataContainerIndex();
    }
    NSString *path = g_dovDataIndex[bundleID];
    if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    }
    return @"";
}

/// Prefer MCM metadata (authoritative). Fall back to LS dataContainerURL only.
/// Never map Bundle Container UUID onto Data Container path.
static NSString *dov_resolveDataPath(id proxy, NSString *bundleID, NSString *bundlePath) {
#pragma unused(bundlePath)
    NSString *byMeta = dov_lookupDataByBundleID(bundleID);
    if (byMeta.length) return byMeta;

    NSURL *dataURL = dov_safePerform(proxy, NSSelectorFromString(@"dataContainerURL"));
    NSString *dataPath = dov_normalizePath(dov_stringValue(dataURL));
    if (dataPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:dataPath]) {
        // Reject if this looks like a Bundle path mistakenly returned as data.
        if ([dataPath containsString:@"/containers/Bundle/"] ||
            [dataPath containsString:@"/Bundle/Application/"]) {
            return @"";
        }
        return dataPath;
    }

    return @"";
}

static NSData *dov_pngDataFromImage(UIImage *image) {
    if (!image) return nil;
    NSData *png = UIImagePNGRepresentation(image);
    if (png.length > 0) return png;
    return UIImageJPEGRepresentation(image, 0.92);
}

static NSData *dov_iconViaPrivateUIImage(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:sel]) return nil;

    CGFloat scale = [UIScreen mainScreen].scale;
    // formats commonly used by SpringBoard / UIKit private API
    int formats[] = { 2, 1, 0, 10, 11 };
    for (size_t i = 0; i < sizeof(formats) / sizeof(formats[0]); i++) {
        NSMethodSignature *sig = [UIImage methodSignatureForSelector:sel];
        if (!sig) break;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv setTarget:[UIImage class]];
        NSString *bid = bundleID;
        int format = formats[i];
        [inv setArgument:&bid atIndex:2];
        [inv setArgument:&format atIndex:3];
        [inv setArgument:&scale atIndex:4];
        [inv invoke];
        __unsafe_unretained UIImage *result = nil;
        if (sig.methodReturnLength > 0) {
            [inv getReturnValue:&result];
        }
        NSData *data = dov_pngDataFromImage(result);
        if (data.length > 0) return data;
    }
    return nil;
}

static NSData *dov_iconDataFromProxy(id proxy) __attribute__((unused));
static NSData *dov_iconDataFromProxy(id proxy) {
    SEL sels[] = {
        NSSelectorFromString(@"primaryIconData"),
        NSSelectorFromString(@"iconData"),
    };
    for (size_t i = 0; i < sizeof(sels) / sizeof(sels[0]); i++) {
        id val = dov_safePerform(proxy, sels[i]);
        if ([val isKindOfClass:[NSData class]] && [(NSData *)val length] > 0) {
            // May already be PNG; if CgBI-ish, try re-encode via UIImage(contents) path later.
            UIImage *img = [UIImage imageWithData:(NSData *)val];
            if (img) {
                NSData *png = dov_pngDataFromImage(img);
                if (png.length) return png;
            }
            return (NSData *)val;
        }
    }

    SEL variantSel = NSSelectorFromString(@"iconDataForVariant:");
    if ([proxy respondsToSelector:variantSel]) {
        NSArray *variants = @[@(2), @(1), @(0), @(5), @(17)];
        for (NSNumber *v in variants) {
            NSMethodSignature *sig = [proxy methodSignatureForSelector:variantSel];
            if (!sig) break;
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setSelector:variantSel];
            [inv setTarget:proxy];
            NSInteger variant = v.integerValue;
            [inv setArgument:&variant atIndex:2];
            [inv invoke];
            __unsafe_unretained id result = nil;
            if (sig.methodReturnLength > 0) {
                [inv getReturnValue:&result];
            }
            if ([result isKindOfClass:[NSData class]] && [(NSData *)result length] > 0) {
                UIImage *img = [UIImage imageWithData:(NSData *)result];
                if (img) {
                    NSData *png = dov_pngDataFromImage(img);
                    if (png.length) return png;
                }
                return (NSData *)result;
            }
        }
    }
    return nil;
}

/// iOS app-bundle PNGs are often Apple CgBI. UIImage(data:) fails; contentsOfFile works.
static NSData *dov_iconFromBundlePath(NSString *appPath) {
    if (appPath.length == 0) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSArray *fixed = @[
        @"AppIcon60x60@3x.png",
        @"AppIcon60x60@2x.png",
        @"AppIcon76x76@2x~ipad.png",
        @"Icon.png",
        @"Icon@2x.png",
        @"Icon@3x.png",
        @"icon.png"
    ];
    [candidates addObjectsFromArray:fixed];

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSDictionary *icons = info[@"CFBundleIcons"][@"CFBundlePrimaryIcon"];
    NSArray *files = icons[@"CFBundleIconFiles"];
    if ([files isKindOfClass:[NSArray class]]) {
        for (NSString *base in files) {
            if (![base isKindOfClass:[NSString class]]) continue;
            for (NSString *suffix in @[@"@3x.png", @"@2x.png", @".png", @"~ipad.png", @"@2x~ipad.png"]) {
                [candidates addObject:[base stringByAppendingString:suffix]];
            }
        }
    }

    // Also pick any AppIcon*.png present in the bundle root.
    NSArray *kids = [fm contentsOfDirectoryAtPath:appPath error:nil];
    for (NSString *name in kids) {
        NSString *lower = name.lowercaseString;
        if ([lower hasPrefix:@"appicon"] && [lower hasSuffix:@".png"]) {
            [candidates addObject:name];
        }
    }

    NSMutableSet *tried = [NSMutableSet set];
    for (NSString *name in candidates) {
        if ([tried containsObject:name]) continue;
        [tried addObject:name];
        NSString *p = [appPath stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:p]) continue;
        UIImage *img = [UIImage imageWithContentsOfFile:p];
        NSData *png = dov_pngDataFromImage(img);
        if (png.length > 0) return png;
    }
    return nil;
}

static NSString *dov_bundleContainerPath(NSString *bundlePath) {
    if (bundlePath.length == 0) return @"";
    NSString *path = dov_normalizePath(bundlePath);
    if ([path.pathExtension.lowercaseString isEqualToString:@"app"]) {
        return [path stringByDeletingLastPathComponent];
    }
    return path;
}

static NSMutableDictionary *dov_dictFromProxy(id proxy) {
    if (!proxy) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    NSString *bundleID = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"applicationIdentifier")));
    if (bundleID.length == 0) {
        bundleID = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"bundleIdentifier")));
    }
    if (bundleID.length == 0) return nil;

    dict[@"bundleID"] = bundleID;
    dict[@"name"] = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"localizedName")));
    if ([dict[@"name"] length] == 0) {
        dict[@"name"] = bundleID;
    }
    dict[@"version"] = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"shortVersionString")));
    dict[@"build"] = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"bundleVersion")));
    dict[@"executable"] = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"bundleExecutable")));
    dict[@"minimumOS"] = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"minimumSystemVersion")));
    dict[@"teamID"] = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"teamID")));

    NSURL *bundleURL = dov_safePerform(proxy, NSSelectorFromString(@"bundleURL"));
    if (!bundleURL) bundleURL = dov_safePerform(proxy, NSSelectorFromString(@"bundleContainerURL"));
    NSString *bundlePath = dov_normalizePath(dov_stringValue(bundleURL));
    if (bundlePath.length && ![bundlePath.pathExtension.lowercaseString isEqualToString:@"app"]) {
        NSArray *kids = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePath error:nil];
        for (NSString *k in kids) {
            if ([k.pathExtension.lowercaseString isEqualToString:@"app"]) {
                bundlePath = [bundlePath stringByAppendingPathComponent:k];
                break;
            }
        }
    }
    dict[@"bundlePath"] = bundlePath ?: @"";
    dict[@"bundleContainerPath"] = dov_bundleContainerPath(bundlePath);

    NSString *appType = dov_stringValue(dov_safePerform(proxy, NSSelectorFromString(@"applicationType")));
    dict[@"type"] = appType.length ? appType : @"Unknown";

    NSString *role = dov_classifyRole(appType, bundlePath, bundleID);
    dict[@"role"] = role;
    dict[@"isSystem"] = @([role isEqualToString:@"system"]);

    dict[@"dataPath"] = @"";

    return dict;
}

static void dov_appendFromDirectory(NSString *dir, NSMutableArray *out, NSMutableSet *seen) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *children = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *child in children) {
        NSString *path = [dir stringByAppendingPathComponent:child];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) continue;

        NSArray *inner = [fm contentsOfDirectoryAtPath:path error:nil] ?: @[path.lastPathComponent];
        NSString *base = path;
        NSArray *scan = inner;
        if ([child.pathExtension.lowercaseString isEqualToString:@"app"]) {
            scan = @[child];
            base = dir;
        }
        for (NSString *item in scan) {
            if (![item.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            NSString *appPath = [base stringByAppendingPathComponent:item];
            NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            if (![info isKindOfClass:[NSDictionary class]]) continue;
            NSString *bundleID = info[@"CFBundleIdentifier"];
            if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) continue;
            if ([seen containsObject:bundleID]) continue;
            [seen addObject:bundleID];

            NSString *role = dov_classifyRole(@"", appPath, bundleID);
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"bundleID"] = bundleID;
            dict[@"name"] = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bundleID;
            dict[@"version"] = info[@"CFBundleShortVersionString"] ?: @"";
            dict[@"build"] = info[@"CFBundleVersion"] ?: @"";
            dict[@"executable"] = info[@"CFBundleExecutable"] ?: @"";
            dict[@"minimumOS"] = info[@"MinimumOSVersion"] ?: @"";
            dict[@"bundlePath"] = appPath;
            dict[@"bundleContainerPath"] = dov_bundleContainerPath(appPath);
            dict[@"dataPath"] = @"";
            dict[@"type"] = [role isEqualToString:@"system"] ? @"System" : @"User";
            dict[@"role"] = role;
            dict[@"isSystem"] = @([role isEqualToString:@"system"]);
            dict[@"teamID"] = @"";
            [out addObject:dict];
        }
    }
}

NSArray<NSDictionary *> *DOVCopyInstalledApplications(void) {
    // List load stays cheap: no MCM index, icons, entitlements, or App Groups.
    // Those are resolved on demand from App detail.

    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = dov_safePerform((id)workspaceClass, NSSelectorFromString(@"defaultWorkspace"));
    NSArray *apps = dov_safePerform(workspace, NSSelectorFromString(@"allApplications"));
    if (![apps isKindOfClass:[NSArray class]]) {
        apps = dov_safePerform(workspace, NSSelectorFromString(@"allInstalledApplications"));
    }
    if ([apps isKindOfClass:[NSArray class]]) {
        for (id proxy in apps) {
            NSMutableDictionary *dict = dov_dictFromProxy(proxy);
            if (!dict) continue;
            NSString *bid = dict[@"bundleID"];
            if ([seen containsObject:bid]) continue;
            [seen addObject:bid];
            [result addObject:dict];
        }
    }

    if (result.count > 0) {
        // LS usually has user + system; only supplement jailbreak /Applications.
        dov_appendFromDirectory(@"/var/jb/Applications", result, seen);
    } else {
        dov_appendFromDirectory(@"/var/containers/Bundle/Application", result, seen);
        dov_appendFromDirectory(@"/private/var/containers/Bundle/Application", result, seen);
        dov_appendFromDirectory(@"/Applications", result, seen);
        dov_appendFromDirectory(@"/var/jb/Applications", result, seen);
    }

    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [dov_stringValue(a[@"name"]) localizedCaseInsensitiveCompare:dov_stringValue(b[@"name"])];
    }];
    return result;
}

/// Shared App Group MCM index: group id → container path.
static NSDictionary<NSString *, NSString *> *dov_buildSharedAppGroupIndex(void) {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSArray *roots = @[
        @"/var/mobile/Containers/Shared/AppGroup",
        @"/private/var/mobile/Containers/Shared/AppGroup",
        @"/var/containers/Shared/AppGroup"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in roots) {
        NSArray *uuids = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *uuid in uuids) {
            NSString *dir = [root stringByAppendingPathComponent:uuid];
            NSString *meta = [dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:meta];
            NSString *owner = plist[@"MCMMetadataIdentifier"];
            if (![owner isKindOfClass:[NSString class]] || owner.length == 0) continue;
            if (map[owner]) continue;
            map[owner] = dov_normalizePath(dir);
        }
    }
    return [map copy];
}

/// PluginKitPlugin MCM index: extension bundle id → data path.
static NSDictionary<NSString *, NSString *> *dov_buildPluginKitDataIndex(void) {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSArray *roots = @[
        @"/var/mobile/Containers/Data/PluginKitPlugin",
        @"/private/var/mobile/Containers/Data/PluginKitPlugin",
        @"/var/containers/Data/PluginKitPlugin"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in roots) {
        NSArray *uuids = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *uuid in uuids) {
            NSString *dir = [root stringByAppendingPathComponent:uuid];
            NSString *meta = [dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:meta];
            NSString *owner = plist[@"MCMMetadataIdentifier"];
            if (![owner isKindOfClass:[NSString class]] || owner.length == 0) continue;
            if (map[owner]) continue;
            map[owner] = dov_normalizePath(dir);
        }
    }
    return [map copy];
}

static NSString *dov_executablePath(NSString *bundlePath, NSString *executableName) {
    if (bundlePath.length == 0) return @"";
    NSString *appPath = dov_normalizePath(bundlePath);
    if (![appPath.pathExtension.lowercaseString isEqualToString:@"app"]) {
        NSArray *kids = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:nil];
        for (NSString *k in kids) {
            if ([k.pathExtension.lowercaseString isEqualToString:@"app"]) {
                appPath = [appPath stringByAppendingPathComponent:k];
                break;
            }
        }
    }
    NSString *exe = executableName;
    if (exe.length == 0) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
        exe = info[@"CFBundleExecutable"];
    }
    if (exe.length == 0) return @"";
    return [appPath stringByAppendingPathComponent:exe];
}

static NSDictionary *dov_entitlementsViaLdid(NSString *execPath) {
    if (execPath.length == 0) return nil;
    NSArray *binaries = @[
        @"/var/jb/usr/bin/ldid",
        @"/usr/bin/ldid",
        @"/var/jb/bin/ldid"
    ];
    NSString *ldid = nil;
    for (NSString *p in binaries) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) {
            ldid = p;
            break;
        }
    }
    if (!ldid) return nil;

    NSString *cmd = [NSString stringWithFormat:@"%@ -e %@ 2>/dev/null",
                     ldid,
                     [NSString stringWithFormat:@"'%@'", [execPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]];
    FILE *fp = popen(cmd.UTF8String, "r");
    if (!fp) return nil;
    NSMutableData *data = [NSMutableData data];
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        [data appendBytes:buf length:n];
    }
    pclose(fp);
    if (data.length == 0) return nil;
    id obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListImmutable
                                                        format:NULL
                                                         error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? (NSDictionary *)obj : nil;
}

/// Prefer Security.framework SecCode (dlsym — not in public iOS headers), else ldid on jailbroken hosts.
static NSDictionary *dov_entitlementsForExecutable(NSString *execPath) {
    if (execPath.length == 0) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:execPath]) return nil;

    typedef int32_t DOVOSStatus;
    typedef struct __SecCode const *DOVSecStaticCodeRef;
    typedef DOVOSStatus (*DOVCreateFn)(CFURLRef, uint32_t, DOVSecStaticCodeRef *);
    typedef DOVOSStatus (*DOVCopyInfoFn)(DOVSecStaticCodeRef, uint32_t, CFDictionaryRef *);

    static DOVCreateFn createFn = NULL;
    static DOVCopyInfoFn copyFn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (handle) {
            createFn = (DOVCreateFn)dlsym(handle, "SecStaticCodeCreateWithPath");
            copyFn = (DOVCopyInfoFn)dlsym(handle, "SecCodeCopySigningInformation");
        }
    });

    if (createFn && copyFn) {
        NSURL *url = [NSURL fileURLWithPath:execPath isDirectory:NO];
        DOVSecStaticCodeRef code = NULL;
        DOVOSStatus st = createFn((__bridge CFURLRef)url, 0 /* kSecCSDefaultFlags */, &code);
        if (st == 0 && code != NULL) {
            CFDictionaryRef cfInfo = NULL;
            // 2 == kSecCSSigningInformation on Darwin
            st = copyFn(code, 2, &cfInfo);
            CFRelease((CFTypeRef)code);
            if (st == 0 && cfInfo != NULL) {
                NSDictionary *info = CFBridgingRelease(cfInfo);
                id ents = info[@"entitlements"] ?: info[(id)CFSTR("entitlements")];
                // Common key string for kSecCodeInfoEntitlementsDict
                if (![ents isKindOfClass:[NSDictionary class]]) {
                    ents = info[@"Entitlements"];
                }
                for (NSString *key in info) {
                    id val = info[key];
                    if ([val isKindOfClass:[NSDictionary class]] &&
                        (val[@"com.apple.security.application-groups"] ||
                         val[@"application-identifier"] ||
                         val[@"keychain-access-groups"])) {
                        ents = val;
                        break;
                    }
                }
                if ([ents isKindOfClass:[NSDictionary class]]) {
                    return (NSDictionary *)ents;
                }
                id xml = info[@"entitlements"] ?: info[(id)CFSTR("entitlements-xml")];
                if ([xml isKindOfClass:[NSData class]]) {
                    id obj = [NSPropertyListSerialization propertyListWithData:(NSData *)xml
                                                                       options:NSPropertyListImmutable
                                                                        format:NULL
                                                                         error:nil];
                    if ([obj isKindOfClass:[NSDictionary class]]) return (NSDictionary *)obj;
                }
            }
        }
    }

    return dov_entitlementsViaLdid(execPath);
}

static NSArray<NSString *> *dov_stringArrayFromEntitlement(NSDictionary *ents, NSString *key) {
    if (![ents isKindOfClass:[NSDictionary class]]) return @[];
    id val = ents[key];
    if ([val isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in (NSArray *)val) {
            NSString *s = dov_stringValue(item);
            if (s.length) [out addObject:s];
        }
        return out;
    }
    if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 0) {
        return @[ (NSString *)val ];
    }
    return @[];
}

static NSDictionary<NSString *, NSString *> *dov_groupsFromLS(NSString *bundleID) {
    if (bundleID.length == 0) return @{};
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = dov_safePerform((id)workspaceClass, NSSelectorFromString(@"defaultWorkspace"));
    id proxy = dov_safePerform1(workspace, NSSelectorFromString(@"applicationProxyForIdentifier:"), bundleID);
    if (!proxy) return @{};
    NSDictionary *groups = dov_safePerform(proxy, NSSelectorFromString(@"groupContainerURLs"));
    if (![groups isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *mapped = [NSMutableDictionary dictionary];
    [groups enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        mapped[dov_stringValue(key)] = dov_normalizePath(dov_stringValue(obj));
    }];
    return mapped;
}

NSDictionary<NSString *, NSString *> *DOVCopyGroupContainersForBundleID(NSString *bundleID) {
    NSDictionary *info = DOVResolveAppGroupInfo(bundleID, nil);
    NSDictionary *containers = info[@"containers"];
    if ([containers isKindOfClass:[NSDictionary class]] && containers.count > 0) {
        return containers;
    }
    return nil;
}

NSDictionary<NSString *, id> *DOVResolveAppGroupInfo(NSString *bundleID, NSString *bundlePath) {
    NSMutableDictionary *containers = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *declared = [NSMutableArray array];
    BOOL entsReadable = NO;

    NSDictionary *fromLS = dov_groupsFromLS(bundleID);
    [containers addEntriesFromDictionary:fromLS];
    for (NSString *gid in fromLS) {
        if (![declared containsObject:gid]) [declared addObject:gid];
    }

    NSString *exec = dov_executablePath(bundlePath ?: @"", nil);
    NSDictionary *ents = dov_entitlementsForExecutable(exec);
    if (ents) {
        entsReadable = YES;
        NSArray *groups = dov_stringArrayFromEntitlement(ents, @"com.apple.security.application-groups");
        for (NSString *gid in groups) {
            if (![declared containsObject:gid]) [declared addObject:gid];
        }
    }

    NSDictionary *mcm = dov_buildSharedAppGroupIndex();
    for (NSString *gid in declared) {
        NSString *existing = containers[gid];
        if ([existing isKindOfClass:[NSString class]] && existing.length > 0) continue;
        NSString *path = mcm[gid];
        if (path.length) containers[gid] = path;
    }

    // Heuristic: if nothing declared but we know bundleID, pick groups that share the same reverse-DNS stem.
    // Only when entitlements were unreadable — avoid inventing groups for apps that truly have none.
    if (declared.count == 0 && !entsReadable && bundleID.length > 0) {
        NSString *stem = bundleID;
        NSArray *parts = [bundleID componentsSeparatedByString:@"."];
        if (parts.count >= 2) {
            stem = [[parts subarrayWithRange:NSMakeRange(0, MIN(parts.count, 3))] componentsJoinedByString:@"."];
        }
        [mcm enumerateKeysAndObjectsUsingBlock:^(NSString *gid, NSString *path, BOOL *stop) {
#pragma unused(stop)
            if ([gid containsString:stem] || [gid containsString:bundleID]) {
                containers[gid] = path;
                if (![declared containsObject:gid]) [declared addObject:gid];
            }
        }];
    }

    return @{
        @"containers": [containers copy],
        @"declaredGroups": [declared copy],
        @"entitlementsReadable": @(entsReadable)
    };
}

NSArray<NSDictionary *> *DOVCopyExtensionContainersForAppBundle(NSString *appBundlePath) {
    if (appBundlePath.length == 0) return @[];
    NSString *appPath = dov_normalizePath(appBundlePath);
    if (![appPath.pathExtension.lowercaseString isEqualToString:@"app"]) {
        NSArray *kids = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:nil];
        for (NSString *k in kids) {
            if ([k.pathExtension.lowercaseString isEqualToString:@"app"]) {
                appPath = [appPath stringByAppendingPathComponent:k];
                break;
            }
        }
    }

    NSString *plugins = [appPath stringByAppendingPathComponent:@"PlugIns"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:plugins error:nil];
    if (items.count == 0) return @[];

    NSDictionary *pluginIndex = dov_buildPluginKitDataIndex();
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in items) {
        if (![name.pathExtension.lowercaseString isEqualToString:@"appex"]) continue;
        NSString *appexPath = [plugins stringByAppendingPathComponent:name];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appexPath stringByAppendingPathComponent:@"Info.plist"]];
        NSString *bid = info[@"CFBundleIdentifier"];
        if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;
        NSString *display = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bid;
        NSString *dataPath = pluginIndex[bid] ?: @"";
        [out addObject:@{
            @"bundleID": bid,
            @"name": display,
            @"appexPath": appexPath,
            @"dataPath": dataPath
        }];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [dov_stringValue(a[@"name"]) localizedCaseInsensitiveCompare:dov_stringValue(b[@"name"])];
    }];
    return out;
}

NSArray<NSString *> *DOVCopyMobileDocumentsPathsForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return @[];
    NSString *tildeID = [bundleID stringByReplacingOccurrencesOfString:@"." withString:@"~"];
    NSArray *roots = @[
        @"/var/mobile/Library/Mobile Documents",
        @"/private/var/mobile/Library/Mobile Documents"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *hits = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *root in roots) {
        NSArray *kids = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *name in kids) {
            NSString *lower = name.lowercaseString;
            NSString *needle = tildeID.lowercaseString;
            BOOL match =
                [lower isEqualToString:needle] ||
                [lower hasSuffix:[@"~" stringByAppendingString:needle]] ||
                [lower hasPrefix:[@"icloud~" stringByAppendingString:needle]] ||
                [lower containsString:needle];
            if (!match) continue;
            NSString *path = dov_normalizePath([root stringByAppendingPathComponent:name]);
            if ([seen containsObject:path]) continue;
            [seen addObject:path];
            [hits addObject:path];
        }
    }
    return hits;
}

NSArray<NSString *> *DOVCopyKeychainAccessGroups(NSString *bundlePath, NSString *executableName) {
    NSString *exec = dov_executablePath(bundlePath ?: @"", executableName);
    NSDictionary *ents = dov_entitlementsForExecutable(exec);
    if (!ents) return @[];
    NSArray *groups = dov_stringArrayFromEntitlement(ents, @"keychain-access-groups");
    if (groups.count == 0) {
        // application-identifier is often the default keychain access group.
        NSString *appID = dov_stringValue(ents[@"application-identifier"]);
        if (appID.length) return @[appID];
    }
    return groups;
}

NSString *DOVResolveDataContainerPath(NSString *bundleID, NSString *bundlePath) {
#pragma unused(bundlePath)
    if (!g_dovDataIndex) {
        g_dovDataIndex = dov_buildDataContainerIndex();
    }
    NSString *byMeta = dov_lookupDataByBundleID(bundleID);
    if (byMeta.length) return byMeta;

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = dov_safePerform((id)workspaceClass, NSSelectorFromString(@"defaultWorkspace"));
    id proxy = nil;
    if (bundleID.length) {
        proxy = dov_safePerform1(workspace, NSSelectorFromString(@"applicationProxyForIdentifier:"), bundleID);
    }
    return dov_resolveDataPath(proxy, bundleID, bundlePath ?: @"");
}

NSData *DOVIconDataForBundleID(NSString *bundleID, NSString *bundlePath) {
    NSData *icon = dov_iconViaPrivateUIImage(bundleID);
    if (!icon) icon = dov_iconFromBundlePath(bundlePath);
    return icon;
}

NSDictionary<NSString *, id> *DOVCopyEntitlementsForApp(NSString *bundlePath, NSString *executableName) {
    NSString *exec = dov_executablePath(bundlePath ?: @"", executableName);
    return dov_entitlementsForExecutable(exec);
}
