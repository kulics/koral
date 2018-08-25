using System;

namespace XyLang.Library
{
    public class i8
    {
        private sbyte v;
        public i8() { }
        public i8(object o)
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
                    v = Convert.ToSByte(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator i8(sbyte it) { return new i8(it); }
        public static implicit operator sbyte(i8 it) { return it.v; }

        public static i8 operator +(i8 a, i8 b) { return new i8(a.v + b.v); }
        public static i8 operator -(i8 a, i8 b) { return new i8(a.v - b.v); }
        public static i8 operator *(i8 a, i8 b) { return new i8(a.v * b.v); }
        public static i8 operator /(i8 a, i8 b) { return new i8(a.v / b.v); }
        public static i8 operator %(i8 a, i8 b) { return new i8(a.v % b.v); }

        public static bool operator <(i8 a, i8 b) { return a.v < b.v; }
        public static bool operator <=(i8 a, i8 b) { return a.v <= b.v; }
        public static bool operator >(i8 a, i8 b) { return a.v > b.v; }
        public static bool operator >=(i8 a, i8 b) { return a.v >= b.v; }
        public static bool operator ==(i8 a, i8 b) { return a.v == b.v; }
        public static bool operator !=(i8 a, i8 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is i8)
            {
                i8 b = (i8)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(i8 b) { return b != null && v == b.v; }

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

    public class i16
    {
        private short v;
        public i16() { }
        public i16(object o)
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
                    v = Convert.ToInt16(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator i16(short it) { return new i16(it); }
        public static implicit operator short(i16 it) { return it.v; }

        public static i16 operator +(i16 a, i16 b) { return new i16(a.v + b.v); }
        public static i16 operator -(i16 a, i16 b) { return new i16(a.v - b.v); }
        public static i16 operator *(i16 a, i16 b) { return new i16(a.v * b.v); }
        public static i16 operator /(i16 a, i16 b) { return new i16(a.v / b.v); }
        public static i16 operator %(i16 a, i16 b) { return new i16(a.v % b.v); }

        public static bool operator <(i16 a, i16 b) { return a.v < b.v; }
        public static bool operator <=(i16 a, i16 b) { return a.v <= b.v; }
        public static bool operator >(i16 a, i16 b) { return a.v > b.v; }
        public static bool operator >=(i16 a, i16 b) { return a.v >= b.v; }
        public static bool operator ==(i16 a, i16 b) { return a.v == b.v; }
        public static bool operator !=(i16 a, i16 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is i16)
            {
                i16 b = (i16)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(i16 b) { return b != null && v == b.v; }

        public override int GetHashCode() { return v.GetHashCode(); }

        public override string ToString() { return v.ToString(); }

        public string ToString(string format)
        {
            return v.ToString(format);
        }

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

    public class i32
    {
        private int v;
        public i32() { }
        public i32(object o)
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
                    v = Convert.ToInt32(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator i32(int it) { return new i32(it); }
        public static implicit operator int(i32 it) { return it.v; }

        public static i32 operator +(i32 a, i32 b) { return new i32(a.v + b.v); }
        public static i32 operator -(i32 a, i32 b) { return new i32(a.v - b.v); }
        public static i32 operator *(i32 a, i32 b) { return new i32(a.v * b.v); }
        public static i32 operator /(i32 a, i32 b) { return new i32(a.v / b.v); }
        public static i32 operator %(i32 a, i32 b) { return new i32(a.v % b.v); }

        public static bool operator <(i32 a, i32 b) { return a.v < b.v; }
        public static bool operator <=(i32 a, i32 b) { return a.v <= b.v; }
        public static bool operator >(i32 a, i32 b) { return a.v > b.v; }
        public static bool operator >=(i32 a, i32 b) { return a.v >= b.v; }
        public static bool operator ==(i32 a, i32 b) { return a.v == b.v; }
        public static bool operator !=(i32 a, i32 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is i32)
            {
                i32 b = (i32)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(i32 b) { return b != null && v == b.v; }

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

    public class i64
    {
        private long v;
        public i64() { }
        public i64(object o)
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
                    v = Convert.ToInt64(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator i64(long it) { return new i64(it); }
        public static implicit operator long(i64 it) { return it.v; }

        public static i64 operator +(i64 a, i64 b) { return new i64(a.v + b.v); }
        public static i64 operator -(i64 a, i64 b) { return new i64(a.v - b.v); }
        public static i64 operator *(i64 a, i64 b) { return new i64(a.v * b.v); }
        public static i64 operator /(i64 a, i64 b) { return new i64(a.v / b.v); }
        public static i64 operator %(i64 a, i64 b) { return new i64(a.v % b.v); }

        public static bool operator <(i64 a, i64 b) { return a.v < b.v; }
        public static bool operator <=(i64 a, i64 b) { return a.v <= b.v; }
        public static bool operator >(i64 a, i64 b) { return a.v > b.v; }
        public static bool operator >=(i64 a, i64 b) { return a.v >= b.v; }
        public static bool operator ==(i64 a, i64 b) { return a.v == b.v; }
        public static bool operator !=(i64 a, i64 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is i64)
            {
                i64 b = (i64)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(i64 b) { return b != null && v == b.v; }

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
