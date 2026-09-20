//
//  MacieDisplayIdentity.m
//  MacieWallpaper - Stable identity for a physical display
//
//  Created on 2026-09-01.
//

#import "MacieDisplayIdentity.h"
#import <ColorSync/ColorSync.h>

CGDirectDisplayID MacieDisplayIDForScreen(NSScreen *screen) {
    NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
    if (![number isKindOfClass:[NSNumber class]]) return kCGNullDirectDisplay;
    return (CGDirectDisplayID)number.unsignedIntValue;
}

/// The preferred key. CGDisplayCreateUUIDFromDisplayID is tied to the physical panel
/// rather than to the connection, which is exactly the property we need.
static NSString *UUIDKeyForDisplayID(CGDirectDisplayID displayID) {
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!uuid) return nil;

    CFStringRef string = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    if (!string) return nil;

    NSString *key = [NSString stringWithFormat:@"uuid-%@", (__bridge NSString *)string];
    CFRelease(string);
    return key;
}

/// Fallback for displays with no UUID. Vendor and model alone would collide for two
/// identical monitors, so the serial is part of the key; monitors that report no
/// serial at all fall through to nil rather than silently sharing one key.
static NSString *HardwareKeyForDisplayID(CGDirectDisplayID displayID) {
    uint32_t vendor = CGDisplayVendorNumber(displayID);
    uint32_t model  = CGDisplayModelNumber(displayID);
    uint32_t serial = CGDisplaySerialNumber(displayID);

    if (vendor == 0 && model == 0 && serial == 0) return nil;

    return [NSString stringWithFormat:@"hw-%u-%u-%u", vendor, model, serial];
}

NSString *MacieDisplayKeyForScreen(NSScreen *screen) {
    CGDirectDisplayID displayID = MacieDisplayIDForScreen(screen);
    if (displayID == kCGNullDirectDisplay) return nil;

    NSString *key = UUIDKeyForDisplayID(displayID);
    if (key.length) return key;

    return HardwareKeyForDisplayID(displayID);
}

NSString *MacieDisplayNameForScreen(NSScreen *screen) {
    NSString *name = screen.localizedName;
    if (name.length) return name;

    // localizedName is documented non-null, but a display that reports nothing
    // useful should still produce a selectable menu item.
    return CGDisplayIsBuiltin(MacieDisplayIDForScreen(screen)) ? @"Built-in Display"
                                                              : @"Display";
}

NSArray<NSString *> *MacieDisambiguateDisplayNames(NSArray<NSString *> *names) {
    NSCountedSet *totals = [[NSCountedSet alloc] initWithArray:names];
    NSMutableDictionary<NSString *, NSNumber *> *seen = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:names.count];

    for (NSString *name in names) {
        if ([totals countForObject:name] < 2) {
            [result addObject:name];
            continue;
        }

        NSUInteger index = seen[name].unsignedIntegerValue + 1;
        seen[name] = @(index);

        // The first of a set keeps the bare name, so a two-monitor setup reads as
        // "LG UltraFine" and "LG UltraFine (2)" rather than "(1)" and "(2)".
        [result addObject:index == 1 ? name
                                     : [NSString stringWithFormat:@"%@ (%lu)",
                                        name, (unsigned long)index]];
    }

    return [result copy];
}
