#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Device-side Mach-O gate for RE intake (cryptid / arch / UUID).
/// Keys: path, exists, cryptid, encrypted, architectures (NSArray), uuid, sliceCount, error
NSDictionary<NSString *, id> *DOVCopyMachOGate(NSString * _Nullable executablePath);

NS_ASSUME_NONNULL_END
