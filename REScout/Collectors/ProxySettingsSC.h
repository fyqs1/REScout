#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Apply Proxies onto one or more NetworkServices UUIDs via SCPreferences when possible.
/// `services` values are NSDictionary (Proxies payload to merge / replace under that UUID).
/// Returns nil on success, or an error description.
NSString * _Nullable DOVApplyNetworkServiceProxies(NSDictionary<NSString *, NSDictionary *> *serviceProxies,
                                                   BOOL enabled);

NS_ASSUME_NONNULL_END
