using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Library {
    public static partial class ExpressionExtension {
        // object 
        public static string to_str(this object it) => it.ToString();
        public static T to<T>(this object it) => (T)it;
        public static bool @is<T>(this object it) => it is T;
        public static T @as<T>(this object it) where T : class => it as T;
        public static T or_else<T>(this T it, T value) where T : class => it != null ? it : value;

        public static sbyte to_i8(this object it) => Convert.ToSByte(it);
        public static short to_i16(this object it) => Convert.ToInt16(it);
        public static int to_i32(this object it) => Convert.ToInt32(it);
        public static long to_i64(this object it) => Convert.ToInt64(it);
        public static byte to_u8(this object it) => Convert.ToByte(it);
        public static ushort to_u16(this object it) => Convert.ToUInt16(it);
        public static uint to_u32(this object it) => Convert.ToUInt32(it);
        public static ulong to_u64(this object it) => Convert.ToUInt64(it);
        public static float to_f32(this object it) => Convert.ToSingle(it);
        public static double to_f64(this object it) => Convert.ToDouble(it);
        // sbyte
        public static string to_str(this sbyte it, string format) => it.ToString(format);
        public static string to_base(this sbyte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_i8(this sbyte it) => Convert.ToSByte(it);
        public static short to_i16(this sbyte it) => Convert.ToInt16(it);
        public static int to_i32(this sbyte it) => Convert.ToInt32(it);
        public static long to_i64(this sbyte it) => Convert.ToInt64(it);
        public static byte to_u8(this sbyte it) => Convert.ToByte(it);
        public static ushort to_u16(this sbyte it) => Convert.ToUInt16(it);
        public static uint to_u32(this sbyte it) => Convert.ToUInt32(it);
        public static ulong to_u64(this sbyte it) => Convert.ToUInt64(it);
        public static float to_f32(this sbyte it) => Convert.ToSingle(it);
        public static double to_f64(this sbyte it) => Convert.ToDouble(it);

        public static sbyte and(this sbyte it, sbyte v) => Convert.ToSByte(it & v);
        public static sbyte or(this sbyte it, sbyte v) => Convert.ToSByte(it | v);
        public static sbyte xor(this sbyte it, sbyte v) => Convert.ToSByte(it ^ v);
        public static sbyte not(this sbyte it) => Convert.ToSByte(~it);
        public static sbyte lft(this sbyte it, int v) => Convert.ToSByte(it << v);
        public static sbyte rht(this sbyte it, int v) => Convert.ToSByte(it >> v);
        // byte
        public static string to_str(this byte it, string format) => it.ToString(format);
        public static string to_base(this byte it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_i8(this byte it) => Convert.ToSByte(it);
        public static short to_i16(this byte it) => Convert.ToInt16(it);
        public static int to_i32(this byte it) => Convert.ToInt32(it);
        public static long to_i64(this byte it) => Convert.ToInt64(it);
        public static byte to_u8(this byte it) => Convert.ToByte(it);
        public static ushort to_u16(this byte it) => Convert.ToUInt16(it);
        public static uint to_u32(this byte it) => Convert.ToUInt32(it);
        public static ulong to_u64(this byte it) => Convert.ToUInt64(it);
        public static float to_f32(this byte it) => Convert.ToSingle(it);
        public static double to_f64(this byte it) => Convert.ToDouble(it);

        public static byte and(this byte it, byte v) => Convert.ToByte(it & v);
        public static byte or(this byte it, byte v) => Convert.ToByte(it | v);
        public static byte xor(this byte it, byte v) => Convert.ToByte(it ^ v);
        public static byte not(this byte it) => Convert.ToByte(~it);
        public static byte lft(this byte it, int v) => Convert.ToByte(it << v);
        public static byte rht(this byte it, int v) => Convert.ToByte(it >> v);

        // short
        public static string to_str(this short it, string format) => it.ToString(format);
        public static string to_base(this short it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_i8(this short it) => Convert.ToSByte(it);
        public static short to_i16(this short it) => Convert.ToInt16(it);
        public static int to_i32(this short it) => Convert.ToInt32(it);
        public static long to_i64(this short it) => Convert.ToInt64(it);
        public static byte to_u8(this short it) => Convert.ToByte(it);
        public static ushort to_u16(this short it) => Convert.ToUInt16(it);
        public static uint to_u32(this short it) => Convert.ToUInt32(it);
        public static ulong to_u64(this short it) => Convert.ToUInt64(it);
        public static float to_f32(this short it) => Convert.ToSingle(it);
        public static double to_f64(this short it) => Convert.ToDouble(it);

        public static short and(this short it, short v) => Convert.ToInt16(it & v);
        public static short or(this short it, short v) => Convert.ToInt16(it | v);
        public static short xor(this short it, short v) => Convert.ToInt16(it ^ v);
        public static short not(this short it) => Convert.ToInt16(~it);
        public static short lft(this short it, int v) => Convert.ToInt16(it << v);
        public static short rht(this short it, int v) => Convert.ToInt16(it >> v);

        // ushort
        public static string to_str(this ushort it, string format) => it.ToString(format);
        public static string to_base(this ushort it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_i8(this ushort it) => Convert.ToSByte(it);
        public static short to_i16(this ushort it) => Convert.ToInt16(it);
        public static int to_i32(this ushort it) => Convert.ToInt32(it);
        public static long to_i64(this ushort it) => Convert.ToInt64(it);
        public static byte to_u8(this ushort it) => Convert.ToByte(it);
        public static ushort to_u16(this ushort it) => Convert.ToUInt16(it);
        public static uint to_u32(this ushort it) => Convert.ToUInt32(it);
        public static ulong to_u64(this ushort it) => Convert.ToUInt64(it);
        public static float to_f32(this ushort it) => Convert.ToSingle(it);
        public static double to_f64(this ushort it) => Convert.ToDouble(it);

        public static ushort and(this ushort it, ushort v) => Convert.ToUInt16(it & v);
        public static ushort or(this ushort it, ushort v) => Convert.ToUInt16(it | v);
        public static ushort xor(this ushort it, ushort v) => Convert.ToUInt16(it ^ v);
        public static ushort not(this ushort it) => Convert.ToUInt16(~it);
        public static ushort lft(this ushort it, int v) => Convert.ToUInt16(it << v);
        public static ushort rht(this ushort it, int v) => Convert.ToUInt16(it >> v);

        // int
        public static string to_str(this int it, string format) => it.ToString(format);
        public static string to_base(this int it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_i8(this int it) => Convert.ToSByte(it);
        public static short to_i16(this int it) => Convert.ToInt16(it);
        public static int to_i32(this int it) => Convert.ToInt32(it);
        public static long to_i64(this int it) => Convert.ToInt64(it);
        public static byte to_u8(this int it) => Convert.ToByte(it);
        public static ushort to_u16(this int it) => Convert.ToUInt16(it);
        public static uint to_u32(this int it) => Convert.ToUInt32(it);
        public static ulong to_u64(this int it) => Convert.ToUInt64(it);
        public static float to_f32(this int it) => Convert.ToSingle(it);
        public static double to_f64(this int it) => Convert.ToDouble(it);

        public static int and(this int it, int v) => Convert.ToInt32(it & v);
        public static int or(this int it, int v) => Convert.ToInt32(it | v);
        public static int xor(this int it, int v) => Convert.ToInt32(it ^ v);
        public static int not(this int it) => Convert.ToInt32(~it);
        public static int lft(this int it, int v) => Convert.ToInt32(it << v);
        public static int rht(this int it, int v) => Convert.ToInt32(it >> v);

        // uint
        public static string to_str(this uint it, string format) => it.ToString(format);
        public static string to_base(this uint it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_i8(this uint it) => Convert.ToSByte(it);
        public static short to_i16(this uint it) => Convert.ToInt16(it);
        public static int to_i32(this uint it) => Convert.ToInt32(it);
        public static long to_i64(this uint it) => Convert.ToInt64(it);
        public static byte to_u8(this uint it) => Convert.ToByte(it);
        public static ushort to_u16(this uint it) => Convert.ToUInt16(it);
        public static uint to_u32(this uint it) => Convert.ToUInt32(it);
        public static ulong to_u64(this uint it) => Convert.ToUInt64(it);
        public static float to_f32(this uint it) => Convert.ToSingle(it);
        public static double to_f64(this uint it) => Convert.ToDouble(it);

        public static uint and(this uint it, uint v) => Convert.ToUInt32(it & v);
        public static uint or(this uint it, uint v) => Convert.ToUInt32(it | v);
        public static uint xor(this uint it, uint v) => Convert.ToUInt32(it ^ v);
        public static uint not(this uint it) => Convert.ToUInt32(~it);
        public static uint lft(this uint it, int v) => Convert.ToUInt32(it << v);
        public static uint rht(this uint it, int v) => Convert.ToUInt32(it >> v);

        // long
        public static string to_str(this long it, string format) => it.ToString(format);
        public static string to_base(this long it, int fromBase) => Convert.ToString(it, fromBase);
        public static sbyte to_i8(this long it) => Convert.ToSByte(it);
        public static short to_i16(this long it) => Convert.ToInt16(it);
        public static int to_i32(this long it) => Convert.ToInt32(it);
        public static long to_i64(this long it) => Convert.ToInt64(it);
        public static byte to_u8(this long it) => Convert.ToByte(it);
        public static ushort to_u16(this long it) => Convert.ToUInt16(it);
        public static uint to_u32(this long it) => Convert.ToUInt32(it);
        public static ulong to_u64(this long it) => Convert.ToUInt64(it);
        public static float to_f32(this long it) => Convert.ToSingle(it);
        public static double to_f64(this long it) => Convert.ToDouble(it);

        public static long and(this long it, long v) => Convert.ToInt64(it & v);
        public static long or(this long it, long v) => Convert.ToInt64(it | v);
        public static long xor(this long it, long v) => Convert.ToInt64(it ^ v);
        public static long not(this long it) => Convert.ToInt64(~it);
        public static long lft(this long it, int v) => Convert.ToInt64(it << v);
        public static long rht(this long it, int v) => Convert.ToInt64(it >> v);

        // ulong
        public static string to_str(this ulong it, string format) => it.ToString(format);
        public static string to_base(this ulong it, int fromBase) => Convert.ToString((long)it, fromBase);
        public static sbyte to_i8(this ulong it) => Convert.ToSByte(it);
        public static short to_i16(this ulong it) => Convert.ToInt16(it);
        public static int to_i32(this ulong it) => Convert.ToInt32(it);
        public static long to_i64(this ulong it) => Convert.ToInt64(it);
        public static byte to_u8(this ulong it) => Convert.ToByte(it);
        public static ushort to_u16(this ulong it) => Convert.ToUInt16(it);
        public static uint to_u32(this ulong it) => Convert.ToUInt32(it);
        public static ulong to_u64(this ulong it) => Convert.ToUInt64(it);
        public static float to_f32(this ulong it) => Convert.ToSingle(it);
        public static double to_f64(this ulong it) => Convert.ToDouble(it);

        public static ulong and(this ulong it, ulong v) => Convert.ToUInt64(it & v);
        public static ulong or(this ulong it, ulong v) => Convert.ToUInt64(it | v);
        public static ulong xor(this ulong it, ulong v) => Convert.ToUInt64(it ^ v);
        public static ulong not(this ulong it) => Convert.ToUInt64(~it);
        public static ulong lft(this ulong it, int v) => Convert.ToUInt64(it << v);
        public static ulong rht(this ulong it, int v) => Convert.ToUInt64(it >> v);

        // float
        public static string to_str(this float it, string format) => it.ToString(format);
        public static sbyte to_i8(this float it) => Convert.ToSByte(it);
        public static short to_i16(this float it) => Convert.ToInt16(it);
        public static int to_i32(this float it) => Convert.ToInt32(it);
        public static long to_i64(this float it) => Convert.ToInt64(it);
        public static byte to_u8(this float it) => Convert.ToByte(it);
        public static ushort to_u16(this float it) => Convert.ToUInt16(it);
        public static uint to_u32(this float it) => Convert.ToUInt32(it);
        public static ulong to_u64(this float it) => Convert.ToUInt64(it);
        public static float to_f32(this float it) => Convert.ToSingle(it);
        public static double to_f64(this float it) => Convert.ToDouble(it);

        // double
        public static string to_str(this double it, string format) => it.ToString(format);
        public static sbyte to_i8(this double it) => Convert.ToSByte(it);
        public static short to_i16(this double it) => Convert.ToInt16(it);
        public static int to_i32(this double it) => Convert.ToInt32(it);
        public static long to_i64(this double it) => Convert.ToInt64(it);
        public static byte to_u8(this double it) => Convert.ToByte(it);
        public static ushort to_u16(this double it) => Convert.ToUInt16(it);
        public static uint to_u32(this double it) => Convert.ToUInt32(it);
        public static ulong to_u64(this double it) => Convert.ToUInt64(it);
        public static float to_f32(this double it) => Convert.ToSingle(it);
        public static double to_f64(this double it) => Convert.ToDouble(it);

        // Char
        public static string to_str(this char it, string format) => it.ToString();
        public static sbyte to_i8(this char it) => Convert.ToSByte(it);
        public static short to_i16(this char it) => Convert.ToInt16(it);
        public static int to_i32(this char it) => Convert.ToInt32(it);
        public static long to_i64(this char it) => Convert.ToInt64(it);
        public static byte to_u8(this char it) => Convert.ToByte(it);
        public static ushort to_u16(this char it) => Convert.ToUInt16(it);
        public static uint to_u32(this char it) => Convert.ToUInt32(it);
        public static ulong to_u64(this char it) => Convert.ToUInt64(it);
        public static float to_f32(this char it) => Convert.ToSingle(it);
        public static double to_f64(this char it) => Convert.ToDouble(it);

        public static char to_lower(this char it) => char.ToLower(it);
        public static char to_upper(this char it) => char.ToUpper(it);

        public static bool is_lower(this char it) => char.IsLower(it);
        public static bool is_upper(this char it) => char.IsUpper(it);

        public static bool is_letter(this char it) => char.IsLetter(it);
        public static bool is_digit(this char it) => char.IsDigit(it);
        public static bool is_letter_or_digit(this char it) => char.IsLetterOrDigit(it);

        public static bool is_number(this char it) => char.IsNumber(it);
        public static bool is_symbol(this char it) => char.IsSymbol(it);
        public static bool is_white_space(this char it) => char.IsWhiteSpace(it);
        public static bool is_control(this char it) => char.IsControl(it);

        // String
        public static bool not_empty(this string it) => !it.is_empty();
        public static bool is_empty(this string it) => string.IsNullOrEmpty(it);
        public static string sub_str(this string it, int startIndex, int length) => it.Substring(startIndex, length);
        public static string sub_str(this string it, int startIndex) => it.Substring(startIndex);

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
                return it.sub_str(startIndex ?? 0, it.last_index() - startIndex ?? 0);
            } else // (startIndex == null)
              {
                return it.sub_str(0, it.last_index() - endIndex ?? 0);
            }
        }

        public static string join(this string it, string j) => string.Join(j, it);

        public static string to_str(this string it, string format) => it;
        public static byte[] to_bytes(this string it) => Encoding.UTF8.GetBytes(it);
        public static sbyte to_i8(this string it) => Convert.ToSByte(it);
        public static short to_i16(this string it) => Convert.ToInt16(it);
        public static int to_i32(this string it) => Convert.ToInt32(it);
        public static long to_i64(this string it) => Convert.ToInt64(it);
        public static byte to_u8(this string it) => Convert.ToByte(it);
        public static ushort to_u16(this string it) => Convert.ToUInt16(it);
        public static uint to_u32(this string it) => Convert.ToUInt32(it);
        public static ulong to_u64(this string it) => Convert.ToUInt64(it);
        public static float to_f32(this string it) => Convert.ToSingle(it);
        public static double to_f64(this string it) => Convert.ToDouble(it);

        public static sbyte to_i8_from_base(this string it, int fromBase) => Convert.ToSByte(it, fromBase);
        public static short to_i16_from_base(this string it, int fromBase) => Convert.ToInt16(it, fromBase);
        public static int to_i32_from_base(this string it, int fromBase) => Convert.ToInt32(it, fromBase);
        public static long to_i64_from_base(this string it, int fromBase) => Convert.ToInt64(it, fromBase);
        public static byte to_u8_from_base(this string it, int fromBase) => Convert.ToByte(it, fromBase);
        public static ushort to_u16_from_base(this string it, int fromBase) => Convert.ToUInt16(it, fromBase);
        public static uint to_u32_from_base(this string it, int fromBase) => Convert.ToUInt32(it, fromBase);
        public static ulong to_u64_from_base(this string it, int fromBase) => Convert.ToUInt64(it, fromBase);

        public static byte[] to_bytes_by_base64(this string it) => Convert.FromBase64String(it);

        public static string to_str(this byte[] it) => Encoding.UTF8.GetString(it);
        public static string to_hex(this byte[] it) => BitConverter.ToString(it, 0).Replace("-", string.Empty);
        public static string to_lower_hex(this byte[] it) => it.to_hex().ToLower();
        public static string to_upper_hex(this byte[] it) => it.to_hex();

        public static string to_str_by_base64(this byte[] it) => Convert.ToBase64String(it, 0, it.Length);

        public static byte[] sub_bytes(this byte[] it, int start, int length) => it.Skip(start).Take(length).ToArray();
    }
}
