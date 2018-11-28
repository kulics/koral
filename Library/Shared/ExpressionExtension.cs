using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Library
{
    public static class ExpressionExtension
    {
        // object 
        public static string toStr(this object it) => it.ToString();
        public static T to<T>(this object it)
        {
            return (T)it;
        }
        public static bool @is<T>(this object it)
        {
            return it is T;
        }
        public static T @as<T>(this object it) where T : class
        {
            return it as T;
        }

        public static sbyte toI8(this object it) => Convert.ToSByte(it);
        public static short toI16(this object it) => Convert.ToInt16(it);
        public static int toint(this object it) => Convert.ToInt32(it);
        public static long toI64(this object it) => Convert.ToInt64(it);
        public static byte toU8(this object it) => Convert.ToByte(it);
        public static ushort toU16(this object it) => Convert.ToUInt16(it);
        public static uint toU32(this object it) => Convert.ToUInt32(it);
        public static ulong toU64(this object it) => Convert.ToUInt64(it);
        public static float toF32(this object it) => Convert.ToSingle(it);
        public static double toF64(this object it) => Convert.ToDouble(it);
        // sbyte
        public static string toStr(this sbyte it, string format) => it.ToString(format);
        public static string toBase(this sbyte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte toI8(this sbyte it) => Convert.ToSByte(it);
        public static short toI16(this sbyte it) => Convert.ToInt16(it);
        public static int toint(this sbyte it) => Convert.ToInt32(it);
        public static long toI64(this sbyte it) => Convert.ToInt64(it);
        public static byte toU8(this sbyte it) => Convert.ToByte(it);
        public static ushort toU16(this sbyte it) => Convert.ToUInt16(it);
        public static uint toU32(this sbyte it) => Convert.ToUInt32(it);
        public static ulong toU64(this sbyte it) => Convert.ToUInt64(it);
        public static float toF32(this sbyte it) => Convert.ToSingle(it);
        public static double toF64(this sbyte it) => Convert.ToDouble(it);

        public static sbyte and(this sbyte it, sbyte v) => Convert.ToSByte(it & v);
        public static sbyte or(this sbyte it, sbyte v) => Convert.ToSByte(it | v);
        public static sbyte xor(this sbyte it, sbyte v) => Convert.ToSByte(it ^ v);
        public static sbyte not(this sbyte it) => Convert.ToSByte(~it);
        public static sbyte lft(this sbyte it, int v) => Convert.ToSByte(it << v);
        public static sbyte rht(this sbyte it, int v) => Convert.ToSByte(it >> v);
        // byte
        public static string toStr(this byte it, string format) => it.ToString(format);
        public static string toBase(this byte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte toI8(this byte it) => Convert.ToSByte(it);
        public static short toI16(this byte it) => Convert.ToInt16(it);
        public static int toint(this byte it) => Convert.ToInt32(it);
        public static long toI64(this byte it) => Convert.ToInt64(it);
        public static byte toU8(this byte it) => Convert.ToByte(it);
        public static ushort toU16(this byte it) => Convert.ToUInt16(it);
        public static uint toU32(this byte it) => Convert.ToUInt32(it);
        public static ulong toU64(this byte it) => Convert.ToUInt64(it);
        public static float toF32(this byte it) => Convert.ToSingle(it);
        public static double toF64(this byte it) => Convert.ToDouble(it);

        public static byte and(this byte it, byte v) => Convert.ToByte(it & v);
        public static byte or(this byte it, byte v) => Convert.ToByte(it | v);
        public static byte xor(this byte it, byte v) => Convert.ToByte(it ^ v);
        public static byte not(this byte it) => Convert.ToByte(~it);
        public static byte lft(this byte it, int v) => Convert.ToByte(it << v);
        public static byte rht(this byte it, int v) => Convert.ToByte(it >> v);

        // short
        public static string toStr(this short it, string format) => it.ToString(format);
        public static string toBase(this short it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte toI8(this short it) => Convert.ToSByte(it);
        public static short toI16(this short it) => Convert.ToInt16(it);
        public static int toint(this short it) => Convert.ToInt32(it);
        public static long toI64(this short it) => Convert.ToInt64(it);
        public static byte toU8(this short it) => Convert.ToByte(it);
        public static ushort toU16(this short it) => Convert.ToUInt16(it);
        public static uint toU32(this short it) => Convert.ToUInt32(it);
        public static ulong toU64(this short it) => Convert.ToUInt64(it);
        public static float toF32(this short it) => Convert.ToSingle(it);
        public static double toF64(this short it) => Convert.ToDouble(it);

        public static short and(this short it, short v) => Convert.ToInt16(it & v);
        public static short or(this short it, short v) => Convert.ToInt16(it | v);
        public static short xor(this short it, short v) => Convert.ToInt16(it ^ v);
        public static short not(this short it) => Convert.ToInt16(~it);
        public static short lft(this short it, int v) => Convert.ToInt16(it << v);
        public static short rht(this short it, int v) => Convert.ToInt16(it >> v);

        // ushort
        public static string toStr(this ushort it, string format) => it.ToString(format);
        public static string toBase(this ushort it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte toI8(this ushort it) => Convert.ToSByte(it);
        public static short toI16(this ushort it) => Convert.ToInt16(it);
        public static int toint(this ushort it) => Convert.ToInt32(it);
        public static long toI64(this ushort it) => Convert.ToInt64(it);
        public static byte toU8(this ushort it) => Convert.ToByte(it);
        public static ushort toU16(this ushort it) => Convert.ToUInt16(it);
        public static uint toU32(this ushort it) => Convert.ToUInt32(it);
        public static ulong toU64(this ushort it) => Convert.ToUInt64(it);
        public static float toF32(this ushort it) => Convert.ToSingle(it);
        public static double toF64(this ushort it) => Convert.ToDouble(it);

        public static ushort and(this ushort it, ushort v) => Convert.ToUInt16(it & v);
        public static ushort or(this ushort it, ushort v) => Convert.ToUInt16(it | v);
        public static ushort xor(this ushort it, ushort v) => Convert.ToUInt16(it ^ v);
        public static ushort not(this ushort it) => Convert.ToUInt16(~it);
        public static ushort lft(this ushort it, int v) => Convert.ToUInt16(it << v);
        public static ushort rht(this ushort it, int v) => Convert.ToUInt16(it >> v);

        // int
        public static string toStr(this int it, string format) => it.ToString(format);
        public static string toBase(this int it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte toI8(this int it) => Convert.ToSByte(it);
        public static short toI16(this int it) => Convert.ToInt16(it);
        public static int toint(this int it) => Convert.ToInt32(it);
        public static long toI64(this int it) => Convert.ToInt64(it);
        public static byte toU8(this int it) => Convert.ToByte(it);
        public static ushort toU16(this int it) => Convert.ToUInt16(it);
        public static uint toU32(this int it) => Convert.ToUInt32(it);
        public static ulong toU64(this int it) => Convert.ToUInt64(it);
        public static float toF32(this int it) => Convert.ToSingle(it);
        public static double toF64(this int it) => Convert.ToDouble(it);

        public static int and(this int it, int v) => Convert.ToInt32(it & v);
        public static int or(this int it, int v) => Convert.ToInt32(it | v);
        public static int xor(this int it, int v) => Convert.ToInt32(it ^ v);
        public static int not(this int it) => Convert.ToInt32(~it);
        public static int lft(this int it, int v) => Convert.ToInt32(it << v);
        public static int rht(this int it, int v) => Convert.ToInt32(it >> v);

        // uint
        public static string toStr(this uint it, string format) => it.ToString(format);
        public static string toBase(this uint it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte toI8(this uint it) => Convert.ToSByte(it);
        public static short toI16(this uint it) => Convert.ToInt16(it);
        public static int toint(this uint it) => Convert.ToInt32(it);
        public static long toI64(this uint it) => Convert.ToInt64(it);
        public static byte toU8(this uint it) => Convert.ToByte(it);
        public static ushort toU16(this uint it) => Convert.ToUInt16(it);
        public static uint toU32(this uint it) => Convert.ToUInt32(it);
        public static ulong toU64(this uint it) => Convert.ToUInt64(it);
        public static float toF32(this uint it) => Convert.ToSingle(it);
        public static double toF64(this uint it) => Convert.ToDouble(it);

        public static uint and(this uint it, uint v) => Convert.ToUInt32(it & v);
        public static uint or(this uint it, uint v) => Convert.ToUInt32(it | v);
        public static uint xor(this uint it, uint v) => Convert.ToUInt32(it ^ v);
        public static uint not(this uint it) => Convert.ToUInt32(~it);
        public static uint lft(this uint it, int v) => Convert.ToUInt32(it << v);
        public static uint rht(this uint it, int v) => Convert.ToUInt32(it >> v);

        // long
        public static string toStr(this long it, string format) => it.ToString(format);
        public static string toBase(this long it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte toI8(this long it) => Convert.ToSByte(it);
        public static short toI16(this long it) => Convert.ToInt16(it);
        public static int toint(this long it) => Convert.ToInt32(it);
        public static long toI64(this long it) => Convert.ToInt64(it);
        public static byte toU8(this long it) => Convert.ToByte(it);
        public static ushort toU16(this long it) => Convert.ToUInt16(it);
        public static uint toU32(this long it) => Convert.ToUInt32(it);
        public static ulong toU64(this long it) => Convert.ToUInt64(it);
        public static float toF32(this long it) => Convert.ToSingle(it);
        public static double toF64(this long it) => Convert.ToDouble(it);

        public static long and(this long it, long v) => Convert.ToInt64(it & v);
        public static long or(this long it, long v) => Convert.ToInt64(it | v);
        public static long xor(this long it, long v) => Convert.ToInt64(it ^ v);
        public static long not(this long it) => Convert.ToInt64(~it);
        public static long lft(this long it, int v) => Convert.ToInt64(it << v);
        public static long rht(this long it, int v) => Convert.ToInt64(it >> v);

        // ulong
        public static string toStr(this ulong it, string format) => it.ToString(format);
        public static string toBase(this ulong it, int fromBase) => Convert.ToString((long)it, fromBase);
        public static sbyte toI8(this ulong it) => Convert.ToSByte(it);
        public static short toI16(this ulong it) => Convert.ToInt16(it);
        public static int toint(this ulong it) => Convert.ToInt32(it);
        public static long toI64(this ulong it) => Convert.ToInt64(it);
        public static byte toU8(this ulong it) => Convert.ToByte(it);
        public static ushort toU16(this ulong it) => Convert.ToUInt16(it);
        public static uint toU32(this ulong it) => Convert.ToUInt32(it);
        public static ulong toU64(this ulong it) => Convert.ToUInt64(it);
        public static float toF32(this ulong it) => Convert.ToSingle(it);
        public static double toF64(this ulong it) => Convert.ToDouble(it);

        public static ulong and(this ulong it, ulong v) => Convert.ToUInt64(it & v);
        public static ulong or(this ulong it, ulong v) => Convert.ToUInt64(it | v);
        public static ulong xor(this ulong it, ulong v) => Convert.ToUInt64(it ^ v);
        public static ulong not(this ulong it) => Convert.ToUInt64(~it);
        public static ulong lft(this ulong it, int v) => Convert.ToUInt64(it << v);
        public static ulong rht(this ulong it, int v) => Convert.ToUInt64(it >> v);

        // float
        public static string toStr(this float it, string format) => it.ToString(format);
        public static sbyte toI8(this float it) => Convert.ToSByte(it);
        public static short toI16(this float it) => Convert.ToInt16(it);
        public static int toint(this float it) => Convert.ToInt32(it);
        public static long toI64(this float it) => Convert.ToInt64(it);
        public static byte toU8(this float it) => Convert.ToByte(it);
        public static ushort toU16(this float it) => Convert.ToUInt16(it);
        public static uint toU32(this float it) => Convert.ToUInt32(it);
        public static ulong toU64(this float it) => Convert.ToUInt64(it);
        public static float toF32(this float it) => Convert.ToSingle(it);
        public static double toF64(this float it) => Convert.ToDouble(it);

        // double
        public static string toStr(this double it, string format) => it.ToString(format);
        public static sbyte toI8(this double it) => Convert.ToSByte(it);
        public static short toI16(this double it) => Convert.ToInt16(it);
        public static int toint(this double it) => Convert.ToInt32(it);
        public static long toI64(this double it) => Convert.ToInt64(it);
        public static byte toU8(this double it) => Convert.ToByte(it);
        public static ushort toU16(this double it) => Convert.ToUInt16(it);
        public static uint toU32(this double it) => Convert.ToUInt32(it);
        public static ulong toU64(this double it) => Convert.ToUInt64(it);
        public static float toF32(this double it) => Convert.ToSingle(it);
        public static double toF64(this double it) => Convert.ToDouble(it);

        // Char
        public static string toStr(this char it, string format) => it.ToString();
        public static sbyte toI8(this char it) => Convert.ToSByte(it);
        public static short toI16(this char it) => Convert.ToInt16(it);
        public static int toint(this char it) => Convert.ToInt32(it);
        public static long toI64(this char it) => Convert.ToInt64(it);
        public static byte toU8(this char it) => Convert.ToByte(it);
        public static ushort toU16(this char it) => Convert.ToUInt16(it);
        public static uint toU32(this char it) => Convert.ToUInt32(it);
        public static ulong toU64(this char it) => Convert.ToUInt64(it);
        public static float toF32(this char it) => Convert.ToSingle(it);
        public static double toF64(this char it) => Convert.ToDouble(it);

        public static char toLower(this char it) => char.ToLower(it);
        public static char toUpper(this char it) => char.ToUpper(it);

        public static bool isLower(this char it) => char.IsLower(it);
        public static bool isUpper(this char it) => char.IsUpper(it);

        public static bool isLetter(this char it) => char.IsLetter(it);
        public static bool isDigit(this char it) => char.IsDigit(it);
        public static bool isLetterOrDigit(this char it) => char.IsLetterOrDigit(it);

        public static bool isNumber(this char it) => char.IsNumber(it);
        public static bool isSymbol(this char it) => char.IsSymbol(it);
        public static bool isWhiteSpace(this char it) => char.IsWhiteSpace(it);
        public static bool isControl(this char it) => char.IsControl(it);

        // String
        public static bool notEmpty(this string it) => !it.isEmpty();
        public static bool isEmpty(this string it) => string.IsNullOrEmpty(it);
        public static string subStr(this string it, int startIndex, int length) => it.Substring(startIndex, length);
        public static string subStr(this string it, int startIndex) => it.Substring(startIndex);

        public static string replace(this string it, string older, string newer) => it.Replace(older, newer);
        public static int count(this string it) => it.Length;
        public static int lastIndex(this string it) => it.Length - 1;

        public static bool contains(this string it, string value) => it.Contains(value);

        public static int findFirst(this string it, Func<char,bool> fn)
        {
            for (int i = 0; i < it.count(); i++)
            {
                if (fn(it[i]))
                {
                    return i;
                }
            }
            return 0;
        }

        public static int firstIndexOf(this string it, string value, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, comparisonType);
        public static int firstIndexOf(this string it, string value, int startIndex, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, startIndex, comparisonType);
        public static int firstIndexOf(this string it, string value, int startIndex, int count, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, startIndex, count, comparisonType);

        public static int lastIndexOf(this string it, string value, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, comparisonType);
        public static int lastIndexOf(this string it, string value, int startIndex, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, startIndex, comparisonType);
        public static int lastIndexOf(this string it, string value, int startIndex, int count, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, startIndex, count, comparisonType);


        public static string[] split(this string it, string[] separator, StringSplitOptions options = StringSplitOptions.None) => it.Split(separator,options);
        public static string slice(this string it, int? startIndex, int? endIndex)
        {
            if (startIndex == null && endIndex == null)
            {
                return it;
            }
            else if (endIndex == null)
            {
                return it.subStr(startIndex??0, it.lastIndex() - startIndex??0);
            }
            else // (startIndex == null)
            {
                return it.subStr(0, it.lastIndex() - endIndex??0);
            }
        }

        public static string normalize(this string it, NormalizationForm normalizationForm = NormalizationForm.FormC) => it.Normalize(normalizationForm);

        public static string remove(this string it, int startIndex) => it.Remove(startIndex);
        public static string remove(this string it, int startIndex, int count) => it.Remove(startIndex, count);

        public static string reverse(this string it) => new string(it.Reverse().ToArray());

        public static bool startsWith(this string it, string value) => it.StartsWith(value);
        public static bool startsWith(this string it, string value, StringComparison comparisonType) => it.StartsWith(value, comparisonType);

        public static bool endsWith(this string it, string value) => it.EndsWith(value);
        public static bool endsWith(this string it, string value, StringComparison comparisonType) => it.EndsWith(value, comparisonType);

        public static string substring(this string it, int startIndex) => it.Substring(startIndex);
        public static string substring(this string it, int startIndex, int count) => it.Substring(startIndex, count);

        public static string join(this string it, string j) => string.Join(j, it);

        public static string toUpper(this string it) => it.ToUpper();
        public static string toLower(this string it) => it.ToLower();

        public static string trim(this string it) => it.Trim();
        public static string trimEnd(this string it) => it.TrimEnd();
        public static string trimStart(this string it) => it.TrimStart();

        public static string toStr(this string it, string format) => it;
        public static sbyte toI8(this string it) => Convert.ToSByte(it);
        public static short toI16(this string it) => Convert.ToInt16(it);
        public static int toint(this string it) => Convert.ToInt32(it);
        public static long toI64(this string it) => Convert.ToInt64(it);
        public static byte toU8(this string it) => Convert.ToByte(it);
        public static ushort toU16(this string it) => Convert.ToUInt16(it);
        public static uint toU32(this string it) => Convert.ToUInt32(it);
        public static ulong toU64(this string it) => Convert.ToUInt64(it);
        public static float toF32(this string it) => Convert.ToSingle(it);
        public static double toF64(this string it) => Convert.ToDouble(it);

        public static sbyte toI8FromBase(this string it, int fromBase) => Convert.ToSByte(it, fromBase);
        public static short toI16FromBase(this string it, int fromBase) => Convert.ToInt16(it, fromBase);
        public static int tointFromBase(this string it, int fromBase) => Convert.ToInt32(it, fromBase);
        public static long toI64FromBase(this string it, int fromBase) => Convert.ToInt64(it, fromBase);
        public static byte toU8FromBase(this string it, int fromBase) => Convert.ToByte(it, fromBase);
        public static ushort toU16FromBase(this string it, int fromBase) => Convert.ToUInt16(it, fromBase);
        public static uint toU32FromBase(this string it, int fromBase) => Convert.ToUInt32(it, fromBase);
        public static ulong toU64FromBase(this string it, int fromBase) => Convert.ToUInt64(it, fromBase);

        public static IEnumerable<(int index, T item)> range<T>(this IEnumerable<T> self)
   => self.Select((item, index) => (index, item));

        public static IEnumerable<(TKey, TValue)> range<TKey, TValue>(this IEnumerable<KeyValuePair<TKey, TValue>> self)
   => self.Select((item) => (item.Key, item.Value));
    }
}
