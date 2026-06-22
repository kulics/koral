# Std.Net API

## Overview
This page lists the public API of module `Std.Net` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait IntoSocketAddr {
    into_socket_addr(self) Result[SocketAddr]
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
    public octets(self ref) List[UInt8]
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
    public parse(s String) Result[Self]
}

given Ipv6Addr {
    public new(a UInt16, b UInt16, c UInt16, d UInt16, e UInt16, f UInt16, g UInt16, h UInt16) Ipv6Addr
    public localhost() Ipv6Addr
    public unspecified() Ipv6Addr
    public segments(self ref) List[UInt16]
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
    public parse(s String) Result[Self]
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
    public parse(s String) Result[Self]
}

given String as IntoSocketAddr {
    public into_socket_addr(self) Result[SocketAddr]
}

given SocketAddr as IntoSocketAddr {
    public into_socket_addr(self) Result[SocketAddr]
}

given SocketAddr {
    public new(ip IpAddr, port UInt16) SocketAddr
    public from_ipv4(addr Ipv4Addr, port UInt16) SocketAddr
    public from_ipv6(addr Ipv6Addr, port UInt16) SocketAddr
    public ip(self ref) IpAddr
    public port(self ref) UInt16
    public is_ipv4(self ref) Bool
    public is_ipv6(self ref) Bool
    public to_sockaddr_bytes(self ref) List[UInt8]
    public from_sockaddr_bytes(buf List[UInt8]) Result[SocketAddr]
}

given SocketAddr as ToString {
    public to_string(self ref) String
}

given SocketAddr as Parseable {
    public parse(s String) Result[Self]
}

given SocketAddr as Eq {
    public equals(self, other SocketAddr) Bool
}

given TcpListener {
    public fd(self ref) Int
    public bind[T IntoSocketAddr](addr T) Result[TcpListener]
    public accept(self ref) Result[Pair[TcpSocket, SocketAddr]]
    public local_addr(self ref) Result[SocketAddr]
}

given TcpSocket {
    public fd(self ref) Int
    public connect[T IntoSocketAddr](addr T) Result[TcpSocket]
    public local_addr(self ref) Result[SocketAddr]
    public peer_addr(self ref) Result[SocketAddr]
    public shutdown(self ref, how Shutdown) Result[Void]
    public set_nodelay(self ref, nodelay Bool) Result[Void]
    public nodelay(self ref) Result[Bool]
    public set_read_timeout(self ref, timeout Option[Duration]) Result[Void]
    public set_write_timeout(self ref, timeout Option[Duration]) Result[Void]
    public read_timeout(self ref) Result[Option[Duration]]
    public write_timeout(self ref) Result[Option[Duration]]
}

given TcpSocket as Reader {
    public read(self ref, into: ref mut List[UInt8], range Range[UInt]) Result[UInt]
}

given TcpSocket as Writer {
    public write(self ref, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(self ref) Result[Void]
}

given UdpSocket {
    public fd(self ref) Int
    public bind[T IntoSocketAddr](addr T) Result[UdpSocket]
    public send_to[T IntoSocketAddr](self ref, addr T, from: List[UInt8], range Range[UInt]) Result[UInt]
    public recv_from(self ref, into: ref mut List[UInt8], range Range[UInt]) Result[Pair[UInt, SocketAddr]]
    public connect[T IntoSocketAddr](self ref, addr T) Result[Void]
    public send(self ref, from: List[UInt8], range Range[UInt]) Result[UInt]
    public recv(self ref, into: ref mut List[UInt8], range Range[UInt]) Result[UInt]
    public local_addr(self ref) Result[SocketAddr]
    public peer_addr(self ref) Result[SocketAddr]
    public set_broadcast(self ref, broadcast Bool) Result[Void]
    public broadcast(self ref) Result[Bool]
    public set_read_timeout(self ref, timeout Option[Duration]) Result[Void]
    public set_write_timeout(self ref, timeout Option[Duration]) Result[Void]
    public read_timeout(self ref) Result[Option[Duration]]
    public write_timeout(self ref) Result[Option[Duration]]
}
```
