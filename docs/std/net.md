# Std.Net API

## Overview
This page lists the public API of module `Std.Net` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait IntoSocketAddr {
    into_socket_addr(self) [SocketAddr]Result
}
```

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
    public octets(self ref) [UInt8]List
    public is_loopback(self ref) Bool
    public is_unspecified(self ref) Bool
    public is_broadcast(self ref) Bool
    public is_multicast(self ref) Bool
    public is_private(self ref) Bool
}

given Ipv4Addr as Eq {
    public equals(self, other Ipv4Addr) Bool
}

given Ipv4Addr as ToString {
    public to_string(self ref) String
}

given Ipv4Addr as Parseable {
    public parse(s String) [Self]Result
}

given Ipv6Addr {
    public new(a UInt16, b UInt16, c UInt16, d UInt16, e UInt16, f UInt16, g UInt16, h UInt16) Ipv6Addr
    public localhost() Ipv6Addr
    public unspecified() Ipv6Addr
    public segments(self ref) [UInt16]List
    public is_loopback(self ref) Bool
    public is_unspecified(self ref) Bool
    public is_multicast(self ref) Bool
}

given Ipv6Addr as Eq {
    public equals(self, other Ipv6Addr) Bool
}

given Ipv6Addr as ToString {
    public to_string(self ref) String
}

given Ipv6Addr as Parseable {
    public parse(s String) [Self]Result
}

given IpAddr {
    public is_loopback(self ref) Bool
    public is_unspecified(self ref) Bool
    public is_multicast(self ref) Bool
    public is_ipv4(self ref) Bool
    public is_ipv6(self ref) Bool
}

given IpAddr as Eq {
    public equals(self, other IpAddr) Bool
}

given IpAddr as ToString {
    public to_string(self ref) String
}

given IpAddr as Parseable {
    public parse(s String) [Self]Result
}

given String as IntoSocketAddr {
    public into_socket_addr(self) [SocketAddr]Result
}

given SocketAddr as IntoSocketAddr {
    public into_socket_addr(self) [SocketAddr]Result
}

given SocketAddr {
    public new(ip IpAddr, port UInt16) SocketAddr
    public from_ipv4(addr Ipv4Addr, port UInt16) SocketAddr
    public from_ipv6(addr Ipv6Addr, port UInt16) SocketAddr
    public ip(self ref) IpAddr
    public port(self ref) UInt16
    public is_ipv4(self ref) Bool
    public is_ipv6(self ref) Bool
    public to_sockaddr_bytes(self ref) [UInt8]List
    public from_sockaddr_bytes(buf [UInt8]List) [SocketAddr]Result
}

given SocketAddr as ToString {
    public to_string(self ref) String
}

given SocketAddr as Parseable {
    public parse(s String) [Self]Result
}

given SocketAddr as Eq {
    public equals(self, other SocketAddr) Bool
}

given TcpListener {
    public fd(self ref) Int
    public [T IntoSocketAddr]bind(addr T) [TcpListener]Result
    public accept(self ref) [[TcpSocket, SocketAddr]Pair]Result
    public local_addr(self ref) [SocketAddr]Result
}

given TcpSocket {
    public fd(self ref) Int
    public [T IntoSocketAddr]connect(addr T) [TcpSocket]Result
    public local_addr(self ref) [SocketAddr]Result
    public peer_addr(self ref) [SocketAddr]Result
    public shutdown(self ref, how Shutdown) [Void]Result
    public set_nodelay(self ref, nodelay Bool) [Void]Result
    public nodelay(self ref) [Bool]Result
    public set_read_timeout(self ref, timeout [Duration]Option) [Void]Result
    public set_write_timeout(self ref, timeout [Duration]Option) [Void]Result
    public read_timeout(self ref) [[Duration]Option]Result
    public write_timeout(self ref) [[Duration]Option]Result
}

given TcpSocket as Reader {
    public read(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
}

given TcpSocket as Writer {
    public write(self ref, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self ref) [Void]Result
}

given UdpSocket {
    public fd(self ref) Int
    public [T IntoSocketAddr]bind(addr T) [UdpSocket]Result
    public [T IntoSocketAddr]send_to(self ref, addr T, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public recv_from(self ref, into: [UInt8]List mut ref, range [UInt]Range) [[UInt, SocketAddr]Pair]Result
    public [T IntoSocketAddr]connect(self ref, addr T) [Void]Result
    public send(self ref, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public recv(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
    public local_addr(self ref) [SocketAddr]Result
    public peer_addr(self ref) [SocketAddr]Result
    public set_broadcast(self ref, broadcast Bool) [Void]Result
    public broadcast(self ref) [Bool]Result
    public set_read_timeout(self ref, timeout [Duration]Option) [Void]Result
    public set_write_timeout(self ref, timeout [Duration]Option) [Void]Result
    public read_timeout(self ref) [[Duration]Option]Result
    public write_timeout(self ref) [[Duration]Option]Result
}
```
