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
   if (!assets.back().Init("", [[root stringByAppendingPathComponent:@"identity.p12"] UTF8String], [[root stringByAppendingPathComponent:[@"profiles/" stringByAppendingString:name]] UTF8String], "", "fixture", false,false,false)) return 2;
  }
  ZBundle bundle;return bundle.SignFolder(&assets,[[root stringByAppendingPathComponent:@"installed/Regram.app"] UTF8String],"","","",{},{},true,false,false)?0:3;
 }
 NSData *p12=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"identity.p12"]]; NSString*installed=[root stringByAppendingPathComponent:@"installed/Regram.app"];NSError*error=nil;
 NSString *name=[RGUpdateSigner validateCertificate:p12 password:@"fixture" installedApp:installed error:&error]; if(!name||error){NSLog(@"certificate failure %@",error);return 4;}
 error=nil; if ([RGUpdateSigner validateCertificate:p12 password:@"wrong" installedApp:installed error:&error] || error.code!=1) return 5;
 error=nil; NSString *output=[root stringByAppendingPathComponent:@"updated.ipa"];
 BOOL ok=[RGUpdateSigner prepareIPA:[root stringByAppendingPathComponent:@"new.ipa"] output:output installedApp:installed certificate:p12 password:@"fixture" profiles:@[] expectedVersion:@"13.0" expectedBuild:@"34591" error:&error];
 if(!ok||error){NSLog(@"signing failure %@",error);return 6;}
 error=nil; ok=[RGUpdateSigner prepareIPA:[root stringByAppendingPathComponent:@"new.ipa"] output:[root stringByAppendingPathComponent:@"wrong-version.ipa"] installedApp:installed certificate:p12 password:@"fixture" profiles:@[] expectedVersion:@"13.0" expectedBuild:@"99999" error:&error];
 if(ok||error.code!=5) return 7;
 puts("Certificate and multi-extension signing checks passed; wrong password/build rejected.");return 0;
}}
