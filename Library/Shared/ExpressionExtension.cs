using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Library {
    public static partial class ExpressionExtension {
        // object 
        public static string to_Str(this object it) => it.ToString();
        public static T to<T>(this object it) => (T)it;
        public static bool @is<T>(this object it) => it is T;
        public static T @as<T>(this object it) where T : class => it as T;
        public static T or_else<T>(this T it, T value) where T : class => it != null ? it : value;
        public static T or_else<T>(this T? it, T value) where T : struct => it ?? value;

        public static int to_Int(this object it) => Convert.ToInt32(it);
        public static double to_Num(this object it) => Convert.ToDouble(it);
        public static sbyte to_I8(this object it) => Convert.ToSByte(it);
        public static short to_I16(this object it) => Convert.ToInt16(it);
        public static int to_I32(this object it) => Convert.ToInt32(it);
        public static long to_I64(this object it) => Convert.ToInt64(it);
        public static byte to_U8(this object it) => Convert.ToByte(it);
        public static ushort to_U16(this object it) => Convert.ToUInt16(it);
        public static uint to_U32(this object it) => Convert.ToUInt32(it);
        public static ulong to_U64(this object it) => Convert.ToUInt64(it);
        public static float to_F32(this object it) => Convert.ToSingle(it);
        public static double to_F64(this object it) => Convert.ToDouble(it);
        // sbyte
        public static int to_Int(this sbyte it) => Convert.ToInt32(it);
        public static double to_Num(this sbyte it) => Convert.ToDouble(it);
        public static string to_Str(this sbyte it, string format) => it.ToString(format);
        public static string to_Base(this sbyte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_I8(this sbyte it) => Convert.ToSByte(it);
        public static short to_I16(this sbyte it) => Convert.ToInt16(it);
        public static int to_I32(this sbyte it) => Convert.ToInt32(it);
        public static long to_I64(this sbyte it) => Convert.ToInt64(it);
        public static byte to_U8(this sbyte it) => Convert.ToByte(it);
        public static ushort to_U16(this sbyte it) => Convert.ToUInt16(it);
        public static uint to_U32(this sbyte it) => Convert.ToUInt32(it);
        public static ulong to_U64(this sbyte it) => Convert.ToUInt64(it);
        public static float to_F32(this sbyte it) => Convert.ToSingle(it);
        public static double to_F64(this sbyte it) => Convert.ToDouble(it);

        public static sbyte and(this sbyte it, sbyte v) => Convert.ToSByte(it & v);
        public static sbyte or(this sbyte it, sbyte v) => Convert.ToSByte(it | v);
        public static sbyte xor(this sbyte it, sbyte v) => Convert.ToSByte(it ^ v);
        public static sbyte not(this sbyte it) => Convert.ToSByte(~it);
        public static sbyte lft(this sbyte it, int v) => Convert.ToSByte(it << v);
        public static sbyte rht(this sbyte it, int v) => Convert.ToSByte(it >> v);
        // byte
        public static int to_Int(this byte it) => Convert.ToInt32(it);
        public static double to_Num(this byte it) => Convert.ToDouble(it);
        public static string to_Str(this byte it, string format) => it.ToString(format);
        public static string to_Base(this byte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_I8(this byte it) => Convert.ToSByte(it);
        public static short to_I16(this byte it) => Convert.ToInt16(it);
        public static int to_I32(this byte it) => Convert.ToInt32(it);
        public static long to_I64(this byte it) => Convert.ToInt64(it);
        public static byte to_U8(this byte it) => Convert.ToByte(it);
        public static ushort to_U16(this byte it) => Convert.ToUInt16(it);
        public static uint to_U32(this byte it) => Convert.ToUInt32(it);
        public static ulong to_U64(this byte it) => Convert.ToUInt64(it);
        public static float to_F32(this byte it) => Convert.ToSingle(it);
        public static double to_F64(this byte it) => Convert.ToDouble(it);

        public static byte and(this byte it, byte v) => Convert.ToByte(it & v);
        public static byte or(this byte it, byte v) => Convert.ToByte(it | v);
        public static byte xor(this byte it, byte v) => Convert.ToByte(it ^ v);
        public static byte not(this byte it) => Convert.ToByte(~it);
        public static byte lft(this byte it, int v) => Convert.ToByte(it << v);
        public static byte rht(this byte it, int v) => Convert.ToByte(it >> v);

        // short
        public static int to_Int(this short it) => Convert.ToInt32(it);
        public static double to_Num(this short it) => Convert.ToDouble(it);
        public static string to_Str(this short it, string format) => it.ToString(format);
        public static string to_Base(this short it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_I8(this short it) => Convert.ToSByte(it);
        public static short to_I16(this short it) => Convert.ToInt16(it);
        public static int to_I32(this short it) => Convert.ToInt32(it);
        public static long to_I64(this short it) => Convert.ToInt64(it);
        public static byte to_U8(this short it) => Convert.ToByte(it);
        public static ushort to_U16(this short it) => Convert.ToUInt16(it);
        public static uint to_U32(this short it) => Convert.ToUInt32(it);
        public static ulong to_U64(this short it) => Convert.ToUInt64(it);
        public static float to_F32(this short it) => Convert.ToSingle(it);
        public static double to_F64(this short it) => Convert.ToDouble(it);

        public static short and(this short it, short v) => Convert.ToInt16(it & v);
        public static short or(this short it, short v) => Convert.ToInt16(it | v);
        public static short xor(this short it, short v) => Convert.ToInt16(it ^ v);
        public static short not(this short it) => Convert.ToInt16(~it);
        public static short lft(this short it, int v) => Convert.ToInt16(it << v);
        public static short rht(this short it, int v) => Convert.ToInt16(it >> v);

        // ushort
        public static int to_Int(this ushort it) => Convert.ToInt32(it);
        public static double to_Num(this ushort it) => Convert.ToDouble(it);
        public static string to_Str(this ushort it, string format) => it.ToString(format);
        public static string to_Base(this ushort it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_I8(this ushort it) => Convert.ToSByte(it);
        public static short to_I16(this ushort it) => Convert.ToInt16(it);
        public static int to_I32(this ushort it) => Convert.ToInt32(it);
        public static long to_I64(this ushort it) => Convert.ToInt64(it);
        public static byte to_U8(this ushort it) => Convert.ToByte(it);
        public static ushort to_U16(this ushort it) => Convert.ToUInt16(it);
        public static uint to_U32(this ushort it) => Convert.ToUInt32(it);
        public static ulong to_U64(this ushort it) => Convert.ToUInt64(it);
        public static float to_F32(this ushort it) => Convert.ToSingle(it);
        public static double to_F64(this ushort it) => Convert.ToDouble(it);

        public static ushort and(this ushort it, ushort v) => Convert.ToUInt16(it & v);
        public static ushort or(this ushort it, ushort v) => Convert.ToUInt16(it | v);
        public static ushort xor(this ushort it, ushort v) => Convert.ToUInt16(it ^ v);
        public static ushort not(this ushort it) => Convert.ToUInt16(~it);
        public static ushort lft(this ushort it, int v) => Convert.ToUInt16(it << v);
        public static ushort rht(this ushort it, int v) => Convert.ToUInt16(it >> v);

        // int
        public static int to_Int(this int it) => Convert.ToInt32(it);
        public static double to_Num(this int it) => Convert.ToDouble(it);
        public static string to_Str(this int it, string format) => it.ToString(format);
        public static string to_Base(this int it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_I8(this int it) => Convert.ToSByte(it);
        public static short to_I16(this int it) => Convert.ToInt16(it);
        public static int to_I32(this int it) => Convert.ToInt32(it);
        public static long to_I64(this int it) => Convert.ToInt64(it);
        public static byte to_U8(this int it) => Convert.ToByte(it);
        public static ushort to_U16(this int it) => Convert.ToUInt16(it);
        public static uint to_U32(this int it) => Convert.ToUInt32(it);
        public static ulong to_U64(this int it) => Convert.ToUInt64(it);
        public static float to_F32(this int it) => Convert.ToSingle(it);
        public static double to_F64(this int it) => Convert.ToDouble(it);

        public static int and(this int it, int v) => Convert.ToInt32(it & v);
        public static int or(this int it, int v) => Convert.ToInt32(it | v);
        public static int xor(this int it, int v) => Convert.ToInt32(it ^ v);
        public static int not(this int it) => Convert.ToInt32(~it);
        public static int lft(this int it, int v) => Convert.ToInt32(it << v);
        public static int rht(this int it, int v) => Convert.ToInt32(it >> v);

        // uint
        public static int to_Int(this uint it) => Convert.ToInt32(it);
        public static double to_Num(this uint it) => Convert.ToDouble(it);
        public static string to_Str(this uint it, string format) => it.ToString(format);
        public static string to_Base(this uint it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_I8(this uint it) => Convert.ToSByte(it);
        public static short to_I16(this uint it) => Convert.ToInt16(it);
        public static int to_I32(this uint it) => Convert.ToInt32(it);
        public static long to_I64(this uint it) => Convert.ToInt64(it);
        public static byte to_U8(this uint it) => Convert.ToByte(it);
        public static ushort to_U16(this uint it) => Convert.ToUInt16(it);
        public static uint to_U32(this uint it) => Convert.ToUInt32(it);
        public static ulong to_U64(this uint it) => Convert.ToUInt64(it);
        public static float to_F32(this uint it) => Convert.ToSingle(it);
        public static double to_F64(this uint it) => Convert.ToDouble(it);

        public static uint and(this uint it, uint v) => Convert.ToUInt32(it & v);
        public static uint or(this uint it, uint v) => Convert.ToUInt32(it | v);
        public static uint xor(this uint it, uint v) => Convert.ToUInt32(it ^ v);
        public static uint not(this uint it) => Convert.ToUInt32(~it);
        public static uint lft(this uint it, int v) => Convert.ToUInt32(it << v);
        public static uint rht(this uint it, int v) => Convert.ToUInt32(it >> v);

        // long
        public static int to_Int(this long it) => Convert.ToInt32(it);
        public static double to_Num(this long it) => Convert.ToDouble(it);
        public static string to_Str(this long it, string format) => it.ToString(format);
        public static string to_Base(this long it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_I8(this long it) => Convert.ToSByte(it);
        public static short to_I16(this long it) => Convert.ToInt16(it);
        public static int to_I32(this long it) => Convert.ToInt32(it);
        public static long to_I64(this long it) => Convert.ToInt64(it);
        public static byte to_U8(this long it) => Convert.ToByte(it);
        public static ushort to_U16(this long it) => Convert.ToUInt16(it);
        public static uint to_U32(this long it) => Convert.ToUInt32(it);
        public static ulong to_U64(this long it) => Convert.ToUInt64(it);
        public static float to_F32(this long it) => Convert.ToSingle(it);
        public static double to_F64(this long it) => Convert.ToDouble(it);

        public static long and(this long it, long v) => Convert.ToInt64(it & v);
        public static long or(this long it, long v) => Convert.ToInt64(it | v);
        public static long xor(this long it, long v) => Convert.ToInt64(it ^ v);
        public static long not(this long it) => Convert.ToInt64(~it);
        public static long lft(this long it, int v) => Convert.ToInt64(it << v);
        public static long rht(this long it, int v) => Convert.ToInt64(it >> v);

        // ulong
        public static int to_Int(this ulong it) => Convert.ToInt32(it);
        public static double to_Num(this ulong it) => Convert.ToDouble(it);
        public static string to_Str(this ulong it, string format) => it.ToString(format);
        public static string to_Base(this ulong it, int fromBase) => Convert.ToString((long)it, fromBase);
        public static sbyte to_I8(this ulong it) => Convert.ToSByte(it);
        public static short to_I16(this ulong it) => Convert.ToInt16(it);
        public static int to_I32(this ulong it) => Convert.ToInt32(it);
        public static long to_I64(this ulong it) => Convert.ToInt64(it);
        public static byte to_U8(this ulong it) => Convert.ToByte(it);
        public static ushort to_U16(this ulong it) => Convert.ToUInt16(it);
        public static uint to_U32(this ulong it) => Convert.ToUInt32(it);
        public static ulong to_U64(this ulong it) => Convert.ToUInt64(it);
        public static float to_F32(this ulong it) => Convert.ToSingle(it);
        public static double to_F64(this ulong it) => Convert.ToDouble(it);

        public static ulong and(this ulong it, ulong v) => Convert.ToUInt64(it & v);
        public static ulong or(this ulong it, ulong v) => Convert.ToUInt64(it | v);
        public static ulong xor(this ulong it, ulong v) => Convert.ToUInt64(it ^ v);
        public static ulong not(this ulong it) => Convert.ToUInt64(~it);
        public static ulong lft(this ulong it, int v) => Convert.ToUInt64(it << v);
        public static ulong rht(this ulong it, int v) => Convert.ToUInt64(it >> v);

        // float
        public static int to_Int(this float it) => Convert.ToInt32(it);
        public static double to_Num(this float it) => Convert.ToDouble(it);
        public static string to_Str(this float it, string format) => it.ToString(format);
        public static sbyte to_I8(this float it) => Convert.ToSByte(it);
        public static short to_I16(this float it) => Convert.ToInt16(it);
        public static int to_I32(this float it) => Convert.ToInt32(it);
        public static long to_I64(this float it) => Convert.ToInt64(it);
        public static byte to_U8(this float it) => Convert.ToByte(it);
        public static ushort to_U16(this float it) => Convert.ToUInt16(it);
        public static uint to_U32(this float it) => Convert.ToUInt32(it);
        public static ulong to_U64(this float it) => Convert.ToUInt64(it);
        public static float to_F32(this float it) => Convert.ToSingle(it);
        public static double to_F64(this float it) => Convert.ToDouble(it);

        // double
        public static int to_Int(this double it) => Convert.ToInt32(it);
        public static double to_Num(this double it) => Convert.ToDouble(it);
        public static string to_Str(this double it, string format) => it.ToString(format);
        public static sbyte to_I8(this double it) => Convert.ToSByte(it);
        public static short to_I16(this double it) => Convert.ToInt16(it);
        public static int to_I32(this double it) => Convert.ToInt32(it);
        public static long to_I64(this double it) => Convert.ToInt64(it);
        public static byte to_U8(this double it) => Convert.ToByte(it);
        public static ushort to_U16(this double it) => Convert.ToUInt16(it);
        public static uint to_U32(this double it) => Convert.ToUInt32(it);
        public static ulong to_U64(this double it) => Convert.ToUInt64(it);
        public static float to_F32(this double it) => Convert.ToSingle(it);
        public static double to_F64(this double it) => Convert.ToDouble(it);

        // Char
        public static int to_Int(this char it) => Convert.ToInt32(it);
        public static double to_Num(this char it) => Convert.ToDouble(it);
        public static string to_Str(this char it, string format) => it.ToString();
        public static sbyte to_I8(this char it) => Convert.ToSByte(it);
        public static short to_I16(this char it) => Convert.ToInt16(it);
        public static int to_I32(this char it) => Convert.ToInt32(it);
        public static long to_I64(this char it) => Convert.ToInt64(it);
        public static byte to_U8(this char it) => Convert.ToByte(it);
        public static ushort to_U16(this char it) => Convert.ToUInt16(it);
        public static uint to_U32(this char it) => Convert.ToUInt32(it);
        public static ulong to_U64(this char it) => Convert.ToUInt64(it);
        public static float to_F32(this char it) => Convert.ToSingle(it);
        public static double to_F64(this char it) => Convert.ToDouble(it);

        public static char to_Lower(this char it) => char.ToLower(it);
        public static char to_Upper(this char it) => char.ToUpper(it);

        public static bool is_Lower(this char it) => char.IsLower(it);
        public static bool is_Upper(this char it) => char.IsUpper(it);

        public static bool is_Letter(this char it) => char.IsLetter(it);
        public static bool is_Digit(this char it) => char.IsDigit(it);
        public static bool is_Letter_or_Digit(this char it) => char.IsLetterOrDigit(it);

        public static bool is_Number(this char it) => char.IsNumber(it);
        public static bool is_Symbol(this char it) => char.IsSymbol(it);
        public static bool is_White_Space(this char it) => char.IsWhiteSpace(it);
        public static bool is_Control(this char it) => char.IsControl(it);

        // String
        public static bool not_empty(this string it) => !it.is_empty();
        public static bool is_empty(this string it) => string.IsNullOrEmpty(it);
        public static string sub_Str(this string it, int startIndex, int length) => it.Substring(startIndex, length);
        public static string sub_Str(this string it, int startIndex) => it.Substring(startIndex);

        public static string replace(this string it, string older, string newer) => it.Replace(older, newer);
        public static int len(this string it) => it.Length;
        public static int length(this string it) => it.Length;
        public static int last_index(this string it) => it.Length - 1;

        public static bool contains(this string it, string value) => it.Contains(value);

        public static int find_first(this string it, Func<char, bool> fn) {
            for (int i = 0; i < it.len(); i++) {
                if (fn(it[i])) {
                    return i;
                }
            }
            return 0;
        }

        public static int first_index_of(this string it, string value, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, comparisonType);
        public static int first_index_of(this string it, string value, int startIndex, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, startIndex, comparisonType);
        public static int first_index_of(this string it, string value, int startIndex, int count, StringComparison comparisonType = StringComparison.Ordinal) => it.IndexOf(value, startIndex, count, comparisonType);

        public static int last_index_of(this string it, string value, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, comparisonType);
        public static int last_index_of(this string it, string value, int startIndex, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, startIndex, comparisonType);
        public static int last_index_of(this string it, string value, int startIndex, int count, StringComparison comparisonType = StringComparison.Ordinal) => it.LastIndexOf(value, startIndex, count, comparisonType);


        public static string[] split(this string it, string[] separator, StringSplitOptions options = StringSplitOptions.None) => it.Split(separator, options);
        public static string slice(this string it, int? startIndex, int? endIndex) {
            if (startIndex == null && endIndex == null) {
                return it;
            } else if (endIndex == null) {
                return it.sub_Str(startIndex ?? 0, it.last_index() - startIndex ?? 0);
            } else // (startIndex == null)
              {
                return it.sub_Str(0, it.last_index() - endIndex ?? 0);
            }
        }

        public static string join(this string it, string j) => string.Join(j, it);

        public static string to_Str(this string it, string format) => it;
        public static byte[] to_Bytes(this string it) => Encoding.UTF8.GetBytes(it);
        public static int to_Int(this string it) => Convert.ToInt32(it);
        public static double to_Num(this string it) => Convert.ToDouble(it);
        public static sbyte to_I8(this string it) => Convert.ToSByte(it);
        public static short to_I16(this string it) => Convert.ToInt16(it);
        public static int to_I32(this string it) => Convert.ToInt32(it);
        public static long to_I64(this string it) => Convert.ToInt64(it);
        public static byte to_U8(this string it) => Convert.ToByte(it);
        public static ushort to_U16(this string it) => Convert.ToUInt16(it);
        public static uint to_U32(this string it) => Convert.ToUInt32(it);
        public static ulong to_U64(this string it) => Convert.ToUInt64(it);
        public static float to_F32(this string it) => Convert.ToSingle(it);
        public static double to_F64(this string it) => Convert.ToDouble(it);

        public static sbyte to_I8_from_Base(this string it, int fromBase) => Convert.ToSByte(it, fromBase);
        public static short to_I16_from_Base(this string it, int fromBase) => Convert.ToInt16(it, fromBase);
        public static int to_I32_from_Base(this string it, int fromBase) => Convert.ToInt32(it, fromBase);
        public static long to_I64_from_Base(this string it, int fromBase) => Convert.ToInt64(it, fromBase);
        public static byte to_U8_from_Base(this string it, int fromBase) => Convert.ToByte(it, fromBase);
        public static ushort to_U16_from_Base(this string it, int fromBase) => Convert.ToUInt16(it, fromBase);
        public static uint to_U32_from_Base(this string it, int fromBase) => Convert.ToUInt32(it, fromBase);
        public static ulong to_U64_from_Base(this string it, int fromBase) => Convert.ToUInt64(it, fromBase);

        public static byte[] to_Bytes_by_Base64(this string it) => Convert.FromBase64String(it);

        public static string to_Str(this byte[] it) => Encoding.UTF8.GetString(it);
        public static string to_Hex(this byte[] it) => BitConverter.ToString(it, 0).Replace("-", string.Empty);
        public static string to_Lower_Hex(this byte[] it) => it.to_Hex().ToLower();
        public static string to_Upper_Hex(this byte[] it) => it.to_Hex();

        public static string to_Str_by_Base64(this byte[] it) => Convert.ToBase64String(it, 0, it.Length);

        public static byte[] sub_Bytes(this byte[] it, int start, int length) => it.Skip(start).Take(length).ToArray();
    }
}
