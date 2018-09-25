using System;
using System.Collections.Generic;
using System.Linq;

namespace XyLang.Library
{
    public interface iXyValue 
    { 
        string ToString(string format);
        object toAny();
    }

    public static class ExpressionExtension
    {
        // object 
        public static str toStr(this object it) => it.ToString();
        // IXyValue
        public static str toStr(this iXyValue it, str format) => it.ToString(format);
        public static chr toChr(this iXyValue it) => new chr(it.toAny());
        public static i8 toI8(this iXyValue it) => new i8(it.toAny());
        public static i16 toI16(this iXyValue it) => new i16(it.toAny());
        public static i32 toI32(this iXyValue it) => new i32(it.toAny());
        public static i64 toI64(this iXyValue it) => new i64(it.toAny());
        public static u8 toU8(this iXyValue it) => new u8(it.toAny());
        public static u16 toU16(this iXyValue it) => new u16(it.toAny());
        public static u32 toU32(this iXyValue it) => new u32(it.toAny());
        public static u64 toU64(this iXyValue it) => new u64(it.toAny());
        public static f32 toF32(this iXyValue it) => new f32(it.toAny());
        public static f64 toF64(this iXyValue it) => new f64(it.toAny());
        // sbyte
        public static str toStr(this sbyte it, str format) => it.ToString(format);
        public static str toBase(this sbyte it, i32 fromBase) => Convert.ToString(it, fromBase);
        public static i8 toI8(this sbyte it) => new i8(it);
        public static i16 toI16(this sbyte it) => new i16(it);
        public static i32 toI32(this sbyte it) => new i32(it);
        public static i64 toI64(this sbyte it) => new i64(it);
        public static u8 toU8(this sbyte it) => new u8(it);
        public static u16 toU16(this sbyte it) => new u16(it);
        public static u32 toU32(this sbyte it) => new u32(it);
        public static u64 toU64(this sbyte it) => new u64(it);
        public static f32 toF32(this sbyte it) => new f32(it);
        public static f64 toF64(this sbyte it) => new f64(it);

        public static i8 and(this sbyte it, sbyte v) => new i8(it & v);
        public static i8 or(this sbyte it, sbyte v) => new i8(it | v);
        public static i8 xor(this sbyte it, sbyte v) => new i8(it ^ v);
        public static i8 not(this sbyte it) => new i8(~it);
        public static i8 lft(this sbyte it, int v) => new i8(it << v);
        public static i8 rht(this sbyte it, int v) => new i8(it >> v);
        // byte
        public static str toStr(this byte it, str format) => it.ToString(format);
        public static str toBase(this byte it, i32 fromBase) => Convert.ToString(it, fromBase);
        public static i8 toI8(this byte it) => new i8(it);
        public static i16 toI16(this byte it) => new i16(it);
        public static i32 toI32(this byte it) => new i32(it);
        public static i64 toI64(this byte it) => new i64(it);
        public static u8 toU8(this byte it) => new u8(it);
        public static u16 toU16(this byte it) => new u16(it);
        public static u32 toU32(this byte it) => new u32(it);
        public static u64 toU64(this byte it) => new u64(it);
        public static f32 toF32(this byte it) => new f32(it);
        public static f64 toF64(this byte it) => new f64(it);

        public static u8 and(this byte it, byte v) => new u8(it & v);
        public static u8 or(this byte it, byte v) => new u8(it | v);
        public static u8 xor(this byte it, byte v) => new u8(it ^ v);
        public static u8 not(this byte it) => new u8(~it);
        public static u8 lft(this byte it, int v) => new u8(it << v);
        public static u8 rht(this byte it, int v) => new u8(it >> v);

        // short
        public static str toStr(this short it, str format) => it.ToString(format);
        public static str toBase(this short it, i32 fromBase) => Convert.ToString(it, fromBase);
        public static i8 toI8(this short it) => new i8(it);
        public static i16 toI16(this short it) => new i16(it);
        public static i32 toI32(this short it) => new i32(it);
        public static i64 toI64(this short it) => new i64(it);
        public static u8 toU8(this short it) => new u8(it);
        public static u16 toU16(this short it) => new u16(it);
        public static u32 toU32(this short it) => new u32(it);
        public static u64 toU64(this short it) => new u64(it);
        public static f32 toF32(this short it) => new f32(it);
        public static f64 toF64(this short it) => new f64(it);

        public static i16 and(this short it, short v) => new i16(it & v);
        public static i16 or(this short it, short v) => new i16(it | v);
        public static i16 xor(this short it, short v) => new i16(it ^ v);
        public static i16 not(this short it) => new i16(~it);
        public static i16 lft(this short it, int v) => new i16(it << v);
        public static i16 rht(this short it, int v) => new i16(it >> v);

