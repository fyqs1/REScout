#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Running processes similar to `frida-ps -Ua` (user apps with UI when possible).
/// Keys: pid (NSNumber), name, path, bundleID, isApple
NSArray<NSDictionary *> *DOVCopyRunningApplications(void);

NS_ASSUME_NONNULL_END
