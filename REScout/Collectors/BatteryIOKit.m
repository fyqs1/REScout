#import "BatteryIOKit.h"

#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <stdint.h>
#import <stdio.h>
#import <string.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_registry_entry_t;
typedef mach_port_t io_connect_t;

#ifndef IOKit_kIOMasterPortDefault
#define IOKit_kIOMasterPortDefault ((mach_port_t)0)
#endif

typedef io_service_t (*IOServiceGetMatchingService_t)(mach_port_t, CFDictionaryRef);
typedef CFMutableDictionaryRef (*IOServiceMatching_t)(const char *);
typedef CFTypeRef (*IORegistryEntryCreateCFProperty_t)(io_registry_entry_t, CFStringRef, CFAllocatorRef, uint32_t);
typedef kern_return_t (*IOObjectRelease_t)(io_object_t);

static void *gIOKit;
static IOServiceGetMatchingService_t pIOServiceGetMatchingService;
static IOServiceMatching_t pIOServiceMatching;
static IORegistryEntryCreateCFProperty_t pIORegistryEntryCreateCFProperty;
static IOObjectRelease_t pIOObjectRelease;
static int gIOKitReady = -1;

static int ensureIOKit(void) {
    if (gIOKitReady >= 0) return gIOKitReady;
    gIOKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!gIOKit) {
        gIOKitReady = 0;
        return 0;
    }
    pIOServiceGetMatchingService = (IOServiceGetMatchingService_t)dlsym(gIOKit, "IOServiceGetMatchingService");
    pIOServiceMatching = (IOServiceMatching_t)dlsym(gIOKit, "IOServiceMatching");
    pIORegistryEntryCreateCFProperty = (IORegistryEntryCreateCFProperty_t)dlsym(gIOKit, "IORegistryEntryCreateCFProperty");
    pIOObjectRelease = (IOObjectRelease_t)dlsym(gIOKit, "IOObjectRelease");
    gIOKitReady = (pIOServiceGetMatchingService && pIOServiceMatching &&
                   pIORegistryEntryCreateCFProperty && pIOObjectRelease) ? 1 : 0;
    return gIOKitReady;
}

static CFTypeRef copyBatteryProperty(CFStringRef key) {
    if (!ensureIOKit()) return NULL;
    CFMutableDictionaryRef matching = pIOServiceMatching("AppleSmartBattery");
    if (!matching) return NULL;
    io_service_t service = pIOServiceGetMatchingService(IOKit_kIOMasterPortDefault, matching);
    if (!service) {
        // Some devices expose IOPMPowerSource instead.
        matching = pIOServiceMatching("IOPMPowerSource");
        if (!matching) return NULL;
        service = pIOServiceGetMatchingService(IOKit_kIOMasterPortDefault, matching);
    }
    if (!service) return NULL;
    CFTypeRef value = pIORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    pIOObjectRelease(service);
    return value;
}

static int intFromCF(CFTypeRef value, long long *out) {
    if (!value || !out) return 0;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        return CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, out) ? 1 : 0;
    }
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        *out = CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
        return 1;
    }
    return 0;
}

static void fillString(char *dst, int dstLen, const char *src) {
    if (!dst || dstLen <= 0) return;
    if (!src) { dst[0] = '\0'; return; }
    strncpy(dst, src, (size_t)dstLen - 1);
    dst[dstLen - 1] = '\0';
}

int DOVCopyBatteryExtras(DOVBatteryExtras *out) {
    if (!out) return 0;
    memset(out, 0, sizeof(*out));
    if (!ensureIOKit()) return 0;

    long long number = 0;
    CFTypeRef value = NULL;
    int hit = 0;

    value = copyBatteryProperty(CFSTR("Voltage"));
    if (intFromCF(value, &number)) { out->voltage_mV = (int)number; out->has_voltage = 1; hit = 1; }
    if (value) CFRelease(value);

    value = copyBatteryProperty(CFSTR("InstantAmperage"));
    if (!value) value = copyBatteryProperty(CFSTR("Amperage"));
    if (intFromCF(value, &number)) { out->amperage_mA = (int)number; out->has_amperage = 1; hit = 1; }
    if (value) CFRelease(value);

    value = copyBatteryProperty(CFSTR("Temperature"));
    if (intFromCF(value, &number)) {
        // IOKit temperature is often decidegrees C (e.g. 3012 => 30.12C)
        out->temperature_C = (double)number / 100.0;
        out->has_temperature = 1;
        hit = 1;
    }
    if (value) CFRelease(value);

    value = copyBatteryProperty(CFSTR("CycleCount"));
    if (intFromCF(value, &number)) { out->cycle_count = (int)number; out->has_cycle_count = 1; hit = 1; }
    if (value) CFRelease(value);

    value = copyBatteryProperty(CFSTR("DesignCapacity"));
    if (intFromCF(value, &number)) { out->design_capacity_mAh = (int)number; out->has_design_capacity = 1; hit = 1; }
    if (value) CFRelease(value);

    value = copyBatteryProperty(CFSTR("AppleRawMaxCapacity"));
    if (!value) value = copyBatteryProperty(CFSTR("MaxCapacity"));
    if (intFromCF(value, &number)) { out->max_capacity_mAh = (int)number; out->has_max_capacity = 1; hit = 1; }
    if (value) CFRelease(value);

    value = copyBatteryProperty(CFSTR("AppleRawCurrentCapacity"));
    if (!value) value = copyBatteryProperty(CFSTR("CurrentCapacity"));
    if (intFromCF(value, &number)) { out->current_capacity_mAh = (int)number; out->has_current_capacity = 1; hit = 1; }
    if (value) CFRelease(value);

    if (out->has_design_capacity && out->has_max_capacity && out->design_capacity_mAh > 0) {
        out->health_percent = (int)lround((double)out->max_capacity_mAh * 100.0 / (double)out->design_capacity_mAh);
        if (out->health_percent > 100) out->health_percent = 100;
        if (out->health_percent < 0) out->health_percent = 0;
        out->has_health = 1;
        hit = 1;
    } else {
        value = copyBatteryProperty(CFSTR("MaxCapacity"));
        // Some firmwares report MaxCapacity as percentage health already (0-100 / 0-1000)
        if (intFromCF(value, &number)) {
            if (number <= 100) {
                out->health_percent = (int)number;
                out->has_health = 1;
                hit = 1;
            } else if (number <= 1000) {
                out->health_percent = (int)(number / 10);
                out->has_health = 1;
                hit = 1;
            }
        }
        if (value) CFRelease(value);
    }

    value = copyBatteryProperty(CFSTR("Serial"));
    if (!value) value = copyBatteryProperty(CFSTR("BatterySerialNumber"));
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        char tmp[96] = {0};
        if (CFStringGetCString((CFStringRef)value, tmp, sizeof(tmp), kCFStringEncodingUTF8)) {
            fillString(out->serial, (int)sizeof(out->serial), tmp);
            out->has_serial = 1;
            hit = 1;
        }
    }
    if (value) CFRelease(value);

    return hit;
}
