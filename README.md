# REScout

Device-side iOS reverse-engineering intake tool.

**Bundle ID:** `com.fyqs.REScout`  
**Display name:** REScout  
**Version:** 2.1.0  
**Min iOS:** 15.0  
**Distribute:** TrollStore IPA via `./scripts/package_ipa.sh`

## Purpose

Browse installed apps on a jailbroken / TrollStore device and keep a **neutral profile pack**:

- Copy essentials (name / bundle / paths / encryption status)
- Export profile JSON + short README (identity, binary status, entitlements, paths)
- Profiles tab with **on-device preview** of saved packs

Does **not** decrypt App Store binaries or perform memory dumps.


## Build

```bash
./scripts/package_ipa.sh
# → REScout.ipa
```

Requires: Xcode CLI, `xcodegen`, `ldid`.

## Relation to DeviceOverview

`../DeviceOverview` remains the device-overview product. REScout is the RE-focused tool.
