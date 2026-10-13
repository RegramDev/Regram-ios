#!/usr/bin/env python3
"""Build a signer-only OpenSSL without sharing symbols or headers with BoringSSL."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from namespace_archive import namespace_archive

PREFIX = 'RGUpdateSSL_'


def defined_symbols(archive):
    output = subprocess.check_output(['xcrun', 'nm', '-g', '-U', '-j', str(archive)], text=True)
    return {line[1:] for line in output.splitlines() if re.fullmatch(r'_[A-Za-z_][A-Za-z_0-9]*', line)}


def build(args):
    output = args.output.resolve()
    public = output / 'Public/RGUpdateOpenSSL'
    public.mkdir(parents=True, exist_ok=True)
    symbols = sorted(set(args.symbols.read_text().splitlines()) if args.symbols else defined_symbols(args.baseline))
    if not symbols or 'BN_div' not in symbols or 'CMS_sign' not in symbols:
        raise ValueError('The baseline must contain the full signing crypto API')
    prefix_header = '#ifndef RG_UPDATE_OPENSSL_SYMBOLS_H\n#define RG_UPDATE_OPENSSL_SYMBOLS_H\n' + ''.join('#define ' + name + ' ' + PREFIX + name + '\n' for name in symbols) + '#endif\n'
    (public / 'Symbols.h').write_text(prefix_header)
    with tempfile.TemporaryDirectory(prefix='private-crypto-', dir=output) as directory:
        root = Path(directory)
        source = root / 'work'
        source.mkdir()
        for path in [args.archive, args.configuration_patch, args.header_patch]:
            shutil.copyfile(path, source / path.name)
        script = args.builder.read_text()
        configure = './Configure $PLATFORM "-arch $ARCH" ${DEFAULT_FLAGS[@]}'
        if configure not in script:
            raise ValueError('Upstream OpenSSL builder changed; review its configuration')
        # Compile the original sources unchanged. Several digest implementations
        # use #ifndef function_name, so defining prefix macros during compilation
        # would accidentally remove their bodies. Rename object symbols afterward.
        script = script.replace('make && make install_sw', 'make build_libs && make install_dev')
        if args.cpu in ('darwin_arm64', 'darwin_x86_64'):
            # Offline coexistence checks use the identical no-assembly signing API.
            arch = 'arm64' if args.cpu == 'darwin_arm64' else 'x86_64'
            script = script.replace('build_for ios64-cross arm64 IOS', 'build_for darwin64-x86_64-cc arm64 IOS')
            script = script.replace('build_for ios64sim-cross x86_64 SIM', 'build_for darwin64-x86_64-cc x86_64 SIM')
            sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
            script = script.replace(configure, configure + ' "-isysroot ' + sdk + '"')
        else:
            arch = {'ios_arm64': 'arm64', 'ios_armv7': 'armv7', 'ios_x86_64': 'x86_64'}.get(args.cpu)
            if not arch:
                raise ValueError('Unsupported signing crypto architecture: ' + args.cpu)
        builder = root / 'build.sh'
        builder.write_text(script)
        # The upstream script expects relative directories when calculating --prefix.
        build_log = root / 'build.log'
        with build_log.open('w') as log:
            completed = subprocess.run(['bash', str(builder), 'work', 'work', arch], cwd=root, stdout=log, stderr=subprocess.STDOUT)
        if completed.returncode:
            print('\n'.join(build_log.read_text(errors='replace').splitlines()[-60:]))
            raise ValueError('Private signing crypto compilation failed')
        archive = source / 'build' / arch / 'lib/libcrypto.a'
        if not archive.read_bytes().startswith(b'!<arch>\n'):
            # darwin64-x86_64-cc plus -arch arm64 may emit a universal archive.
            thin = root / 'thin-libcrypto.a'
            subprocess.run(['xcrun', 'lipo', str(archive), '-thin', arch, '-output', str(thin)], check=True)
            archive = thin
        originals = defined_symbols(archive)
        mapping = {('_' + name).encode(): ('_' + PREFIX + name).encode() for name in set(symbols) | originals if not name.startswith(PREFIX)}
        private_archive = output / 'libRGUpdateCrypto.a'
        namespace_archive(archive, private_archive, mapping)
        emitted = defined_symbols(private_archive)
        leaked = sorted(name for name in emitted if not name.startswith(PREFIX))
        if leaked:
            raise ValueError('Signing crypto exported unprefixed symbols: ' + ', '.join(leaked[:20]))
        if PREFIX + 'BN_div' not in emitted or PREFIX + 'CMS_sign' not in emitted:
            raise ValueError('Missing isolated signing API')
        headers = source / 'build' / arch / 'include/openssl'
        destination = public / 'openssl'
        destination.mkdir(exist_ok=True)
        for header in headers.glob('*.h'):
            text = header.read_text()
            text = re.sub(r'([#]\s*include\s*[<"])openssl/', r'\1RGUpdateOpenSSL/openssl/', text)
            (destination / header.name).write_text('#include <RGUpdateOpenSSL/Symbols.h>\n' + text)
    print('Isolated signer OpenSSL: ' + str(len(emitted)) + ' prefixed symbols; no shared crypto exports.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ['archive', 'builder', 'configuration-patch', 'header-patch', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--symbols', type=Path)
    inputs.add_argument('--baseline', type=Path)
    parser.add_argument('--cpu', required=True)
    build(parser.parse_args())
