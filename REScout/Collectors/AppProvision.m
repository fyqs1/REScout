#import "AppProvision.h"

static NSData *dov_extract_plist_blob(NSData *raw) {
    if (raw.length < 16) return nil;
    const uint8_t *bytes = raw.bytes;
    NSUInteger len = raw.length;
    // Prefer XML plist markers inside CMS blob.
    NSData *startTag = [@"<?xml" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *endTag = [@"</plist>" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange start = [raw rangeOfData:startTag options:0 range:NSMakeRange(0, len)];
    if (start.location == NSNotFound) {
        // Binary plist magic "bplist"
        NSData *bp = [@"bplist" dataUsingEncoding:NSASCIIStringEncoding];
        NSRange bpr = [raw rangeOfData:bp options:0 range:NSMakeRange(0, len)];
        if (bpr.location == NSNotFound) return nil;
        // Take from bplist to end (CMS may have trailing junk — PropertyListSerialization often still works).
        return [raw subdataWithRange:NSMakeRange(bpr.location, len - bpr.location)];
    }
    NSRange search = NSMakeRange(start.location, len - start.location);
    NSRange end = [raw rangeOfData:endTag options:0 range:search];
    if (end.location == NSNotFound) return nil;
    NSUInteger endPos = end.location + end.length;
    return [raw subdataWithRange:NSMakeRange(start.location, endPos - start.location)];
}

static NSString *dov_string(id v) {
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    if ([v isKindOfClass:[NSDate class]]) {
        return [NSISO8601DateFormatter.new stringFromDate:(NSDate *)v] ?: @"";
    }
    return @"";
}

NSDictionary<NSString *, id> *DOVCopyMobileProvisionSummary(NSString *appBundlePath) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"path"] = @"";
    out[@"exists"] = @NO;
    out[@"name"] = @"";
    out[@"teamName"] = @"";
    out[@"teamIdentifier"] = @"";
    out[@"appIDName"] = @"";
    out[@"uuid"] = @"";
    out[@"creationDate"] = @"";
    out[@"expirationDate"] = @"";
    out[@"platforms"] = @[];
    out[@"entitlements"] = @{};

    if (appBundlePath.length == 0) {
        out[@"error"] = @"empty bundle path";
        return out;
    }
    NSString *provPath = [appBundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    out[@"path"] = provPath;
    NSData *raw = [NSData dataWithContentsOfFile:provPath];
    if (!raw.length) {
        out[@"error"] = @"missing or unreadable";
        return out;
    }
    out[@"exists"] = @YES;

    NSData *plistData = dov_extract_plist_blob(raw);
    if (!plistData.length) {
        out[@"error"] = @"plist not found in provision";
        return out;
    }

    NSError *err = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:plistData
                                                       options:NSPropertyListImmutable
                                                        format:nil
                                                         error:&err];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        out[@"error"] = err.localizedDescription ?: @"plist parse failed";
        return out;
    }
    NSDictionary *prov = (NSDictionary *)obj;
    out[@"name"] = dov_string(prov[@"Name"]);
    out[@"teamName"] = dov_string(prov[@"TeamName"]);
    out[@"appIDName"] = dov_string(prov[@"AppIDName"]);
    out[@"uuid"] = dov_string(prov[@"UUID"]);
    out[@"creationDate"] = dov_string(prov[@"CreationDate"]);
    out[@"expirationDate"] = dov_string(prov[@"ExpirationDate"]);

    id teams = prov[@"TeamIdentifier"];
    if ([teams isKindOfClass:[NSArray class]] && [(NSArray *)teams count] > 0) {
        out[@"teamIdentifier"] = dov_string([(NSArray *)teams firstObject]);
    } else {
        out[@"teamIdentifier"] = dov_string(teams);
    }
    if ([prov[@"Platform"] isKindOfClass:[NSArray class]]) {
        out[@"platforms"] = prov[@"Platform"];
    }
    if ([prov[@"Entitlements"] isKindOfClass:[NSDictionary class]]) {
        out[@"entitlements"] = prov[@"Entitlements"];
    }
    return out;
}
