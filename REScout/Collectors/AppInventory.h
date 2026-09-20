#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns an array of dictionaries describing installed applications.
/// Keys: bundleID, name, version, build, bundlePath, bundleContainerPath,
/// type, role, isSystem, executable, minimumOS, teamID.
/// dataPath / groupContainers / iconData are resolved on the detail screen.
NSArray<NSDictionary *> *DOVCopyInstalledApplications(void);

NSDictionary<NSString *, NSString *> * _Nullable DOVCopyGroupContainersForBundleID(NSString *bundleID);

/// Resolve App Groups via LS + entitlements + Shared/AppGroup MCM index.
/// Returns @{ @"containers": @{ groupID: path }, @"declaredGroups": @[groupID], @"entitlementsReadable": @YES/@NO }
NSDictionary<NSString *, id> *DOVResolveAppGroupInfo(NSString * _Nullable bundleID, NSString * _Nullable bundlePath);

/// PlugIns/*.appex → PluginKitPlugin data containers.
/// Each item: bundleID, name, appexPath, dataPath
NSArray<NSDictionary *> *DOVCopyExtensionContainersForAppBundle(NSString * _Nullable appBundlePath);

/// iCloud / Mobile Documents folders that match this bundle id (may be empty).
NSArray<NSString *> *DOVCopyMobileDocumentsPathsForBundleID(NSString * _Nullable bundleID);

/// Keychain access groups from code signature entitlements (may be empty).
NSArray<NSString *> *DOVCopyKeychainAccessGroups(NSString * _Nullable bundlePath, NSString * _Nullable executableName);

/// Resolve data container path for bundle (proxy + MCM metadata index).
NSString *DOVResolveDataContainerPath(NSString * _Nullable bundleID, NSString * _Nullable bundlePath);

/// Best-effort icon PNG data (private UIImage API + CgBI-safe file read).
NSData * _Nullable DOVIconDataForBundleID(NSString * _Nullable bundleID, NSString * _Nullable bundlePath);

/// Full entitlements dictionary for the app executable (may be nil).
NSDictionary<NSString *, id> * _Nullable DOVCopyEntitlementsForApp(NSString * _Nullable bundlePath, NSString * _Nullable executableName);

NS_ASSUME_NONNULL_END
