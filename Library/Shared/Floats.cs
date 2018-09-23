using Newtonsoft.Json;
using System;

namespace XyLang.Library
{
    public class F32 : IXyValue
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

                case char _:
                case Chr _:

                case string _:
                case Str _:
                    v = Convert.ToSingle(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator F32(float it) => new F32(it);
        public static implicit operator float(F32 it) => it.v;

        public static F32 operator +(F32 a, F32 b) => new F32(a.v + b.v);
        public static F32 operator -(F32 a, F32 b) => new F32(a.v - b.v);
        public static F32 operator *(F32 a, F32 b) => new F32(a.v * b.v);
        public static F32 operator /(F32 a, F32 b) => new F32(a.v / b.v);
        public static F32 operator %(F32 a, F32 b) => new F32(a.v % b.v);

        public static bool operator <(F32 a, F32 b) => a.v < b.v;
        public static bool operator <=(F32 a, F32 b) => a.v <= b.v;
        public static bool operator >(F32 a, F32 b) => a.v > b.v;
        public static bool operator >=(F32 a, F32 b) => a.v >= b.v;
        public static bool operator ==(F32 a, F32 b) => a.v == b.v;
        public static bool operator !=(F32 a, F32 b) => a.v != b.v;

        public override bool Equals(object o)
        {
            if (o is F32 b)
            {
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(F32 b) => b != null && v == b.v;

        public override int GetHashCode() => v.GetHashCode();

        public TypeCode GetTypeCode() => v.GetTypeCode();

        public override string ToString() => v.ToString();
        public string ToString(string format) => v.ToString(format);

        public float ToValue() => v;
    }

    public class F64 : IXyValue
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

                case char _:
                case Chr _:

                case string _:
                case Str _:
                    v = Convert.ToDouble(o);
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator F64(double it) => new F64(it);
        public static implicit operator double(F64 it) => it.v;

        public static F64 operator +(F64 a, F64 b) => new F64(a.v + b.v);
        public static F64 operator -(F64 a, F64 b) => new F64(a.v - b.v);
        public static F64 operator *(F64 a, F64 b) => new F64(a.v * b.v);
        public static F64 operator /(F64 a, F64 b) => new F64(a.v / b.v);
        public static F64 operator %(F64 a, F64 b) => new F64(a.v % b.v);

        public static bool operator <(F64 a, F64 b) => a.v < b.v;
        public static bool operator <=(F64 a, F64 b) => a.v <= b.v;
        public static bool operator >(F64 a, F64 b) => a.v > b.v;
        public static bool operator >=(F64 a, F64 b) => a.v >= b.v;
        public static bool operator ==(F64 a, F64 b) => a.v == b.v;
        public static bool operator !=(F64 a, F64 b) => a.v != b.v;

        public override bool Equals(object o)
        {
            if (o is F64 b)
            {
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(F64 b) => b != null && v == b.v;

        public override int GetHashCode() => v.GetHashCode();

        public TypeCode GetTypeCode() => v.GetTypeCode();

        public override string ToString() => v.ToString();
        public string ToString(string format) => v.ToString(format);

        public double ToValue() => v;
    }
    public class F32Converter : JsonConverter<F32>
    {
        public override void WriteJson(JsonWriter writer, F32 value, JsonSerializer serializer) => writer.WriteValue(value);
        public override F32 ReadJson(JsonReader reader, Type objectType, F32 existingValue, bool hasExistingValue, JsonSerializer serializer) => new F32((float)reader.Value);
    }
    public class F64Converter : JsonConverter<F64>
    {
        public override void WriteJson(JsonWriter writer, F64 value, JsonSerializer serializer) => writer.WriteValue(value);
        public override F64 ReadJson(JsonReader reader, Type objectType, F64 existingValue, bool hasExistingValue, JsonSerializer serializer) => new F64((double)reader.Value);
    }
}
