
/*
 *
 * Copyright (C) Freecomm. All Rights Reserved.
 */
 
package device

import (
    "io"
    "net"
    "net/netip"
    "syscall"
    "strconv"
    
    "gvisor.dev/gvisor/pkg/tcpip"
    "gvisor.dev/gvisor/pkg/tcpip/adapters/gonet"
    "gvisor.dev/gvisor/pkg/tcpip/header"
    "gvisor.dev/gvisor/pkg/tcpip/link/channel"
    "gvisor.dev/gvisor/pkg/tcpip/network/ipv4"
    _ "gvisor.dev/gvisor/pkg/tcpip/network/ipv6"
    "gvisor.dev/gvisor/pkg/tcpip/stack"
    "gvisor.dev/gvisor/pkg/tcpip/transport/tcp"
    _ "gvisor.dev/gvisor/pkg/tcpip/transport/udp"
    "gvisor.dev/gvisor/pkg/buffer"
    "gvisor.dev/gvisor/pkg/waiter"
)

type SplitTrafficNetstack struct {
    stack                   *stack.Stack
    linkEP                  *channel.Endpoint
    device                  *Device
    physicalInterfaceIndex  int
}

func (device *Device) NewSplitTrafficHandler() {
    s := &SplitTrafficNetstack{
        device: device,
    }
    nicName := ""
    nicName, s.physicalInterfaceIndex = s.findPhysicalInterface()
    s.device.log.Verbosef("NetNavi local forwarding interface: %s - %d", nicName, s.physicalInterfaceIndex)
    
    // Create channel endpoint
    const defaultMTU = 1500
    const nicID = 1
    s.linkEP = channel.New(512, defaultMTU, "")
    
    // Create gVisor userspace network stack
    s.stack = stack.New(stack.Options{
        NetworkProtocols: []stack.NetworkProtocolFactory{
            ipv4.NewProtocol,
            // ipv6.NewProtocol,
        },
        TransportProtocols: []stack.TransportProtocolFactory{
            tcp.NewProtocol,
            // udp.NewProtocol,
        },
    })
    
    // Create NIC in the userspace stack
    if err := s.stack.CreateNIC(nicID, s.linkEP); err != nil {
        if device.log != nil {
            device.log.Errorf("NetNavi Failed to create NIC: %v", err)
        }
        return
    }
    
    s.stack.SetPromiscuousMode(nicID, true)
    s.stack.SetSpoofing(nicID, true)
    
    // Assign a generic local address, as a primary identity.
    addr := tcpip.AddrFrom4([4]byte{10, 0, 0, 2})

    protocolAddr := tcpip.ProtocolAddress{
        Protocol:          header.IPv4ProtocolNumber,
        AddressWithPrefix: addr.WithPrefix(),
    }

    if err := s.stack.AddProtocolAddress(nicID, protocolAddr, stack.AddressProperties{}); err != nil {
        device.log.Errorf("NetNavi: Failed to add protocol address: %v", err)
    }
    
    
    // Add routes in the userspace stack
    s.stack.SetRouteTable([]tcpip.Route{
        {
            Destination: header.IPv4EmptySubnet,
            NIC:         nicID,
        },
        {
            Destination: header.IPv6EmptySubnet,
            NIC:         nicID,
        },
    })
    
    // Set up TCP forwarder to intercept TCP connections
    tcpForwarder := tcp.NewForwarder(s.stack, 0, 1024, s.handleTCP)
    s.stack.SetTransportProtocolHandler(tcp.ProtocolNumber, tcpForwarder.HandlePacket)
    
    go s.loopWriteToTun()
    
    // Store in device
    device.splitter = s
}

func (s *SplitTrafficNetstack) loopWriteToTun() {
    for {
        pkt := s.linkEP.Read()
        if pkt == nil {
            if s.device.isClosed() { return }
            continue
        }

        // Convert gVisor PacketBuffer to raw bytes
        vv := pkt.ToView()
        rawBytes := vv.AsSlice()

        // Write the response back to the physical iOS TUN device
        // offset is required by wireguard-go TUN implementation
        offset := MessageTransportHeaderSize
        buf := make([]byte, len(rawBytes)+offset)
        copy(buf[offset:], rawBytes)
        
        _, err := s.device.tun.device.Write(buf, offset)
        if err != nil {
             s.device.log.Errorf("NetNavi Failed write back: %v", err)
        }
        vv.Release()
    }
}

