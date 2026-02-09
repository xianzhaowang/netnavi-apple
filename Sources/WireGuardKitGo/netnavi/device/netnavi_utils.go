/*
 *
 * Copyright (C) Freecomm. All Rights Reserved.
 */
 
package device

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
