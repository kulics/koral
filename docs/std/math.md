# std.math API

## 概述
本页摘录模块 `std.math` 的公开 API（仅保留声明语法），按自由函数 / trait / 类型 / given 组织。

## 自由函数
```koral
public let [T FloatingPoint]sqrt(x T) T

public let [T FloatingPoint]cbrt(x T) T

public let [T FloatingPoint]hypot(x T, y T) T

public let [T FloatExpLog]exp(x T) T

public let [T FloatExpLog]exp2(x T) T

public let [T FloatExpLog]exp_m1(x T) T

public let [T FloatingPoint]ln(x T) T

public let [T FloatingPoint]log2(x T) T

public let [T FloatingPoint]log10(x T) T

public let [T FloatExpLog]ln_1p(x T) T

public let [T FloatTrigHyper]sin(x T) T

public let [T FloatTrigHyper]cos(x T) T

public let [T FloatTrigHyper]tan(x T) T

public let [T FloatTrigHyper]asin(x T) T

public let [T FloatTrigHyper]acos(x T) T

public let [T FloatTrigHyper]atan(x T) T

public let [T FloatTrigHyper]atan2(y T, x T) T

public let [T FloatTrigHyper]sinh(x T) T

public let [T FloatTrigHyper]cosh(x T) T

public let [T FloatTrigHyper]tanh(x T) T

public let [T FloatTrigHyper]asinh(x T) T

public let [T FloatTrigHyper]acosh(x T) T

public let [T FloatTrigHyper]atanh(x T) T

public let [T FloatSpecial]fma(x T, mul T, add T) T

public let [T FloatingPoint]lerp(a T, b T, t T) T

public let [T FloatSpecial]erf(x T) T

public let [T FloatSpecial]erfc(x T) T

public let [T FloatSpecial]gamma(x T) T

public let [T FloatSpecial]log_gamma(x T) T

public let [T FloatingPoint]log(x T, base T) T

public let [T Integer]gcd(a T, b T) T

public let [T Integer]lcm(a T, b T) T

public let [T Integer]ilog2(x T) UInt

public let [T Integer]ilog10(x T) UInt
```

## trait
```koral
public trait Numeric Sub and Mul and Ord {
    abs(self) Self
}

public trait FloatingPoint Numeric and Div and Neg {
    sqrt(x Self) Self
    cbrt(x Self) Self
    pow(self, exp Self) Self
    powi(self, exp Int) Self
    hypot(x Self, y Self) Self
    log(x Self, base Self) Self
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
    pi() Self
    e() Self
    tau() Self
    ln2() Self
    ln10() Self
    sqrt2() Self
}

public trait FloatExpLog FloatingPoint {
    exp(x Self) Self
    exp2(x Self) Self
    exp_m1(x Self) Self
    ln_1p(x Self) Self
}

public trait FloatTrigHyper FloatingPoint {
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
    to_radians(self) Self
    to_degrees(self) Self
}

public trait FloatSpecial FloatingPoint {
    fma(x Self, mul Self, add Self) Self
    erf(x Self) Self
    erfc(x Self) Self
    gamma(x Self) Self
    log_gamma(x Self) Self
}

public trait Integer Numeric and Rem {
    wrapping_abs(self) Self
    pow(self, exp UInt) Self
    wrapping_pow(self, exp UInt) Self
    gcd(a Self, b Self) Self
    lcm(a Self, b Self) Self
    ilog2(x Self) UInt
    ilog10(x Self) UInt
}
```

## 类型
（无）

## given
（无）
