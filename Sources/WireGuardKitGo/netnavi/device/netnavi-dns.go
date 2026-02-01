/*
 *
 * Copyright (C) Freecomm. All Rights Reserved.
 */

package device

import (
    "encoding/binary"
    _ "errors"
    _ "fmt"
    _ "io"
    _ "net"
    _ "strconv"
    "time"
    "sync"
    
    "github.com/miekg/dns"
 
    /*
    "gvisor.dev/gvisor/pkg/tcpip"
    "gvisor.dev/gvisor/pkg/tcpip/adapters/gonet"
    "gvisor.dev/gvisor/pkg/tcpip/header"
    "gvisor.dev/gvisor/pkg/tcpip/stack"
    "gvisor.dev/gvisor/pkg/tcpip/link/channel"
    "gvisor.dev/gvisor/pkg/tcpip/network/ipv4"
    "gvisor.dev/gvisor/pkg/tcpip/network/ipv6"
    "gvisor.dev/gvisor/pkg/tcpip/transport/tcp"
    "gvisor.dev/gvisor/pkg/tcpip/transport/udp"
    "gvisor.dev/gvisor/pkg/waiter"
    */
)

const (
    DNSDefaultPort = 53
    IPv4UDPProto   = 17
    IPv4MinLen     = 20
)

var tunWriteMu sync.Mutex

func calculateChecksum(b []byte) uint16 {
    var sum uint32
    for i := 0; i < len(b)-1; i += 2 {
        sum += uint32(binary.BigEndian.Uint16(b[i : i+2]))
    }
    if len(b)%2 == 1 {
        sum += uint32(b[len(b)-1]) << 8
    }
    for sum > 0xffff {
        sum = (sum & 0xffff) + (sum >> 16)
    }
    return ^uint16(sum)
}

// isDNSPacket checks if a raw packet is an IPv4 UDP DNS request (Port 53)
func (device *Device) isDNSPacket(packet []byte) bool {
    if len(packet) < 28 { // 20 (IP) + 8 (UDP)
        return false
    }

    // Check if IPv4 (0x45) and Protocol is UDP (17)
    if packet[0]>>4 != 4 || packet[9] != IPv4UDPProto {
        return false
    }

    // IHL (Internet Header Length) - start of UDP header
    ihl := int(packet[0]&0x0f) * 4
    
    srcPort := binary.BigEndian.Uint16(packet[ihl : ihl+2])
    if srcPort == 53 {
        return false
    }
    
    // Destination Port is bytes 2 and 3 of the UDP header
    destPort := binary.BigEndian.Uint16(packet[ihl+2 : ihl+4])
    
    return destPort == DNSDefaultPort
}

// handleDNS processes the DNS query and forwards to selected upstreams
func (device *Device) handleDNS(packet []byte) {
    defer func() {
        if r := recover(); r != nil {
            device.log.Errorf("RECOVERED PANIC: %v", r)
        }
    }()
    ihl := int(packet[0]&0x0f) * 4
    udpPayload := packet[ihl+8:]

    msg := new(dns.Msg)
    if err := msg.Unpack(udpPayload); err != nil {
        return
    }

    upstream := "8.8.8.8:53"
    if len(msg.Question) > 0 {
        domain := msg.Question[0].Name // e.g., "example.com."
        if domain == "apple.com." || domain == "icloud.com." {
            upstream = "8.8.4.4:53"
        }
    }

    // Forward the query using a DNS client
    device.log.Errorf("query: %v - upstream: %v", msg.Question, upstream)
    client := new(dns.Client)
    client.Net = "udp4"
    client.Timeout = 2 * time.Second
    response, _, err := client.Exchange(msg, upstream)
    if err != nil {
        return
    }

    // Send the resolved answer back to the iOS system
    device.injectDNSResponse(packet, response)
}

func (device *Device) injectDNSResponse(requestPacket []byte, dnsResp *dns.Msg) {
    defer func() {
        if r := recover(); r != nil {
            device.log.Errorf("DNS Injection Panic: %v", r)
        }
    }()

    respData, err := dnsResp.Pack()
    if err != nil {
        device.log.Errorf("DNS Pack error: %v", err)
        return
    }

    // Setup Offsets (Matching WireGuard's MessageTransportOffsetContent)
    const offset = 4
    const ipHeaderLen = 20
    const udpHeaderLen = 8
    
    actualTotalLen := ipHeaderLen + udpHeaderLen + len(respData)
    
    // 3. Create a buffer large enough to hold the offset + the packet
    buffer := make([]byte, offset + actualTotalLen)
    
    // 4. Build IP Header at index 'offset'
    respPacket := buffer[offset:]
    respPacket[0] = (4 << 4) | 5
    binary.BigEndian.PutUint16(respPacket[2:4], uint16(actualTotalLen))
    respPacket[9] = 17 // UDP
    respPacket[8] = 64 // TTL
    
    // Swap IPs
    copy(respPacket[12:16], requestPacket[16:20])
    copy(respPacket[16:20], requestPacket[12:16])

    // IP Checksum (Calculated on the slice starting at offset)
    ipChecksum := calculateChecksum(respPacket[:ipHeaderLen])
    binary.BigEndian.PutUint16(respPacket[10:12], ipChecksum)

    // Build UDP Header
    // We must find original ports. requestPacket is raw, so use its IHL.
    inputIHL := int(requestPacket[0]&0x0f) * 4
    copy(respPacket[ipHeaderLen:ipHeaderLen+2], requestPacket[inputIHL+2:inputIHL+4])
    copy(respPacket[ipHeaderLen+2:ipHeaderLen+4], requestPacket[inputIHL:inputIHL+2])
    binary.BigEndian.PutUint16(respPacket[ipHeaderLen+4:ipHeaderLen+6], uint16(udpHeaderLen+len(respData)))

    // Copy DNS Payload
    copy(respPacket[ipHeaderLen+udpHeaderLen:], respData)

    // Write to TUN using the SAME pattern as WireGuard
    tunWriteMu.Lock()
    defer tunWriteMu.Unlock()
    
    // Argument 1: The full buffer (not a slice)
    // Argument 2: The offset where the IP packet begins
    // The internal tun_darwin.go will access buffer[offset-4 : offset] to write the Family ID.
    _, err = device.tun.device.Write(buffer, offset)
    
    if err != nil {
        device.log.Errorf("DNS Response to Tun Write Error: %v", err)
    } else {
        device.log.Errorf("DNS Response % X -> % X to Tun Write Length: %d", respPacket[12:16], respPacket[16:20], actualTotalLen)
    }
}

