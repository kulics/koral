# Std.Net API

## Overview
This page lists the public API of module `Std.Net` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

## Types
```koral
public type Ipv4Addr

public type Ipv6Addr

public type IpAddr {
    V4(addr Ipv4Addr),
    V6(addr Ipv6Addr),
}

public type Shutdown {
    Read(),
    Write(),
    Both(),
}

public type SocketAddr

public type TcpListener

public type TcpSocket

public type UdpSocket
```

## Given Implementations
```koral
given Ipv4Addr {
    public new(a UInt8, b UInt8, c UInt8, d UInt8) Ipv4Addr
    public localhost() Ipv4Addr
    public unspecified() Ipv4Addr
    public broadcast() Ipv4Addr
    public octets(self) [UInt8]List
    public is_loopback(self) Bool
    public is_unspecified(self) Bool
    public is_broadcast(self) Bool
    public is_multicast(self) Bool
    public is_private(self) Bool
}

given Ipv4Addr Eq {
    public equals(self, other Ipv4Addr) Bool
}

given Ipv4Addr ToString {
    public to_string(self) String
}

given Ipv4Addr Parseable {
    public parse(s String) [Self]Result
}

given Ipv6Addr {
    public new(a UInt16, b UInt16, c UInt16, d UInt16, e UInt16, f UInt16, g UInt16, h UInt16) Ipv6Addr
    public localhost() Ipv6Addr
    public unspecified() Ipv6Addr
    public segments(self) [UInt16]List
    public is_loopback(self) Bool
    public is_unspecified(self) Bool
    public is_multicast(self) Bool
}

given Ipv6Addr Eq {
    public equals(self, other Ipv6Addr) Bool
}

given Ipv6Addr ToString {
    public to_string(self) String
}

given Ipv6Addr Parseable {
    public parse(s String) [Self]Result
}

given IpAddr {
    public is_loopback(self) Bool
    public is_unspecified(self) Bool
    public is_multicast(self) Bool
    public is_ipv4(self) Bool
    public is_ipv6(self) Bool
}

given IpAddr Eq {
    public equals(self, other IpAddr) Bool
}

given IpAddr ToString {
    public to_string(self) String
}

given IpAddr Parseable {
    public parse(s String) [Self]Result
}

given SocketAddr {
    public new(ip IpAddr, port UInt16) SocketAddr
    public from_ipv4(addr Ipv4Addr, port UInt16) SocketAddr
    public from_ipv6(addr Ipv6Addr, port UInt16) SocketAddr
    public ip(self) IpAddr
    public port(self) UInt16
    public is_ipv4(self) Bool
    public is_ipv6(self) Bool
    public to_sockaddr_bytes(self) [UInt8]List
    public from_sockaddr_bytes(buf [UInt8]List) [SocketAddr]Result
}

given SocketAddr ToString {
    public to_string(self) String
}

given SocketAddr Parseable {
    public parse(s String) [Self]Result
}

given SocketAddr Eq {
    public equals(self, other SocketAddr) Bool
}

given TcpListener {
    public bind(addr String) [TcpListener]Result
    public bind_addr(addr SocketAddr) [TcpListener]Result
    public accept(self) [[TcpSocket, SocketAddr]Pair]Result
    public local_addr(self) [SocketAddr]Result
}

given TcpSocket {
    public connect(addr String) [TcpSocket]Result
    public connect_addr(addr SocketAddr) [TcpSocket]Result
    public local_addr(self) [SocketAddr]Result
    public peer_addr(self) [SocketAddr]Result
    public shutdown(self, how Shutdown) [Void]Result
    public set_nodelay(self, nodelay Bool) [Void]Result
    public nodelay(self) [Bool]Result
    public set_read_timeout(self, timeout [Duration]Option) [Void]Result
    public set_write_timeout(self, timeout [Duration]Option) [Void]Result
    public read_timeout(self) [[Duration]Option]Result
    public write_timeout(self) [[Duration]Option]Result
}

given TcpSocket Reader {
    public read(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
}

given TcpSocket Writer {
    public write(self, src [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self) [Void]Result
}

given UdpSocket {
    public bind(addr String) [UdpSocket]Result
    public bind_addr(addr SocketAddr) [UdpSocket]Result
    public send_to(self, src [UInt8]List, range [UInt]Range, addr SocketAddr) [UInt]Result
    public recv_from(self, dst [UInt8]List ref, range [UInt]Range) [[UInt, SocketAddr]Pair]Result
    public connect(self, addr String) [Void]Result
    public connect_addr(self, addr SocketAddr) [Void]Result
    public send(self, src [UInt8]List, range [UInt]Range) [UInt]Result
    public recv(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
    public local_addr(self) [SocketAddr]Result
    public peer_addr(self) [SocketAddr]Result
    public set_broadcast(self, broadcast Bool) [Void]Result
    public broadcast(self) [Bool]Result
    public set_read_timeout(self, timeout [Duration]Option) [Void]Result
    public set_write_timeout(self, timeout [Duration]Option) [Void]Result
    public read_timeout(self) [[Duration]Option]Result
    public write_timeout(self) [[Duration]Option]Result
}
```
