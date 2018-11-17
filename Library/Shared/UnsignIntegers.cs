//using Newtonsoft.Json;
//using System;

//namespace Library
//{
//    [JsonConverter(typeof(u8Converter))]
//    public class u8 : iXsValue
//    {
//        private byte v;
//        public u8() { }
//        public u8(object o)
//        {
//            switch (o)
//            {
//                case sbyte _:
//                case short _:
//                case int _:
//                case long _:

//                case byte _:
//                case ushort _:
//                case uint _:
//                case ulong _:

//                case float _:
//                case double _:

//                case char _:

//                case string _:
//                    v = Convert.ToByte(o);
//                    break;

//                case iXsValue i:
//                    v = i.toU8();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public u8(str value, i32 fromBase) => v = Convert.ToByte(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString(v, fromBase);

//        public static implicit operator u8(byte it) => new u8(it);
//        public static implicit operator byte(u8 it) => it.v;

//        public static u8 operator +(u8 a, u8 b) => new u8(a.v + b.v);
//        public static u8 operator -(u8 a, u8 b) => new u8(a.v - b.v);
//        public static u8 operator *(u8 a, u8 b) => new u8(a.v * b.v);
//        public static u8 operator /(u8 a, u8 b) => new u8(a.v / b.v);
//        public static u8 operator %(u8 a, u8 b) => new u8(a.v % b.v);

//        public static bool operator <(u8 a, u8 b) => a.v < b.v;
//        public static bool operator <=(u8 a, u8 b) => a.v <= b.v;
//        public static bool operator >(u8 a, u8 b) => a.v > b.v;
//        public static bool operator >=(u8 a, u8 b) => a.v >= b.v;

//        public u8 and(u8 it) => new u8(v & it);
//        public u8 or(u8 it) => new u8(v | it);
//        public u8 xor(u8 it) => new u8(v ^ it);
//        public u8 not() => new u8(~v);
//        public u8 lft(int it) => new u8(v << it);
//        public u8 rht(int it) => new u8(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is u8 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(u8 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public byte toValue() => v;
//        public object toAny() => v;
//    }

//    [JsonConverter(typeof(u16Converter))]
//    public class u16 : iXsValue
//    {
//        private ushort v;
//        public u16() { }
//        public u16(object o)
//        {
//            switch (o)
//            {
//                case sbyte _:
//                case short _:
//                case int _:
//                case long _:

//                case byte _:
//                case ushort _:
//                case uint _:
//                case ulong _:

//                case float _:
//                case double _:

//                case char _:

//                case string _:
//                    v = Convert.ToUInt16(o);
//                    break;

//                case iXsValue i:
//                    v = i.toU16();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public u16(str value, i32 fromBase) => v = Convert.ToUInt16(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString(v, fromBase);

//        public static implicit operator u16(ushort it) => new u16(it);
//        public static implicit operator ushort(u16 it) => it.v;

//        public static u16 operator +(u16 a, u16 b) => new u16(a.v + b.v);
//        public static u16 operator -(u16 a, u16 b) => new u16(a.v - b.v);
//        public static u16 operator *(u16 a, u16 b) => new u16(a.v * b.v);
//        public static u16 operator /(u16 a, u16 b) => new u16(a.v / b.v);
//        public static u16 operator %(u16 a, u16 b) => new u16(a.v % b.v);

//        public static bool operator <(u16 a, u16 b) => a.v < b.v;
//        public static bool operator <=(u16 a, u16 b) => a.v <= b.v;
//        public static bool operator >(u16 a, u16 b) => a.v > b.v;
//        public static bool operator >=(u16 a, u16 b) => a.v >= b.v;

//        public u16 and(u16 it) => new u16(v & it);
//        public u16 or(u16 it) => new u16(v | it);
//        public u16 xor(u16 it) => new u16(v ^ it);
//        public u16 not() => new u16(~v);
//        public u16 lft(int it) => new u16(v << it);
//        public u16 rht(int it) => new u16(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is u16 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(u16 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public ushort toValue() => v;
//        public object toAny() => v;
//    }

//    [JsonConverter(typeof(u32Converter))]
//    public class u32 : iXsValue
//    {
//        private uint v;
//        public u32() { }
//        public u32(object o)
//        {
//            switch (o)
//            {
//                case sbyte _:
//                case short _:
//                case int _:
//                case long _:

//                case byte _:
//                case ushort _:
//                case uint _:
//                case ulong _:

//                case float _:
//                case double _:

//                case char _:

//                case string _:
//                    v = Convert.ToUInt32(o);
//                    break;

