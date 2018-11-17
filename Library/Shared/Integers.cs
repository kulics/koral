//using Newtonsoft.Json;
//using System;

//namespace Library
//{
//    [JsonConverter(typeof(i8Converter))]
//    public class i8: iXsValue
//    {
//        private sbyte v;
//        public i8() { }
//        public i8(object o)
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
//                    v = Convert.ToSByte(o);
//                    break;

//                case iXsValue i:
//                    v = i.toI8();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public i8(str value, i32 fromBase) => v = Convert.ToSByte(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString(v, fromBase);

//        public static implicit operator i8(sbyte it) => new i8(it);
//        public static implicit operator sbyte(i8 it) => it.v;

//        public static i8 operator +(i8 a, i8 b) => new i8(a.v + b.v);
//        public static i8 operator -(i8 a, i8 b) => new i8(a.v - b.v);
//        public static i8 operator *(i8 a, i8 b) => new i8(a.v * b.v);
//        public static i8 operator /(i8 a, i8 b) => new i8(a.v / b.v);
//        public static i8 operator %(i8 a, i8 b) => new i8(a.v % b.v);

//        public static bool operator <(i8 a, i8 b) => a.v < b.v;
//        public static bool operator <=(i8 a, i8 b) => a.v <= b.v;
//        public static bool operator >(i8 a, i8 b) => a.v > b.v;
//        public static bool operator >=(i8 a, i8 b) => a.v >= b.v;

//        public i8 and(i8 it) => new i8(v & it);
//        public i8 or(i8 it) => new i8(v | it);
//        public i8 xor(i8 it) => new i8(v ^ it);
//        public i8 not() => new i8(~v);
//        public i8 lft(int it) => new i8(v << it);
//        public i8 rht(int it) => new i8(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is i8 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(i8 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public sbyte toValue() => v;
//        public object toAny() => v;
//    }

//    [JsonConverter(typeof(i16Converter))]
//    public class i16 : iXsValue
//    {
//        private short v;
//        public i16() { }
//        public i16(object o)
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
//                    v = Convert.ToInt16(o);
//                    break;

//                case iXsValue i:
//                    v = i.toI16();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public i16(str value, i32 fromBase) => v = Convert.ToInt16(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString(v, fromBase);

//        public static implicit operator i16(short it) => new i16(it);
//        public static implicit operator short(i16 it) => it.v;

//        public static i16 operator +(i16 a, i16 b) => new i16(a.v + b.v);
//        public static i16 operator -(i16 a, i16 b) => new i16(a.v - b.v);
//        public static i16 operator *(i16 a, i16 b) => new i16(a.v * b.v);
//        public static i16 operator /(i16 a, i16 b) => new i16(a.v / b.v);
//        public static i16 operator %(i16 a, i16 b) => new i16(a.v % b.v);

//        public static bool operator <(i16 a, i16 b) => a.v < b.v;
//        public static bool operator <=(i16 a, i16 b) => a.v <= b.v;
//        public static bool operator >(i16 a, i16 b) => a.v > b.v;
//        public static bool operator >=(i16 a, i16 b) => a.v >= b.v;

//        public i16 and(i16 it) => new i16(v & it);
//        public i16 or(i16 it) => new i16(v | it);
//        public i16 xor(i16 it) => new i16(v ^ it);
//        public i16 not() => new i16(~v);
//        public i16 lft(int it) => new i16(v << it);
//        public i16 rht(int it) => new i16(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is i16 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(i16 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public short toValue() => v;
//        public object toAny() => v;
//    }

//    [JsonConverter(typeof(i32Converter))]
//    public class i32 : iXsValue
//    {
//        private int v;
//        public i32() { }
//        public i32(object o)
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
//                    v = Convert.ToInt32(o);
//                    break;

//                case iXsValue i:
//                    v = i.toI32();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public i32(str value, i32 fromBase) => v = Convert.ToInt32(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString(v, fromBase);

//        public static implicit operator i32(int it) => new i32(it);
//        public static implicit operator int(i32 it) => it.v;

