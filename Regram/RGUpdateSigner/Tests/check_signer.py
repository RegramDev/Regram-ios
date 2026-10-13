#!/usr/bin/env python3
"""Offline signer checks with a freshly generated synthetic CA/P12 and seven bundles."""
import subprocess,os,argparse,platform
from pathlib import Path
root=Path(__file__).resolve().parents[3]
task=root/'build-input/update-signer-checks';task.mkdir(parents=True,exist_ok=True)
build=task/'host-signer';build.mkdir(exist_ok=True)
env=dict(os.environ)
parser=argparse.ArgumentParser()
parser.add_argument('--crypto-directory',type=Path)
args=parser.parse_args()
crypto=args.crypto_directory.resolve() if args.crypto_directory else task/'private-crypto'
if not (crypto/'libRGUpdateCrypto.a').is_file():
 subprocess.run(['python3',str(root/'Regram/RGUpdateOpenSSL/build_private_crypto.py'),'--symbols',str(root/'Regram/RGUpdateOpenSSL/symbols.txt'),'--archive',str(root/'submodules/openssl/openssl-1.1.1d.tar.gz'),'--builder',str(root/'submodules/openssl/build-openssl-bazel.sh'),'--configuration-patch',str(root/'submodules/openssl/patch-conf.patch'),'--header-patch',str(root/'submodules/openssl/patch-include.patch'),'--cpu','darwin_arm64' if platform.machine()=='arm64' else 'darwin_x86_64','--output',str(crypto)],env=env,check=True)
flags=['-I'+str(root/'Regram/RGUpdateSigner/Public'),'-I'+str(root/'Regram/RGUpdateSigner/Vendor/zsign'),'-I'+str(root/'Regram/RGUpdateSigner/Vendor/zsign/common'),'-I'+str(root/'third-party/ZipArchive/PublicHeaders'),'-I'+str(crypto/'Public')]
sources=list((root/'Regram/RGUpdateSigner/Vendor/zsign').glob('*.cpp'))+list((root/'Regram/RGUpdateSigner/Vendor/zsign/common').glob('*.cpp'))+list((root/'third-party/ZipArchive/Sources/minizip').glob('*.c'))+[root/'third-party/ZipArchive/Sources/SSZipArchive.m',root/'Regram/RGUpdateSigner/Sources/RGUpdateSigner.mm']
objects=[]
for n,p in enumerate(sources):
 out=build/f'{n}.o';cmd=['xcrun','clang++' if p.suffix in ('.cpp','.mm') else 'clang','-O1','-Wno-deprecated-declarations','-Wno-incompatible-pointer-types']+flags
 if p.suffix in ('.cpp','.mm'):cmd+=['-std=c++17']
 if p.suffix in ('.m','.mm'):cmd+=['-fobjc-arc']
 cmd+=['-DHAVE_ZLIB','-DHAVE_INTTYPES_H','-DHAVE_PKCRYPT','-DHAVE_STDINT_H','-DHAVE_WZAES','-c',str(p),'-o',str(out)]
 r=subprocess.run(cmd,env=env,capture_output=True)
 if r.returncode:
  print(p,r.stderr.decode()[-4000:]);raise SystemExit(r.returncode)
 objects.append(str(out))
subprocess.run(['ar','rcs',str(build/'libRGHostSigner.a')]+objects,check=True)
(task/'host-signer-flags.txt').write_text('\n'.join(flags))
print('Host signer library built')

libs=[str(crypto/'libRGUpdateCrypto.a')]
subprocess.run(['xcrun','clang++','-std=c++17','-fobjc-arc','-Wno-deprecated-declarations']+flags+[str(root/'Regram/RGUpdateSigner/Tests/SignerFixtureTests.mm'),str(build/'libRGHostSigner.a'),'-framework','Foundation','-framework','Security','-lz']+libs+['-o',str(task/'signer-fixture')],env=env,check=True)

import plistlib,datetime,shutil,zipfile,struct,hashlib
openssl_prefix=subprocess.check_output(['pkg-config','--variable=prefix','openssl'],text=True).strip()
openssl=str(Path(openssl_prefix)/'bin/openssl')
dest=task/'fixture'
if dest.exists():shutil.rmtree(dest)
dest.mkdir()
def run(args):
 r=subprocess.run(args,env=env,capture_output=True)
 if r.returncode:raise RuntimeError(str(r.returncode)+' '+r.stdout.decode()[-1500:]+' '+r.stderr.decode()[-2000:])