//                case iXsValue i:
//                    v = i.toU32();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public u32(str value, i32 fromBase) => v = Convert.ToUInt32(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString(v, fromBase);

//        public static implicit operator u32(uint it) => new u32(it);
//        public static implicit operator uint(u32 it) => it.v;

//        public static u32 operator +(u32 a, u32 b) => new u32(a.v + b.v);
//        public static u32 operator -(u32 a, u32 b) => new u32(a.v - b.v);
//        public static u32 operator *(u32 a, u32 b) => new u32(a.v * b.v);
//        public static u32 operator /(u32 a, u32 b) => new u32(a.v / b.v);
//        public static u32 operator %(u32 a, u32 b) => new u32(a.v % b.v);

//        public static bool operator <(u32 a, u32 b) => a.v < b.v;
//        public static bool operator <=(u32 a, u32 b) => a.v <= b.v;
//        public static bool operator >(u32 a, u32 b) => a.v > b.v;
//        public static bool operator >=(u32 a, u32 b) => a.v >= b.v;

//        public u32 and(u32 it) => new u32(v & it);
//        public u32 or(u32 it) => new u32(v | it);
//        public u32 xor(u32 it) => new u32(v ^ it);
//        public u32 not() => new u32(~v);
//        public u32 lft(int it) => new u32(v << it);
//        public u32 rht(int it) => new u32(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is u32 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(u32 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public uint toValue() => v;
//        public object toAny() => v;
//    }

//    [JsonConverter(typeof(u64Converter))]
//    public class u64 : iXsValue
//    {
//        private ulong v;
//        public u64() { }
//        public u64(object o)
//        {
//            switch (o)
//            {
//                case sbyte _:
//                case short _:
//                case int _:
//                case long _:

//                case byte _:
//                case ushort _:
//                case uint _:
//                case ulong _:

//                case float _:
//                case double _:

//                case char _:

//                case string _:
//                    v = Convert.ToUInt64(o);
//                    break;

//                case iXsValue i:
//                    v = i.toU64();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public u64(str value, i32 fromBase) => v = Convert.ToUInt64(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString((long)v, fromBase);

//        public static implicit operator u64(ulong it) => new u64(it);
//        public static implicit operator ulong(u64 it) => it.v;

//        public static u64 operator +(u64 a, u64 b) => new u64(a.v + b.v);
//        public static u64 operator -(u64 a, u64 b) => new u64(a.v - b.v);
//        public static u64 operator *(u64 a, u64 b) => new u64(a.v * b.v);
//        public static u64 operator /(u64 a, u64 b) => new u64(a.v / b.v);
//        public static u64 operator %(u64 a, u64 b) => new u64(a.v % b.v);

//        public static bool operator <(u64 a, u64 b) => a.v < b.v;
//        public static bool operator <=(u64 a, u64 b) => a.v <= b.v;
//        public static bool operator >(u64 a, u64 b) => a.v > b.v;
//        public static bool operator >=(u64 a, u64 b) => a.v >= b.v;

//        public u64 and(u64 it) => new u64(v & it);
//        public u64 or(u64 it) => new u64(v | it);
//        public u64 xor(u64 it) => new u64(v ^ it);
//        public u64 not() => new u64(~v);
//        public u64 lft(int it) => new u64(v << it);
//        public u64 rht(int it) => new u64(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is u64 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(u64 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public ulong toValue() => v;
//        public object toAny() => v;
//    }
//    public class u8Converter : JsonConverter<u8>
//    {
//        public override void WriteJson(JsonWriter writer, u8 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override u8 ReadJson(JsonReader reader, Type objectType, u8 existingValue, bool hasExistingValue, JsonSerializer serializer) => new u8((byte)reader.Value);
//    }
//    public class u16Converter : JsonConverter<u16>
//    {
//        public override void WriteJson(JsonWriter writer, u16 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override u16 ReadJson(JsonReader reader, Type objectType, u16 existingValue, bool hasExistingValue, JsonSerializer serializer) => new u16((ushort)reader.Value);
//    }
//    public class u32Converter : JsonConverter<u32>
//    {
//        public override void WriteJson(JsonWriter writer, u32 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override u32 ReadJson(JsonReader reader, Type objectType, u32 existingValue, bool hasExistingValue, JsonSerializer serializer) => new u32((uint)reader.Value);
//    }
//    public class u64Converter : JsonConverter<u64>
//    {
//        public override void WriteJson(JsonWriter writer, u64 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override u64 ReadJson(JsonReader reader, Type objectType, u64 existingValue, bool hasExistingValue, JsonSerializer serializer) => new u64((ulong)reader.Value);
//    }
//}
