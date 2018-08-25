namespace XyLang.Library
{
    public static class ExpressionExtension
    {
        public static str ToStr(this int it) { return it.ToString(); ; }
        public static str ToStr(this int it, str format) { return it.ToString(format); ; }
        public static i8 ToI8(this int it) { return new i8(it); }
        public static i16 ToI16(this int it) { return new i16(it); }
        public static i32 ToI32(this int it) { return new i32(it); }
        public static i64 ToI64(this int it) { return new i64(it); }
        public static u8 ToU8(this int it) { return new u8(it); }
        public static u16 ToU16(this int it) { return new u16(it); }
        public static u32 ToU32(this int it) { return new u32(it); }
        public static u64 ToU64(this int it) { return new u64(it); }
        public static f32 ToF32(this int it) { return new f32(it); }
        public static f64 ToF64(this int it) { return new f64(it); }

        public static str ToStr(this double it) { return it.ToString(); ; }
        public static str ToStr(this double it, str format) { return it.ToString(format); ; }
        public static i8 ToI8(this double it) { return new i8(it); }
        public static i16 ToI16(this double it) { return new i16(it); }
        public static i32 ToI32(this double it) { return new i32(it); }
        public static i64 ToI64(this double it) { return new i64(it); }
        public static u8 ToU8(this double it) { return new u8(it); }
        public static u16 ToU16(this double it) { return new u16(it); }
        public static u32 ToU32(this double it) { return new u32(it); }
        public static u64 ToU64(this double it) { return new u64(it); }
        public static f32 ToF32(this double it) { return new f32(it); }
        public static f64 ToF64(this double it) { return new f64(it); }

        public static str ToStr(this string it) { return it.ToString(); ; }
        public static str ToStr(this string it, str format) { return it.ToString(); ; }
        public static i8 ToI8(this string it) { return new i8(it); }
        public static i16 ToI16(this string it) { return new i16(it); }
        public static i32 ToI32(this string it) { return new i32(it); }
        public static i64 ToI64(this string it) { return new i64(it); }
        public static u8 ToU8(this string it) { return new u8(it); }
        public static u16 ToU16(this string it) { return new u16(it); }
        public static u32 ToU32(this string it) { return new u32(it); }
        public static u64 ToU64(this string it) { return new u64(it); }
        public static f32 ToF32(this string it) { return new f32(it); }
        public static f64 ToF64(this string it) { return new f64(it); }
    }
}
