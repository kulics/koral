using System;
using System.Collections.Generic;
using System.Linq;

namespace XyLang.Library
{
    public interface IXyValue { string ToString(string format); }

    public static class ExpressionExtension
    {
        // object 
        public static Str ToStr(this object it) => it.ToString();
        // IXyValue
        public static Str ToStr(this IXyValue it, Str format) => it.ToString(format);
        public static I8 ToI8(this IXyValue it) => new I8(it);
        public static I16 ToI16(this IXyValue it) => new I16(it);
        public static I32 ToI32(this IXyValue it) => new I32(it);
        public static I64 ToI64(this IXyValue it) => new I64(it);
        public static U8 ToU8(this IXyValue it) => new U8(it);
        public static U16 ToU16(this IXyValue it) => new U16(it);
        public static U32 ToU32(this IXyValue it) => new U32(it);
        public static U64 ToU64(this IXyValue it) => new U64(it);
        public static F32 ToF32(this IXyValue it) => new F32(it);
        public static F64 ToF64(this IXyValue it) => new F64(it);
        // sbyte
        public static Str ToStr(this sbyte it, Str format) => it.ToString(format);
        public static Str ToBase(this sbyte it, I32 fromBase) => Convert.ToString(it, fromBase);
        public static I8 ToI8(this sbyte it) => new I8(it);
        public static I16 ToI16(this sbyte it) => new I16(it);
        public static I32 ToI32(this sbyte it) => new I32(it);
        public static I64 ToI64(this sbyte it) => new I64(it);
        public static U8 ToU8(this sbyte it) => new U8(it);
        public static U16 ToU16(this sbyte it) => new U16(it);
        public static U32 ToU32(this sbyte it) => new U32(it);
        public static U64 ToU64(this sbyte it) => new U64(it);
        public static F32 ToF32(this sbyte it) => new F32(it);
        public static F64 ToF64(this sbyte it) => new F64(it);

        public static I8 AND(this sbyte it, sbyte v) => new I8(it & v);
        public static I8 OR(this sbyte it, sbyte v) => new I8(it | v);
        public static I8 XOR(this sbyte it, sbyte v) => new I8(it ^ v);
        public static I8 NOT(this sbyte it) => new I8(~it);
        public static I8 LFT(this sbyte it, int v) => new I8(it << v);
        public static I8 RHT(this sbyte it, int v) => new I8(it >> v);
        // byte
        public static Str ToStr(this byte it, Str format) => it.ToString(format);
        public static Str ToBase(this byte it, I32 fromBase) => Convert.ToString(it, fromBase);
        public static I8 ToI8(this byte it) => new I8(it);
        public static I16 ToI16(this byte it) => new I16(it);
        public static I32 ToI32(this byte it) => new I32(it);
        public static I64 ToI64(this byte it) => new I64(it);
        public static U8 ToU8(this byte it) => new U8(it);
        public static U16 ToU16(this byte it) => new U16(it);
        public static U32 ToU32(this byte it) => new U32(it);
        public static U64 ToU64(this byte it) => new U64(it);
        public static F32 ToF32(this byte it) => new F32(it);
        public static F64 ToF64(this byte it) => new F64(it);

        public static U8 AND(this byte it, byte v) => new U8(it & v);
        public static U8 OR(this byte it, byte v) => new U8(it | v);
        public static U8 XOR(this byte it, byte v) => new U8(it ^ v);
        public static U8 NOT(this byte it) => new U8(~it);
        public static U8 LFT(this byte it, int v) => new U8(it << v);
        public static U8 RHT(this byte it, int v) => new U8(it >> v);

        // short
        public static Str ToStr(this short it, Str format) => it.ToString(format);
        public static Str ToBase(this short it, I32 fromBase) => Convert.ToString(it, fromBase);
        public static I8 ToI8(this short it) => new I8(it);
        public static I16 ToI16(this short it) => new I16(it);
        public static I32 ToI32(this short it) => new I32(it);
        public static I64 ToI64(this short it) => new I64(it);
        public static U8 ToU8(this short it) => new U8(it);
        public static U16 ToU16(this short it) => new U16(it);
        public static U32 ToU32(this short it) => new U32(it);
        public static U64 ToU64(this short it) => new U64(it);
        public static F32 ToF32(this short it) => new F32(it);
        public static F64 ToF64(this short it) => new F64(it);

        public static I16 AND(this short it, short v) => new I16(it & v);
        public static I16 OR(this short it, short v) => new I16(it | v);
        public static I16 XOR(this short it, short v) => new I16(it ^ v);
        public static I16 NOT(this short it) => new I16(~it);
        public static I16 LFT(this short it, int v) => new I16(it << v);
        public static I16 RHT(this short it, int v) => new I16(it >> v);