run([openssl,'req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(dest/'ca-key.pem'),'-out',str(dest/'ca.pem'),'-subj','/CN=Regram Update Fixture CA','-days','1'])
run([openssl,'req','-new','-newkey','rsa:2048','-nodes','-keyout',str(dest/'key.pem'),'-out',str(dest/'cert.csr'),'-subj','/CN=Regram Update Fixture/OU=TESTTEAM01'])
run([openssl,'x509','-req','-in',str(dest/'cert.csr'),'-CA',str(dest/'ca.pem'),'-CAkey',str(dest/'ca-key.pem'),'-CAcreateserial','-out',str(dest/'cert.pem'),'-days','1'])
run([openssl,'x509','-in',str(dest/'cert.pem'),'-outform','DER','-out',str(dest/'cert.der')])
run([openssl,'pkcs12','-export','-inkey',str(dest/'key.pem'),'-in',str(dest/'cert.pem'),'-certfile',str(dest/'ca.pem'),'-passout','pass:fixture','-out',str(dest/'identity.p12')])
(dest/'main.c').write_text('int main() { return 0; }\n')
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],env=env,text=True).strip()
run(['xcrun','clang','-target','arm64-apple-ios15.0','-isysroot',sdk,str(dest/'main.c'),'-o',str(dest/'Fixture')])
now=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
(dest/'profiles').mkdir(exist_ok=True)
for index in range(7):
 suffix='' if index==0 else f'.Ext{index}'; bundle_id='com.example.Regram'+suffix
 ent={'application-identifier':'TESTTEAM01.'+bundle_id,'com.apple.developer.team-identifier':'TESTTEAM01','keychain-access-groups':['TESTTEAM01.com.example.Regram'],'com.apple.security.application-groups':['group.com.example.Regram'],'get-task-allow':False,'com.apple.developer.icloud-container-environment':'Production','com.apple.developer.icloud-services':['CloudKit']}
 allowed=dict(ent,**{'keychain-access-groups':['TESTTEAM01.*'],'com.apple.developer.icloud-container-environment':['Development','Production'],'com.apple.developer.icloud-services':'*'})
 profile={'Entitlements':allowed,'TeamIdentifier':['TESTTEAM01'],'ExpirationDate':now+datetime.timedelta(days=1),'DeveloperCertificates':[(dest/'cert.der').read_bytes()],'ProvisionsAllDevices':True,'Name':'Synthetic Regram update check'}
 (dest/'profiles'/f'{index}.entitlements.plist').write_bytes(plistlib.dumps(ent))
 path=dest/'profiles'/f'{index}.plist';path.write_bytes(plistlib.dumps(profile))
 run([openssl,'cms','-sign','-binary','-in',str(path),'-signer',str(dest/'cert.pem'),'-inkey',str(dest/'key.pem'),'-nodetach','-outform','DER','-out',str(path.with_suffix('.mobileprovision'))])
 for folder,build,prefix in [('installed','34590','com.example.Regram'),('new/Payload','34591','com.reference.Regram')]:
  app=dest/folder/'Regram.app'
  target=app if index==0 else app/'PlugIns'/f'Ext{index}.appex';target.mkdir(parents=True,exist_ok=True)
  info={'CFBundleIdentifier':prefix+suffix,'CFBundleExecutable':'Fixture','CFBundleVersion':build,'CFBundleShortVersionString':'13.0','CFBundleDisplayName':'Regram '+folder,'CFBundlePackageType':'APPL' if index==0 else 'XPC!'}
  (target/'Info.plist').write_bytes(plistlib.dumps(info));shutil.copyfile(dest/'Fixture',target/'Fixture');(target/'Fixture').chmod(0o755)
# Independent profiles exercise wildcard reuse and actionable mismatch reasons.
variants=dest/'variants';variants.mkdir(exist_ok=True)
base=dict(profile);base['Entitlements']=dict(allowed,**{'application-identifier':'TESTTEAM01.*'})
for label,change in {
 'universal':{},
 'expired':{'ExpirationDate':now-datetime.timedelta(days=1)},
 'certificate':{'DeveloperCertificates':[b'wrong synthetic certificate']},
 'applicationIdentifier':{'Entitlements':dict(base['Entitlements'],**{'application-identifier':'TESTTEAM01.com.other.App'})},
 'entitlement':{'Entitlements':dict(base['Entitlements'],**{'com.apple.developer.icloud-container-environment':['Development']})},
}.items():
 value=dict(base,**change);path=variants/f'{label}.plist';path.write_bytes(plistlib.dumps(value))
 run([openssl,'cms','-sign','-binary','-in',str(path),'-signer',str(dest/'cert.pem'),'-inkey',str(dest/'key.pem'),'-nodetach','-outform','DER','-out',str(path.with_suffix('.mobileprovision'))])
