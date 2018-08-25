using System;

namespace XyLang.Library
{
    public class I8
    {
        private sbyte v;
        public I8() { }
        public I8(object o)
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
                    v = Convert.ToSByte(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator I8(sbyte it) { return new I8(it); }
        public static implicit operator sbyte(I8 it) { return it.v; }

        public static I8 operator +(I8 a, I8 b) { return new I8(a.v + b.v); }
        public static I8 operator -(I8 a, I8 b) { return new I8(a.v - b.v); }
        public static I8 operator *(I8 a, I8 b) { return new I8(a.v * b.v); }
        public static I8 operator /(I8 a, I8 b) { return new I8(a.v / b.v); }
        public static I8 operator %(I8 a, I8 b) { return new I8(a.v % b.v); }

        public static bool operator <(I8 a, I8 b) { return a.v < b.v; }
        public static bool operator <=(I8 a, I8 b) { return a.v <= b.v; }
        public static bool operator >(I8 a, I8 b) { return a.v > b.v; }
        public static bool operator >=(I8 a, I8 b) { return a.v >= b.v; }
        public static bool operator ==(I8 a, I8 b) { return a.v == b.v; }
        public static bool operator !=(I8 a, I8 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is I8)
            {
                I8 b = (I8)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(I8 b) { return b != null && v == b.v; }

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

    public class I16
    {
        private short v;
        public I16() { }
        public I16(object o)
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
                    v = Convert.ToInt16(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator I16(short it) { return new I16(it); }
        public static implicit operator short(I16 it) { return it.v; }

        public static I16 operator +(I16 a, I16 b) { return new I16(a.v + b.v); }
        public static I16 operator -(I16 a, I16 b) { return new I16(a.v - b.v); }
        public static I16 operator *(I16 a, I16 b) { return new I16(a.v * b.v); }
        public static I16 operator /(I16 a, I16 b) { return new I16(a.v / b.v); }
        public static I16 operator %(I16 a, I16 b) { return new I16(a.v % b.v); }

        public static bool operator <(I16 a, I16 b) { return a.v < b.v; }
        public static bool operator <=(I16 a, I16 b) { return a.v <= b.v; }
        public static bool operator >(I16 a, I16 b) { return a.v > b.v; }
        public static bool operator >=(I16 a, I16 b) { return a.v >= b.v; }
        public static bool operator ==(I16 a, I16 b) { return a.v == b.v; }
        public static bool operator !=(I16 a, I16 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is I16)
            {
                I16 b = (I16)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(I16 b) { return b != null && v == b.v; }

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

    public class I32
    {
        private int v;
        public I32() { }
        public I32(object o)
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
                    v = Convert.ToInt32(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator I32(int it) { return new I32(it); }
        public static implicit operator int(I32 it) { return it.v; }

        public static I32 operator +(I32 a, I32 b) { return new I32(a.v + b.v); }
        public static I32 operator -(I32 a, I32 b) { return new I32(a.v - b.v); }
        public static I32 operator *(I32 a, I32 b) { return new I32(a.v * b.v); }
        public static I32 operator /(I32 a, I32 b) { return new I32(a.v / b.v); }
        public static I32 operator %(I32 a, I32 b) { return new I32(a.v % b.v); }

        public static bool operator <(I32 a, I32 b) { return a.v < b.v; }
        public static bool operator <=(I32 a, I32 b) { return a.v <= b.v; }
        public static bool operator >(I32 a, I32 b) { return a.v > b.v; }
        public static bool operator >=(I32 a, I32 b) { return a.v >= b.v; }
        public static bool operator ==(I32 a, I32 b) { return a.v == b.v; }
        public static bool operator !=(I32 a, I32 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is I32)
            {
                I32 b = (I32)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(I32 b) { return b != null && v == b.v; }

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

    public class I64
    {
        private long v;
        public I64() { }
        public I64(object o)
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
                    v = Convert.ToInt64(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator I64(long it) { return new I64(it); }
        public static implicit operator long(I64 it) { return it.v; }

        public static I64 operator +(I64 a, I64 b) { return new I64(a.v + b.v); }
        public static I64 operator -(I64 a, I64 b) { return new I64(a.v - b.v); }
        public static I64 operator *(I64 a, I64 b) { return new I64(a.v * b.v); }
        public static I64 operator /(I64 a, I64 b) { return new I64(a.v / b.v); }
        public static I64 operator %(I64 a, I64 b) { return new I64(a.v % b.v); }

        public static bool operator <(I64 a, I64 b) { return a.v < b.v; }
        public static bool operator <=(I64 a, I64 b) { return a.v <= b.v; }
        public static bool operator >(I64 a, I64 b) { return a.v > b.v; }
        public static bool operator >=(I64 a, I64 b) { return a.v >= b.v; }
        public static bool operator ==(I64 a, I64 b) { return a.v == b.v; }
        public static bool operator !=(I64 a, I64 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is I64)
            {
                I64 b = (I64)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(I64 b) { return b != null && v == b.v; }

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
