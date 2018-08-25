using System;

namespace XyLang.Library
{
    public class F32
    {
        private float v;
        public F32() { }
        public F32(object o)
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
                    v = Convert.ToSingle(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator F32(float it) { return new F32(it); }
        public static implicit operator float(F32 it) { return it.v; }

        public static F32 operator +(F32 a, F32 b) { return new F32(a.v + b.v); }
        public static F32 operator -(F32 a, F32 b) { return new F32(a.v - b.v); }
        public static F32 operator *(F32 a, F32 b) { return new F32(a.v * b.v); }
        public static F32 operator /(F32 a, F32 b) { return new F32(a.v / b.v); }
        public static F32 operator %(F32 a, F32 b) { return new F32(a.v % b.v); }

        public static bool operator <(F32 a, F32 b) { return a.v < b.v; }
        public static bool operator <=(F32 a, F32 b) { return a.v <= b.v; }
        public static bool operator >(F32 a, F32 b) { return a.v > b.v; }
        public static bool operator >=(F32 a, F32 b) { return a.v >= b.v; }
        public static bool operator ==(F32 a, F32 b) { return a.v == b.v; }
        public static bool operator !=(F32 a, F32 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is F32)
            {
                F32 b = (F32)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(F32 b) { return b != null && v == b.v; }

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

    public class F64
    {
        private double v;
        public F64() { }
        public F64(object o)
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
                    v = Convert.ToDouble(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator F64(double it) { return new F64(it); }
        public static implicit operator double(F64 it) { return it.v; }

        public static F64 operator +(F64 a, F64 b) { return new F64(a.v + b.v); }
        public static F64 operator -(F64 a, F64 b) { return new F64(a.v - b.v); }
        public static F64 operator *(F64 a, F64 b) { return new F64(a.v * b.v); }
        public static F64 operator /(F64 a, F64 b) { return new F64(a.v / b.v); }
        public static F64 operator %(F64 a, F64 b) { return new F64(a.v % b.v); }

        public static bool operator <(F64 a, F64 b) { return a.v < b.v; }
        public static bool operator <=(F64 a, F64 b) { return a.v <= b.v; }
        public static bool operator >(F64 a, F64 b) { return a.v > b.v; }
        public static bool operator >=(F64 a, F64 b) { return a.v >= b.v; }
        public static bool operator ==(F64 a, F64 b) { return a.v == b.v; }
        public static bool operator !=(F64 a, F64 b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is F64)
            {
                F64 b = (F64)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(F64 b) { return b != null && v == b.v; }

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