run([str(task/'signer-fixture'),'initial',str(dest)])
with zipfile.ZipFile(dest/'new.ipa','w',compression=zipfile.ZIP_DEFLATED) as z:
 for path in (dest/'new').rglob('*'):
  if path.is_file():z.write(path,path.relative_to(dest/'new'))
run([str(task/'signer-fixture'),'verify',str(dest)])
run([str(task/'signer-fixture'),'profiles',str(dest)])
run([str(task/'signer-fixture'),'legacy',str(dest)])
print('Provisioning regression checks passed: imported profiles, a wildcard covering seven bundles, scalar/list permissions and six distinct failure reasons.')
print('Automatic certificate/profile binding passed, including installed signing identifiers independent of plist bundle IDs.')
print('Synthetic P12/profile fixture passed for main app and six extensions.')
with zipfile.ZipFile(dest/'updated.ipa') as z:
 bundles=[x for x in z.namelist() if x.endswith('/Info.plist')]
 assert len(bundles)==7
 for p in bundles:
  info=plistlib.loads(z.read(p));assert info['CFBundleIdentifier'].startswith('com.example.Regram')
 assert not any(x.endswith(('.p12','.pem')) for x in z.namelist())
print('Output IPA retains all identities and includes no signing keys.')

# Check the actual signed pages, special slots and CMS on every executable.
# The mock CA cannot satisfy Apple's trust requirement; cryptographic integrity
# is checked separately, without claiming device installation eligibility.
for artifact in ['updated.ipa', 'legacy-updated.ipa']:
    with zipfile.ZipFile(dest/artifact) as archive:
        for name in archive.namelist():
            if not name.endswith('/Info.plist'):
                continue
            bundle = name.removesuffix('Info.plist')
            info = plistlib.loads(archive.read(name))
            executable = archive.read(bundle + info['CFBundleExecutable'])
            offset = 32
            base = None
            for _ in range(struct.unpack_from('<I', executable, 16)[0]):
                kind, length = struct.unpack_from('<II', executable, offset)
                if kind == 0x1d:
                    base = struct.unpack_from('<I', executable, offset + 8)[0]
                offset += length
            assert base is not None
            slots = {}
            for index in range(struct.unpack_from('>I', executable, base + 8)[0]):
                kind, relative = struct.unpack_from('>II', executable, base + 12 + index * 8)
                length = struct.unpack_from('>I', executable, base + relative + 4)[0]
                slots[kind] = executable[base + relative:base + relative + length]
            for kind in [0, 0x1000]:
                directory = slots[kind]
                hash_offset, _, _, pages, limit = struct.unpack_from('>IIIII', directory, 16)
                hash_size, hash_type, page_size = directory[36], directory[37], 1 << directory[39]
                algorithm = hashlib.sha1 if hash_type == 1 else hashlib.sha256
                for page in range(pages):
                    actual = algorithm(executable[page * page_size:min(limit, (page + 1) * page_size)]).digest()
                    assert actual == directory[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
                for slot, data in [(1, archive.read(name)), (2, slots[2]), (3, archive.read(bundle + '_CodeSignature/CodeResources')), (5, slots[5]), (7, slots[7])]:
                    assert algorithm(data).digest() == directory[hash_offset - slot * hash_size:hash_offset - (slot - 1) * hash_size]
            (dest/'cms.der').write_bytes(slots[0x10000][8:])
            (dest/'content.bin').write_bytes(slots[0])
            run([openssl, 'cms', '-verify', '-binary', '-inform', 'DER', '-in', str(dest/'cms.der'), '-content', str(dest/'content.bin'), '-noverify', '-out', os.devnull])
            entitlements = plistlib.loads(slots[5][8:])
            expected = info['CFBundleIdentifier'] if artifact == 'updated.ipa' else info['CFBundleIdentifier'].replace('com.example.Regram', 'com.legacy.Regram', 1)
            assert entitlements['application-identifier'] == 'TESTTEAM01.' + expected
            assert entitlements['keychain-access-groups'] == ['TESTTEAM01.com.example.Regram']
            assert entitlements['com.apple.security.application-groups'] == ['group.com.example.Regram']
print('Fourteen executables passed page hashes, plist/resource/entitlement slots and CMS verification; app groups, keychain groups and installed identities retained.')
