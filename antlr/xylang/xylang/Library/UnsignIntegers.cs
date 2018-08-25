using System;

namespace XyLang.Library
{
    public class U8
    {
        private byte v;
        public U8() { }
        public U8(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case I8 _:
                case I16 _:
                case I32 _:
                case I64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case U8 _:
                case U16 _:
                case U32 _:
                case U64 _:

                case float _:
                case double _:
                case F32 _:
                case F64 _:

                case string _:
                case Str _:
                    v = Convert.ToByte(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator U8(byte it) { return new U8(it); }
        public static implicit operator byte(U8 it) { return it.v; }

        public static U8 operator +(U8 a, U8 b) { return new U8(a.v + b.v); }
        public static U8 operator -(U8 a, U8 b) { return new U8(a.v - b.v); }
        public static U8 operator *(U8 a, U8 b) { return new U8(a.v * b.v); }
        public static U8 operator /(U8 a, U8 b) { return new U8(a.v / b.v); }
        public static U8 operator %(U8 a, U8 b) { return new U8(a.v % b.v); }

        public static bool operator <(U8 a, U8 b) { return a.v < b.v; }
        public static bool operator <=(U8 a, U8 b) { return a.v <= b.v; }
        public static bool operator >(U8 a, U8 b) { return a.v > b.v; }
        public static bool operator >=(U8 a, U8 b) { return a.v >= b.v; }
        public static bool operator ==(U8 a, U8 b) { return a.v == b.v; }
        public static bool operator !=(U8 a, U8 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is U8)
            {
                U8 b = (U8)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(U8 b) { return b != null && v == b.v; }

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
        public Str ToStr() { return ToString(); }
        public Str ToStr(Str format) { return ToString(format); }

        public I8 ToI8() { return new I8(v); }
        public I16 ToI16() { return new I16(v); }
        public I32 ToI32() { return new I32(v); }
        public I64 ToI64() { return new I64(v); }
        public U8 ToU8() { return new U8(v); }
        public U16 ToU16() { return new U16(v); }
        public U32 ToU32() { return new U32(v); }
        public U64 ToU64() { return new U64(v); }
        public F32 ToF32() { return new F32(v); }
        public F64 ToF64() { return new F64(v); }
    }

    public class U16
    {
        private ushort v;
        public U16() { }
        public U16(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case I8 _:
                case I16 _:
                case I32 _:
                case I64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case U8 _:
                case U16 _:
                case U32 _:
                case U64 _:

                case float _:
                case double _:
                case F32 _:
                case F64 _:

                case string _:
                case Str _:
                    v = Convert.ToUInt16(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator U16(ushort it) { return new U16(it); }
        public static implicit operator ushort(U16 it) { return it.v; }

        public static U16 operator +(U16 a, U16 b) { return new U16(a.v + b.v); }
        public static U16 operator -(U16 a, U16 b) { return new U16(a.v - b.v); }
        public static U16 operator *(U16 a, U16 b) { return new U16(a.v * b.v); }
        public static U16 operator /(U16 a, U16 b) { return new U16(a.v / b.v); }
        public static U16 operator %(U16 a, U16 b) { return new U16(a.v % b.v); }

        public static bool operator <(U16 a, U16 b) { return a.v < b.v; }
        public static bool operator <=(U16 a, U16 b) { return a.v <= b.v; }
        public static bool operator >(U16 a, U16 b) { return a.v > b.v; }
        public static bool operator >=(U16 a, U16 b) { return a.v >= b.v; }
        public static bool operator ==(U16 a, U16 b) { return a.v == b.v; }
        public static bool operator !=(U16 a, U16 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is U16)
            {
                U16 b = (U16)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(U16 b) { return b != null && v == b.v; }

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
        public Str ToStr() { return ToString(); }
        public Str ToStr(Str format) { return ToString(format); }

        public I8 ToI8() { return new I8(v); }
        public I16 ToI16() { return new I16(v); }
        public I32 ToI32() { return new I32(v); }
        public I64 ToI64() { return new I64(v); }
        public U8 ToU8() { return new U8(v); }
        public U16 ToU16() { return new U16(v); }
        public U32 ToU32() { return new U32(v); }
        public U64 ToU64() { return new U64(v); }
        public F32 ToF32() { return new F32(v); }
        public F64 ToF64() { return new F64(v); }
    }

    public class U32
    {
        private uint v;
        public U32() { }
        public U32(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case I8 _:
                case I16 _:
                case I32 _:
                case I64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case U8 _:
                case U16 _:
                case U32 _:
                case U64 _:

                case float _:
                case double _:
                case F32 _:
                case F64 _:

                case string _:
                case Str _:
                    v = Convert.ToUInt32(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator U32(uint it) { return new U32(it); }
        public static implicit operator uint(U32 it) { return it.v; }

        public static U32 operator +(U32 a, U32 b) { return new U32(a.v + b.v); }
        public static U32 operator -(U32 a, U32 b) { return new U32(a.v - b.v); }
        public static U32 operator *(U32 a, U32 b) { return new U32(a.v * b.v); }
        public static U32 operator /(U32 a, U32 b) { return new U32(a.v / b.v); }
        public static U32 operator %(U32 a, U32 b) { return new U32(a.v % b.v); }

        public static bool operator <(U32 a, U32 b) { return a.v < b.v; }
        public static bool operator <=(U32 a, U32 b) { return a.v <= b.v; }
        public static bool operator >(U32 a, U32 b) { return a.v > b.v; }
        public static bool operator >=(U32 a, U32 b) { return a.v >= b.v; }
        public static bool operator ==(U32 a, U32 b) { return a.v == b.v; }
        public static bool operator !=(U32 a, U32 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is U32)
            {
                U32 b = (U32)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(U32 b) { return b != null && v == b.v; }

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
        public Str ToStr() { return ToString(); }
        public Str ToStr(Str format) { return ToString(format); }

        public I8 ToI8() { return new I8(v); }
        public I16 ToI16() { return new I16(v); }
        public I32 ToI32() { return new I32(v); }
        public I64 ToI64() { return new I64(v); }
        public U8 ToU8() { return new U8(v); }
        public U16 ToU16() { return new U16(v); }
        public U32 ToU32() { return new U32(v); }
        public U64 ToU64() { return new U64(v); }
        public F32 ToF32() { return new F32(v); }
        public F64 ToF64() { return new F64(v); }
    }

    public class U64
    {
        private ulong v;
        public U64() { }
        public U64(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:
                case I8 _:
                case I16 _:
                case I32 _:
                case I64 _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:
                case U8 _:
                case U16 _:
                case U32 _:
                case U64 _:

                case float _:
                case double _:
                case F32 _:
                case F64 _:

                case string _:
                case Str _:
                    v = Convert.ToUInt64(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator U64(ulong it) { return new U64(it); }
        public static implicit operator ulong(U64 it) { return it.v; }

        public static U64 operator +(U64 a, U64 b) { return new U64(a.v + b.v); }
        public static U64 operator -(U64 a, U64 b) { return new U64(a.v - b.v); }
        public static U64 operator *(U64 a, U64 b) { return new U64(a.v * b.v); }
        public static U64 operator /(U64 a, U64 b) { return new U64(a.v / b.v); }
        public static U64 operator %(U64 a, U64 b) { return new U64(a.v % b.v); }

        public static bool operator <(U64 a, U64 b) { return a.v < b.v; }
        public static bool operator <=(U64 a, U64 b) { return a.v <= b.v; }
        public static bool operator >(U64 a, U64 b) { return a.v > b.v; }
        public static bool operator >=(U64 a, U64 b) { return a.v >= b.v; }
        public static bool operator ==(U64 a, U64 b) { return a.v == b.v; }
        public static bool operator !=(U64 a, U64 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is U64)
            {
                U64 b = (U64)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(U64 b) { return b != null && v == b.v; }

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
        public Str ToStr() { return ToString(); }
        public Str ToStr(Str format) { return ToString(format); }

        public I8 ToI8() { return new I8(v); }
        public I16 ToI16() { return new I16(v); }
        public I32 ToI32() { return new I32(v); }
        public I64 ToI64() { return new I64(v); }
        public U8 ToU8() { return new U8(v); }
        public U16 ToU16() { return new U16(v); }
        public U32 ToU32() { return new U32(v); }
        public U64 ToU64() { return new U64(v); }
        public F32 ToF32() { return new F32(v); }
        public F64 ToF64() { return new F64(v); }
    }
}
