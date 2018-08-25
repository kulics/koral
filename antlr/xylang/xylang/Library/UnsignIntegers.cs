using System;

namespace XyLang.Library
{
    public class u8
    {
        private byte v;
        public u8() { }
        public u8(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case i8 _:
                case i16 _:
                case i32 _:
                case i64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case u8 _:
                case u16 _:
                case u32 _:
                case u64 _:

                case float _:
                case double _:
                case f32 _:
                case f64 _:

                case string _:
                case str _:
                    v = Convert.ToByte(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator u8(byte it) { return new u8(it); }
        public static implicit operator byte(u8 it) { return it.v; }

        public static u8 operator +(u8 a, u8 b) { return new u8(a.v + b.v); }
        public static u8 operator -(u8 a, u8 b) { return new u8(a.v - b.v); }
        public static u8 operator *(u8 a, u8 b) { return new u8(a.v * b.v); }
        public static u8 operator /(u8 a, u8 b) { return new u8(a.v / b.v); }
        public static u8 operator %(u8 a, u8 b) { return new u8(a.v % b.v); }

        public static bool operator <(u8 a, u8 b) { return a.v < b.v; }
        public static bool operator <=(u8 a, u8 b) { return a.v <= b.v; }
        public static bool operator >(u8 a, u8 b) { return a.v > b.v; }
        public static bool operator >=(u8 a, u8 b) { return a.v >= b.v; }
        public static bool operator ==(u8 a, u8 b) { return a.v == b.v; }
        public static bool operator !=(u8 a, u8 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is u8)
            {
                u8 b = (u8)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(u8 b) { return b != null && v == b.v; }

        public override int GetHashCode() { return v.GetHashCode(); }

        public override string ToString() { return v.ToString(); }

        public string ToString(string format) { return v.ToString(format); }

#if !UNITY_FLASH
        public string ToString(IFormatProvider provider)
        {
            return v.ToString(provider);
        }

        public string ToString(string format, IFormatProvider provider)
        {
            return v.ToString(format, provider);
        }
#endif
        public str ToStr() { return ToString(); }
        public str ToStr(str format) { return ToString(format); }

        public i8 ToI8() { return new i8(v); }
        public i16 ToI16() { return new i16(v); }
        public i32 ToI32() { return new i32(v); }
        public i64 ToI64() { return new i64(v); }
        public u8 ToU8() { return new u8(v); }
        public u16 ToU16() { return new u16(v); }
        public u32 ToU32() { return new u32(v); }
        public u64 ToU64() { return new u64(v); }
        public f32 ToF32() { return new f32(v); }
        public f64 ToF64() { return new f64(v); }
    }

    public class u16
    {
        private ushort v;
        public u16() { }
        public u16(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case i8 _:
                case i16 _:
                case i32 _:
                case i64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case u8 _:
                case u16 _:
                case u32 _:
                case u64 _:

                case float _:
                case double _:
                case f32 _:
                case f64 _:

                case string _:
                case str _:
                    v = Convert.ToUInt16(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator u16(ushort it) { return new u16(it); }
        public static implicit operator ushort(u16 it) { return it.v; }

        public static u16 operator +(u16 a, u16 b) { return new u16(a.v + b.v); }
        public static u16 operator -(u16 a, u16 b) { return new u16(a.v - b.v); }
        public static u16 operator *(u16 a, u16 b) { return new u16(a.v * b.v); }
        public static u16 operator /(u16 a, u16 b) { return new u16(a.v / b.v); }
        public static u16 operator %(u16 a, u16 b) { return new u16(a.v % b.v); }

        public static bool operator <(u16 a, u16 b) { return a.v < b.v; }
        public static bool operator <=(u16 a, u16 b) { return a.v <= b.v; }
        public static bool operator >(u16 a, u16 b) { return a.v > b.v; }
        public static bool operator >=(u16 a, u16 b) { return a.v >= b.v; }
        public static bool operator ==(u16 a, u16 b) { return a.v == b.v; }
        public static bool operator !=(u16 a, u16 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is u16)
            {
                u16 b = (u16)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(u16 b) { return b != null && v == b.v; }

        public override int GetHashCode() { return v.GetHashCode(); }

        public override string ToString() { return v.ToString(); }

        public string ToString(string format) { return v.ToString(format); }

#if !UNITY_FLASH
        public string ToString(IFormatProvider provider)
        {
            return v.ToString(provider);
        }

        public string ToString(string format, IFormatProvider provider)
        {
            return v.ToString(format, provider);
        }
#endif
        public str ToStr() { return ToString(); }
        public str ToStr(str format) { return ToString(format); }

        public i8 ToI8() { return new i8(v); }
        public i16 ToI16() { return new i16(v); }
        public i32 ToI32() { return new i32(v); }
        public i64 ToI64() { return new i64(v); }
        public u8 ToU8() { return new u8(v); }
        public u16 ToU16() { return new u16(v); }
        public u32 ToU32() { return new u32(v); }
        public u64 ToU64() { return new u64(v); }
        public f32 ToF32() { return new f32(v); }
        public f64 ToF64() { return new f64(v); }
    }

    public class u32
    {
        private uint v;
        public u32() { }
        public u32(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case i8 _:
                case i16 _:
                case i32 _:
                case i64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case u8 _:
                case u16 _:
                case u32 _:
                case u64 _:

                case float _:
                case double _:
                case f32 _:
                case f64 _:

                case string _:
                case str _:
                    v = Convert.ToUInt32(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator u32(uint it) { return new u32(it); }
        public static implicit operator uint(u32 it) { return it.v; }

        public static u32 operator +(u32 a, u32 b) { return new u32(a.v + b.v); }
        public static u32 operator -(u32 a, u32 b) { return new u32(a.v - b.v); }
        public static u32 operator *(u32 a, u32 b) { return new u32(a.v * b.v); }
        public static u32 operator /(u32 a, u32 b) { return new u32(a.v / b.v); }
        public static u32 operator %(u32 a, u32 b) { return new u32(a.v % b.v); }

        public static bool operator <(u32 a, u32 b) { return a.v < b.v; }
        public static bool operator <=(u32 a, u32 b) { return a.v <= b.v; }
        public static bool operator >(u32 a, u32 b) { return a.v > b.v; }
        public static bool operator >=(u32 a, u32 b) { return a.v >= b.v; }
        public static bool operator ==(u32 a, u32 b) { return a.v == b.v; }
        public static bool operator !=(u32 a, u32 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is u32)
            {
                u32 b = (u32)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(u32 b) { return b != null && v == b.v; }

        public override int GetHashCode() { return v.GetHashCode(); }

        public override string ToString() { return v.ToString(); }

        public string ToString(string format) { return v.ToString(format); }

#if !UNITY_FLASH
        public string ToString(IFormatProvider provider)
        {
            return v.ToString(provider);
        }

        public string ToString(string format, IFormatProvider provider)
        {
            return v.ToString(format, provider);
        }
#endif
        public str ToStr() { return ToString(); }
        public str ToStr(str format) { return ToString(format); }

        public i8 ToI8() { return new i8(v); }
        public i16 ToI16() { return new i16(v); }
        public i32 ToI32() { return new i32(v); }
        public i64 ToI64() { return new i64(v); }
        public u8 ToU8() { return new u8(v); }
        public u16 ToU16() { return new u16(v); }
        public u32 ToU32() { return new u32(v); }
        public u64 ToU64() { return new u64(v); }
        public f32 ToF32() { return new f32(v); }
        public f64 ToF64() { return new f64(v); }
    }

    public class u64
    {
        private ulong v;
        public u64() { }
        public u64(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case i8 _:
                case i16 _:
                case i32 _:
                case i64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case u8 _:
                case u16 _:
                case u32 _:
                case u64 _:

                case float _:
                case double _:
                case f32 _:
                case f64 _:

                case string _:
                case str _:
                    v = Convert.ToUInt64(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator u64(ulong it) { return new u64(it); }
        public static implicit operator ulong(u64 it) { return it.v; }

        public static u64 operator +(u64 a, u64 b) { return new u64(a.v + b.v); }
        public static u64 operator -(u64 a, u64 b) { return new u64(a.v - b.v); }
        public static u64 operator *(u64 a, u64 b) { return new u64(a.v * b.v); }
        public static u64 operator /(u64 a, u64 b) { return new u64(a.v / b.v); }
        public static u64 operator %(u64 a, u64 b) { return new u64(a.v % b.v); }

        public static bool operator <(u64 a, u64 b) { return a.v < b.v; }
        public static bool operator <=(u64 a, u64 b) { return a.v <= b.v; }
        public static bool operator >(u64 a, u64 b) { return a.v > b.v; }
        public static bool operator >=(u64 a, u64 b) { return a.v >= b.v; }
        public static bool operator ==(u64 a, u64 b) { return a.v == b.v; }
        public static bool operator !=(u64 a, u64 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is u64)
            {
                u64 b = (u64)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(u64 b) { return b != null && v == b.v; }

        public override int GetHashCode() { return v.GetHashCode(); }

        public override string ToString() { return v.ToString(); }

        public string ToString(string format) { return v.ToString(format); }

#if !UNITY_FLASH
        public string ToString(IFormatProvider provider)
        {
            return v.ToString(provider);
        }

        public string ToString(string format, IFormatProvider provider)
        {
            return v.ToString(format, provider);
        }
#endif
        public str ToStr() { return ToString(); }
        public str ToStr(str format) { return ToString(format); }

        public i8 ToI8() { return new i8(v); }
        public i16 ToI16() { return new i16(v); }
        public i32 ToI32() { return new i32(v); }
        public i64 ToI64() { return new i64(v); }
        public u8 ToU8() { return new u8(v); }
        public u16 ToU16() { return new u16(v); }
        public u32 ToU32() { return new u32(v); }
        public u64 ToU64() { return new u64(v); }
        public f32 ToF32() { return new f32(v); }
        public f64 ToF64() { return new f64(v); }
    }
}
