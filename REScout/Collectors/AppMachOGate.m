#import "AppMachOGate.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach/machine.h>
#import <libkern/OSByteOrder.h>
#include <string.h>
#include <stdlib.h>

#ifndef CPU_SUBTYPE_ARM64E
#define CPU_SUBTYPE_ARM64E ((cpu_subtype_t)2)
#endif

static NSString *dov_arch_name(cpu_type_t cputype, cpu_subtype_t cpusubtype) {
#pragma unused(cpusubtype)
    if (cputype == CPU_TYPE_ARM64) {
        if ((cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E) return @"arm64e";
        return @"arm64";
    }
    if (cputype == CPU_TYPE_ARM) return @"armv7";
    if (cputype == CPU_TYPE_X86_64) return @"x86_64";
    if (cputype == CPU_TYPE_I386) return @"i386";
    return [NSString stringWithFormat:@"cpu_%d", (int)cputype];
}

static uint32_t dov_swap32(uint32_t v, BOOL swap) {
    return swap ? OSSwapInt32(v) : v;
}

static uint64_t dov_swap64(uint64_t v, BOOL swap) {
    return swap ? OSSwapInt64(v) : v;
}

static BOOL dov_parse_thin(const uint8_t *base, size_t len, BOOL swap,
                           int *outCryptid, NSString * _Nullable *outUUID,
                           cpu_type_t *outCPU, cpu_subtype_t *outSub) {
    if (len < sizeof(struct mach_header_64)) return NO;
    const struct mach_header_64 *mh = (const struct mach_header_64 *)base;
    uint32_t ncmds = dov_swap32(mh->ncmds, swap);
    uint32_t sizeofcmds = dov_swap32(mh->sizeofcmds, swap);
    if (outCPU) *outCPU = (cpu_type_t)dov_swap32((uint32_t)mh->cputype, swap);
    if (outSub) *outSub = (cpu_subtype_t)dov_swap32((uint32_t)mh->cpusubtype, swap);

    const uint8_t *ptr = base + sizeof(struct mach_header_64);
    const uint8_t *end = base + MIN(len, sizeof(struct mach_header_64) + sizeofcmds);
    if (outCryptid) *outCryptid = 0;

    for (uint32_t i = 0; i < ncmds && ptr + sizeof(struct load_command) <= end; i++) {
        const struct load_command *lc = (const struct load_command *)ptr;
        uint32_t cmd = dov_swap32(lc->cmd, swap);
        uint32_t cmdsize = dov_swap32(lc->cmdsize, swap);
        if (cmdsize < sizeof(struct load_command) || ptr + cmdsize > end) break;

        if (cmd == LC_ENCRYPTION_INFO_64 && cmdsize >= sizeof(struct encryption_info_command_64)) {
            const struct encryption_info_command_64 *enc = (const struct encryption_info_command_64 *)ptr;
            if (outCryptid) *outCryptid = (int)dov_swap32(enc->cryptid, swap);
        } else if (cmd == LC_ENCRYPTION_INFO && cmdsize >= sizeof(struct encryption_info_command)) {
            const struct encryption_info_command *enc = (const struct encryption_info_command *)ptr;
            if (outCryptid) *outCryptid = (int)dov_swap32(enc->cryptid, swap);
        } else if (cmd == LC_UUID && cmdsize >= sizeof(struct uuid_command) && outUUID && !*outUUID) {
            const struct uuid_command *u = (const struct uuid_command *)ptr;
            *outUUID = [[NSUUID alloc] initWithUUIDBytes:u->uuid].UUIDString;
        }
        ptr += cmdsize;
    }
    return YES;
}

static BOOL dov_parse_thin32(const uint8_t *base, size_t len, BOOL swap,
                             int *outCryptid, NSString * _Nullable *outUUID,
                             cpu_type_t *outCPU, cpu_subtype_t *outSub) {
    if (len < sizeof(struct mach_header)) return NO;
    const struct mach_header *mh = (const struct mach_header *)base;
    uint32_t ncmds = dov_swap32(mh->ncmds, swap);
    uint32_t sizeofcmds = dov_swap32(mh->sizeofcmds, swap);
    if (outCPU) *outCPU = (cpu_type_t)dov_swap32((uint32_t)mh->cputype, swap);
    if (outSub) *outSub = (cpu_subtype_t)dov_swap32((uint32_t)mh->cpusubtype, swap);

    const uint8_t *ptr = base + sizeof(struct mach_header);
    const uint8_t *end = base + MIN(len, sizeof(struct mach_header) + sizeofcmds);
    if (outCryptid) *outCryptid = 0;

    for (uint32_t i = 0; i < ncmds && ptr + sizeof(struct load_command) <= end; i++) {
        const struct load_command *lc = (const struct load_command *)ptr;
        uint32_t cmd = dov_swap32(lc->cmd, swap);
        uint32_t cmdsize = dov_swap32(lc->cmdsize, swap);
        if (cmdsize < sizeof(struct load_command) || ptr + cmdsize > end) break;

        if (cmd == LC_ENCRYPTION_INFO && cmdsize >= sizeof(struct encryption_info_command)) {
            const struct encryption_info_command *enc = (const struct encryption_info_command *)ptr;
            if (outCryptid) *outCryptid = (int)dov_swap32(enc->cryptid, swap);
        } else if (cmd == LC_UUID && cmdsize >= sizeof(struct uuid_command) && outUUID && !*outUUID) {
            const struct uuid_command *u = (const struct uuid_command *)ptr;
            *outUUID = [[NSUUID alloc] initWithUUIDBytes:u->uuid].UUIDString;
        }
        ptr += cmdsize;
    }
    return YES;
}

NSDictionary<NSString *, id> *DOVCopyMachOGate(NSString *executablePath) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"path"] = executablePath ?: @"";
    out[@"exists"] = @NO;
    out[@"cryptid"] = @(-1);
    out[@"encrypted"] = @NO;
    out[@"architectures"] = @[];
    out[@"uuid"] = @"";
    out[@"sliceCount"] = @0;

    if (executablePath.length == 0) {
        out[@"error"] = @"empty path";
        return out;
    }
    NSData *data = [NSData dataWithContentsOfFile:executablePath options:NSDataReadingMappedIfSafe error:nil];
    if (data.length < 4) {
        out[@"error"] = @"unreadable or too small";
        return out;
    }
    out[@"exists"] = @YES;
    const uint8_t *bytes = data.bytes;
    size_t len = data.length;
    uint32_t magic = 0;
    memcpy(&magic, bytes, sizeof(magic));

    NSMutableArray *archs = [NSMutableArray array];
    int maxCryptid = 0;
    NSString *uuid = nil;
    NSUInteger slices = 0;

    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        BOOL swap = (magic == FAT_CIGAM);
        if (len < sizeof(struct fat_header)) {
            out[@"error"] = @"truncated fat header";
            return out;
        }
        const struct fat_header *fh = (const struct fat_header *)bytes;
        uint32_t nfat = dov_swap32(fh->nfat_arch, swap);
        const struct fat_arch *fa = (const struct fat_arch *)(bytes + sizeof(struct fat_header));
        for (uint32_t i = 0; i < nfat; i++) {
            if ((const uint8_t *)&fa[i + 1] > bytes + len) break;
            uint32_t offset = dov_swap32(fa[i].offset, swap);
            uint32_t size = dov_swap32(fa[i].size, swap);
            if ((size_t)offset + size > len) continue;
            const uint8_t *slice = bytes + offset;
            uint32_t smagic = 0;
            memcpy(&smagic, slice, sizeof(smagic));
            int cryptid = 0;
            cpu_type_t cpu = 0;
            cpu_subtype_t sub = 0;
            BOOL ok = NO;
            if (smagic == MH_MAGIC_64 || smagic == MH_CIGAM_64) {
                ok = dov_parse_thin(slice, size, smagic == MH_CIGAM_64, &cryptid, &uuid, &cpu, &sub);
            } else if (smagic == MH_MAGIC || smagic == MH_CIGAM) {
                ok = dov_parse_thin32(slice, size, smagic == MH_CIGAM, &cryptid, &uuid, &cpu, &sub);
            }
            if (!ok) continue;
            slices += 1;
            if (cryptid > maxCryptid) maxCryptid = cryptid;
            [archs addObject:dov_arch_name(cpu, sub)];
        }
    } else if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        int cryptid = 0;
        cpu_type_t cpu = 0;
        cpu_subtype_t sub = 0;
        if (dov_parse_thin(bytes, len, magic == MH_CIGAM_64, &cryptid, &uuid, &cpu, &sub)) {
            slices = 1;
            maxCryptid = cryptid;
            [archs addObject:dov_arch_name(cpu, sub)];
        }
    } else if (magic == MH_MAGIC || magic == MH_CIGAM) {
        int cryptid = 0;
        cpu_type_t cpu = 0;
        cpu_subtype_t sub = 0;
        if (dov_parse_thin32(bytes, len, magic == MH_CIGAM, &cryptid, &uuid, &cpu, &sub)) {
            slices = 1;
            maxCryptid = cryptid;
            [archs addObject:dov_arch_name(cpu, sub)];
        }
    } else {
        out[@"error"] = [NSString stringWithFormat:@"unknown magic 0x%08x", magic];
        return out;
    }

    out[@"cryptid"] = @(maxCryptid);
    out[@"encrypted"] = @(maxCryptid != 0);
    out[@"architectures"] = [archs copy];
    out[@"uuid"] = uuid ?: @"";
    out[@"sliceCount"] = @(slices);
    return out;
}
