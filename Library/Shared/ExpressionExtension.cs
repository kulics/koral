using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Library {
    public static partial class ExpressionExtension {
        // object 
        public static string ToStr(this object it) => it.ToString();
        public static T To<T>(this object it) => (T)it;
        public static bool Is<T>(this object it) => it is T;
        public static T As<T>(this object it) where T : class => it as T;
        public static T Def<T>(this T it, T value) where T : class => it != null ? it : value;
        public static T Default<T>(this T it, T value) where T : class => it.Def(value);

        public static sbyte ToI8(this object it) => Convert.ToSByte(it);
        public static short ToI16(this object it) => Convert.ToInt16(it);
        public static int ToI32(this object it) => Convert.ToInt32(it);
        public static long ToI64(this object it) => Convert.ToInt64(it);
        public static byte ToU8(this object it) => Convert.ToByte(it);
        public static ushort ToU16(this object it) => Convert.ToUInt16(it);
        public static uint ToU32(this object it) => Convert.ToUInt32(it);
        public static ulong ToU64(this object it) => Convert.ToUInt64(it);
        public static float ToF32(this object it) => Convert.ToSingle(it);
        public static double ToF64(this object it) => Convert.ToDouble(it);
        // sbyte
        public static string ToStr(this sbyte it, string format) => it.ToString(format);
        public static string ToBase(this sbyte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte ToI8(this sbyte it) => Convert.ToSByte(it);
        public static short ToI16(this sbyte it) => Convert.ToInt16(it);
        public static int ToI32(this sbyte it) => Convert.ToInt32(it);
        public static long ToI64(this sbyte it) => Convert.ToInt64(it);
        public static byte ToU8(this sbyte it) => Convert.ToByte(it);
        public static ushort ToU16(this sbyte it) => Convert.ToUInt16(it);
        public static uint ToU32(this sbyte it) => Convert.ToUInt32(it);
        public static ulong ToU64(this sbyte it) => Convert.ToUInt64(it);
        public static float ToF32(this sbyte it) => Convert.ToSingle(it);
        public static double ToF64(this sbyte it) => Convert.ToDouble(it);

        public static sbyte And(this sbyte it, sbyte v) => Convert.ToSByte(it & v);
        public static sbyte Or(this sbyte it, sbyte v) => Convert.ToSByte(it | v);
        public static sbyte Xor(this sbyte it, sbyte v) => Convert.ToSByte(it ^ v);
        public static sbyte Not(this sbyte it) => Convert.ToSByte(~it);
        public static sbyte Lft(this sbyte it, int v) => Convert.ToSByte(it << v);
        public static sbyte Rht(this sbyte it, int v) => Convert.ToSByte(it >> v);
        // byte
        public static string ToStr(this byte it, string format) => it.ToString(format);
        public static string ToBase(this byte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte ToI8(this byte it) => Convert.ToSByte(it);
        public static short ToI16(this byte it) => Convert.ToInt16(it);
        public static int ToI32(this byte it) => Convert.ToInt32(it);
        public static long ToI64(this byte it) => Convert.ToInt64(it);
        public static byte ToU8(this byte it) => Convert.ToByte(it);
        public static ushort ToU16(this byte it) => Convert.ToUInt16(it);
        public static uint ToU32(this byte it) => Convert.ToUInt32(it);
        public static ulong ToU64(this byte it) => Convert.ToUInt64(it);
        public static float ToF32(this byte it) => Convert.ToSingle(it);
        public static double ToF64(this byte it) => Convert.ToDouble(it);

        public static byte And(this byte it, byte v) => Convert.ToByte(it & v);
        public static byte Or(this byte it, byte v) => Convert.ToByte(it | v);
        public static byte Xor(this byte it, byte v) => Convert.ToByte(it ^ v);
        public static byte Not(this byte it) => Convert.ToByte(~it);
        public static byte Lft(this byte it, int v) => Convert.ToByte(it << v);
        public static byte Rht(this byte it, int v) => Convert.ToByte(it >> v);

        // short
        public static string ToStr(this short it, string format) => it.ToString(format);
        public static string ToBase(this short it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte ToI8(this short it) => Convert.ToSByte(it);
        public static short ToI16(this short it) => Convert.ToInt16(it);
        public static int ToI32(this short it) => Convert.ToInt32(it);
        public static long ToI64(this short it) => Convert.ToInt64(it);
        public static byte ToU8(this short it) => Convert.ToByte(it);
        public static ushort ToU16(this short it) => Convert.ToUInt16(it);
        public static uint ToU32(this short it) => Convert.ToUInt32(it);
        public static ulong ToU64(this short it) => Convert.ToUInt64(it);
        public static float ToF32(this short it) => Convert.ToSingle(it);
        public static double ToF64(this short it) => Convert.ToDouble(it);

        public static short And(this short it, short v) => Convert.ToInt16(it & v);
        public static short Or(this short it, short v) => Convert.ToInt16(it | v);
        public static short Xor(this short it, short v) => Convert.ToInt16(it ^ v);
        public static short Not(this short it) => Convert.ToInt16(~it);
        public static short Lft(this short it, int v) => Convert.ToInt16(it << v);
        public static short Rht(this short it, int v) => Convert.ToInt16(it >> v);

        // ushort
        public static string ToStr(this ushort it, string format) => it.ToString(format);
        public static string ToBase(this ushort it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte ToI8(this ushort it) => Convert.ToSByte(it);
        public static short ToI16(this ushort it) => Convert.ToInt16(it);
        public static int ToI32(this ushort it) => Convert.ToInt32(it);
        public static long ToI64(this ushort it) => Convert.ToInt64(it);
        public static byte ToU8(this ushort it) => Convert.ToByte(it);
        public static ushort ToU16(this ushort it) => Convert.ToUInt16(it);
        public static uint ToU32(this ushort it) => Convert.ToUInt32(it);
        public static ulong ToU64(this ushort it) => Convert.ToUInt64(it);
        public static float ToF32(this ushort it) => Convert.ToSingle(it);
        public static double ToF64(this ushort it) => Convert.ToDouble(it);

        public static ushort And(this ushort it, ushort v) => Convert.ToUInt16(it & v);
        public static ushort Or(this ushort it, ushort v) => Convert.ToUInt16(it | v);
        public static ushort Xor(this ushort it, ushort v) => Convert.ToUInt16(it ^ v);
        public static ushort Not(this ushort it) => Convert.ToUInt16(~it);
        public static ushort Lft(this ushort it, int v) => Convert.ToUInt16(it << v);
        public static ushort Rht(this ushort it, int v) => Convert.ToUInt16(it >> v);

        // int
        public static string ToStr(this int it, string format) => it.ToString(format);
        public static string ToBase(this int it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte ToI8(this int it) => Convert.ToSByte(it);
        public static short ToI16(this int it) => Convert.ToInt16(it);
        public static int ToI32(this int it) => Convert.ToInt32(it);
        public static long ToI64(this int it) => Convert.ToInt64(it);
        public static byte ToU8(this int it) => Convert.ToByte(it);
        public static ushort ToU16(this int it) => Convert.ToUInt16(it);
        public static uint ToU32(this int it) => Convert.ToUInt32(it);
        public static ulong ToU64(this int it) => Convert.ToUInt64(it);
        public static float ToF32(this int it) => Convert.ToSingle(it);
        public static double ToF64(this int it) => Convert.ToDouble(it);

        public static int And(this int it, int v) => Convert.ToInt32(it & v);
        public static int Or(this int it, int v) => Convert.ToInt32(it | v);
        public static int Xor(this int it, int v) => Convert.ToInt32(it ^ v);
        public static int Not(this int it) => Convert.ToInt32(~it);
        public static int Lft(this int it, int v) => Convert.ToInt32(it << v);
        public static int Rht(this int it, int v) => Convert.ToInt32(it >> v);

        // uint
        public static string ToStr(this uint it, string format) => it.ToString(format);
        public static string ToBase(this uint it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte ToI8(this uint it) => Convert.ToSByte(it);
        public static short ToI16(this uint it) => Convert.ToInt16(it);
        public static int ToI32(this uint it) => Convert.ToInt32(it);
        public static long ToI64(this uint it) => Convert.ToInt64(it);
        public static byte ToU8(this uint it) => Convert.ToByte(it);
        public static ushort ToU16(this uint it) => Convert.ToUInt16(it);
        public static uint ToU32(this uint it) => Convert.ToUInt32(it);
        public static ulong ToU64(this uint it) => Convert.ToUInt64(it);
        public static float ToF32(this uint it) => Convert.ToSingle(it);
        public static double ToF64(this uint it) => Convert.ToDouble(it);

        public static uint And(this uint it, uint v) => Convert.ToUInt32(it & v);
        public static uint Or(this uint it, uint v) => Convert.ToUInt32(it | v);
        public static uint Xor(this uint it, uint v) => Convert.ToUInt32(it ^ v);
        public static uint Not(this uint it) => Convert.ToUInt32(~it);
        public static uint Lft(this uint it, int v) => Convert.ToUInt32(it << v);
        public static uint Rht(this uint it, int v) => Convert.ToUInt32(it >> v);

        // long
        public static string ToStr(this long it, string format) => it.ToString(format);
        public static string ToBase(this long it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte ToI8(this long it) => Convert.ToSByte(it);
        public static short ToI16(this long it) => Convert.ToInt16(it);
        public static int ToI32(this long it) => Convert.ToInt32(it);
        public static long ToI64(this long it) => Convert.ToInt64(it);
        public static byte ToU8(this long it) => Convert.ToByte(it);
        public static ushort ToU16(this long it) => Convert.ToUInt16(it);
        public static uint ToU32(this long it) => Convert.ToUInt32(it);
        public static ulong ToU64(this long it) => Convert.ToUInt64(it);
        public static float ToF32(this long it) => Convert.ToSingle(it);
        public static double ToF64(this long it) => Convert.ToDouble(it);

        public static long And(this long it, long v) => Convert.ToInt64(it & v);
        public static long Or(this long it, long v) => Convert.ToInt64(it | v);
        public static long Xor(this long it, long v) => Convert.ToInt64(it ^ v);
        public static long Not(this long it) => Convert.ToInt64(~it);
        public static long Lft(this long it, int v) => Convert.ToInt64(it << v);
        public static long Rht(this long it, int v) => Convert.ToInt64(it >> v);

        // ulong
        public static string ToStr(this ulong it, string format) => it.ToString(format);
        public static string ToBase(this ulong it, int fromBase) => Convert.ToString((long)it, fromBase);
        public static sbyte ToI8(this ulong it) => Convert.ToSByte(it);
        public static short ToI16(this ulong it) => Convert.ToInt16(it);
        public static int ToI32(this ulong it) => Convert.ToInt32(it);
        public static long ToI64(this ulong it) => Convert.ToInt64(it);
        public static byte ToU8(this ulong it) => Convert.ToByte(it);
        public static ushort ToU16(this ulong it) => Convert.ToUInt16(it);
        public static uint ToU32(this ulong it) => Convert.ToUInt32(it);
        public static ulong ToU64(this ulong it) => Convert.ToUInt64(it);
        public static float ToF32(this ulong it) => Convert.ToSingle(it);
        public static double ToF64(this ulong it) => Convert.ToDouble(it);

        public static ulong And(this ulong it, ulong v) => Convert.ToUInt64(it & v);
        public static ulong Or(this ulong it, ulong v) => Convert.ToUInt64(it | v);
        public static ulong Xor(this ulong it, ulong v) => Convert.ToUInt64(it ^ v);
        public static ulong Not(this ulong it) => Convert.ToUInt64(~it);
        public static ulong Lft(this ulong it, int v) => Convert.ToUInt64(it << v);
        public static ulong Rht(this ulong it, int v) => Convert.ToUInt64(it >> v);

        // float
        public static string ToStr(this float it, string format) => it.ToString(format);
        public static sbyte ToI8(this float it) => Convert.ToSByte(it);
        public static short ToI16(this float it) => Convert.ToInt16(it);
        public static int ToI32(this float it) => Convert.ToInt32(it);
        public static long ToI64(this float it) => Convert.ToInt64(it);
        public static byte ToU8(this float it) => Convert.ToByte(it);
        public static ushort ToU16(this float it) => Convert.ToUInt16(it);
        public static uint ToU32(this float it) => Convert.ToUInt32(it);
        public static ulong ToU64(this float it) => Convert.ToUInt64(it);
        public static float ToF32(this float it) => Convert.ToSingle(it);
        public static double ToF64(this float it) => Convert.ToDouble(it);

        // double
        public static string ToStr(this double it, string format) => it.ToString(format);
        public static sbyte ToI8(this double it) => Convert.ToSByte(it);
        public static short ToI16(this double it) => Convert.ToInt16(it);
        public static int ToI32(this double it) => Convert.ToInt32(it);
        public static long ToI64(this double it) => Convert.ToInt64(it);
        public static byte ToU8(this double it) => Convert.ToByte(it);
        public static ushort ToU16(this double it) => Convert.ToUInt16(it);
        public static uint ToU32(this double it) => Convert.ToUInt32(it);
        public static ulong ToU64(this double it) => Convert.ToUInt64(it);
        public static float ToF32(this double it) => Convert.ToSingle(it);
        public static double ToF64(this double it) => Convert.ToDouble(it);

        // Char
        public static string ToStr(this char it, string format) => it.ToString();
        public static sbyte ToI8(this char it) => Convert.ToSByte(it);
        public static short ToI16(this char it) => Convert.ToInt16(it);
        public static int ToI32(this char it) => Convert.ToInt32(it);
        public static long ToI64(this char it) => Convert.ToInt64(it);
        public static byte ToU8(this char it) => Convert.ToByte(it);
        public static ushort ToU16(this char it) => Convert.ToUInt16(it);
        public static uint ToU32(this char it) => Convert.ToUInt32(it);
        public static ulong ToU64(this char it) => Convert.ToUInt64(it);
        public static float ToF32(this char it) => Convert.ToSingle(it);
        public static double ToF64(this char it) => Convert.ToDouble(it);

        public static char ToLower(this char it) => char.ToLower(it);
        public static char ToUpper(this char it) => char.ToUpper(it);

        public static bool IsLower(this char it) => char.IsLower(it);
        public static bool IsUpper(this char it) => char.IsUpper(it);

        public static bool IsLetter(this char it) => char.IsLetter(it);
        public static bool IsDigit(this char it) => char.IsDigit(it);
        public static bool IsLetterOrDigit(this char it) => char.IsLetterOrDigit(it);

        public static bool IsNumber(this char it) => char.IsNumber(it);
        public static bool IsSymbol(this char it) => char.IsSymbol(it);
        public static bool IsWhiteSpace(this char it) => char.IsWhiteSpace(it);
        public static bool IsControl(this char it) => char.IsControl(it);

        // String
        public static bool NotEmpty(this string it) => !it.IsEmpty();
        public static bool IsEmpty(this string it) => string.IsNullOrEmpty(it);
        public static string SubStr(this string it, int startIndex, int length) => it.Substring(startIndex, length);
        public static string SubStr(this string it, int startIndex) => it.Substring(startIndex);

        public static string Replace(this string it, string older, string newer) => it.Replace(older, newer);
        public static int Len(this string it) => it.Length;
        public static int Length(this string it) => it.Length;
        public static int LastIndex(this string it) => it.Length - 1;

        public static bool Contains(this string it, string value) => it.Contains(value);

        public static int FindFirst(this string it, Func<char, bool> fn) {
            for (int i = 0; i < it.Len(); i++) {
                if (fn(it[i])) {
                    return i;
                }
            }
            return 0;
        }

        public static int FirstIndexOf(this string it, string value, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, comparisonType);
        public static int FirstIndexOf(this string it, string value, int startIndex, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, startIndex, comparisonType);
        public static int FirstIndexOf(this string it, string value, int startIndex, int count, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, startIndex, count, comparisonType);

        public static int LastIndexOf(this string it, string value, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, comparisonType);
        public static int LastIndexOf(this string it, string value, int startIndex, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, startIndex, comparisonType);
        public static int LastIndexOf(this string it, string value, int startIndex, int count, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, startIndex, count, comparisonType);


        public static string[] Split(this string it, string[] separator, StringSplitOptions options = StringSplitOptions.None) => it.Split(separator, options);
        public static string Slice(this string it, int? startIndex, int? endIndex) {
            if (startIndex == null && endIndex == null) {
                return it;
            } else if (endIndex == null) {
                return it.SubStr(startIndex ?? 0, it.LastIndex() - startIndex ?? 0);
            } else // (startIndex == null)
              {
                return it.SubStr(0, it.LastIndex() - endIndex ?? 0);
            }
        }
        
        public static string Join(this string it, string j) => string.Join(j, it);

        public static string ToStr(this string it, string format) => it;
        public static sbyte ToI8(this string it) => Convert.ToSByte(it);
        public static short ToI16(this string it) => Convert.ToInt16(it);
        public static int ToI32(this string it) => Convert.ToInt32(it);
        public static long ToI64(this string it) => Convert.ToInt64(it);
        public static byte ToU8(this string it) => Convert.ToByte(it);
        public static ushort ToU16(this string it) => Convert.ToUInt16(it);
        public static uint ToU32(this string it) => Convert.ToUInt32(it);
        public static ulong ToU64(this string it) => Convert.ToUInt64(it);
        public static float ToF32(this string it) => Convert.ToSingle(it);
        public static double ToF64(this string it) => Convert.ToDouble(it);

        public static sbyte ToI8FromBase(this string it, int fromBase) => Convert.ToSByte(it, fromBase);
        public static short ToI16FromBase(this string it, int fromBase) => Convert.ToInt16(it, fromBase);
        public static int ToI32FromBase(this string it, int fromBase) => Convert.ToInt32(it, fromBase);
        public static long ToI64FromBase(this string it, int fromBase) => Convert.ToInt64(it, fromBase);
        public static byte ToU8FromBase(this string it, int fromBase) => Convert.ToByte(it, fromBase);
        public static ushort ToU16FromBase(this string it, int fromBase) => Convert.ToUInt16(it, fromBase);
        public static uint ToU32FromBase(this string it, int fromBase) => Convert.ToUInt32(it, fromBase);
        public static ulong ToU64FromBase(this string it, int fromBase) => Convert.ToUInt64(it, fromBase);
        
        public static IEnumerable<(int index, T item)> Range<T>(this IEnumerable<T> self)
   => self.Select((item, index) => (index, item));

        public static IEnumerable<(TKey, TValue)> Range<TKey, TValue>(this IEnumerable<KeyValuePair<TKey, TValue>> self)
   => self.Select((item) => (item.Key, item.Value));
    }
}