        // ushort
        public static str toStr(this ushort it, str format) => it.ToString(format);
        public static str toBase(this ushort it, i32 fromBase) => Convert.ToString(it, fromBase);
        public static i8 toI8(this ushort it) => new i8(it);
        public static i16 toI16(this ushort it) => new i16(it);
        public static i32 toI32(this ushort it) => new i32(it);
        public static i64 toI64(this ushort it) => new i64(it);
        public static u8 toU8(this ushort it) => new u8(it);
        public static u16 toU16(this ushort it) => new u16(it);
        public static u32 toU32(this ushort it) => new u32(it);
        public static u64 toU64(this ushort it) => new u64(it);
        public static f32 toF32(this ushort it) => new f32(it);
        public static f64 toF64(this ushort it) => new f64(it);

        public static u16 and(this ushort it, ushort v) => new u16(it & v);
        public static u16 or(this ushort it, ushort v) => new u16(it | v);
        public static u16 xor(this ushort it, ushort v) => new u16(it ^ v);
        public static u16 not(this ushort it) => new u16(~it);
        public static u16 lft(this ushort it, int v) => new u16(it << v);
        public static u16 rht(this ushort it, int v) => new u16(it >> v);

        // int
        public static str toStr(this int it, str format) => it.ToString(format);
        public static str toBase(this int it, i32 fromBase) => Convert.ToString(it, fromBase);
        public static i8 toI8(this int it) => new i8(it);
        public static i16 toI16(this int it) => new i16(it);
        public static i32 toI32(this int it) => new i32(it);
        public static i64 toI64(this int it) => new i64(it);
        public static u8 toU8(this int it) => new u8(it);
        public static u16 toU16(this int it) => new u16(it);
        public static u32 toU32(this int it) => new u32(it);
        public static u64 toU64(this int it) => new u64(it);
        public static f32 toF32(this int it) => new f32(it);
        public static f64 toF64(this int it) => new f64(it);

        public static i32 and(this int it, int v) => new i32(it & v);
        public static i32 or(this int it, int v) => new i32(it | v);
        public static i32 xor(this int it, int v) => new i32(it ^ v);
        public static i32 not(this int it) => new i32(~it);
        public static i32 lft(this int it, int v) => new i32(it << v);
        public static i32 rht(this int it, int v) => new i32(it >> v);

        // uint
        public static str toStr(this uint it, str format) => it.ToString(format);
        public static str toBase(this uint it, i32 fromBase) => Convert.ToString(it, fromBase);
        public static i8 toI8(this uint it) => new i8(it);
        public static i16 toI16(this uint it) => new i16(it);
        public static i32 toI32(this uint it) => new i32(it);
        public static i64 toI64(this uint it) => new i64(it);
        public static u8 toU8(this uint it) => new u8(it);
        public static u16 toU16(this uint it) => new u16(it);
        public static u32 toU32(this uint it) => new u32(it);
        public static u64 toU64(this uint it) => new u64(it);
        public static f32 toF32(this uint it) => new f32(it);
        public static f64 toF64(this uint it) => new f64(it);

        public static u32 and(this uint it, uint v) => new u32(it & v);
        public static u32 or(this uint it, uint v) => new u32(it | v);
        public static u32 xor(this uint it, uint v) => new u32(it ^ v);
        public static u32 not(this uint it) => new u32(~it);
        public static u32 lft(this uint it, int v) => new u32(it << v);
        public static u32 rht(this uint it, int v) => new u32(it >> v);

        // long
        public static str toStr(this long it, str format) => it.ToString(format);
        public static str toBase(this long it, i32 fromBase) => Convert.ToString(it, fromBase);
        public static i8 toI8(this long it) => new i8(it);
        public static i16 toI16(this long it) => new i16(it);
        public static i32 toI32(this long it) => new i32(it);
        public static i64 toI64(this long it) => new i64(it);
        public static u8 toU8(this long it) => new u8(it);
        public static u16 toU16(this long it) => new u16(it);
        public static u32 toU32(this long it) => new u32(it);
        public static u64 toU64(this long it) => new u64(it);
        public static f32 toF32(this long it) => new f32(it);
        public static f64 toF64(this long it) => new f64(it);

        public static i64 and(this long it, long v) => new i64(it & v);
        public static i64 or(this long it, long v) => new i64(it | v);
        public static i64 xor(this long it, long v) => new i64(it ^ v);
        public static i64 not(this long it) => new i64(~it);
        public static i64 lft(this long it, int v) => new i64(it << v);
        public static i64 rht(this long it, int v) => new i64(it >> v);

