// Synthetic identities only; never load production signing credentials.
#import <Foundation/Foundation.h>
#import <ZipArchive/ZipArchive.h>
#import "RGUpdateSigner.h"
#include "bundle.h"
int main(int argc, char**argv) { @autoreleasepool {
 NSString *root=[NSString stringWithUTF8String:argv[2]];
 if (strcmp(argv[1],"initial")==0) {
  ZLog::SetLogLever(ZLog::E_NONE); std::list<ZSignAsset> assets;
  NSArray *profilePaths=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:@"profiles"] error:nil] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString*name in profilePaths) { if (![name hasSuffix:@".mobileprovision"]) continue; assets.emplace_back();
   NSString *entitlementPath=[root stringByAppendingPathComponent:[@"profiles/" stringByAppendingString:[[name stringByDeletingPathExtension] stringByAppendingString:@".entitlements.plist"]]];
   if (!assets.back().Init("", [[root stringByAppendingPathComponent:@"identity.p12"] UTF8String], [[root stringByAppendingPathComponent:[@"profiles/" stringByAppendingString:name]] UTF8String], entitlementPath.UTF8String, "fixture", false,false,false)) return 2;
  }
  ZBundle bundle;return bundle.SignFolder(&assets,[[root stringByAppendingPathComponent:@"installed/Regram.app"] UTF8String],"","","",{},{},true,false,false)?0:3;
 }
 NSData *p12=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"identity.p12"]]; NSString*installed=[root stringByAppendingPathComponent:@"installed/Regram.app"];NSError*error=nil;
 NSString *name=[RGUpdateSigner validateCertificate:p12 password:@"fixture" installedApp:installed error:&error]; if(!name||error){NSLog(@"certificate failure %@",error);return 4;}
 error=nil; if ([RGUpdateSigner validateCertificate:p12 password:@"wrong" installedApp:installed error:&error] || error.code!=1) return 5;
 error=nil;
 NSArray<NSData *> *automatic=[RGUpdateSigner installedProfiles:installed certificate:p12 password:@"fixture" error:&error];
 if (automatic.count!=7 || error) return 20;
 if (strcmp(argv[1],"legacy")==0) {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSString *parent=[root stringByAppendingPathComponent:@"installed-legacy"];
  if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&error]) return 21;
  NSString *legacy=[parent stringByAppendingPathComponent:@"Regram.app"];
  if (![fm copyItemAtPath:installed toPath:legacy error:&error]) return 22;
  std::list<ZSignAsset> assets;
  for (NSUInteger index=0;index<7;index++) {
   NSString *bundle=index==0?legacy:[legacy stringByAppendingPathComponent:[NSString stringWithFormat:@"PlugIns/Ext%lu.appex",(unsigned long)index]];
   NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]];
   NSString *suffix=index==0?@"":[NSString stringWithFormat:@".Ext%lu",(unsigned long)index];
   NSMutableDictionary *ent=[[NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:[NSString stringWithFormat:@"profiles/%lu.entitlements.plist",(unsigned long)index]]] mutableCopy];
   ent[@"application-identifier"]=[@"TESTTEAM01.com.legacy.Regram" stringByAppendingString:suffix];
   NSString *path=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"legacy-%lu.entitlements.plist",(unsigned long)index]];
   if (![ent writeToFile:path atomically:YES]) return 23;
   assets.emplace_back();
   if (!assets.back().Init("",[[root stringByAppendingPathComponent:@"identity.p12"] UTF8String],[[root stringByAppendingPathComponent:@"variants/universal.mobileprovision"] UTF8String],path.UTF8String,"fixture",false,false,false)) return 24;
   assets.back().m_strApplicationId=[info[@"CFBundleIdentifier"] UTF8String];
  }
  ZBundle signer;
  if (!signer.SignFolder(&assets,legacy.UTF8String,"","","",{},{},true,false,false)) return 25;
  error=nil;
  if ([[RGUpdateSigner installedProfiles:legacy certificate:p12 password:@"fixture" error:&error] count]!=1 || error) return 26;
  if (![RGUpdateSigner prepareIPA:[root stringByAppendingPathComponent:@"new.ipa"] output:[root stringByAppendingPathComponent:@"legacy-updated.ipa"] installedApp:legacy certificate:p12 password:@"fixture" profiles:@[] expectedVersion:@"13.0" expectedBuild:@"34591" error:&error] || error) return 27;
  puts("Automatic profile binding and independent installed application identifiers passed for all seven bundles.");
  return 0;
 }
 if (strcmp(argv[1],"profiles")==0) {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSMutableArray<NSString *> *paths=[NSMutableArray arrayWithObject:[installed stringByAppendingPathComponent:@"embedded.mobileprovision"]];
  for (NSString *relative in [fm enumeratorAtPath:installed]) {
   if ([relative.lastPathComponent isEqual:@"embedded.mobileprovision"] && ![relative isEqual:@"embedded.mobileprovision"]) [paths addObject:[installed stringByAppendingPathComponent:relative]];
  }
  NSMutableArray<NSData *> *imports=[NSMutableArray new];
  for (NSString *path in paths) { [imports addObject:[NSData dataWithContentsOfFile:path]]; [fm moveItemAtPath:path toPath:[path stringByAppendingString:@".fixture-backup"] error:nil]; }
  error=nil;
  if (![RGUpdateSigner validateProfiles:imports error:&error] || error) return 10;
  error=nil;
  if (![RGUpdateSigner validateInstalledApp:installed certificate:p12 password:@"fixture" profiles:imports error:&error] || error) return 11;
  NSData *universal=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"variants/universal.mobileprovision"]];
  error=nil;
  if (![RGUpdateSigner prepareIPA:[root stringByAppendingPathComponent:@"new.ipa"] output:[root stringByAppendingPathComponent:@"universal.ipa"] installedApp:installed certificate:p12 password:@"fixture" profiles:@[universal] expectedVersion:@"13.0" expectedBuild:@"34591" error:&error] || error) return 12;
  for (NSString *reason in @[@"missing",@"unreadable",@"expired",@"certificate",@"applicationIdentifier",@"entitlement"]) {
   NSArray *input=@[];
   if ([reason isEqual:@"unreadable"]) input=@[[NSData dataWithBytes:"bad" length:3]];
   else if (![reason isEqual:@"missing"]) input=@[[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:[NSString stringWithFormat:@"variants/%@.mobileprovision",reason]]]];
   error=nil;
   if ([RGUpdateSigner validateInstalledApp:installed certificate:p12 password:@"fixture" profiles:input error:&error] || error.code!=3 || ![error.userInfo[@"profileReason"] isEqual:reason] || ![error.userInfo[@"bundleName"] isEqual:@"Regram.app"]) return 13;
   if ([reason isEqual:@"entitlement"] && ![error.userInfo[@"entitlement"] isEqual:@"com.apple.developer.icloud-container-environment"]) return 14;
  }
  error=nil;
  NSData *expired=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"variants/expired.mobileprovision"]];
  if ([RGUpdateSigner validateProfiles:@[expired] error:&error] || ![error.userInfo[@"profileReason"] isEqual:@"expired"]) return 15;
  // A main-app-only profile cannot cover the first extension. Report its name.
  error=nil;
  NSData *main=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"profiles/0.mobileprovision"]];
  if ([RGUpdateSigner validateInstalledApp:installed certificate:p12 password:@"fixture" profiles:@[main] error:&error] || ![error.userInfo[@"bundleName"] isEqual:@"PlugIns/Ext1.appex"] || ![error.userInfo[@"profileReason"] isEqual:@"applicationIdentifier"]) return 16;
  for (NSString *path in paths) [fm moveItemAtPath:[path stringByAppendingString:@".fixture-backup"] toPath:path error:nil];
  puts("Provisioning checks passed: imported profiles, one wildcard for seven bundles, scalar/list/wildcard permissions and bundle-specific failure reasons.");
  return 0;
 }
 error=nil; NSString *output=[root stringByAppendingPathComponent:@"updated.ipa"];
 BOOL ok=[RGUpdateSigner prepareIPA:[root stringByAppendingPathComponent:@"new.ipa"] output:output installedApp:installed certificate:p12 password:@"fixture" profiles:@[] expectedVersion:@"13.0" expectedBuild:@"34591" error:&error];
 if(!ok||error){NSLog(@"signing failure %@",error);return 6;}
 error=nil;
 if (![RGUpdateSigner validateTrollStoreIPA:output installedApp:installed expectedVersion:@"13.0" expectedBuild:@"34591" error:&error] || error) return 30;
 error=nil;
 if ([RGUpdateSigner validateTrollStoreIPA:[root stringByAppendingPathComponent:@"new.ipa"] installedApp:installed expectedVersion:@"13.0" expectedBuild:@"34591" error:&error] || error.code!=5) return 31;
 error=nil;
 if ([RGUpdateSigner validateTrollStoreIPA:output installedApp:installed expectedVersion:@"13.0" expectedBuild:@"99999" error:&error] || error.code!=5) return 32;
 NSFileManager *fm=NSFileManager.defaultManager;
 NSString *mismatch=[root stringByAppendingPathComponent:@"trollstore-mismatch"];
 if (![SSZipArchive unzipFileAtPath:output toDestination:mismatch]) return 33;
 NSString *plist=[mismatch stringByAppendingPathComponent:@"Payload/Regram.app/Info.plist"];
 NSMutableDictionary *info=[[NSDictionary dictionaryWithContentsOfFile:plist] mutableCopy];
 info[@"TelegramApplicationGroupIdentifier"]=@"group.com.other.App";
 if (![info writeToFile:plist atomically:YES]) return 34;
 NSString *wrongGroup=[root stringByAppendingPathComponent:@"wrong-group.ipa"];
 if (![SSZipArchive createZipFileAtPath:wrongGroup withContentsOfDirectory:mismatch]) return 35;
 error=nil;
 if ([RGUpdateSigner validateTrollStoreIPA:wrongGroup installedApp:installed expectedVersion:@"13.0" expectedBuild:@"34591" error:&error] || error.code!=5) return 36;
 puts("TrollStore archive checks passed: seven bundle identities, version, entitlements and app-group mismatch rejection without a certificate.");
 error=nil; ok=[RGUpdateSigner prepareIPA:[root stringByAppendingPathComponent:@"new.ipa"] output:[root stringByAppendingPathComponent:@"wrong-version.ipa"] installedApp:installed certificate:p12 password:@"fixture" profiles:@[] expectedVersion:@"13.0" expectedBuild:@"99999" error:&error];
 if(ok||error.code!=5) return 7;
 puts("Certificate and multi-extension signing checks passed; wrong password/build rejected.");return 0;
}}
