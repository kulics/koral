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
    public octets(*self) List[UInt8]
    public is_loopback(*self) Bool
    public is_unspecified(*self) Bool
    public is_broadcast(*self) Bool
    public is_multicast(*self) Bool
    public is_private(*self) Bool
}

given Ipv4Addr as Eq {
    public equals(self, other Ipv4Addr) Bool
}

given Ipv4Addr as ToString {
    public to_string(*self) String
}

given Ipv4Addr as Parseable {
    public parse(s String) Result[Self]
}

given Ipv6Addr {
    public new(a UInt16, b UInt16, c UInt16, d UInt16, e UInt16, f UInt16, g UInt16, h UInt16) Ipv6Addr
    public localhost() Ipv6Addr
    public unspecified() Ipv6Addr
    public segments(*self) List[UInt16]
    public is_loopback(*self) Bool
    public is_unspecified(*self) Bool
    public is_multicast(*self) Bool
}

given Ipv6Addr as Eq {
    public equals(self, other Ipv6Addr) Bool
}

given Ipv6Addr as ToString {
    public to_string(*self) String
}

given Ipv6Addr as Parseable {
    public parse(s String) Result[Self]
}

given IpAddr {
    public is_loopback(*self) Bool
    public is_unspecified(*self) Bool
    public is_multicast(*self) Bool
    public is_ipv4(*self) Bool
    public is_ipv6(*self) Bool
}

given IpAddr as Eq {
    public equals(self, other IpAddr) Bool
}

given IpAddr as ToString {
    public to_string(*self) String
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
    public ip(*self) IpAddr
    public port(*self) UInt16
    public is_ipv4(*self) Bool
    public is_ipv6(*self) Bool
    public to_sockaddr_bytes(*self) List[UInt8]
    public from_sockaddr_bytes(buf List[UInt8]) Result[SocketAddr]
}

given SocketAddr as ToString {
    public to_string(*self) String
}

given SocketAddr as Parseable {
    public parse(s String) Result[Self]
}

given SocketAddr as Eq {
    public equals(self, other SocketAddr) Bool
}

given TcpListener {
    public fd(*self) Int
    public bind[T IntoSocketAddr](addr T) Result[TcpListener]
    public accept(*self) Result[Pair[TcpSocket, SocketAddr]]
    public local_addr(*self) Result[SocketAddr]
}

given TcpSocket {
    public fd(*self) Int
    public connect[T IntoSocketAddr](addr T) Result[TcpSocket]
    public local_addr(*self) Result[SocketAddr]
    public peer_addr(*self) Result[SocketAddr]
    public shutdown(*self, how Shutdown) Result[Void]
    public set_nodelay(*self, nodelay Bool) Result[Void]
    public nodelay(*self) Result[Bool]
    public set_read_timeout(*self, timeout Option[Duration]) Result[Void]
    public set_write_timeout(*self, timeout Option[Duration]) Result[Void]
    public read_timeout(*self) Result[Option[Duration]]
    public write_timeout(*self) Result[Option[Duration]]
}

given TcpSocket as Reader {
    public read(*self, into: *mut List[UInt8], range Range[UInt]) Result[UInt]
}

given TcpSocket as Writer {
    public write(*self, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(*self) Result[Void]
}

given UdpSocket {
    public fd(*self) Int
    public bind[T IntoSocketAddr](addr T) Result[UdpSocket]
    public send_to[T IntoSocketAddr](*self, addr T, from: List[UInt8], range Range[UInt]) Result[UInt]
    public recv_from(*self, into: *mut List[UInt8], range Range[UInt]) Result[Pair[UInt, SocketAddr]]
    public connect[T IntoSocketAddr](*self, addr T) Result[Void]
    public send(*self, from: List[UInt8], range Range[UInt]) Result[UInt]
    public recv(*self, into: *mut List[UInt8], range Range[UInt]) Result[UInt]
    public local_addr(*self) Result[SocketAddr]
    public peer_addr(*self) Result[SocketAddr]
    public set_broadcast(*self, broadcast Bool) Result[Void]
    public broadcast(*self) Result[Bool]
    public set_read_timeout(*self, timeout Option[Duration]) Result[Void]
    public set_write_timeout(*self, timeout Option[Duration]) Result[Void]
    public read_timeout(*self) Result[Option[Duration]]
    public write_timeout(*self) Result[Option[Duration]]
}
```