        // ulong
        public static str toStr(this ulong it, str format) => it.ToString(format);
        public static str toBase(this ulong it, i32 fromBase) => Convert.ToString((long)it, fromBase);
        public static i8 toI8(this ulong it) => new i8(it);
        public static i16 toI16(this ulong it) => new i16(it);
        public static i32 toI32(this ulong it) => new i32(it);
        public static i64 toI64(this ulong it) => new i64(it);
        public static u8 toU8(this ulong it) => new u8(it);
        public static u16 toU16(this ulong it) => new u16(it);
        public static u32 toU32(this ulong it) => new u32(it);
        public static u64 toU64(this ulong it) => new u64(it);
        public static f32 toF32(this ulong it) => new f32(it);
        public static f64 toF64(this ulong it) => new f64(it);

        public static u64 and(this ulong it, ulong v) => new u64(it & v);
        public static u64 or(this ulong it, ulong v) => new u64(it | v);
        public static u64 xor(this ulong it, ulong v) => new u64(it ^ v);
        public static u64 not(this ulong it) => new u64(~it);
        public static u64 lft(this ulong it, int v) => new u64(it << v);
        public static u64 rht(this ulong it, int v) => new u64(it >> v);

        // float
        public static str toStr(this float it, str format) => it.ToString(format);
        public static i8 toI8(this float it) => new i8(it);
        public static i16 toI16(this float it) => new i16(it);
        public static i32 toI32(this float it) => new i32(it);
        public static i64 toI64(this float it) => new i64(it);
        public static u8 toU8(this float it) => new u8(it);
        public static u16 toU16(this float it) => new u16(it);
        public static u32 toU32(this float it) => new u32(it);
        public static u64 toU64(this float it) => new u64(it);
        public static f32 toF32(this float it) => new f32(it);
        public static f64 toF64(this float it) => new f64(it);

        // double
        public static str toStr(this double it, str format) => it.ToString(format);
        public static i8 toI8(this double it) => new i8(it);
        public static i16 toI16(this double it) => new i16(it);
        public static i32 toI32(this double it) => new i32(it);
        public static i64 toI64(this double it) => new i64(it);
        public static u8 toU8(this double it) => new u8(it);
        public static u16 toU16(this double it) => new u16(it);
        public static u32 toU32(this double it) => new u32(it);
        public static u64 toU64(this double it) => new u64(it);
        public static f32 toF32(this double it) => new f32(it);
        public static f64 toF64(this double it) => new f64(it);

        // Char
        public static str toStr(this char it, str format) => it.ToString();
        public static i8 toI8(this char it) => new i8(it);
        public static i16 toI16(this char it) => new i16(it);
        public static i32 toI32(this char it) => new i32(it);
        public static i64 toI64(this char it) => new i64(it);
        public static u8 toU8(this char it) => new u8(it);
        public static u16 toU16(this char it) => new u16(it);
        public static u32 toU32(this char it) => new u32(it);
        public static u64 toU64(this char it) => new u64(it);
        public static f32 toF32(this char it) => new f32(it);
        public static f64 toF64(this char it) => new f64(it);

        public static chr toLower(this char it) => char.ToLower(it);
        public static chr toUpper(this char it) => char.ToUpper(it);

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

        public static str toStr(this string it, str format) => it;
        public static i8 toI8(this string it) => new i8(it);
        public static i16 toI16(this string it) => new i16(it);
        public static i32 toI32(this string it) => new i32(it);
        public static i64 toI64(this string it) => new i64(it);
        public static u8 toU8(this string it) => new u8(it);
        public static u16 toU16(this string it) => new u16(it);
        public static u32 toU32(this string it) => new u32(it);
        public static u64 toU64(this string it) => new u64(it);
        public static f32 toF32(this string it) => new f32(it);
        public static f64 toF64(this string it) => new f64(it);

        public static i8 toI8FromBase(this string it, i32 fromBase) => new i8(it, fromBase);
        public static i16 toI16FromBase(this string it, i32 fromBase) => new i16(it, fromBase);
        public static i32 toI32FromBase(this string it, i32 fromBase) => new i32(it, fromBase);
        public static i64 toI64FromBase(this string it, i32 fromBase) => new i64(it, fromBase);
        public static u8 toU8FromBase(this string it, i32 fromBase) => new u8(it, fromBase);
        public static u16 toU16FromBase(this string it, i32 fromBase) => new u16(it, fromBase);
        public static u32 toU32FromBase(this string it, i32 fromBase) => new u32(it, fromBase);
        public static u64 toU64FromBase(this string it, i32 fromBase) => new u64(it, fromBase);

        public static IEnumerable<(int index, T item)> ForEachWithIndex<T>(this IEnumerable<T> self)
   => self.Select((item, index) => (index, item));

        public static IEnumerable<(TKey, TValue)> ForEachWithIndex<TKey, TValue>(this IEnumerable<KeyValuePair<TKey, TValue>> self)
   => self.Select((item) => (item.Key, item.Value));
    }
}