// findPhysicalInterface finds WiFi or Cellular interface to bypass VPN
func (s *SplitTrafficNetstack) findPhysicalInterface() (string, int) {
    interfaces, err := net.Interfaces()
    if err != nil {
        return "", 0
    }
    
    for _, iface := range interfaces {
        if iface.Flags&net.FlagLoopback != 0 {
            continue
        }
        // Skip VPN/tunnel interfaces (utun)
        if len(iface.Name) >= 4 && iface.Name[:4] == "utun" {
            continue
        }
        // Prefer WiFi (en0) or Cellular (pdp_ip0)
        if iface.Name == "en0" || iface.Name == "pdp_ip0" {
            return iface.Name, iface.Index
        }
    }
    
    return "", 0
}

func (s *SplitTrafficNetstack) handleTCP(r *tcp.ForwarderRequest) {
    id := r.ID()
    // The LocalAddress in the request is the packet's DESTINATION IP
    dstAddr, _ := netip.AddrFromSlice(id.LocalAddress.AsSlice())
    dstPort := id.LocalPort
    remoteTarget := net.JoinHostPort(dstAddr.String(), strconv.Itoa(int(dstPort)))

    // Check bypass logic using the destination IP
    /*
    if !s.device.shouldBypassTunnel(net.ParseIP(dstAddr.String())) {
        r.Complete(false)
        return
    }
    */

    var wq waiter.Queue
    ep, err := r.CreateEndpoint(&wq)
    if err != nil {
        r.Complete(false)
        return
    }
    r.Complete(true)

    conn := gonet.NewTCPConn(&wq, ep)
    
    go s.handleLocalRoute(conn, remoteTarget)
}

func (s *SplitTrafficNetstack) handleLocalRoute(conn net.Conn, remoteTarget string) {
    defer conn.Close()
    
    // s.device.log.Errorf("NetNavi: Proxying the local forwarding traffic: %s", remoteTarget)
    
    dialer := &net.Dialer{
        Control: func(network, address string, c syscall.RawConn) error {
            var operr error
            err := c.Control(func(fd uintptr) {
                if s.physicalInterfaceIndex > 0 {
                    // Force the dialer to use the physical interface (WiFi/Cellular)
                    // TODO: now enforce Cellular for debugging purpose
                    operr = syscall.SetsockoptInt(
                        int(fd),
                        syscall.IPPROTO_IP,
                        0x19, // IP_BOUND_IF
                        s.physicalInterfaceIndex,
                    )
                }
            })
            if err != nil {return err }
            return operr
        },
    }
    
    localConn, err := dialer.Dial("tcp", remoteTarget)
    if err != nil {
        s.device.log.Errorf("NetNavi: Failed to dial destination %s: %v", remoteTarget, err)
        return
    }
    defer localConn.Close()

    // Bidirectional Copy
    done := make(chan struct{})
    go func() {
        io.Copy(localConn, conn)
        close(done)
    }()
    io.Copy(conn, localConn)
    <-done
}

// ProcessTunPacket injects a packet into the userspace network stack
func (s *SplitTrafficNetstack) ProcessTunPacket(packet []byte) {
    if s.linkEP == nil {
        return
    }
    
    if len(packet) < 1 {
        return
    }
    
    // Determine IP version
    version := packet[0] >> 4
    var proto tcpip.NetworkProtocolNumber
    if version == 4 {
        proto = header.IPv4ProtocolNumber
    } else if version == 6 {
        proto = header.IPv6ProtocolNumber
    } else {
        return
    }
    
    // Create packet buffer from the raw packet
    pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
        Payload: buffer.MakeWithData(packet),
    })
    defer pkt.DecRef()
    // s.device.log.Errorf("NetNavi: Local forwarding injection")
    s.linkEP.InjectInbound(proto, pkt)
}

func (device *Device) shouldBypassTunnel(dst net.IP) bool {
    bypassIPs := map[string]bool{
        "103.47.27.48": true,
        "103.47.27.39": true,
        "1.1.1.1":      false,
    }
    return bypassIPs[dst.String()]
}
