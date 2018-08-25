using System;

namespace XyLang.Library
{
    public class str
    {
        private string v;
        public str() { }
        public str(object o)
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

        public static implicit operator str(string it) { return new str(it); }
        public static implicit operator string(str it) { return it.v; }

        public static str operator +(str a, str b) { return new str(a.v + b.v); }

        public static bool operator ==(str a, str b) { return a.v == b.v; }
        public static bool operator !=(str a, str b) { return a.v != b.v; }

        public override bool Equals(object o)
        {
            if (o is str)
            {
                str b = (str)o;
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(str b) { return b != null && v == b.v; }

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
