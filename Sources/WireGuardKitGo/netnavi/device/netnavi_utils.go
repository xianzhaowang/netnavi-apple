/*
 *
 * Copyright (C) Freecomm. All Rights Reserved.
 */
package device

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Foundation
#import <Foundation/Foundation.h>
#include <stdbool.h>

bool is_ios_app_on_mac() {
    if (@available(iOS 14.0, *)) {
        return [[NSProcessInfo processInfo] isiOSAppOnMac];
    }
    return false;
}
*/
import "C"
import (
    "runtime"
    "time"
)
    
func (device *Device) RoutineMemoryMonitor() {
    device.log.Verbosef("Routine: Memory monitor - started")
    var m runtime.MemStats
    
    // Create a ticker for every 30 seconds
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-device.closed: // Stop if device is closed
            return
        case <-ticker.C:
            runtime.ReadMemStats(&m)
            
            // Log key metrics for iOS Network Extension survival:
            // - HeapAlloc: Byte size of live objects
            // - Sys: Total memory obtained from OS (The number iOS cares about)
            // - NumGC: Number of completed GC cycles
            device.log.Verbosef("MEM STATS: Sys=%dMB, HeapAlloc=%dMB, NumGC=%d",
                m.Sys/1024/1024,
                m.HeapAlloc/1024/1024,
                m.NumGC,
            )
        }
    }
}

func (device *Device) InitMacOS() bool {
    device.IsMacOS = runtime.GOOS == "darwin" && runtime.GOARCH == "arm64"
    device.log.Errorf("NetNavi Running on MacOS: %v", device.IsMacOS)
    return device.IsMacOS
}