        // ushort
        public static Str ToStr(this ushort it, Str format) => it.ToString(format);
        public static Str ToBase(this ushort it, I32 fromBase) => Convert.ToString(it, fromBase);
        public static I8 ToI8(this ushort it) => new I8(it);
        public static I16 ToI16(this ushort it) => new I16(it);
        public static I32 ToI32(this ushort it) => new I32(it);
        public static I64 ToI64(this ushort it) => new I64(it);
        public static U8 ToU8(this ushort it) => new U8(it);
        public static U16 ToU16(this ushort it) => new U16(it);
        public static U32 ToU32(this ushort it) => new U32(it);
        public static U64 ToU64(this ushort it) => new U64(it);
        public static F32 ToF32(this ushort it) => new F32(it);
        public static F64 ToF64(this ushort it) => new F64(it);

        public static U16 AND(this ushort it, ushort v) => new U16(it & v);
        public static U16 OR(this ushort it, ushort v) => new U16(it | v);
        public static U16 XOR(this ushort it, ushort v) => new U16(it ^ v);
        public static U16 NOT(this ushort it) => new U16(~it);
        public static U16 LFT(this ushort it, int v) => new U16(it << v);
        public static U16 RHT(this ushort it, int v) => new U16(it >> v);

        // int
        public static Str ToStr(this int it, Str format) => it.ToString(format);
        public static Str ToBase(this int it, I32 fromBase) => Convert.ToString(it, fromBase);
        public static I8 ToI8(this int it) => new I8(it);
        public static I16 ToI16(this int it) => new I16(it);
        public static I32 ToI32(this int it) => new I32(it);
        public static I64 ToI64(this int it) => new I64(it);
        public static U8 ToU8(this int it) => new U8(it);
        public static U16 ToU16(this int it) => new U16(it);
        public static U32 ToU32(this int it) => new U32(it);
        public static U64 ToU64(this int it) => new U64(it);
        public static F32 ToF32(this int it) => new F32(it);
        public static F64 ToF64(this int it) => new F64(it);

        public static I32 AND(this int it, int v) => new I32(it & v);
        public static I32 OR(this int it, int v) => new I32(it | v);
        public static I32 XOR(this int it, int v) => new I32(it ^ v);
        public static I32 NOT(this int it) => new I32(~it);
        public static I32 LFT(this int it, int v) => new I32(it << v);
        public static I32 RHT(this int it, int v) => new I32(it >> v);

        // uint
        public static Str ToStr(this uint it, Str format) => it.ToString(format);
        public static Str ToBase(this uint it, I32 fromBase) => Convert.ToString(it, fromBase);
        public static I8 ToI8(this uint it) => new I8(it);
        public static I16 ToI16(this uint it) => new I16(it);
        public static I32 ToI32(this uint it) => new I32(it);
        public static I64 ToI64(this uint it) => new I64(it);
        public static U8 ToU8(this uint it) => new U8(it);
        public static U16 ToU16(this uint it) => new U16(it);
        public static U32 ToU32(this uint it) => new U32(it);
        public static U64 ToU64(this uint it) => new U64(it);
        public static F32 ToF32(this uint it) => new F32(it);
        public static F64 ToF64(this uint it) => new F64(it);

        public static U32 AND(this uint it, uint v) => new U32(it & v);
        public static U32 OR(this uint it, uint v) => new U32(it | v);
        public static U32 XOR(this uint it, uint v) => new U32(it ^ v);
        public static U32 NOT(this uint it) => new U32(~it);
        public static U32 LFT(this uint it, int v) => new U32(it << v);
        public static U32 RHT(this uint it, int v) => new U32(it >> v);

        // long
        public static Str ToStr(this long it, Str format) => it.ToString(format);
        public static Str ToBase(this long it, I32 fromBase) => Convert.ToString(it, fromBase);
        public static I8 ToI8(this long it) => new I8(it);
        public static I16 ToI16(this long it) => new I16(it);
        public static I32 ToI32(this long it) => new I32(it);
        public static I64 ToI64(this long it) => new I64(it);
        public static U8 ToU8(this long it) => new U8(it);
        public static U16 ToU16(this long it) => new U16(it);
        public static U32 ToU32(this long it) => new U32(it);
        public static U64 ToU64(this long it) => new U64(it);
        public static F32 ToF32(this long it) => new F32(it);
        public static F64 ToF64(this long it) => new F64(it);

        public static I64 AND(this long it, long v) => new I64(it & v);
        public static I64 OR(this long it, long v) => new I64(it | v);
        public static I64 XOR(this long it, long v) => new I64(it ^ v);
        public static I64 NOT(this long it) => new I64(~it);
        public static I64 LFT(this long it, int v) => new I64(it << v);
        public static I64 RHT(this long it, int v) => new I64(it >> v);

