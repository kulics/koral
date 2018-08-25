namespace XyLang.Library
{
    public static class ExpressionExtension
    {
        public static Str ToStr(this int it) => it.ToString();
        public static Str ToStr(this int it, Str format) => it.ToString(format);
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

        public static Str ToStr(this uint it) => it.ToString();
        public static Str ToStr(this uint it, Str format) => it.ToString(format);
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

        public static Str ToStr(this double it) => it.ToString();
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

        public static Str ToStr(this string it) => it.ToString();
        public static Str ToStr(this string it, Str format) => it.ToString();
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
        public static bool NoEmpty(this string it) => it.Length > 0;
    }
}
