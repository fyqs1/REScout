#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Parse embedded.mobileprovision (CMS-wrapped plist) into a flat dictionary of useful fields.
/// Keys: path, exists, name, teamName, teamIdentifier, appIDName, uuid, creationDate, expirationDate,
///       platforms (NSArray), entitlements (NSDictionary), error
NSDictionary<NSString *, id> *DOVCopyMobileProvisionSummary(NSString * _Nullable appBundlePath);

NS_ASSUME_NONNULL_END
