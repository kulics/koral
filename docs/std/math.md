# Std.Math API

## Overview
This page lists the public API of module `Std.Math` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let sqrt[T FloatingPoint](x T) T

public let cbrt[T FloatingPoint](x T) T

public let hypot[T FloatingPoint](x T, y T) T

public let exp[T FloatMath](x T) T

public let exp2[T FloatMath](x T) T

public let exp_m1[T FloatMath](x T) T

public let ln[T FloatingPoint](x T) T

public let log2[T FloatingPoint](x T) T

public let log10[T FloatingPoint](x T) T

public let ln_1p[T FloatMath](x T) T

public let sin[T FloatMath](x T) T

public let cos[T FloatMath](x T) T

public let tan[T FloatMath](x T) T

public let asin[T FloatMath](x T) T

public let acos[T FloatMath](x T) T

public let atan[T FloatMath](x T) T

public let atan2[T FloatMath](y T, x T) T

public let sinh[T FloatMath](x T) T

public let cosh[T FloatMath](x T) T

public let tanh[T FloatMath](x T) T

public let asinh[T FloatMath](x T) T

public let acosh[T FloatMath](x T) T

public let atanh[T FloatMath](x T) T

public let fma[T FloatingPoint](x T, mul: T, add: T) T

public let lerp[T FloatingPoint](a T, b T, t T) T

public let erf[T FloatMath](x T) T

public let erfc[T FloatMath](x T) T

public let gamma[T FloatMath](x T) T

public let log_gamma[T FloatMath](x T) T

public let log[T FloatingPoint](x T, base: T) T

public let gcd[T Integer](a T, b T) T

public let lcm[T Integer](a T, b T) T

public let ilog2[T Integer](x T) UInt

public let ilog10[T Integer](x T) UInt
```

## Traits
```koral
public trait Numeric Add[Self] and Sub[Self] and Mul[Self] and Ord {
    abs(self) Self
}

public trait FloatingPoint Numeric and Div[Self] and Neg {
    sqrt(x Self) Self
    cbrt(x Self) Self
    pow(self, exp Self) Self
    powi(self, exp Int) Self
    hypot(x Self, y Self) Self
    log(x Self, base: Self) Self
    ln(x Self) Self
    log2(x Self) Self
    log10(x Self) Self
    floor(self) Self
    ceil(self) Self
    round(self) Self
    trunc(self) Self
    signum(self) Self
    fract(self) Self
    copysign(self, sign Self) Self
    fmod(self, y Self) Self
    fma(x Self, mul: Self, add: Self) Self
    to_radians(self) Self
    to_degrees(self) Self
    pi() Self
    e() Self
    tau() Self
    ln2() Self
    ln10() Self
    sqrt2() Self
}

public trait FloatMath FloatingPoint {
    exp(x Self) Self
    exp2(x Self) Self
    exp_m1(x Self) Self
    ln_1p(x Self) Self
    sin(x Self) Self
    cos(x Self) Self
    tan(x Self) Self
    asin(x Self) Self
    acos(x Self) Self
    atan(x Self) Self
    atan2(y Self, x Self) Self
    sinh(x Self) Self
    cosh(x Self) Self
    tanh(x Self) Self
    asinh(x Self) Self
    acosh(x Self) Self
    atanh(x Self) Self
    erf(x Self) Self
    erfc(x Self) Self
    gamma(x Self) Self
    log_gamma(x Self) Self
}

public trait Integer Numeric and Div[Self] and Rem[Self] {
    wrapping_abs(self) Self
    pow(self, exp UInt) Self
    wrapping_pow(self, exp UInt) Self
    gcd(a Self, b Self) Self
    lcm(a Self, b Self) Self
    ilog2(x Self) UInt
    ilog10(x Self) UInt
}
```

## Types
(none)

## Given Implementations
(none)
