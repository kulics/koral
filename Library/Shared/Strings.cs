//using Newtonsoft.Json;
//using System;
//using System.Collections;
//using System.Collections.Generic;
//using System.Linq;
//using System.Text;

//namespace Library
//{
//    [JsonConverter(typeof(strConverter))]
//    public class str : IComparable, IEnumerable<chr>, iXsValue
//    {
//        private string v = "";
//        public str() { }
//        public str(object o)
//        {
//            v = o.ToString();
//        }

//        public chr this[int index] { get => v[index]; }

//        public IEnumerator<chr> GetEnumerator() => new StrEnumerator(this);

//        IEnumerator IEnumerable.GetEnumerator() => new StrEnumerator(this);

//        class StrEnumerator : IEnumerator<chr>
//        {
//            private str _collection;
//            private int curIndex;
//            public chr Current { get; private set; }

//            public StrEnumerator(str collection)
//            {
//                _collection = collection;
//                curIndex = -1;
//                Current = default(chr);
//            }

//            object IEnumerator.Current
//            {
//                get { return Current; }
//            }

//            void IDisposable.Dispose() { }

//            public bool MoveNext()
//            {
//                //Avoids going beyond the end of the collection.
//                if (++curIndex >= _collection.count)
//                {
//                    return false;
//                }
//                else
//                {
//                    // Set current box to next item in collection.
//                    Current = _collection[curIndex];
//                }
//                return true;
//            }

//            public void Reset() { curIndex = -1; }
//        }

//        public i32 count => v.Length;
//        public i32 lastIndex => count - 1;
//        public bool isEmpty => string.IsNullOrEmpty(v);
//        public bool notEmpty => !isEmpty;

//        public static implicit operator str(string it) => new str(it);
//        public static implicit operator string(str it) => it.v;

