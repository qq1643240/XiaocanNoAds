#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""导出 Mach-O 的 ObjC 类名 / 方法名 / cstring 到文本文件，便于反复 grep。"""
import struct, sys, os

LC_SEGMENT_64 = 0x19

def parse(path):
    data = open(path, 'rb').read()
    magic = struct.unpack('<I', data[:4])[0]
    if magic != 0xfeedfacf:
        raise SystemExit('not mach-o64')
    ncmds = struct.unpack('<I', data[16:20])[0]
    off = 32
    secs = {}
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', data[off:off+8])
        if cmd == LC_SEGMENT_64:
            segname = data[off+8:off+24].split(b'\x00')[0].decode('latin1')
            nsects = struct.unpack('<I', data[off+64:off+68])[0]
            soff = off + 72
            for _i in range(nsects):
                sectname = data[soff:soff+16].split(b'\x00')[0].decode('latin1')
                segn = data[soff+16:soff+32].split(b'\x00')[0].decode('latin1')
                addr, size = struct.unpack('<QQ', data[soff+32:soff+48])
                offset = struct.unpack('<I', data[soff+48:soff+52])[0]
                secs[segn + ',' + sectname] = (offset, size)
                soff += 80
        off += cmdsize
    return data, secs

def cstr(data, off, size):
    blob = data[off:off+size]
    return [s.decode('utf-8', 'replace') for s in blob.split(b'\x00') if s]

def main():
    path = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else 'dump'
    os.makedirs(outdir, exist_ok=True)
    data, secs = parse(path)

    targets = {
        '__objc_classname': '__TEXT,__objc_classname',
        '__objc_methname':  '__TEXT,__objc_methname',
        '__objc_methtype':  '__TEXT,__objc_methtype',
        '__cstring':        '__TEXT,__cstring',
        '__swift5_reflstr': '__TEXT,__swift5_reflstr',
    }
    for name, key in targets.items():
        if key in secs:
            o, s = secs[key]
            items = cstr(data, o, s)
            p = os.path.join(outdir, name + '.txt')
            with open(p, 'w', encoding='utf-8') as f:
                f.write('\n'.join(items))
            print('%-20s %7d items -> %s' % (name, len(items), p))
        else:
            print('%-20s MISSING' % name)

if __name__ == '__main__':
    main()
