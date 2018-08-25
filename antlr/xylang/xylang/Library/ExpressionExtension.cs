namespace XyLang.Library
{
    public static class ExpressionExtension
    {
        public static Str ToStr(this int it) { return it.ToString(); ; }
        public static Str ToStr(this int it, Str format) { return it.ToString(format); ; }
        public static I8 ToI8(this int it) { return new I8(it); }
        public static I16 ToI16(this int it) { return new I16(it); }
        public static I32 ToI32(this int it) { return new I32(it); }
        public static I64 ToI64(this int it) { return new I64(it); }
        public static U8 ToU8(this int it) { return new U8(it); }
        public static U16 ToU16(this int it) { return new U16(it); }
        public static U32 ToU32(this int it) { return new U32(it); }
        public static U64 ToU64(this int it) { return new U64(it); }
        public static F32 ToF32(this int it) { return new F32(it); }
        public static F64 ToF64(this int it) { return new F64(it); }

        public static Str ToStr(this double it) { return it.ToString(); ; }
        public static Str ToStr(this double it, Str format) { return it.ToString(format); ; }
        public static I8 ToI8(this double it) { return new I8(it); }
        public static I16 ToI16(this double it) { return new I16(it); }
        public static I32 ToI32(this double it) { return new I32(it); }
        public static I64 ToI64(this double it) { return new I64(it); }
        public static U8 ToU8(this double it) { return new U8(it); }
        public static U16 ToU16(this double it) { return new U16(it); }
        public static U32 ToU32(this double it) { return new U32(it); }
        public static U64 ToU64(this double it) { return new U64(it); }
        public static F32 ToF32(this double it) { return new F32(it); }
        public static F64 ToF64(this double it) { return new F64(it); }

        public static Str ToStr(this string it) { return it.ToString(); ; }
        public static Str ToStr(this string it, Str format) { return it.ToString(); ; }
        public static I8 ToI8(this string it) { return new I8(it); }
        public static I16 ToI16(this string it) { return new I16(it); }
        public static I32 ToI32(this string it) { return new I32(it); }
        public static I64 ToI64(this string it) { return new I64(it); }
        public static U8 ToU8(this string it) { return new U8(it); }
        public static U16 ToU16(this string it) { return new U16(it); }
        public static U32 ToU32(this string it) { return new U32(it); }
        public static U64 ToU64(this string it) { return new U64(it); }
        public static F32 ToF32(this string it) { return new F32(it); }
        public static F64 ToF64(this string it) { return new F64(it); }
    }
}
