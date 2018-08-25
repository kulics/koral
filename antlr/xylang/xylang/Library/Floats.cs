using System;

namespace XyLang.Library
{
    public class f32
    {
        private float v;
        public f32() { }
        public f32(object o)
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
                    v = Convert.ToSingle(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator f32(float it) { return new f32(it); }
        public static implicit operator float(f32 it) { return it.v; }

        public static f32 operator +(f32 a, f32 b) { return new f32(a.v + b.v); }
        public static f32 operator -(f32 a, f32 b) { return new f32(a.v - b.v); }
        public static f32 operator *(f32 a, f32 b) { return new f32(a.v * b.v); }
        public static f32 operator /(f32 a, f32 b) { return new f32(a.v / b.v); }
        public static f32 operator %(f32 a, f32 b) { return new f32(a.v % b.v); }

        public static bool operator <(f32 a, f32 b) { return a.v < b.v; }
        public static bool operator <=(f32 a, f32 b) { return a.v <= b.v; }
        public static bool operator >(f32 a, f32 b) { return a.v > b.v; }
        public static bool operator >=(f32 a, f32 b) { return a.v >= b.v; }
        public static bool operator ==(f32 a, f32 b) { return a.v == b.v; }
        public static bool operator !=(f32 a, f32 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is f32)
            {
                f32 b = (f32)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(f32 b) { return b != null && v == b.v; }

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

    public class f64
    {
        private double v;
        public f64() { }
        public f64(object o)
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
                    v = Convert.ToDouble(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator f64(double it) { return new f64(it); }
        public static implicit operator double(f64 it) { return it.v; }

        public static f64 operator +(f64 a, f64 b) { return new f64(a.v + b.v); }
        public static f64 operator -(f64 a, f64 b) { return new f64(a.v - b.v); }
        public static f64 operator *(f64 a, f64 b) { return new f64(a.v * b.v); }
        public static f64 operator /(f64 a, f64 b) { return new f64(a.v / b.v); }
        public static f64 operator %(f64 a, f64 b) { return new f64(a.v % b.v); }

        public static bool operator <(f64 a, f64 b) { return a.v < b.v; }
        public static bool operator <=(f64 a, f64 b) { return a.v <= b.v; }
        public static bool operator >(f64 a, f64 b) { return a.v > b.v; }
        public static bool operator >=(f64 a, f64 b) { return a.v >= b.v; }
        public static bool operator ==(f64 a, f64 b) { return a.v == b.v; }
        public static bool operator !=(f64 a, f64 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is f64)
            {
                f64 b = (f64)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(f64 b) { return b != null && v == b.v; }

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