        // ulong
        public static Str ToStr(this ulong it, Str format) => it.ToString(format);
        public static Str ToBase(this ulong it, I32 fromBase) => Convert.ToString((long)it, fromBase);
        public static I8 ToI8(this ulong it) => new I8(it);
        public static I16 ToI16(this ulong it) => new I16(it);
        public static I32 ToI32(this ulong it) => new I32(it);
        public static I64 ToI64(this ulong it) => new I64(it);
        public static U8 ToU8(this ulong it) => new U8(it);
        public static U16 ToU16(this ulong it) => new U16(it);
        public static U32 ToU32(this ulong it) => new U32(it);
        public static U64 ToU64(this ulong it) => new U64(it);
        public static F32 ToF32(this ulong it) => new F32(it);
        public static F64 ToF64(this ulong it) => new F64(it);

        public static U64 AND(this ulong it, ulong v) => new U64(it & v);
        public static U64 OR(this ulong it, ulong v) => new U64(it | v);
        public static U64 XOR(this ulong it, ulong v) => new U64(it ^ v);
        public static U64 NOT(this ulong it) => new U64(~it);
        public static U64 LFT(this ulong it, int v) => new U64(it << v);
        public static U64 RHT(this ulong it, int v) => new U64(it >> v);

        // float
        public static Str ToStr(this float it, Str format) => it.ToString(format);
        public static I8 ToI8(this float it) => new I8(it);
        public static I16 ToI16(this float it) => new I16(it);
        public static I32 ToI32(this float it) => new I32(it);
        public static I64 ToI64(this float it) => new I64(it);
        public static U8 ToU8(this float it) => new U8(it);
        public static U16 ToU16(this float it) => new U16(it);
        public static U32 ToU32(this float it) => new U32(it);
        public static U64 ToU64(this float it) => new U64(it);
        public static F32 ToF32(this float it) => new F32(it);
        public static F64 ToF64(this float it) => new F64(it);

        // double
        public static Str ToStr(this double it, Str format) => it.ToString(format);
        public static I8 ToI8(this double it) => new I8(it);
        public static I16 ToI16(this double it) => new I16(it);
        public static I32 ToI32(this double it) => new I32(it);
        public static I64 ToI64(this double it) => new I64(it);
        public static U8 ToU8(this double it) => new U8(it);
        public static U16 ToU16(this double it) => new U16(it);
        public static U32 ToU32(this double it) => new U32(it);
        public static U64 ToU64(this double it) => new U64(it);
        public static F32 ToF32(this double it) => new F32(it);
        public static F64 ToF64(this double it) => new F64(it);

        // Char
        public static Str ToStr(this char it, Str format) => it.ToString();
        public static I8 ToI8(this char it) => new I8(it);
        public static I16 ToI16(this char it) => new I16(it);
        public static I32 ToI32(this char it) => new I32(it);
        public static I64 ToI64(this char it) => new I64(it);
        public static U8 ToU8(this char it) => new U8(it);
        public static U16 ToU16(this char it) => new U16(it);
        public static U32 ToU32(this char it) => new U32(it);
        public static U64 ToU64(this char it) => new U64(it);
        public static F32 ToF32(this char it) => new F32(it);
        public static F64 ToF64(this char it) => new F64(it);

        public static Chr ToLower(this char it) => char.ToLower(it);
        public static Chr ToUpper(this char it) => char.ToUpper(it);

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

        public static Str ToStr(this string it, Str format) => it;
        public static I8 ToI8(this string it) => new I8(it);
        public static I16 ToI16(this string it) => new I16(it);
        public static I32 ToI32(this string it) => new I32(it);
        public static I64 ToI64(this string it) => new I64(it);
        public static U8 ToU8(this string it) => new U8(it);
        public static U16 ToU16(this string it) => new U16(it);
        public static U32 ToU32(this string it) => new U32(it);
        public static U64 ToU64(this string it) => new U64(it);
        public static F32 ToF32(this string it) => new F32(it);
        public static F64 ToF64(this string it) => new F64(it);

        public static I8 ToI8FromBase(this string it, I32 fromBase) => new I8(it, fromBase);
        public static I16 ToI16FromBase(this string it, I32 fromBase) => new I16(it, fromBase);
        public static I32 ToI32FromBase(this string it, I32 fromBase) => new I32(it, fromBase);
        public static I64 ToI64FromBase(this string it, I32 fromBase) => new I64(it, fromBase);
        public static U8 ToU8FromBase(this string it, I32 fromBase) => new U8(it, fromBase);
        public static U16 ToU16FromBase(this string it, I32 fromBase) => new U16(it, fromBase);
        public static U32 ToU32FromBase(this string it, I32 fromBase) => new U32(it, fromBase);
        public static U64 ToU64FromBase(this string it, I32 fromBase) => new U64(it, fromBase);

        public static IEnumerable<(int index, T item)> ForEachWithIndex<T>(this IEnumerable<T> self)
   => self.Select((item, index) => (index, item));

        public static IEnumerable<(TKey, TValue)> ForEachWithIndex<TKey, TValue>(this IEnumerable<KeyValuePair<TKey, TValue>> self)
   => self.Select((item) => (item.Key, item.Value));
    }
}
