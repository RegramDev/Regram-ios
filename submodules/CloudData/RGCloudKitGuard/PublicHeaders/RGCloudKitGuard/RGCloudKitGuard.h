#import <Foundation/Foundation.h>

@class CKContainer;

NS_ASSUME_NONNULL_BEGIN

/// Gatekeeper for CloudKit. `+[CKContainer defaultContainer]` terminates the process when the
/// container declared in the entitlements was never provisioned for the signing team — the normal
/// state of a re-signed build — and it does so from inside a dispatch_once, where the exception
/// cannot be caught. The only safe strategy is to consult the embedded provisioning profile first
/// and never make the call when the container is not actually provisioned.
@interface RGCloudKitGuard : NSObject

/// Whether the embedded provisioning profile provisions this app's iCloud container (or there is no
/// embedded profile at all, i.e. a store build). Cached after the first call.
+ (BOOL)isCloudKitProvisioned;

/// The default container, or nil when CloudKit is unusable in this signing environment.
+ (nullable CKContainer *)defaultContainer;

@end

NS_ASSUME_NONNULL_END
