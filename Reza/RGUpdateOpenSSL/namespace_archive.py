"""Rename C symbols in thin Mach-O archive members without changing relocation indexes.

OpenSSL uses function-name #ifndef guards and token-pasting macros. Preserve
its original preprocessing and rename every object definition/reference before
the final link; only clients include the API prefix header.
"""
from pathlib import Path
import struct
import subprocess


def rename_object(data, names):
    magic = struct.unpack_from('<I', data)[0]
    if magic not in (0xfeedface, 0xfeedfacf):
        raise ValueError('Expected a thin little-endian Mach-O crypto object')
    is64 = magic == 0xfeedfacf
    result = bytearray(data)
    command = 32 if is64 else 28
    symtab = None
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        kind, size = struct.unpack_from('<II', data, command)
        if size < 8 or command + size > len(data):
            raise ValueError('Invalid Mach-O load command')
        if kind == 2:
            symtab = command
        command += size
    if symtab is None:
        return data
    symbols, count, strings, string_size = struct.unpack_from('<IIII', data, symtab + 8)
    entry_size = 16 if is64 else 12
    if symbols + count * entry_size > len(data) or strings + string_size > len(data):
        raise ValueError('Invalid Mach-O symbol table')
    rebuilt = bytearray(b'\0')
    offsets = {b'': 0}
    for index in range(count):
        entry = symbols + index * entry_size
        old_offset = struct.unpack_from('<I', data, entry)[0]
        if old_offset >= string_size:
            raise ValueError('Invalid Mach-O string offset')
        end = data.find(b'\0', strings + old_offset, strings + string_size)
        if end < 0:
            raise ValueError('Unterminated Mach-O symbol')
        old_name = data[strings + old_offset:end]
        new_name = names.get(old_name, old_name)
        if new_name not in offsets:
            offsets[new_name] = len(rebuilt)
            rebuilt.extend(new_name + b'\0')
        struct.pack_into('<I', result, entry, offsets[new_name])
    result.extend(b'\0' * (-len(result) % 8))
    new_strings = len(result)
    rebuilt.extend(b'\0' * (-len(rebuilt) % 8))
    result.extend(rebuilt)
    struct.pack_into('<II', result, symtab + 16, new_strings, len(rebuilt))
    return bytes(result)


def namespace_archive(source, destination, names):
    data = Path(source).read_bytes()
    if not data.startswith(b'!<arch>\n'):
        raise ValueError('Expected a static archive')
    result = bytearray(b'!<arch>\n')
    position = 8
    while position < len(data):
        header = bytearray(data[position:position + 60])
        if len(header) != 60 or header[58:] != b'`\n':
            raise ValueError('Invalid archive member header')
        size = int(header[48:58])
        member = data[position + 60:position + 60 + size]
        if len(member) != size:
            raise ValueError('Truncated archive member')
        position += 60 + size + (size % 2)
        label = bytes(header[:16]).rstrip()
        name_size = int(label[3:]) if label.startswith(b'#1/') else 0
        name = member[:name_size].rstrip(b'\0') if name_size else label.rstrip(b'/')
        if name.startswith(b'__.SYMDEF') or label in (b'/', b'/SYM64/'):
            continue
        content = member[name_size:]
        content = rename_object(content, names)
        member = member[:name_size] + content
        header[48:58] = str(len(member)).encode().ljust(10)
        result.extend(header + member)
        if len(member) % 2:
            result.extend(b'\n')
    Path(destination).write_bytes(result)
    subprocess.run(['xcrun', 'ranlib', '-D', str(destination)], check=True)
