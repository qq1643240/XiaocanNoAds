#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 Mach-O 二进制里提取真实的 ObjC 类名 / 方法名 / 协议名。
用法: python objc_dump.py <binary> [grep关键字...]
"""
import struct, sys, re

LC_SEGMENT_64 = 0x19

def parse_sections(path):
    f = open(path, 'rb')
    data = f.read()
    magic = struct.unpack('<I', data[:4])[0]
    if magic != 0xfeedfacf:
        raise SystemExit('not a 64-bit mach-o: %x' % magic)
    ncmds = struct.unpack('<I', data[16:20])[0]
    off = 32
    sections = {}
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
                sections[segn + ',' + sectname] = (offset, size)
                soff += 80
        off += cmdsize
    return data, sections

def cstrings(data, offset, size):
    blob = data[offset:offset+size]
    return [s.decode('utf-8', 'replace') for s in blob.split(b'\x00') if s]

def main():
    path = sys.argv[1]
    kws = sys.argv[2:]
    data, sections = parse_sections(path)

    out = {}
    for key in ['__TEXT,__objc_classname', '__TEXT,__objc_methname',
                '__TEXT,__objc_protolist', '__TEXT,__cstring']:
        if key in sections:
            o, s = sections[key]
            out[key] = cstrings(data, o, s)

    cls = out.get('__TEXT,__objc_classname', [])
    meth = out.get('__TEXT,__objc_methname', [])

    print('=== sections ===')
    for k, v in sections.items():
        print('  %-40s off=%d size=%d' % (k, v[0], v[1]))
    print()
    print('objc_classname count:', len(cls))
    print('objc_methname  count:', len(meth))
    print()

    if kws:
        for kw in kws:
            print('=== 类名匹配 "%s" ===' % kw)
            hits = sorted(set(c for c in cls if kw.lower() in c.lower()))
            for c in hits:
                print('  ' + c)
            print('  (count=%d)' % len(hits))
            print()
    else:
        print('=== 类名样本 (前 60) ===')
        for c in sorted(set(cls))[:60]:
            print('  ' + c)

if __name__ == '__main__':
    main()
