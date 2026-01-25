/*
 *
 * Copyright (C) Freecomm. All Rights Reserved.
 */

package device

import (
    "errors"
    "fmt"
    "io"
    "net"
    "strconv"
 
    "gvisor.dev/gvisor/pkg/bufferv2"
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
)

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