//        public static i32 operator +(i32 a, i32 b) => new i32(a.v + b.v);
//        public static i32 operator -(i32 a, i32 b) => new i32(a.v - b.v);
//        public static i32 operator *(i32 a, i32 b) => new i32(a.v * b.v);
//        public static i32 operator /(i32 a, i32 b) => new i32(a.v / b.v);
//        public static i32 operator %(i32 a, i32 b) => new i32(a.v % b.v);

//        public static bool operator <(i32 a, i32 b) => a.v < b.v;
//        public static bool operator <=(i32 a, i32 b) => a.v <= b.v;
//        public static bool operator >(i32 a, i32 b) => a.v > b.v;
//        public static bool operator >=(i32 a, i32 b) => a.v >= b.v;

//        public i32 and(i32 it) => new i32(v & it);
//        public i32 or(i32 it) => new i32(v | it);
//        public i32 xor(i32 it) => new i32(v ^ it);
//        public i32 not() => new i32(~v);
//        public i32 lft(int it) => new i32(v << it);
//        public i32 rht(int it) => new i32(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is i32 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(i32 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public int toValue() => v;
//        public object toAny() => v;
//    }

//    [JsonConverter(typeof(i64Converter))]
//    public class i64 : iXsValue
//    {
//        private long v;
//        public i64() { }
//        public i64(object o)
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
//                    v = Convert.ToInt64(o);
//                    break;

//                case iXsValue i:
//                    v = i.toI64();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }
//        public i64(str value, i32 fromBase) => v = Convert.ToInt64(value, fromBase);
//        public str toBase(i32 fromBase) => Convert.ToString(v, fromBase);

//        public static implicit operator i64(long it) => new i64(it);
//        public static implicit operator long(i64 it) => it.v;

//        public static i64 operator +(i64 a, i64 b) => new i64(a.v + b.v);
//        public static i64 operator -(i64 a, i64 b) => new i64(a.v - b.v);
//        public static i64 operator *(i64 a, i64 b) => new i64(a.v * b.v);
//        public static i64 operator /(i64 a, i64 b) => new i64(a.v / b.v);
//        public static i64 operator %(i64 a, i64 b) => new i64(a.v % b.v);

//        public static bool operator <(i64 a, i64 b) => a.v < b.v;
//        public static bool operator <=(i64 a, i64 b) => a.v <= b.v;
//        public static bool operator >(i64 a, i64 b) => a.v > b.v;
//        public static bool operator >=(i64 a, i64 b) => a.v >= b.v;

//        public i64 and(i64 it) => new i64(v & it);
//        public i64 or(i64 it) => new i64(v | it);
//        public i64 xor(i64 it) => new i64(v ^ it);
//        public i64 not() => new i64(~v);
//        public i64 lft(int it) => new i64(v << it);
//        public i64 rht(int it) => new i64(v >> it);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is i64 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(i64 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public long toValue() => v;
//        public object toAny() => v;
//    }
//    public class i8Converter : JsonConverter<i8>
//    {
//        public override void WriteJson(JsonWriter writer, i8 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override i8 ReadJson(JsonReader reader, Type objectType, i8 existingValue, bool hasExistingValue, JsonSerializer serializer) => new i8((sbyte)reader.Value);
//    }
//    public class i16Converter : JsonConverter<i16>
//    {
//        public override void WriteJson(JsonWriter writer, i16 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override i16 ReadJson(JsonReader reader, Type objectType, i16 existingValue, bool hasExistingValue, JsonSerializer serializer) => new i16((short)reader.Value);
//    }
//    public class i32Converter : JsonConverter<i32>
//    {
//        public override void WriteJson(JsonWriter writer, i32 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override i32 ReadJson(JsonReader reader, Type objectType, i32 existingValue, bool hasExistingValue, JsonSerializer serializer) => new i32((int)reader.Value);
//    }
//    public class i64Converter : JsonConverter<i64>
//    {
//        public override void WriteJson(JsonWriter writer, i64 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override i64 ReadJson(JsonReader reader, Type objectType, i64 existingValue, bool hasExistingValue, JsonSerializer serializer) => new i64((long)reader.Value);
//    }
//}
