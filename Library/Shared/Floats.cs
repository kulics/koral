//using Newtonsoft.Json;
//using System;

//namespace Library
//{
//    public class f32 : iXsValue
//    {
//        private float v;
//        public f32() { }
//        public f32(object o)
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
//                    v = Convert.ToSingle(o);
//                    break;

//                case iXsValue i:
//                    v = i.toF32();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }

//        public static implicit operator f32(float it) => new f32(it);
//        public static implicit operator float(f32 it) => it.v;

//        public static f32 operator +(f32 a, f32 b) => new f32(a.v + b.v);
//        public static f32 operator -(f32 a, f32 b) => new f32(a.v - b.v);
//        public static f32 operator *(f32 a, f32 b) => new f32(a.v * b.v);
//        public static f32 operator /(f32 a, f32 b) => new f32(a.v / b.v);
//        public static f32 operator %(f32 a, f32 b) => new f32(a.v % b.v);

//        public static bool operator <(f32 a, f32 b) => a.v < b.v;
//        public static bool operator <=(f32 a, f32 b) => a.v <= b.v;
//        public static bool operator >(f32 a, f32 b) => a.v > b.v;
//        public static bool operator >=(f32 a, f32 b) => a.v >= b.v;

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is f32 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(f32 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public float toValue() => v;
//        public object toAny() => v;
//    }

//    public class f64 : iXsValue
//    {
//        private double v;
//        public f64() { }
//        public f64(object o)
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
//                    v = Convert.ToDouble(o);
//                    break;

//                case iXsValue i:
//                    v = i.toF64();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }

//        public static implicit operator f64(double it) => new f64(it);
//        public static implicit operator double(f64 it) => it.v;

//        public static f64 operator +(f64 a, f64 b) => new f64(a.v + b.v);
//        public static f64 operator -(f64 a, f64 b) => new f64(a.v - b.v);
//        public static f64 operator *(f64 a, f64 b) => new f64(a.v * b.v);
//        public static f64 operator /(f64 a, f64 b) => new f64(a.v / b.v);
//        public static f64 operator %(f64 a, f64 b) => new f64(a.v % b.v);

//        public static bool operator <(f64 a, f64 b) => a.v < b.v;
//        public static bool operator <=(f64 a, f64 b) => a.v <= b.v;
//        public static bool operator >(f64 a, f64 b) => a.v > b.v;
//        public static bool operator >=(f64 a, f64 b) => a.v >= b.v;

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is f64 b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(f64 b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString(format);

//        public double toValue() => v;
//        public object toAny() => v;
//    }
//    public class f32Converter : JsonConverter<f32>
//    {
//        public override void WriteJson(JsonWriter writer, f32 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override f32 ReadJson(JsonReader reader, Type objectType, f32 existingValue, bool hasExistingValue, JsonSerializer serializer) => new f32((float)reader.Value);
//    }
//    public class f64Converter : JsonConverter<f64>
//    {
//        public override void WriteJson(JsonWriter writer, f64 value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override f64 ReadJson(JsonReader reader, Type objectType, f64 existingValue, bool hasExistingValue, JsonSerializer serializer) => new f64((double)reader.Value);
//    }
//}
