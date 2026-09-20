#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Write bytes as root. Returns nil on success.
NSString * _Nullable DOVWriteDataToPathAsRoot(NSData *data, NSString *path);

/// Run `kill -9 <pid>` (direct then sudo). Returns nil on success.
NSString * _Nullable DOVKillPID(int pid);

/// Run `killall -9 <name>` (direct then sudo). Returns nil on success.
NSString * _Nullable DOVKillallName(NSString *name);

NS_ASSUME_NONNULL_END