/*
// create gvisor virtual nic

func (device *Device) InitNetstack() error {
    s := stack.New(stack.Options{
        NetworkProtocols: []stack.NetworkProtocolFactory{
            ipv4.NewProtocol,
            ipv6.NewProtocol,
        },
        TransportProtocols: []stack.TransportProtocolFactory{
            tcp.NewProtocol,
            udp.NewProtocol,
        },
    })

    linkEP := channel.New(1024, uint32(device.tun.mtu.Load()), "")
    nicID := tcpip.NICID(101)

    if err := s.CreateNIC(nicID, linkEP); err != nil {
        return errors.New(fmt.Sprintf("%v",err))
    }

    s.AddProtocolAddress(nicID, tcpip.ProtocolAddress{
        Protocol: ipv4.ProtocolNumber,
        AddressWithPrefix: tcpip.AddressWithPrefix{
            Address:   tcpip.Address(device.tunIP.To4()),
            PrefixLen: 32,
        },
    }, stack.AddressProperties{})

    s.SetRouteTable([]tcpip.Route{
        {Destination: header.IPv6EmptySubnet, NIC: nicID},
    })

    device.netstack = s
    device.linkEP = linkEP
    return nil
}

func (device *Device) injectToNetstack(pkt []byte) {
    var proto tcpip.NetworkProtocolNumber

    switch pkt[0] >> 4 {
    case 4:
        proto = ipv4.ProtocolNumber
    case 6:
        proto = ipv6.ProtocolNumber
    default:
        return
    }

    buf := stack.NewPacketBuffer(stack.PacketBufferOptions{
        Payload: bufferv2.MakeWithData(pkt),
    })

    device.linkEP.InjectInbound(proto, buf)
}


//======For Stream ONLY====

func (device *Device) InitNetstackForStream() error {
    ns := stack.New(stack.Options{
        NetworkProtocols: []stack.NetworkProtocolFactory{
            ipv4.NewProtocol,
            ipv6.NewProtocol,
        },
        TransportProtocols: []stack.TransportProtocolFactory{
            tcp.NewProtocol,
            udp.NewProtocol,
        },
    })

    // TCP forwarder
    tcpForwarder := tcp.NewForwarder(
        ns,
        65535,
        65535,
        device.handleTCPForward,
    )
    ns.SetTransportProtocolHandler(
        tcp.ProtocolNumber,
        tcpForwarder.HandlePacket,
    )

    // UDP forwarder
    udpForwarder := udp.NewForwarder(
        ns,
        device.handleUDPForward,
    )
    ns.SetTransportProtocolHandler(
        udp.ProtocolNumber,
        udpForwarder.HandlePacket,
    )

    device.netstack = ns
    return nil
}

func (device *Device) handleTCPForward(req *tcp.ForwarderRequest) {
    var wq waiter.Queue

    ep, err := req.CreateEndpoint(&wq)
    if err != nil {
        req.Complete(true) // reject SYN
        return
    }
    req.Complete(false) // accept SYN

    go func() {
        defer ep.Close()

        local := gonet.NewTCPConn(&wq, ep)
        defer local.Close()

        id := req.ID()

        dstIP := net.IP(id.LocalAddress).String()
        dstPort := strconv.Itoa(int(id.LocalPort))
        dst := net.JoinHostPort(dstIP, dstPort)

        remote, err := net.Dial("tcp", dst)
        if err != nil {
            return
        }
        defer remote.Close()

        go io.Copy(remote, local)
        io.Copy(local, remote)
    }()
}

func (device *Device) handleUDPForward(req *udp.ForwarderRequest) {
    var wq waiter.Queue

    ep, err := req.CreateEndpoint(&wq)
    if err != nil {
        return
    }

    go func() {
        defer ep.Close()

        local := gonet.NewUDPConn(device.netstack, &wq, ep)
        defer local.Close()

        id := req.ID()

        dstIP := net.IP(id.LocalAddress).String()
        dstPort := strconv.Itoa(int(id.LocalPort))

        raddr, err := net.ResolveUDPAddr(
            "udp",
            net.JoinHostPort(dstIP, dstPort),
        )
        if err != nil {
            return
        }

        remote, err := net.DialUDP("udp", nil, raddr)
        if err != nil {
            return
        }
        defer remote.Close()

        go io.Copy(remote, local)
        io.Copy(local, remote)
    }()
}
*/

