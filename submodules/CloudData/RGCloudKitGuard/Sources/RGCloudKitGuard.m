#import <RGCloudKitGuard/RGCloudKitGuard.h>

#import <CloudKit/CloudKit.h>

/// Reads the entitlements dictionary out of the app's embedded provisioning profile (a CMS blob with
/// the plist as payload). Returns nil when no profile can be read at all.
static NSDictionary * _Nullable rgEmbeddedProfileEntitlements(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
    NSData *data = path != nil ? [NSData dataWithContentsOfFile:path] : nil;
    if (data == nil) {
        // `pathForResource:` can miss when a re-signing tool rewrites the bundle layout, so try the
        // canonical location directly before concluding there is no profile.
        NSString *direct = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"embedded.mobileprovision"];
        data = [NSData dataWithContentsOfFile:direct];
    }
    if (data == nil) {
        return nil;
    }
    // The CMS wrapper is not a plist; find the XML plist embedded in it.
    NSData *start = [@"<?xml" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *end = [@"</plist>" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange startRange = [data rangeOfData:start options:0 range:NSMakeRange(0, data.length)];
    if (startRange.location == NSNotFound) {
        return nil;
    }
    NSRange endRange = [data rangeOfData:end options:0 range:NSMakeRange(startRange.location, data.length - startRange.location)];
    if (endRange.location == NSNotFound) {
        return nil;
    }
    NSData *plistData = [data subdataWithRange:NSMakeRange(startRange.location, NSMaxRange(endRange) - startRange.location)];
    NSDictionary *profile = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:nil error:nil];
    if (![profile isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *entitlements = profile[@"Entitlements"];
    return [entitlements isKindOfClass:[NSDictionary class]] ? entitlements : nil;
}

@implementation RGCloudKitGuard

+ (BOOL)isCloudKitProvisioned {
    static BOOL provisioned = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *entitlements = rgEmbeddedProfileEntitlements();
        if (entitlements == nil) {
            // No profile at all. This used to assume a store-distributed build and allow CloudKit,
            // which is what turned a missing profile into a process abort: an IPA distributed
            // unsigned has no profile, and a tool that ad-hoc signs it does not add one, so the
            // check passed and +[CKContainer defaultContainer] terminated the app on first use.
            //
            // A store build is identifiable by its receipt sitting in the bundle, so require that
            // rather than inferring it from the absence of evidence — the unknown case has to fail
            // closed, since guessing wrong costs the whole process.
            NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
            provisioned = receiptUrl != nil && [[NSFileManager defaultManager] fileExistsAtPath:receiptUrl.path];
            return;
        }
        // The profile must actually list a container. A re-signing profile typically carries
        // `icloud-services = *` (so the entitlement key is accepted at signing time) while its
        // `icloud-container-identifiers` is empty — that is precisely the state in which
        // +[CKContainer defaultContainer] terminates the process.
        NSArray *containers = entitlements[@"com.apple.developer.icloud-container-identifiers"];
        if (![containers isKindOfClass:[NSArray class]] || containers.count == 0) {
            provisioned = NO;
            return;
        }
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *expected = [@"iCloud." stringByAppendingString:bundleId];
        for (id item in containers) {
            if ([item isKindOfClass:[NSString class]] && ([item isEqualToString:expected] || [item isEqualToString:@"*"])) {
                provisioned = YES;
                return;
            }
        }
        provisioned = NO;
    });
    return provisioned;
}

+ (nullable CKContainer *)defaultContainer {
    // +[CKContainer defaultContainer] raises from inside its own dispatch_once when the declared
    // container is not provisioned. Because dispatch's client callout is noexcept, that exception
    // is turned into std::terminate before it can reach any @catch, so it must be avoided rather
    // than caught.
    if (![self isCloudKitProvisioned]) {
        return nil;
    }
    static CKContainer *container = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        container = [CKContainer defaultContainer];
    });
    return container;
}

@end
