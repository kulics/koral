using Newtonsoft.Json;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace XyLang.Library
{
    [JsonConverter(typeof(StrConverter))]
    public class Str : IComparable, IEnumerable<Chr>, IXyValue
    {
        private string v = "";
        public Str() { }
        public Str(object o)
        {
            v = o.ToString();
        }

        public Chr this[int index] { get => v[index]; }

        public IEnumerator<Chr> GetEnumerator() => new StrEnumerator(this);

        IEnumerator IEnumerable.GetEnumerator() => new StrEnumerator(this);

        class StrEnumerator : IEnumerator<Chr>
        {
            private Str _collection;
            private int curIndex;
            public Chr Current { get; private set; }

            public StrEnumerator(Str collection)
            {
                _collection = collection;
                curIndex = -1;
                Current = default(Chr);
            }

            object IEnumerator.Current
            {
                get { return Current; }
            }

            void IDisposable.Dispose() { }

            public bool MoveNext()
            {
                //Avoids going beyond the end of the collection.
                if (++curIndex >= _collection.Count)
                {
                    return false;
                }
                else
                {
                    // Set current box to next item in collection.
                    Current = _collection[curIndex];
                }
                return true;
            }

            public void Reset() { curIndex = -1; }
        }

        public I32 Count => v.Length;
        public I32 LastIndex => Count - 1;
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

        public override string ToString() => v;

        public string ToString(string format) => v;

        public bool Contains(Str value) => v.Contains(value);

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
        public Str Slice(I32 startIndex, I32 endIndex)
        {
            if (startIndex == null && endIndex == null)
            {
                return this;
            }
            else if (endIndex == null)
            {
                return Substring(startIndex, LastIndex - startIndex);
            }
            else // (startIndex == null)
            {
                return Substring(0, LastIndex - endIndex);
            }
        }

        public Str Normalize(NormalizationForm normalizationForm = NormalizationForm.FormC) => v.Normalize(normalizationForm);

        public Str Remove(I32 startIndex) => v.Remove(startIndex);
        public Str Remove(I32 startIndex, I32 count) => v.Remove(startIndex, count);

        public Str Replace(Str oldValue, Str newValue) => v.Replace(oldValue ?? "", newValue ?? "");

        public Str Reverse() => new string(v.Reverse().ToArray());

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
        public object ToAny() => v;
    }

    [JsonConverter(typeof(ChrConverter))]
    public class Chr : IComparable, IXyValue
    {
        private char v;
        public Chr() { }
        public Chr(object o)
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

                case char _:

                case string _:
                    v = Convert.ToChar(o);
                    break;

                case IXyValue i:
                    v = i.ToChr();
                    break;
                default:
                    throw new Exception("not support type");
            }
        }

        public static implicit operator Chr(char it) => new Chr(it);
        public static implicit operator char(Chr it) => it.v;

        public int CompareTo(object obj) => v.CompareTo(obj.ToString());

        public Chr MaxValue { get => char.MaxValue; }
        public Chr MinValue { get => char.MinValue; }

        public Chr ToLower() => char.ToLower(v);
        public Chr ToUpper() => char.ToUpper(v);

        public bool IsLower() => char.IsLower(v);
        public bool IsUpper() => char.IsUpper(v);

        public bool IsLetter() => char.IsLetter(v);
        public bool IsDigit() => char.IsDigit(v);
        public bool IsLetterOrDigit() => char.IsLetterOrDigit(v);

        public bool IsNumber() => char.IsNumber(v);
        public bool IsSymbol() => char.IsSymbol(v);
        public bool IsWhiteSpace() => char.IsWhiteSpace(v);
        public bool IsControl() => char.IsControl(v);

        public double GetNumericValue() => char.GetNumericValue(v);

        public override string ToString() => v.ToString();
        public string ToString(string format) => v.ToString();

        public char ToValue() => v;
        public object ToAny() => v;
    }

    public class StrConverter : JsonConverter<Str>
    {
        public override void WriteJson(JsonWriter writer, Str value, JsonSerializer serializer) => writer.WriteValue(value);
        public override Str ReadJson(JsonReader reader, Type objectType, Str existingValue, bool hasExistingValue, JsonSerializer serializer) => new Str((string)reader.Value);
    }

    public class ChrConverter : JsonConverter<Chr>
    {
        public override void WriteJson(JsonWriter writer, Chr value, JsonSerializer serializer) => writer.WriteValue(value);
        public override Chr ReadJson(JsonReader reader, Type objectType, Chr existingValue, bool hasExistingValue, JsonSerializer serializer) => new Chr((char)reader.Value);
    }
}
