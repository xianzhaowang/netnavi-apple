/*
 *
 * Copyright (C) Freecomm. All Rights Reserved.
 */
 
package device

import (
    _ "embed"
    
    "net"
    "net/netip"
    "strings"
    
    "github.com/oschwald/maxminddb-golang/v2"
)

//go:embed GeoLite2-Country.mmdb
var geoDBBytes []byte

func (device *Device) InitNetNaviGeoDB() bool {
    db, err := maxminddb.OpenBytes(geoDBBytes)
    if err != nil {
        device.log.Errorf("FWDD: Failed to init GeoIP DB: %v", err)
        return false
    }
    
    device.geoDB = db
    device.geoCache = make(map[string]string)
    device.log.Errorf("FWDD: GeoIP DB initialized successfully")
    return true
}

func (device *Device) ShouldBypassByCountry(ip net.IP, homeCountry string) bool {
    dstCountry := device.GetCountryForIP(ip)

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

    if country, found := device.geoCache[ipStr]; found {
        return country
    }

    var record struct {
        Country struct {
            IsoCode string `maxminddb:"iso_code"`
        } `maxminddb:"country"`
    }

    result := device.geoDB.Lookup(addr)
    // Use .Err() to check for errors in v2
    if err := result.Err(); err != nil {
        return ""
    }
    

    if err := result.Decode(&record); err != nil {
        return ""
    }

    dstCountry := strings.ToLower(record.Country.IsoCode)

    if len(device.geoCache) >= 500 {
        device.geoCache = make(map[string]string)
    }
    device.geoCache[ipStr] = dstCountry

    return dstCountry
}
