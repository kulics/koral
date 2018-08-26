using Newtonsoft.Json;
using System;
using System.Text;

namespace XyLang.Library
{
    [JsonConverter(typeof(StrConverter))]
    public class Str : IComparable
    {
        private string v = "";
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

        public Str this[int index] { get => v[index].ToString(); }

        public I32 Count => v.Length;
        public bool IsEmpty => string.IsNullOrEmpty(v);
        public bool NotEmpty => !IsEmpty;

        public static implicit operator Str(string it) => new Str(it);
        public static implicit operator string(Str it) => it.v;

        public static Str operator +(Str a, Str b) => new Str(a.v + b.v);

        public static bool operator ==(Str a, Str b) => a.v == b.v;
        public static bool operator !=(Str a, Str b) => a.v != b.v;

        public override bool Equals(object o)
        {
            if (o is Str b)
            {
                return v == b.v;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(Str b) => b != null && v == b.v;

        public override int GetHashCode() => v.GetHashCode();

        public TypeCode GetTypeCode() => v.GetTypeCode();

        public override string ToString() => v.ToString();

        public string ToString(string format) => v.ToString();

#if !UNITY_FLASH
        public string ToString(IFormatProvider provider) => v.ToString(provider);

        public string ToString(string format, IFormatProvider provider) => v.ToString();

#endif
        public bool Contains(Str value) => v.Contains(value);

        public Str ToStr() => ToString();
        public Str ToStr(Str format) => ToString(format);

        public I8 ToI8() => new I8(v);
        public I16 ToI16() => new I16(v);
        public I32 ToI32() => new I32(v);
        public I64 ToI64() => new I64(v);
        public U8 ToU8() => new U8(v);
        public U16 ToU16() => new U16(v);
        public U32 ToU32() => new U32(v);
        public U64 ToU64() => new U64(v);
        public F32 ToF32() => new F32(v);
        public F64 ToF64() => new F64(v);

        public I8 ToI8FromBase(I32 fromBase) => new I8(v, fromBase);
        public I16 ToI16FromBase(I32 fromBase) => new I16(v, fromBase);
        public I32 ToI32FromBase(I32 fromBase) => new I32(v, fromBase);
        public I64 ToI64FromBase(I32 fromBase) => new I64(v, fromBase);
        public U8 ToU8FromBase(I32 fromBase) => new U8(v, fromBase);
        public U16 ToU16FromBase(I32 fromBase) => new U16(v, fromBase);
        public U32 ToU32FromBase(I32 fromBase) => new U32(v, fromBase);
        public U64 ToU64FromBase(I32 fromBase) => new U64(v, fromBase);

        public int CompareTo(object obj) => v.CompareTo(obj.ToString());

        public I32 FirstIndexOf(Str value, StringComparison comparisonType = StringComparison.Ordinal) => v.IndexOf(value, comparisonType);
        public I32 FirstIndexOf(Str value, I32 startIndex, StringComparison comparisonType = StringComparison.Ordinal) => v.IndexOf(value, startIndex, comparisonType);
        public I32 FirstIndexOf(Str value, I32 startIndex, I32 count, StringComparison comparisonType = StringComparison.Ordinal) => v.IndexOf(value, startIndex, count, comparisonType);

        public I32 LastIndexOf(Str value, StringComparison comparisonType = StringComparison.Ordinal) => v.LastIndexOf(value, comparisonType);
        public I32 LastIndexOf(Str value, I32 startIndex, StringComparison comparisonType = StringComparison.Ordinal) => v.LastIndexOf(value, startIndex, comparisonType);
        public I32 LastIndexOf(Str value, I32 startIndex, I32 count, StringComparison comparisonType = StringComparison.Ordinal) => v.LastIndexOf(value, startIndex, count, comparisonType);

        public Str[] Split(Str[] separator, StringSplitOptions options = StringSplitOptions.None) => Array.ConvertAll(v.Split(Array.ConvertAll(separator, s => s.v), options), s => new Str(s));

        public Str Normalize(NormalizationForm normalizationForm = NormalizationForm.FormC) => v.Normalize(normalizationForm);

        public Str Remove(I32 startIndex) => v.Remove(startIndex);
        public Str Remove(I32 startIndex, I32 count) => v.Remove(startIndex, count);

        public Str Replace(Str oldValue, Str newValue) => v.Replace(oldValue ?? "", newValue ?? "");

        public bool StartsWith(Str value) => v.StartsWith(value);
        public bool StartsWith(Str value, StringComparison comparisonType) => v.StartsWith(value, comparisonType);

        public bool EndsWith(Str value) => v.EndsWith(value);
        public bool EndsWith(Str value, StringComparison comparisonType) => v.EndsWith(value, comparisonType);

        public Str Substring(I32 startIndex) => v.Substring(startIndex);
        public Str Substring(I32 startIndex, I32 count) => v.Substring(startIndex, count);

        public Str ToUpper() => v.ToUpper();
        public Str ToLower() => v.ToLower();

        public Str Trim() => v.Trim();
        public Str TrimEnd() => v.TrimEnd();
        public Str TrimStart() => v.TrimStart();

        public string ToValue() => v;
    }

    public class StrConverter : JsonConverter<Str>
    {
        public override void WriteJson(JsonWriter writer, Str value, JsonSerializer serializer) => writer.WriteValue(value);

        public override Str ReadJson(JsonReader reader, Type objectType, Str existingValue, bool hasExistingValue, JsonSerializer serializer) => new Str((string)reader.Value);
    }
}