//        public static str operator +(str a, str b) => new str(a.v + b.v);

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is str b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(str b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public override string ToString() => v;

//        public string ToString(string format) => v;

//        public bool contains(str value) => v.Contains(value);

//        public i8 toI8() => new i8(v);
//        public i16 toI16() => new i16(v);
//        public i32 toI32() => new i32(v);
//        public i64 toI64() => new i64(v);
//        public u8 toU8() => new u8(v);
//        public u16 toU16() => new u16(v);
//        public u32 toU32() => new u32(v);
//        public u64 toU64() => new u64(v);
//        public f32 toF32() => new f32(v);
//        public f64 toF64() => new f64(v);

//        public i8 toI8FromBase(i32 fromBase) => new i8(v, fromBase);
//        public i16 toI16FromBase(i32 fromBase) => new i16(v, fromBase);
//        public i32 toI32FromBase(i32 fromBase) => new i32(v, fromBase);
//        public i64 toI64FromBase(i32 fromBase) => new i64(v, fromBase);
//        public u8 toU8FromBase(i32 fromBase) => new u8(v, fromBase);
//        public u16 toU16FromBase(i32 fromBase) => new u16(v, fromBase);
//        public u32 toU32FromBase(i32 fromBase) => new u32(v, fromBase);
//        public u64 toU64FromBase(i32 fromBase) => new u64(v, fromBase);

//        public int CompareTo(object obj) => v.CompareTo(obj.ToString());

//        public i32 firstIndexOf(str value, StringComparison comparisonType = StringComparison.Ordinal) => v.IndexOf(value, comparisonType);
//        public i32 firstIndexOf(str value, i32 startIndex, StringComparison comparisonType = StringComparison.Ordinal) => v.IndexOf(value, startIndex, comparisonType);
//        public i32 firstIndexOf(str value, i32 startIndex, i32 count, StringComparison comparisonType = StringComparison.Ordinal) => v.IndexOf(value, startIndex, count, comparisonType);

//        public i32 lastIndexOf(str value, StringComparison comparisonType = StringComparison.Ordinal) => v.LastIndexOf(value, comparisonType);
//        public i32 lastIndexOf(str value, i32 startIndex, StringComparison comparisonType = StringComparison.Ordinal) => v.LastIndexOf(value, startIndex, comparisonType);
//        public i32 lastIndexOf(str value, i32 startIndex, i32 count, StringComparison comparisonType = StringComparison.Ordinal) => v.LastIndexOf(value, startIndex, count, comparisonType);

//        public str[] split(str[] separator, StringSplitOptions options = StringSplitOptions.None) => Array.ConvertAll(v.Split(Array.ConvertAll(separator, s => s.v), options), s => new str(s));
//        public str slice(i32 startIndex, i32 endIndex)
//        {
//            if (startIndex == null && endIndex == null)
//            {
//                return this;
//            }
//            else if (endIndex == null)
//            {
//                return substring(startIndex, lastIndex - startIndex);
//            }
//            else // (startIndex == null)
//            {
//                return substring(0, lastIndex - endIndex);
//            }
//        }

//        public str normalize(NormalizationForm normalizationForm = NormalizationForm.FormC) => v.Normalize(normalizationForm);

//        public str remove(i32 startIndex) => v.Remove(startIndex);
//        public str remove(i32 startIndex, i32 count) => v.Remove(startIndex, count);

//        public str replace(str oldValue, str newValue) => v.Replace(oldValue ?? "", newValue ?? "");

//        public str reverse() => new string(v.Reverse().ToArray());

//        public bool startsWith(str value) => v.StartsWith(value);
//        public bool startsWith(str value, StringComparison comparisonType) => v.StartsWith(value, comparisonType);

//        public bool endsWith(str value) => v.EndsWith(value);
//        public bool endsWith(str value, StringComparison comparisonType) => v.EndsWith(value, comparisonType);

//        public str substring(i32 startIndex) => v.Substring(startIndex);
//        public str substring(i32 startIndex, i32 count) => v.Substring(startIndex, count);

//        public str join(str j) => string.Join(j, v);

//        public str toUpper() => v.ToUpper();
//        public str toLower() => v.ToLower();

//        public str trim() => v.Trim();
//        public str trimEnd() => v.TrimEnd();
//        public str trimStart() => v.TrimStart();

//        public string toValue() => v;
//        public object toAny() => v;
//    }

//    [JsonConverter(typeof(chrConverter))]
//    public class chr : IComparable, iXsValue
//    {
//        private char v;
//        public chr() { }
//        public chr(object o)
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
//                    v = Convert.ToChar(o);
//                    break;

//                case iXsValue i:
//                    v = i.toChr();
//                    break;
//                default:
//                    throw new Exception("not support type");
//            }
//        }

//        public static implicit operator chr(char it) => new chr(it);
//        public static implicit operator char(chr it) => it.v;

//        public override bool Equals(object o)
//        {
//            if (o == null)
//            {
//                return this == null;
//            }
//            else if (o is chr b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(chr b) => b != null && v == b.v;

//        public int CompareTo(object obj) => v.CompareTo(obj.ToString());

//        public chr maxValue { get => char.MaxValue; }
//        public chr minValue { get => char.MinValue; }

//        public chr toLower() => char.ToLower(v);
//        public chr toUpper() => char.ToUpper(v);

//        public bool isLower() => char.IsLower(v);
//        public bool isUpper() => char.IsUpper(v);

//        public bool isLetter() => char.IsLetter(v);
//        public bool isDigit() => char.IsDigit(v);
//        public bool isLetterOrDigit() => char.IsLetterOrDigit(v);

//        public bool isNumber() => char.IsNumber(v);
//        public bool isSymbol() => char.IsSymbol(v);
//        public bool isWhiteSpace() => char.IsWhiteSpace(v);
//        public bool isControl() => char.IsControl(v);

//        public double getNumericValue() => char.GetNumericValue(v);

//        public override string ToString() => v.ToString();
//        public string ToString(string format) => v.ToString();

//        public char toValue() => v;
//        public object toAny() => v;
//    }

//    public class strConverter : JsonConverter<str>
//    {
//        public override void WriteJson(JsonWriter writer, str value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override str ReadJson(JsonReader reader, Type objectType, str existingValue, bool hasExistingValue, JsonSerializer serializer) => new str((string)reader.Value);
//    }

//    public class chrConverter : JsonConverter<chr>
//    {
//        public override void WriteJson(JsonWriter writer, chr value, JsonSerializer serializer) => writer.WriteValue(value);
//        public override chr ReadJson(JsonReader reader, Type objectType, chr existingValue, bool hasExistingValue, JsonSerializer serializer) => new chr((char)reader.Value);
//    }
//}
