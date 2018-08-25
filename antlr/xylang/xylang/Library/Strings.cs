using System;

namespace XyLang.Library
{
    public class Str
    {
        private string v;
        public Str() { }
        public Str(object o)
        {
            switch (o)
            {
                case sbyte _:
                case short _:
                case int _:
                case long _:

                case byte _:
                case ushort _:
                case uint _:
                case ulong _:

                case float _:
                case double _:
                    v = o.ToString();
                    break;

                case string s:
                    v = s;
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator Str(string it) { return new Str(it); }
        public static implicit operator string(Str it) { return it.v; }

        public static Str operator +(Str a, Str b) { return new Str(a.v + b.v); }

        public static bool operator ==(Str a, Str b) { return a.v == b.v; }
        public static bool operator !=(Str a, Str b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is Str)
            {
                Str b = (Str)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(Str b) { return b != null && v == b.v; }

        public override int GetHashCode() { return v.GetHashCode(); }

        public override string ToString() { return v.ToString(); }

        public string ToString(string format) { return v.ToString(); }

#if !UNITY_FLASH
        public string ToString(IFormatProvider provider)
        {
            return v.ToString(provider);
        }

        public string ToString(string format, IFormatProvider provider)
        {
            return v.ToString();
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
