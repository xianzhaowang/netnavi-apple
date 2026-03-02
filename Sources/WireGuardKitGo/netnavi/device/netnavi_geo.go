/*
 *
 * Copyright (C) Freecomm. All Rights Reserved.
 */
 
package device

import (
    _ "embed"
    
    "net"
    "net/netip"
    "runtime"
    "strings"
    
    "github.com/oschwald/maxminddb-golang/v2"
)

//go:embed GeoLite2-Country.mmdb
var geoDBBytes []byte

func (device *Device) InitNetNaviGeoDB() bool {
    var m runtime.MemStats
    runtime.ReadMemStats(&m)
    device.log.Errorf("FWDD: Pre-Init Mem: Sys=%dMB, Heap=%dMB", m.Sys/1024/1024, m.HeapAlloc/1024/1024)
    
    db, err := maxminddb.OpenBytes(geoDBBytes)
    if err != nil {
        device.log.Errorf("FWDD: Failed to init GeoIP DB: %v", err)
        return false
    }
    
    device.geoDB = db
    device.GeoCache = make(map[string]string)
    device.log.Errorf("FWDD: GeoIP DB initialized successfully")
    runtime.ReadMemStats(&m)
    device.log.Errorf("FWDD: Post-Init Mem: Sys=%dMB, Heap=%dMB", m.Sys/1024/1024, m.HeapAlloc/1024/1024)
    return true
}

func (device *Device) ShouldBypassByCountry(ip net.IP, homeCountry string) bool {
    // debug
    return true
    dstCountry := device.GetCountryForIP(ip)
    
    if dstCountry == "" {
        return true
    }
    
    if strings.ToLower(dstCountry) == strings.ToLower(homeCountry) {
        return true
    }
    
    return false
}


func (device *Device) GetCountryForIP(ip net.IP) string {
    if device.geoDB == nil {
        return ""
    }

    addr, ok := netip.AddrFromSlice(ip)
    if !ok {
        return ""
    }
    
    ipStr := addr.String()

    if country, found := device.GeoCache[ipStr]; found {
        return country
    }

    var record struct {
        Country struct {
            IsoCode string `maxminddb:"iso_code"`
        } `maxminddb:"country"`
    }

    result := device.geoDB.Lookup(addr)
    if err := result.Err(); err != nil {
        device.log.Errorf("FWDD: Failed to lookup %v: %v", ip, err)
        return ""
    }
    

    if err := result.Decode(&record); err != nil {
        device.log.Errorf("FWDD: Failed to parse %v: %v", ip, err)
        return ""
    }

    dstCountry := strings.ToLower(record.Country.IsoCode)

    if len(device.GeoCache) >= 500 {
        device.GeoCache = make(map[string]string)
        // clear(device.GeoCache)
    }
    device.GeoCache[ipStr] = dstCountry

    return dstCountry
}
