# Koral 编程语言

Koral 是一个专注于性能、可读性和实用跨平台开发的开源编程语言。

通过精心设计的语法规则，这门语言可以有效降低读写负担，让你能够把真正的注意力放在解决问题上。

规范说明：

- 本文档是面向用户的语言参考手册。
- 涉及文法细节时，请配合 `docs/guide/grammar.bnf` 一起阅读。
- 如果本文档、BNF 与实现出现不一致，请更新实现和/或文档，使三者收敛。

本手册按学习路线组织：**语言基本元素**，到**控制流**，到**自定义类型**，到**模式匹配**，到**抽象设计**，最后是**外部互操作**。

## 概述

### 关键特性

- 现代、易扫读的语法：显式分号 + 表达式化的控制流，`if`、`when`、`while`、`for` 都使用表达式形态的表层语法。`if` 与 `when` 可以产生值；`while` 与 `for` 总是产生 `Void`。
- 由声明处类型语义驱动的自动内存管理：浅层不可变的 `type` 与共享的 `type mutable` 对象。布局与生命周期细节由编译器负责。
- 并发安全在类型声明处决定：`sendable` 族标明哪些类型能跨线程共享，安全的 `sendable mutable` 对象自带对象锁——每次字段访问取一把短锁，不可重入也永远不需要——检查全部落在声明处与形成处。跨线程的集合数据是复制不是移动：`to_frozen_list()` 等整体复制进独立的 `type unsafe sendable mutable` 快照存储（承诺「构造后只读」），源保持可用，`to_list()` 复制回来。
- 带 trait 约束的泛型与单态化，实现零成本抽象。
- 代数数据类型（结构体与枚举）配合穷举性模式匹配。
- 基于 trait 的多态，trait object 提供运行期分发。
- 一等函数、lambda 与闭包。
- 多范式编程（函数式与命令式结合）。
- 带访问控制的模块系统（`private` / `internal` / `protected` / `public`）。
- 外部函数接口（FFI），与 C 平滑互操作。
- C 后端，具备广泛的平台兼容性。

### 核心理念：`type` / `type mutable`

Koral 的 nominal 类型有两种可变性形态，在声明处决定。语言里的其他一切——别名、可变性与布局——都由这一个决定推导而来。另有一条独立的 `sendable` 轴管理跨线程共享（见[并发](#并发)）——它与两种形态组合，不改变它们。

**`type` —— 浅层不可变的 nominal 类型。**

- 构造后字段不可修改，也不能声明 `mutable` 字段。
- **没有 identity**：字段相同的两个值可以互换。
- **内存布局由编译器决定**。内联存储、隐藏间接层、共享 backing 都是实现细节，版本之间可能不同。
- **值语义不属于语言契约**。复制、传参与存储可以共享 backing。正因该类型浅层不可变，这种共享不可观察——所以编译器可以自由地把它优化掉。
- **`type` 不能实现 `Drop`。** `type` 承诺没有 identity——同字段的值可以互换——析构会经由 drop 计数把构造身份泄漏出来。清理走合成的字段释放；需要析构的类型声明 `type mutable`，见 [`Drop`](#drop)。

**`type mutable` —— 共享对象类型。**

- 有 identity：赋值与传参交出的是**同一个**对象的句柄。
- 字段默认不可变；只有显式声明为 `mutable` 的字段才能原地修改，而且只能经由共享句柄进行。

```koral
type Point(x: Int, y: Int);

type mutable Counter(mutable value: Int, id: UInt);

let p = Point(1, 2);
// p.x = 3;      // error: Point 是 `type`，字段不可变

let c = Counter(0, 1);
c.value = 5;      // ok: Counter 是 `type mutable` 且 `value` 是 mutable 字段
// c.id = 2;     // error: `id` 不是 mutable 字段
```

编译器可能在内部对两种形态使用引用计数与隐藏存储。这些都不是用户可见语义：语言契约是 `type` 与 `type mutable` 之分，绝不是某种托管引用语法。清理也循同一条线——`type` 由合成的字段释放清理，只有 `type mutable` 才能实现 `Drop`。

### 安装与使用

`Koral` 目前编译到 C 并在后端调用 `clang`，因此 `PATH` 中必须有 `clang`。

#### 编译与运行

既可以编译单个源文件，也可以编译由 manifest 声明的模块图。

1.  **构建单个文件**：
    ```bash
    koralc build hello.koral;
    ```
2.  **构建 manifest 声明的目标模块**：
    ```bash
    koralc build --package-config koral.json --target-module app;
    ```
3.  **仅做类型检查**：
    ```bash
    koralc check --package-config koral.json --target-module app;
    ```
4.  **编译并运行**：用 `run` 一步完成编译与执行。
    ```bash
    koralc run --package-config koral.json --target-module app;
    ```
5.  **仅生成 C**：用 `emit-c` 生成 C 源码。
    ```bash
    koralc emit-c --package-config koral.json --target-module app -o out;
    ```

常用选项：

- `-o, --output <dir>`：输出目录
- `--package-config <path>`：从包 manifest 构建
- `--target-module <全名>`：选择目标模块（`包名[/子路径]`）；缺省是主模块
- `--requires-root <path>`：manifest 构建的依赖根目录
- `--std-config <path>`：显式指定 std 的 manifest 路径
- `--no-std`：不加载 `std/koral.json` 声明的模块

## 1. 语言基本元素

### 程序结构

#### 语句与分号

在 Koral 中，语句是最小的组成单位。

语句终止规则：

- 每条语句和声明都必须以分号 `;` 结束。
- `}` 不是语句终止符；它是块、类型、trait 与 given 语法的一部分。
- 换行没有语义。
- 没有自动分号插入（ASI）。
- 没有接续符或换行续行概念。
- `()` 与 `[]` 只是分组结构，不提供换行终止语义。
- 作为语句使用的 `if`、`when`、`for`、`while` 必须以 `;` 结束。
- 顶层声明（函数、类型、trait、given 实现）必须以 `;` 结束。

```koral
let a = 0;
let b = 1;

let count = "abc".count();

let branch = if false then 1 else 2;

let grouped = (1 + 2);

let fib(n: Int): Int = {
    if n <= 1 then { return n; };
    return fib(n - 1) + fib(n - 2);
};

if x > 0 then {
    println("positive");
} else {
    println("non-positive");
};
```

#### 入口函数

每个可执行程序都需要一个入口点。在 Koral 中，入口点就是 `main` 函数。典型的 `main` 声明如下。

```koral
let main(): Void = {};
```

这里声明了一个名为 `main` 的函数。`=` 右侧是函数体，`{}` 表示空的块表达式，返回 `Void`。

`main` 函数必须：

- 没有参数。
- 返回 `Int` 或 `Void`。

```koral
let main(): Int = {
    println("Hello");
    return 0;
};
```

#### 显示信息

标准库提供 `println` 函数，把一行文本打印到标准输出。

```koral
let main(): Void = println("Hello, world!");
```

试着执行这个程序，就能在控制台看到 `Hello, world!`。

#### 注释

注释是编译器忽略的代码部分，用来给读代码的人提供说明。

```koral
// 这是单行注释，从双斜杠开始直到行尾

/*
    这是块注释。
    它可以跨越多行。
    /* Koral 支持嵌套块注释 */
*/
```

#### 标识符

标识符是给变量、函数、类型等起的名字。命名规则是：

1. 区分大小写。`Myname` 与 `myname` 是两个不同的标识符。
2. **类型**与**构造器**必须以**大写字母**开头（如 `Int`、`String`、`Point`）。
3. **变量**、**函数**、**成员**必须以**小写字母**或下划线开头（如 `main`、`println`、`x`）。
4. 标识符的其他字符可以是下划线 `_`、字母或数字。
5. 同一个 `{}` 内不能重复定义同名标识符。
6. 不同 `{}` 内可以定义同名标识符，语言优先使用当前作用域中定义的标识符。

### 条件编译声明

`#if` 在编译期按构建目标（os 与 arch）选择声明。它住在声明域：分支里是全局声明（可嵌套 `#if`），不是语句或表达式。

```koral
#if os("windows") then {
    let foreign "CreateFileA" create_file_a(path: *UInt8, access: UInt32): UInt32;
} else {
    let foreign "open" open_path(path: *UInt8, flags: Int32): Int32;
};
```

- 条件是一个封闭的小文法，不是表达式：`os("...")` 与 `arch("...")` 原子，用 `and`、`or`、`not` 与括号组合。值来自封闭集——`os` ∈ `windows` / `linux` / `macos`，`arch` ∈ `x86_64` / `aarch64`。未知谓词头或未知值报错并列出集合。
- 分支一律是块，整条以 `;` 收尾。没有 `#endif`。
- 未选中的分支仍必须能解析，但它的名字不进解析、类型不进检查。
- 同名声明必须在同一条 `#if … else …` 的两分支树上两两分道（一侧一条）。能共存的两条即重复声明；无条件声明与条件声明同名即冲突。检查是纯语法的：不存在「某个构建目标上才炸」的漂移错误。
- `using` 可以出现在分支块内（条件导入）。含 `using` 的 `#if` 整条归入文件的 using 区——与顶层同一条「导入在前」规则。

### 值与字面量

完成大部分工作只需要少数几种基本类型。

#### 布尔

布尔指逻辑值，只能是 true 或 false。默认布尔类型是 `Bool`。

```koral
let b1: Bool = true;
let b2: Bool = false;
let isGreater = 5 > 3; // 结果是 true
```

#### 数值与数值字面量

Koral 提供丰富的数值类型以满足不同需求。默认整数是 `Int`，浮点数使用 `Float64`（64 位）或 `Float32`（32 位）。

- `Int`：平台相关的有符号整数（通常是 64 位）。
- `UInt`：平台相关的无符号整数（通常是 64 位）。
- `Int8`、`Int16`、`Int32`、`Int64`：定宽有符号整数。
- `UInt8`、`UInt16`、`UInt32`、`UInt64`：定宽无符号整数。
- `Float32`：32 位浮点数。
- `Float64`：64 位浮点数。

```koral
let i: Int = 3987349;
let f: Float64 = 3.14;
let b: UInt8 = 255;
```

数值字面量支持用下划线 `_` 作分隔符以提高可读性：

```koral
let million = 1_000_000;
let pi = 3.141_592_653;
```

数字分隔符必须**夹在同一段数位的两个数字之间**——整数部分、小数部分或指数数位皆可，各种进制通用。不能开头、不能结尾、不能连写、不能紧贴 `.`：

```koral
let ok1 = 1_000;        // 合法：夹在数字之间
let ok2 = 1.0_0_1;      // 合法：夹在小数数位之间
let ok3 = 1_0e1_0;      // 合法：尾数与指数里都可以分隔
let ok4 = 0xFF_FF;      // 合法：夹在十六进制数位之间

// let bad1 = 1_;       // 错误：结尾分隔符
// let bad2 = _1;       // 根本不是字面量——`_1` 是标识符
// let bad3 = 1__0;     // 错误：连写分隔符
// let bad4 = 1_.0;     // 错误：分隔符紧贴 '.'
// let bad5 = 1.0_;     // 错误：结尾分隔符
// let bad6 = 0x_1;     // 错误：进制前缀后直接是分隔符
```

以上非法写法都是词法错误：`Invalid digit separator '_' in numeric literal`。数值字面量永远不能以 `_` 开头（那会是标识符）；`1._x` 是对 `1` 的成员访问而非浮点数——小数点后必须紧跟数字。

Koral 还分别用 `0b`、`0o`、`0x` 前缀支持二进制、八进制和十六进制整数字面量：

```koral
let bin = 0b1010;          // 二进制，值为 10
let oct = 0o755;           // 八进制，值为 493
let hex = 0xFF;            // 十六进制，值为 255
```

非十进制字面量同样支持下划线分隔符：

```koral
let mask = 0xFF_FF;        // 十六进制，值为 65535
let flags = 0b1010_0101;   // 二进制，值为 165
```

注意：非十进制字面量只支持整数，不支持浮点数。十六进制字母不区分大小写（`0xABcd` 等价于 `0xabCD`）。

浮点字面量还支持使用 `e` 指数后缀的科学计数法：

```koral
let a = 1e3;      // 1000.0
let b = 1e-3;     // 0.001
let c = 2.5e+2;   // 250.0
let d = 1_000e2;  // 100000.0
```

注意：指数写法只支持小写 `e`，与 `0b`/`0o`/`0x` 前缀的约定一致。`e` 只有在后面跟着数字或 [±] 数字时才开启指数：`1e10`、`2.5e-3` 是浮点数，而 `1exp` 是整数 `1` 与标识符 `exp` 两个记号（`1e_1` 同理，是 `1` 与 `e_1`）。

#### Duration 字面量

Duration 支持整数字面量后缀：

```koral
let a = 10s;
let b = 250ms;
let e = 150us;
let f = 42ns;
```

支持的后缀为 `s`、`ms`、`us`、`ns`。时长字面量是 `Duration` 构造的语法糖——`10s` 等价于 `Duration.new(seconds = 10, nanoseconds = 0)`——并且结果已自动解包。负时长保持一元负号语义（例如 `-5s` 解析为对 `5s` 施加一元 `-`）。

#### 数值转换

不同数值类型之间需要显式转换，使用 `Type(expr)` 语法：

```koral
let a: Int = 42;
let b: Float64 = Float64(a);    // Int -> Float64
let c: Int32 = Int32(a);        // Int -> Int32
let d: UInt8 = UInt8(255);      // Int -> UInt8
```

指针重解释与弱句柄构造换一套拼写：`expr as Type`（见「指针类型」）——`p as *T`、
`u as *Int`、`p as UInt`、`b as ?T`，`as` 的目标只允许指针与弱引用。
`Type(expr)` 做数值转换，外加构造（`Point(1, 2)`）与 trait object upcast
（`Drawable(c)`）；`Bool(x)`、`String(x)` 是错误（`Type does not support cast`），
数值目标的 `x as Int` 同样拒绝（`Numeric conversion is written 'Type(expr)', not 'expr as Type'`），
其它 `as` 目标一律拒绝（`'as' casts to pointer or weak types`）。

转换只有这一套拼写，**策略由目标类型决定**。整数按算术/转换策略分成三个平行家族——
每族十个类型，同宽平行、强制隔离（`WrappingInt` 与 `Int` 不能出现在同一个操作里）：

| 家族 | 类型 | 算术溢出 | 改宽度转换 | 状态 |
|---|---|---|---|---|
| 常规 | `Int` `Int8` `Int16` `Int32` `Int64` `UInt` `UInt8` `UInt16` `UInt32` `UInt64` | panic | 受检 | 默认 |
| 回绕 | `WrappingInt` `WrappingInt8` … `WrappingUInt64` | 模 2^N 回绕 | 取目标宽度低位 | 已内建 |
| 饱和 | `SaturatingInt` `SaturatingInt8` … | 夹到 MIN/MAX | 夹到 MIN/MAX | 预留，未实现 |

分界线是**有没有回绕答案**：有就回绕，没有才 panic。算术溢出回绕（模 2^N）；
移位量越界按宽度取掩码（`WrappingInt8(1) << 9` 得 `2`）；`MIN / -1` 回绕到 `MIN`。
除零 / 取余零没有回绕答案，照样 panic——`NaN` / ±inf 转整数同理。
`Wrapping*` 与同名常规类型同宽同 ABI：家族是编译期策略，不是另一种机器表示。

转换矩阵只看目标：

| 源 → 目标 | 同宽 | 改宽度 |
|---|---|---|
| 常规 → 常规 | 无损重贴标签 | **受检** |
| 常规 → 回绕 | 无损重贴标签 | **截断** |
| 回绕 → 常规 | 无损重贴标签 | **受检** |
| 回绕 → 回绕 | 无损重贴标签 | **截断** |

- **同宽**永远无损重贴标签，双向皆然，含符号互转的位重解释：信息不丢，只是读法
  不同。`n = -5` 的 `UInt(n)` 重解释为 `18446744073709551611`，不是回绕。
- **改宽度 + 常规目标**按目标类型的取值范围受检（收窄、放宽同理）。装不下就在
  运行期 panic。
- **改宽度 + 回绕目标**取目标宽度的低位——截断，放宽时对二进制补码表示做符号/零
  扩展——永不 panic。

```koral
let big: Int = 300;
let a: UInt8 = UInt8(big);                        // Panic: numeric conversion overflow
let n: Int = -5;
let u: UInt = UInt(n);                            // 18446744073709551611 —— 重解释
let low: UInt8 = UInt8(WrappingUInt8(big));       // 44 —— 低字节
let b: Int8 = -1;
let wide: UInt = UInt(WrappingUInt(b));           // 18446744073709551615 —— 先符号扩展
let raw: UInt8 = UInt8(WrappingUInt8(b));         // 255
```

取字节的惯用法——序列化、哈希、位运算技巧——正是回绕目标的价值所在：截断是目的，
panic 只会碍事。负的 `Int8` 经它哈希会符号扩展，于是同一个数无论以哪种宽度进来，
哈希值都一致：

```koral
given Int8: Hash {
    public hash(self): UInt = UInt(WrappingUInt(self));
};
```

字面量一律**编译期**受检，按宽度而不按家族判断：写死的常量装不下是作者笔误，不是
数据相关的溢出。`WrappingUInt8(300)` 与 `UInt8(300)` 报同一个错
（`Integer literal 300 is out of range for UInt8`）。字面量还完整参与整数字面量收窄，
向另一侧的整数类型靠拢——`WrappingInt(n) + 123` 与 `123 + WrappingInt(n)` 都是
普通的回绕算术。

浮点不设家族。整数转浮点永不检查——精度可失（|n| > 2^53）——浮点转浮点同样不检查
（可失精度或溢出得 ±inf）。浮点转整数分两步：

1. **定义域**：`NaN` 与 ±inf 没有可截断的整数值，无论目标家族一律 panic。
2. **范围**：向零截断后的整数值按目标家族的策略处理——常规受检（`Int(1e20)` panic），
   回绕取低位（`WrappingUInt8(300.7)` 得 `44`）。

#### 字符串 ↔ 数值

文本与数值之间的转换不是转型——两者之间没有可利用的数值关系。它走 `std/text`，
由三个 trait 承担：`Parseable`（`parse`）、`RadixParseable`（`parse_radix`）与
`Formattable`（`format`）。

```koral
using "std/text" { ... };

// 字符串 -> 数值：目标类型上的静态方法，返回 Result[Self]
let n = Int.parse("42") or else 0;            // 42
let f = Float64.parse("3.14") or else 0.0;    // 3.14
let b = Int.parse_radix("ff", 16) or else 0;  // 255

// 数值 -> 字符串
let s = 42.to_string();                       // "42"

// 数值 -> 字符串，带格式说明符
let hex = 255.format("x");                    // "ff"
let fixed = 3.14159.format(".2f");            // "3.14"
let sci = 1500.0.format(".2e");               // "1.50e3"
```

`parse` 会拒绝它认不出来的输入，因此返回 `Result` 而不是尽力而为的数字——
`Int.parse("abc")` 是 `.Error`，不是 `0`。整数类型实现 `RadixParseable`，
支持 2–36 进制；浮点只接受十进制、`nan`、`inf` 与 `-inf`。

`std` 中没有自由函数形式的转换——没有 `parse_int`、`to_int`、`to_string(x)`。
用 `T.parse(s)`、`parse_radix`、`.to_string()` 和 `.format(spec)`。

#### 字符串

在 Koral 中，字符串用于表示文本数据。`String` 类型是 UTF-8 编码的字符序列。

字符串字面量只使用双引号 `""`。

```koral
let s1: String = "Hello, world!";
```

Koral 支持字符串插值，可以用 `\(expr)` 语法把表达式嵌入字符串：

```koral
let name = "Koral";
let count = 3;
println("Hello, \(name)!");                    // Hello, Koral!
println("Count: \(count)");                    // Count: 3
println("Mixed \(name) has \(count) messages"); // Mixed Koral has 3 messages
println("Sum \(1 + (2 * 3))");                 // Sum 7
```

转义字符使用反斜杠 `\`：

```koral
"\n";        // 换行
"\t";        // 制表符
"\r";        // 回车
"\v";        // 垂直制表
"\f";        // 换页
"\0";        // 空字符
"\\";        // 反斜杠
"\"";        // 双引号
"\'";        // 单引号
"\x41";      // 十六进制字节转义：恰好 2 位十六进制（0x00–0xFF），如 \x41 = 'A'
"\u{41}";    // Unicode 标量转义：1–6 位十六进制，如 \u{41} = 'A'，\u{1F600} = 😀
```

##### 多行字符串字面量

用 `"""` 界符书写跨多行的字符串，规则与 Swift 相同：

- 开头的 `"""` 之后必须紧跟换行。
- 结尾的 `"""` 必须独占一行。它的前导空白（空格或制表符）定义了要从每个内容行剥离的公共缩进前缀。
- 每个内容行的缩进必须至少与结尾 `"""` 相同，否则报编译错误。
- 支持与普通字符串相同的转义序列和 `\(...)` 插值。

```koral
let message = """
    Hello, Koral!
    Welcome to multiline strings.
    """;
// 等价于 "Hello, Koral!\nWelcome to multiline strings."

let name = "World";
let greeting = """
    Hello, \(name)!
    Have a great day.
    """;
// 等价于 "Hello, World!\nHave a great day."
```

结尾 `"""` 的缩进决定剥离量：

```koral
let s = """
        indented content
        second line
    """;
// 结尾 """ 缩进 4 空格，内容缩进 8 空格。
// 剥离 4 空格后："    indented content\n    second line"
```

常用 String 方法：

```koral
let s = "Hello, World!";
s.count();                        // 13 - 字节长度
s.is_empty();                     // false
s.contains("World");              // true
s.starts_with("Hello");           // true
s.ends_with("!");                 // true
s.to_ascii_lowercase();           // "hello, world!"
s.to_ascii_uppercase();           // "HELLO, WORLD!"
s.trim_ascii();                   // 去掉首尾空白
s.substring(0..<5);               // "Hello" - 切片
s.find("World");                  // Some(7)
s.replace_all("World", with = "Koral"); // "Hello, Koral!"
s.split(",");                     // 按分隔符切分
s.lines();                        // 按行切分

// 连接字符串列表
list.join_to_string(", ");        // 用分隔符连接 List[String]
```

要增量构建 `String`，请使用 `StringBuilder`：

```koral
let sb = StringBuilder.new();
sb.push_string("Hello");
sb.push_byte(',');
sb.push_string(" World");
let s = sb.to_string();
```

#### Rune 字面量

Rune 字面量使用单引号 `''`，表示恰好一个 Unicode 标量值。

```koral
let r: Rune = 'A';
let nl: Rune = '\n';
let smile: Rune = '\u{1F600}';
```

Rune 字面量的类型规则：

- 默认类型是 `Rune`。
- 在显式的 `UInt8` 上下文中，如果它是单个 ASCII 字符，可以推断为字节（`UInt8`）。

#### 集合字面量

Koral 为内建集合类型提供字面量：`List[T]`、`Set[T]`、`Dict[K, V]`，以及冻结快照 `FrozenList[T]`、`FrozenSet[T]`、`FrozenDict[K, V]`（见[冻结集合](#冻结集合)）。

```koral
let a = [1, 2, 3];                    // 推断为 List[Int]
let b: Set[Int] = [1, 2, 3];           // 由上下文推断为 Set[Int]
let c = ["x": 1, "y": 2];             // 推断为 Dict[String, Int]
let f: FrozenList[Int] = [1, 2, 3];   // 由上下文生成冻结快照
let empty: List[Int] = [];             // 空字面量需要类型上下文
```

规则：

- `[e1, e2, ...]` 是集合字面量。没有类型上下文时推断为 `List[T]`。
- 在 `Set[T]` 或 `FrozenSet[T]` 上下文中，同样语法推断为集合；重复元素折叠。
- `[k1: v1, k2: v2, ...]` 是字典字面量，推断为 `Dict[K, V]`——在 `FrozenDict[K, V]` 上下文中推断为后者；重复键后者取胜。
- `[]` 没有类型上下文时无法推断，必须标注类型。
- 集合字面量和字典字面量都允许尾随逗号。
- 集合字面量只面向内建容器及其冻结快照（`List` / `Set` / `Dict` / `FrozenList` / `FrozenSet` / `FrozenDict`），不面向第三方容器类型。

`List`、`Set`、`Dict`、`Deque` 是 `type mutable` 的共享对象：不使用写时复制。修改容器对每个句柄都可见，需要独立副本时必须显式使用 `clone()`。它们是线程内工作状态——全都不能跨线程边界（见[冻结集合](#冻结集合)）。

`Dict` 与 `Set` 的遍历顺序**不作承诺**：顺序跟随表布局，而表布局按进程取种子（散列洪泛防线），因此每次运行可能不同。需要稳定顺序的代码应自行对键排序。`List` 与 `Deque` 按存储顺序遍历。

### 变量与绑定

Koral 的变量采用绑定语义，相当于把变量名和值绑定在一起。出于安全考虑，变量默认不可变，同时也提供可变变量。

#### 只读绑定

在 Koral 中，只读变量用 `let` 关键字声明，遵循先声明后使用的原则。

Koral 通过静态类型保证类型安全。变量绑定可以在声明时显式标注类型。当上下文信息足够时，也可以省略类型，由编译器推断变量类型。

```koral
let a: Int = 5;   // 显式类型标注
let b = 123;     // 自动类型推断
```

只读变量一旦声明，在当前作用域内不能改变其值。

```koral
let a = 5;
a = 6 // 错误
```

注意：绑定到 `type mutable` 对象的只读绑定，仍然可以修改该对象的 `mutable` 字段——绑定是固定的，对象是共享的：

```koral
let xs = [10, 20, 30];
xs[1] = 99;      // ok: List 是 `type mutable`，绑定本身没有被重新赋值
```

#### 可变绑定

如果需要能重新绑定的变量，可以使用 `let mutable` 的可变变量声明。

```koral
let mutable a: Int = 5;   // 显式类型标注
let mutable b = 123;     // 自动类型推断
```

#### 元组解构绑定

圆括号绑定按**位置**解构一个**结构体**：绑定位置的数量必须等于字段数，并按声明顺序绑定。每个绑定位置支持 `_`（丢弃）、`mutable`（可变绑定）和可选的类型标注。至少要两个绑定位置——`(x)` 是加了括号的绑定，不是解构。

`Pair` 就是一个两字段结构体，所以它也是这样拆开的。

```koral
let (a, b) = Pair(1, 2);                    // 两字段结构体
let (c: Int, d: String) = Pair(3, "hello");   // 显式类型标注
let (mutable e, f) = Pair(10, 20);          // 可变绑定
let (_, g) = Pair(1, 2);                    // 丢弃第一个字段

type Point3(x: Int, y: Int, z: Int);
let (px, py, pz) = Point3(1, 2, 3);         // 任意字段数
```

**没有元组 / pair 字面量。** 用构造器构造 `Pair`，和其它类型一样：`Pair[Int, String](1, "a")`。

### 赋值

对于可变绑定，可以在需要时多次改变它们指向的值。

```koral
let mutable a = 0;
a = 1;  // 合法
a = 2;  // 合法
```

### 块表达式

在 Koral 中，`{}` 表示块表达式。

块规则：

- 块包含零条或多条语句。
- `Result` 不允许被静默丢弃：语句位置上的 `Result` 必须被使用，或显式丢弃——`let _ = expr;` 表示"有意丢掉"。被静默丢弃的 `Result` 就是丢失的错误，这条规则正是为堵住它。其它语句值照常静默丢弃（`Void`、`Never`，以及"交回一个观察值、调用方照常忽略"的有副作用辅助函数）。
- 块可以在末尾带一个不写分号的尾表达式。
- 如果块带有尾表达式，块的类型和值就是该表达式的类型和值。
- 如果块没有尾表达式，或最后一个表达式写了分号，块的类型是 `Void`。
- `return`、`break`、`continue` 可以提前结束块，因此让该块的类型是 `Never`。
- 裸 `break` 退出最近的 `while` 或 `for` 循环。
- 以 `return`、`break` 或 `continue` 结尾的块类型为 `Never`。

示例：

```koral
let load(path: String): Result[Int] = {
    let text = read_text_file(path) or return;
    return Int.parse(text);
};

let increment(): Int = {
    let base = 41;
    base + 1
};

let a: Void = {};
let main(): Void = {
    let c = 7;
    let d = c + 14;
    println(((c + 3) * 5 + d / 3).to_string());
};
```

### 操作符

操作符是告诉编译器执行特定数学或逻辑运算的符号。

#### 算术操作符

```koral
let a = 4;
let b = 2;
println( a + b );    // + 加
println( a - b );    // - 减
println( a * b );    // * 乘
println( a / b );    // / 除
println( a % b );    // % 取模
```

#### 比较操作符

比较操作符比较两个值，结果是 `Bool` 类型。

```koral
let a = 4;
let b = 2;
println( a == b );     // == 等于
println( a != b );     // != 不等于
println( a > b );      // > 大于
println( a >= b );     // >= 大于等于
println( a < b );      // < 小于
println( a <= b );     // <= 小于等于
```

Koral 还支持链式序比较，作为区间式谓词的语法糖：

```koral
println(1 < x < 3);
println(10 >= y > 0);
println(a <= b <= c);
```

链式比较只限于 `<`、`<=`、`>`、`>=`，且链中每个操作符必须保持同一方向族（升序 `<`/`<=` 或降序 `>`/`>=`）。`a < b > c`、`a < b == c`、`a == b < c` 这类混合链会被拒绝，请显式改写为 `and`。
合法链中的每个操作数最多求值一次，且从左到右短路。

#### 逻辑操作符

逻辑操作符对两个 Bool 操作数执行逻辑运算（与、或、非）。

```koral
let a = true;
let b = false;
println( a and b );       // 与，两者都为真才为真
println( a or b );        // 或，任一为真即为真
println( not a );         // 非，布尔取反
```

`and` 与 `or` 具有短路语义：

```koral
let a = false and f(); // f() 不会被执行
let b = true or f();   // f() 不会被执行
```

#### 位操作符

```koral
let a = 4;
let b = 2;
println( a & b );    // 按位与
println( a | b );    // 按位或
println( a ^ b );    // 按位异或
println( ~a );       // 按位取反
println( a << b );   // 左移
println( a >> b );   // 右移
```

#### 范围操作符

范围操作符生成范围（Range），常用于循环或模式匹配。

```koral
1..5;     // 1 <= x <= 5（闭区间）
1..<5;    // 1 <= x < 5（右开区间）
1<..5;    // 1 < x <= 5（左开区间）
1<..<5;   // 1 < x < 5（开区间）
1...;     // 1 <= x（右无界，含起点）
1<...;    // 1 < x（右无界，不含起点）
...5;     // x <= 5（左无界，含终点）
...<5;    // x < 5（左无界，不含终点）
...;      // 全范围
```

`..` 族是连接符：两端都写出来，总是二元。`...` 族标记被省略的那一端——它站在
缺掉的界的位子上，所以 `...` 范围至多一端有界（`1...` 是从 1 到无穷，`...5`
是从负无穷到 5，`...` 是全范围）。`<` 永远夹在点与被排除的界之间。

这些范围操作符构造 `Range` 值。它们不同于 `1 < x < 5` 这类链式比较谓词，后者产生 `Bool`。

#### 复合赋值

```koral
let mutable x = 10;
x += 5;       // x = x + 5
x -= 2;       // x = x - 2
x *= 3;       // x = x * 3
x /= 2;       // x = x / 2
x %= 4;       // x = x % 4

let mutable y = 12;
y &= 10;     // y = y & 10
y |= 1;      // y = y | 1
y ^= 15;     // y = y ^ 15
y <<= 1;     // y = y << 1
y >>= 2;     // y = y >> 2
```

每个 `op=` **就是**它写出来的解糖形——两步操作，不是一步原子操作。先求目标
（左边路径与下标），读出当前值，经**运算符**求值——内建算术或 trait 重载，
带 `Add` 实现的泛型 `T` 与内建类型表现一致——再写回结果。在
`type sendable mutable` 字段上每一步各自取短锁或原子访问（见[对象锁](#对象锁)），
所以 `x.f += 1` 跨线程**不**原子；跨线程原子递增属于 `AtomicCell.update_and_get` 或 `Mutex`。

#### 运算符优先级

运算符优先级从高到低：

1. 后缀：调用 `()`、下标 `[]`、成员访问 `.`、限定路径 `Type(Trait)`、泛型方法后缀
2. 前缀 / 控制流：一元 `-`、`~`、解引用 `*`、raw 取址 `&`、`&mutable`；`if`、`while`、`for`、`when`
3. 乘除：`*`、`/`、`%`
4. 加减：`+`、`-`
5. 移位：`<<`、`>>`
6. 按位与：`&`
7. 按位异或：`^`
8. 按位或：`|`
9. 比较：`==`、`!=`、`<`、`>`、`<=`、`>=`
10. 范围：`..`、`..<`、`<..`、`<..<`（闭）；`...`、`...<`、`<...`（开）
11. 模式测试：`is`、`is not`
12. 逻辑非：`not`
13. 流程层，从紧到松：`and then`，然后 `or else` / `or return`
14. 逻辑层，从紧到松：`and`，然后 `or`

第 13 与第 14 行是**两个独立的层**，不是一条阶梯上的四档。它们上面各行才是普通阶梯；
这两层彼此同级，一次只进一层。层内优先级如上——但**两层之间不隐式混用**。跨层必须加括号：

第 1–12 行的一切——包括**比较**——都比这两层更紧，与 Swift 中比较比 `??`/流程运算符更紧一致。
因此 `a == b or else c` 按 `(a == b) or else c` 分组，绝不是 `a == (b or else c)`；
`opt or else x == y` 按 `opt or else (x == y)` 分组。

- `f() and then as v in g(v) or else h()` 按 `(f() and then as v in g(v)) or else h()` 分组——流程接流程，合法。
- `a or b and c` 按 `a or (b and c)` 分组——逻辑接逻辑，合法。
- `a and (b or else c)` —— 合法，语义就是它。
- `(a and b) or else c` —— 合法，语义是另一回事。
- `a and b or else c` —— **拒绝**。它看起来像 `(a and b) or else c`，实际会按 `a and (b or else c)` 分组；两者都不是这行字面读起来的意思，所以用括号说清楚。
- `opt and then as v in v == 1 and false` —— **拒绝**，同理。

```koral
let opt: Option[Int] = Option[Int].Some(1);
let ready: Bool = true;

// 流程层内先 `and then`，再 `or else`：
let inLayer = opt and then as v in v * 2 or else 0;   // 84

// 变换体才是 `and` 的预期作用域——显式写出来：
let good = opt and then as v in (v == 1 and false);   // Some(false)

// 逻辑 `and` 的右侧要的是流程结果——显式写出来：
let good2 = ready and (opt and then as v in v > 0 or else false);   // true
```

这与有 `??` 的语言里 `??` 的规矩一致：值兜底是一个清晰的中间层，不加括号就不与布尔逻辑拼接。注意 `(ready and opt)` 并不是混用写法的修法：`and` 两侧都要求 `Bool`，流程结果必须先归约成 `Bool`（如 `good2`）才能参与逻辑 `and`。

#### 求值顺序

Koral **严格从左到右**求值。语法里操作数的书写顺序就是求值顺序——不存在任何未指定顺序：

1. **调用实参**（含限定调用与构造实参）从左到右：`f(trace(1), trace(2))` 先运行 `trace(1)` 再运行 `trace(2)`。
2. **二元操作数**（`+`、`*`、`==`、`&`、`<<` 等）从左到右：`trace(1) + trace(2)` 先求值左侧。
3. **`and` / `or`** 先求值左操作数，并**短路**：左侧已决定结果时跳过右侧。
4. **`and then` / `or else` / `or return`** 先求值左操作数，并短路：左侧为 `None`/`Error`（`and then`）或 `Some`/`Ok`（`or else`）时跳过变换体/默认值。
5. **集合与字典字面量**按源码顺序求值；字典项先求键再求值。
6. **构造字段**按源码顺序求值，而非声明顺序。
7. **赋值**先求左边路径与下标，再求右边，最后写入——所有类型同一顺序。`xs[f()] = g()` 先运行 `f()`，再运行 `g()`，最后写槽位。

```koral
// trace 打印自己的参数；打印顺序即求值顺序。
let a = trace(1) + trace(2);          // [1][2]
let b = sum(trace(3), trace(4));      // [3][4]
let c = [trace(5), trace(6)];         // [5][6]
let d = [trace(7): trace(8)];         // [7][8] -- 先键后值
let p = Point(trace(9), trace(10));   // [9][10]

// 短路：左侧已决定结果时右侧从不运行。
let e = traceb(false) and traceb(true);   // 只有 [false 侧]
let f = opt_none and then as v in trace(v);   // 跳过变换体
let g = opt_some or else trace(12);       // 跳过默认值
```

### 函数

函数是完成特定任务的独立代码块。

#### 定义

函数用 `let` 关键字定义。函数名后跟 `()` 表示参数，圆括号后以 `:` 引出返回类型。具名函数和方法必须显式写出返回类型。

`=` 右侧必须是表达式，该表达式的值就是函数的返回值。

```koral
let f1(): Int = 1;
let f2(a: Int): Int = a + 1;
let f3(a: Int): Int = a + 1;
```

#### 调用

使用 `()` 语法调用函数：

```koral
let a = f1();
let b = f2(1);
```

#### 参数

参数是函数执行时可以接收的数据。Koral 支持两种参数：位置参数和命名参数。

##### 位置参数

声明为 `name: Type`（不带 `=`）。位置参数必须**按位置**传入——绝不能带标签。

```koral
let add(x: Int, y: Int): Int = x + y;
let a = add(1, 2); // a == 3
```

##### 命名参数

声明为 `name: Type =`——`=` 就是命名标记。`=` 后不写默认值表示调用方必须传入；`name: Type = 123` 则带默认值。命名参数必须**带标签**（`name = value`）调用。

```koral
let connect(host: String, port: Int =): Void = {};
connect("localhost", port = 8080);
```

##### 混合规则

参数的声明形态唯一决定调用形态，没有例外：

- 声明为命名（`name: Type =`）→ 调用时**必须**带标签（`name = value`）。
- 声明为位置（`name: Type`）→ 调用时**绝不能**带标签。

不存在「可选命名」的中间态：声明二选一，调用形态就唯一确定。声明中位置参数必须排在命名参数之前；调用时先按位置匹配位置参数，再按标签匹配命名参数。

```koral
type Window(title: String, width: Int =, height: Int =);

// 位置填 'title'；命名的 'width' / 'height' 必须带标签
let w = Window("hello", width = 900, height = 600);
// Window("hello", 900, 600)                        // error: 'width' 必须带标签
// Window("hello", width = 900, height = 600, title = "x")  // error: 'title' 是位置参数
```

##### 默认值

只有命名参数（带 `=` 标记的）可以有默认值。默认值在 `=` 之后以字面量给出：

```koral
type Config(
    count: Int = 42,
    name: String = "hello",
    enabled: Bool = true,
    ratio: Float64 = 3.14,
    ch: Rune = 'A',
    items: List[Int] = [],
    flags: Dict[String, Int] = [],
    span: Range[Int] = ...,
);
```

支持的默认值字面量：

| 种类 | 示例 |
|------|----------|
| 整数 | `0`、`42` |
| 浮点 | `3.14`、`0.0` |
| 布尔 | `true`、`false` |
| 字符串 | `"hello"` |
| Rune | `'A'` |
| 空集合 | `[]`（List、Set 或 Dict，由类型上下文推断） |
| 空范围 | `...`（解析为 `Range[T].Full()`） |
| 空指针 | `null`（加入 `*T` / `*mutable T`） |

默认值类型必须与参数类型匹配。例如 `name: String = 42` 会报错。

可变参数使用 `mutable` 关键字：

```koral
let increment(mutable x: Int): Int = { x += 1; return x };
```

对普通参数而言，`mutable` 只是让函数体内的局部绑定可写。它不是函数签名的一部分，不改变函数类型，在检查 trait/given 方法兼容性时会被忽略。

##### 构造器调用

结构体、枚举和函数调用遵循同样的位置/命名规则——声明决定形态，调用照做：

```koral
type Shape {
    Circle(radius: Float64),            // 位置变体参数
    Line(start: Point =, end: Point =),    // 命名变体参数
};

// 位置参数：按位置传入，绝不能带标签
let s1 = Shape.Circle(1.0);

// 命名参数：必须带标签（实参顺序可以重排）
let s2 = Shape.Line(end = Point(1, 1), start = Point(0, 0));
// Shape.Line(Point(0, 0), Point(1, 1))   // error: 'start' 必须带标签
```

模式匹配的解构遵循完全相同的标签规则：声明为命名的字段必须带标签匹配，声明为位置的字段绝不能带标签。

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start = p, end = e) then println(p.x),
};

if b is Button(w, height = _, label = l) then println(l);
// Button 的 `width` 是位置字段，`height` / `label` 是命名字段
```

#### 函数类型

在 Koral 中，函数也是类型。函数类型用 `(T1, T2, ...) -> R` 语法声明，其中 `T1, T2, ...` 是参数类型，`R` 是返回类型。

```koral
let square(x: Int): Int = x * x;        // (Int) -> Int
let f: (Int) -> Int = square;
let a = f(2);                         // a == 4
```

也可以把函数类型用作参数类型或返回类型：

```koral
let hello(): Void = println("Hello, world!");
let run(f: () -> Void): Void = f();
let toRun(): (() -> Void) -> Void = run;

let main(): Void = toRun()(hello);
```

### Lambda 与闭包

#### Lambda 表达式

Lambda 表达式与函数定义非常相似，只是把 `=` 换成 `=>`，且没有函数名和 `let` 关键字。

```koral
let f1(x: Int): Int = x + 1;            // (Int) -> Int
let f2 = (x: Int): Int => x + 1;        // (Int) -> Int
let a = f1(1) + f2(1);                // a == 4
```

当 lambda 的类型可以从上下文推断时，可以省略参数类型和返回类型：

```koral
let f: (Int) -> Int = (x) => x + 1;
```

Lambda 支持多种形式：

```koral
() => 42;                           // 无参数
(x) => x * 2;                      // 单参数，类型推断
(x: Int) => x * 2;                  // 单参数带类型
(x, y) => x + y;                   // 多参数，类型推断
(x: Int, y: Int): Int => x + y;       // 完整类型标注
(x) => { let y = x * 2; return y + 1; };  // 块体
```

#### 闭包

Lambda 表达式可以从周围作用域捕获变量，这被称为闭包。

```koral
let make_adder(base: Int): (Int) -> Int = {
    return (x) => base + x;
};

let add10 = make_adder(10);
let result = add10(32);  // result == 42
```

##### 捕获规则

闭包捕获**只有拷贝语义**。闭包拥有自己的捕获，因此可逃逸的闭包绝不会指向它不拥有的存储。

- 不可变绑定（`let`）按拷贝捕获。
- `type mutable` 对象按共享句柄捕获：闭包与外部观察到的是同一个对象。
- `let mutable` 绑定**不能**被捕获。否则闭包就能修改它不拥有的存储，因此编译器会拒绝。

要把可变状态带进闭包，请放进 `Cell`——一个共享的 `type mutable` 盒子——然后捕获这个 cell：

```koral
let make_counter(): () -> Int = {
    let counter = Cell(0);              // 共享可变状态
    return () => {
        counter.value = counter.value + 1;
        return counter.value;
    };
};

let c = make_counter();
c();  // 1
c();  // 2
```

同样的规则适用于任何 `type mutable` 对象——捕获它即共享它：

```koral
let xs = [10, 20];
let add = () => { xs.push(30) };   // ok: `xs` 是共享句柄
```

#### 柯里化

闭包支持柯里化：

```koral
let add: (Int) -> (Int) -> Int = (x) => (y) => x + y;

let add10 = add(10);
let result = add10(32);  // result == 42
let sum = add(20)(22);   // sum == 42
```

## 2. 控制流

### 条件表达式

选择结构用于判断给定条件并控制程序流程。

在 Koral 中，选择结构使用 `if` 语法。`if` 后跟判断条件。条件为 `true` 时执行 `then` 分支，为 `false` 时执行 `else` 分支。`if` 始终是表达式。同时有 `then` 和 `else` 时产生值；没有 `else` 时，单分支 `if` 产生 `Void`。

```koral
let main(): Void = if 1 == 1 then println("yes") else println("no");
```

`if` 始终是表达式。`then` 与 `else` 都写时它产生一个值；不写 `else` 时，单分支 `if` 产生 `Void`。两个分支后都必须是表达式——或一个裸控制转移（见下文）。

```koral
let main(): Void = println(if 1 == 1 then "yes" else "no");
```

由于 `if` 本身也是表达式，`else` 后自然可以再跟一个 `if` 表达式形成链式条件。

```koral
let x = 0;
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less";
```

不需要处理 `else` 分支时可以省略它。单分支形式仍是表达式，但产生 `Void`：它的块分支默认为 `Void`。

```koral
let main(): Void = if 1 == 1 then println("yes");
```

当带 `else` 的 `if` 使用块分支时，该块的尾表达式就是该分支的值。

```koral
let label = if score >= 90 then {
    if score == 100 then {
        "perfect"
    } else {
        "A"
    }
} else {
    "other"
};
```

#### 分支体与控制转移

分支体——`then` / `else` 之后的槽位——是一个表达式，或者三个控制转移之一的**裸写法**：`return <值>?`、`break`、`continue`。裸控制转移是你本来要写的单跳块的语法糖：`then return x` 就是 `then { return x; }`。该分支类型为 `Never`，与一个不会落穿的块分支完全一样，照常与值分支汇合。同一规则覆盖所有分支体槽位：`if` 的两个分支、`while` 与 `for` 的循环体、`when` 的 arm。

```koral
let classify(x: Int): String = {
    if x > 0 then return "pos" else return "non-pos";
};

let findFirst(xs: List[Int]): Int = {
    for x in xs then return x;
    return 0 - 1;
};
```

控制转移不是表达式，只在分支体里合法——`let x = return 3;`、`f(break)` 是语法错误。`return` 带不带值的规则与 `return <值>;` 语句一致：其后能起表达式就取值。分支体自身不带 `;`；`if c then return 3;` 里那个 `;` 终结的是外层语句。

### 循环

#### while 表达式

在 Koral 中，循环结构使用 `while` 语法。`while` 后跟判断条件。条件为 `true` 时执行后面的 body，然后控制回到条件进行下一次迭代。`while` 是产生 `Void` 的表达式。

```koral
let mutable i = 0;
while i < 10 then {
    println(i);
    i += 1;
};
```

#### for 循环

`for` 循环用于遍历任何实现了迭代器接口的对象（如列表、映射、集合、范围等）。

每次迭代中，迭代器产出的下一个值被绑定到循环绑定上，然后执行 `then` 后的语句 body。循环绑定位置接受**全模式**——与 `when` 分支完全同一套 pattern 语法——但**必须覆盖每一个元素值**：循环没法跳过模式拒绝的元素，所以留下任何未匹配值的模式在编译期就报
`For binding cannot fail; use 'when' to match`。覆盖与否由穷尽性检查器判定，不看形状：单 case 枚举的 `.Only(v)`、双 case 枚举的 `.A(x) or .B(x)` 都收，尽管 `or` 的单侧、多 case 枚举的解构各自都会被拒。`for` 是产生 `Void` 的表达式。

```koral
let nums: List[Int] = [10, 20, 30];
for x in nums then {
    println(x);
};

for i in 0..5 then {
    println(i);
};

let loop_value = while false then {
    println("unreachable");
};

let for_value = for x in nums then {
    println(x);
};
```

绑定就是模式：`_`、`x`、`mutable x`、结构体解构、元组解构、嵌套解构都可以，
只要不可反驳：

```koral
let pairs: List[Pair[Int, Int]] = [Pair(1, 2), Pair(3, 4)];

for (left, right) in pairs then {
    println((left + right).to_string());
};

for Point(x, y, z) in points then {
    println(x);
};
```

`for` 也可以带 `where` 守卫，位置在 iterable 之后、`then` 之前——与 `when`
分支里「模式之后、`then` 之前」是同一个槽位。守卫为假就跳过该元素，进入下一轮
迭代（不结束循环）。模式绑定在守卫里可见：

```koral
for p in points where p.x > 0 then {
    println(p.x);
};
```

#### break 和 continue

- `break`：退出最内层的 `while` / `for` 循环。
- `continue`：跳过当前迭代。它与 `break` 一样绑定到循环。

```koral
let mutable i = 0;
while true then {
    if i > 20 then {
        break;
    };
    if i % 2 == 0 then { i += 1; continue; };
    println(i);
    i += 1;
};
```

### 早退出：`return`

- `return` 带值（或 `Void`）离开所在函数。
- 裸 `break` 退出最近的 `while` / `for` 循环。

三者都可以在分支体里裸写——`if c then return v`、`when x in { .None() then break, ... }`——这是单跳块的语法糖（见 [分支体与控制转移](#分支体与控制转移)）。

`break` 始终绑定到最内层的循环。分支不会拦截它：`if`、`when` 的分支体、`or else` 的默认值、`and then` 的变换体，以及作为表达式使用的 `if`，都只是位于 `break` 与它的循环之间，不改变绑定目标。函数或 lambda 边界会拦截这两个语句——闭包里的 `break` 或 `continue` 没有可绑定的循环，是错误。

### 用 `defer` 做清理

`defer` 语句声明一个在当前块作用域退出时执行的清理表达式。无论作用域是正常退出，还是经由 `return`、`break`、`continue` 早退，延迟表达式都会执行。

当执行走上 `Never` 终止路径（例如 `panic()`、`abort()` 或 `exit()`）并立即终止程序时，不保证执行作用域内的 `defer`。

`defer` 后跟一个表达式，其返回值被丢弃。

```koral
let main(): Void = {
    println("start");
    defer println("cleanup");
    println("work");
    // 输出：start, work, cleanup
};
```

同一作用域内多条 `defer` 按声明的逆序执行（LIFO）：

```koral
let main(): Void = {
    defer println("first");
    defer println("second");
    defer println("third");
    // 输出：third, second, first
};
```

`defer` 绑定到声明它的块作用域，而不是函数作用域。在循环中，`defer` 在每次迭代结束时执行：

```koral
let mutable i = 0;
while i < 3 then {
    i += 1;
    defer println("cleanup");
    println(i);
    // 每次迭代输出：i 的值, cleanup
};
```

延迟表达式也可以是块表达式：

```koral
defer {
    println("cleaning up");
    close(handle);
};
```

#### 限制

- `defer` 表达式内不允许 `return`、`break`、`continue`。
- `defer` 表达式内不允许嵌套 `defer`。
- `defer` 不是异常式的栈展开机制；在 `panic/abort/exit` 的 `Never` 终止路径上不保证执行。
- 这些限制不跨越 Lambda 边界——Lambda 有自己独立的作用域。

### Option 与 Result 流程

Koral 为 `Option` 和 `Result` 类型提供三个特殊操作符：

- `or else`：值合并。左侧为 `None` 或 `Error` 时返回右侧默认值。
- `and then`：可选链 / 值变换。左侧为 `Some` 或 `Ok` 时施加右侧变换。结果恒留在同一种 `Option` / `Result` 里：变换体自身的返回类型已经是那一种时，它的值**就是**结果（折叠掉一次包装）；其余情形包一层。泛型变换的类型参数视为不透明，因此总是包一层——于是 `map[U: Any](f: (T) -> U): Option[U]` 对每个 `U`（含 `U = Option[V]`）都给出 `Option[U]`。
- `or return`：早返回传播语法糖。它解包 `Some` / `Ok`，遇到 `None` / `Error` 则从所在函数返回。

#### 给被解包的值命名

没有隐式名字。两种写法让变换体拿到被解包的值，区别只在于需不需要名字：

- **链式** —— `and then .成员(...)`：接收者就是被解包的值，所以
  `config and then .window.title` 读作 `config?.window.title`。这里的前导点一律是
  被解包值的成员（不再是 implicit member 构造）。链式是完整后缀链：`.f(x).g`、`.f()[0]`。
- **绑定** —— `and then as v in 体`：为 `体` 命名被解包的值。`体` 是**单个 layer 操作数**，
  写在它后面的 `or else` 属于外层链：`x and then as v in v * 2 or else 0` 是
  `(x and then as v in v * 2) or else 0`。

链式是绑定的语法糖——`x and then .f()` 与 `x and then as v in v.f()` 类型与取值完全相同
——需要名字时随时可以展开。

`or else` 给的是兜底值，通常不需要名字。要查看错误时再绑定：

- `or else as e in 体` —— `e` 是 `Error` 值。**仅 `Result`**：`None` 没有载荷，
  所以 `Option` 上写绑定形式是错误。
- 兜底值的类型是左操作数的**载荷**类型：`x Option[T]` 时 `x or else d` 里的 `d` 是 `T`，
  不是 `Option[T]`。

其优先级与解析器一致：流程层内 `and then` 比 `or else` / `or return` 更紧。流程层整体不与逻辑 `and` / `or` 隐式混用，跨层必须加括号——见[运算符优先级](#运算符优先级)。

```koral
let opt = Option[Int].Some(42);
let val = opt or else 0;           // 42（因为 opt 是 Some）

let none = Option[Int].None();
let val2 = none or else 0;         // 0（因为 none 是 None）

let mapped = opt and then as v in v * 2;  // Some(84)

// 变换体返回 Option，它的值就是结果——折叠掉一次包装，而不是再套一层。
// 变换体返回裸值时才包一层。
let half(x: Int): Option[Int] =
    if x % 2 == 0 then Option[Int].Some(x / 2) else Option[Int].None();
let chained = opt and then as v in half(v);  // Some(21) —— 类型是 Option[Int]

// 链式是绑定的语法糖：接收者就是被解包的值。
type Config(window: Window);
type Window(title: String);
let cfg = Option[Config].Some(Config(Window("untitled")));
let title = cfg and then .window.title or else "none";   // "untitled"

// 为 Result 的错误命名。
let parsed = Result[String].Error("bad input");
let shown = parsed or else as e in e.message();          // "bad input"

let load_port(path: String): Result[Int] = {
    let text = read_text_file(path) or return;
    return Int.parse(text);
};
```

`or return` 等价于固定的 `or else` 早返回模式：

- 对 `Result`：`expr or return` 等价于 `expr or else as e in { return .Error(e); }`
- 对 `Option`：`expr or return` 等价于 `expr or else { return .None(); }`

它必须用在返回种类与被传播值匹配的函数内：

- `Result` 传播要求所在函数返回 `Result`
- `Option` 传播要求所在函数返回 `Option`

## 3. 自定义类型

Koral 提供强大的类型系统，允许你定义自己的数据结构。用 `type` 关键字定义浅层不可变的 nominal，用 `type mutable` 定义共享对象。

### `type`：浅层不可变的 Nominal

`type` 声明引入字段全部不可变的 nominal 类型。`type` 的值**没有 identity**，布局由编译器决定——内联、隐藏间接层或共享 backing 均可。不承诺值语义：拷贝可以共享存储，正因该类型浅层不可变，这种共享不可观察。它**不能实现 `Drop`**：清理是合成的字段释放，只有 `type mutable` 才携带析构——见 [`Drop`](#drop)。

结构体字段可以是位置字段或命名字段。位置字段写作 `name: Type`；命名字段带 `=` 标记——`width: Int =`（调用方必须传入）或 `height: Int = 600`（带默认值）。

#### 定义

```koral
type Empty();
type Point(x: Int, y: Int);

type Config(
    name: String,               // 位置字段
    width: Int =,               // 命名字段（无默认值）
    height: Int = 600,         // 带默认值的命名字段
    title: String = "Untitled" // 带默认值的命名字段
);
```

规则：

- 位置字段必须排在命名字段之前。
- 只有命名字段可以有默认值。
- 默认值必须是字面量：整数、浮点、布尔、字符串、rune、`[]`（空集合）或 `...`（空范围）。
- `type` 不能声明 `mutable` 字段，自身也不能声明为 `mutable`（`type mutable` 是另一种声明形态）。

#### 构造

使用 `()` 语法调用构造器：

```koral
let a: Point = Point(0, 0);

// 命名字段带标签调用；位置字段不带标签
let c1: Config = Config("main", width = 800);
let c2: Config = Config("main", width = 800, height = 900, title = "App");
// height 与 title 使用默认值：600 与 "Untitled"
```

#### 字段访问

使用 `.` 语法访问成员变量。`type` 的字段只读：

```koral
type Point(x: Int, y: Int);

let main(): Void = {
    let a = Point(64, 128);
    println(a.x);  // 64
    println(a.y);  // 128
    // a.x = 2;    // error: `type` 字段不可变
};
```

### `type mutable`：共享可变对象

`type mutable` 声明引入带 identity 的共享对象。赋值与传参交出的是同一个对象的句柄；字段默认不可变，只有显式声明为 `mutable` 的字段才能原地修改。

#### 可变字段

```koral
type mutable Counter(mutable value: Int, id: UInt);

let main(): Void = {
    let c = Counter(0, 1);
    c.value = 5;  // ok，因为 Counter 是 `type mutable` 且 `value` 是 mutable 字段
    // c.id = 2;  // error: `id` 不是 mutable 字段
};
```

成员变量的可变性由类型定义决定，而不是由绑定决定：绑定到 `type mutable` 对象的只读绑定，仍可修改该对象的 `mutable` 字段。

```koral
type mutable Counter(mutable value: Int);

let c = Counter(0);
c.value = 1;      // ok: 共享对象，绑定本身没有被重新赋值
```

独立副本必须显式获得：容器和其他共享对象不使用写时复制。

```koral
let a = [1, 2];
let b = a.clone();   // 独立副本
b.push(3);
// a 仍是 [1, 2]
```

### 枚举

枚举允许你定义可以是若干不同变体之一的类型，每个变体可以携带不同类型的数据。

```koral
type Shape {
    Circle(radius: Float64),
    Rectangle(width: Float64, height: Float64),
};

let s = Shape.Circle(1.0);
```

枚举声明不能带 `mutable`——枚举与 `type` 一样是浅层不可变的。

#### 使用枚举值

通过模式匹配从枚举变体中提取数据（见[模式匹配](#4-模式匹配)）：

```koral
let area = when s in {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
};
```

#### 隐式成员表达式

隐式成员表达式使用 `.memberName(...)` 语法。

规则：

- 只有在上下文已知期望类型时才有效。
- 可以构造枚举变体或调用静态方法。
- 必须带圆括号；裸 `.Name` 不是合法的隐式成员表达式。
- 编译器无法推断期望类型时，表达式会被拒绝。

设计说明：

- 枚举变体在语义上仍是数据构造器，但 Koral 给隐式成员表达式统一了显式构造或调用的表层形态。
- 因此在表达式位置，零字段枚举变体仍写作 `.Name()`，而不是省略括号写成裸 `.Name`。
- 模式语法同样要求括号，零字段枚举变体模式必须写作 `.Name()`。

```koral
// 枚举构造——省略 Option[Int] 前缀
let a: Option[Int] = .Some(42);
let b: Option[Int] = .None();

// 函数实参中
let process(opt: Option[Int]): Void = when opt in {
    .Some(v) then println(v.to_string()),
    .None() then println("none"),
};
process(.Some(10));

// 赋值中
let mutable x: Option[Int] = .None();
x = .Some(100);

// 条件表达式分支中
let c: Option[Int] = if true then .Some(1) else .None();

// 静态方法调用——省略 List[Int] 前缀
let list: List[Int] = .new();
let list2: List[Int] = .with_capacity(10);
```

### 类型别名

类型别名允许为已有类型定义新名字，提升代码可读性。使用 `type AliasName = TargetType` 语法。

```koral
type Meters = Int;
type Coord = Point;
type IntList = List[Int];
```

类型别名在编译期被完全消除——别名与其目标类型完全等价：

```koral
type Meters = Int;

let distance: Meters = 100;
let add_meters(a: Meters, b: Meters): Meters = a + b;
let result = add_meters(distance, 50);  // result == 150
```

别名可以链式使用：

```koral
type Meters = Int;
type Distance = Meters;  // Distance 最终解析为 Int
```

类型别名支持访问修饰符：

```koral
public type Meters = Int;       // 公开
private type InternalId = Int;  // 仅文件内
```

限制：

- 类型别名支持泛型参数（如 `type OrdList[T: Ord] = List[T];`）：实例化点检查元数与约束，目标类型在实例化时按绑定展开。直接自引用是拼写错误；展开环报 `Circular type alias`。泛型别名不带类型参数不指称任何类型。类型别名在语义检查阶段被完全消除。
- 不允许循环引用（如 `type A = A`）。
- 类型别名必须以大写字母开头。
- 类型别名不能声明为 `mutable`——可变性属于 nominal 声明，而不属于别名。

### 泛型

泛型允许你编写适用于多种类型的代码，提升代码复用性。

#### 泛型数据类型

泛型数据类型用 `TypeName[T: Constraint]` 语法定义泛型参数：

```koral
type Pair[T1: Any, T2: Any](left: T1, right: T2);
```

构造泛型数据类型时，在泛型参数位置传入实际类型：

```koral
let a1 = Pair[Int, Int](1, 2);
let a2 = Pair[Bool, String](true, "hello");
```

上下文类型明确时，可以省略泛型类型参数：

```koral
let a1 = Pair(1, 2);           // 推断为 Pair[Int, Int]
let a2 = Pair(true, "hello");  // 推断为 Pair[Bool, String]
```

**没有元组 / pair 字面量**。`(1, 2)` 不是表达式——它是**解构**形式，只出现在把东西拆开的地方
（`let (a, b) = p;`，以及 `when` / `is` 里的模式）。构造 `Pair` 用它自己的构造器：

```koral
let p1 = Pair(1, 2);
let p2 = Pair(true, "hello");
let (a, b) = p1;              // 解构，不是字面量
```

#### 泛型函数

泛型函数把类型参数写在函数名之后：

```koral
let identity[T: Any](x: T): T = x;

println(identity(42));       // 42
println(identity("hello"));  // hello
```

#### 泛型约束

泛型参数**必须**给出 Trait 约束以限定可接受的类型。不需要 trait 约束的参数写成 `[T: Any]`
——`Any` 是「无约束」的写法，它本身不是一种约束：

```koral
let max_val[T: Ord](a: T, b: T): T = if a > b then a else b;
let contains[T: Eq](list: List[T], value: T): Bool = list.contains(value);
```

多个约束用 `and` 连接：

```koral
let describe[T: ToString and Hash](value: T): String = value.to_string();
```

约束也可以使用泛型 trait 形式（例如 `Iterator[T]`），以及三个**类型种类约束**。类型种类约束是关键字而不是 trait：没有任何声明能实现它，是否满足由编译器从类型自身的声明判定。

- `T: mutable` —— 主体必须声明为 `type mutable`。弱引用要求的就是它（`x as ?T` / `?expr` 亦然）。
- `T: foreign` —— 主体的表示由 Koral 的布局自由之外决定，可以跨 FFI：内置标量、`*` / `*mutable` 指针（指向集合内类型，或 `Void`——C 的 `void*`）或 `type foreign` 声明。这是**封闭集合**；Koral `type` 不在其中，因为它的布局由编译器选——std 的 `Rune` 也不在：它和 `String` 一样是 std 名义类型，表示由编译器做主。`List.borrow_ptr` / `borrow_mut_ptr` 要求的就是它。
- `T: sendable` —— 主体可以跨线程边界：声明了 `sendable`（safe 或 `unsafe` 形态），或按派生规则成立——标量天然满足，复合类型递推（见[并发](#并发)）。共享对象字段、全局量与通道要求的就是它。

```koral
let consume[I: Iterator[Int]](iter: I): Void = {};
let read_bytes[T: foreign](buf: List[T]): *T = buf.borrow_ptr();
let drain[T: Reader and sendable](source: T): Int = source.read();
let bump[T: mutable and sendable](c: T): T = c;
let pass[T: foreign and sendable](x: T): T = x;
```

泛型参数把自己的约束带进调用：在 `f[T: Any]` 里调用要求 `mutable` 约束的函数会被拒绝，因为裸 `T` 并未声明为 `mutable`；在 `g[T: mutable]` 里同样的调用可以通过。`sendable` 约束同样严格：裸 `T: Any` 不会满足内层的 `U: sendable` 槽位，参数必须自己声明 `T: sendable`。

带约束的扩展块只在约束真正成立的类型上贡献成员。给定

```koral
given[T: Add[T] and Zero, R: Iterator[T]] LazyView[T, R] {
    public sum(self): T = { ... };
};
```

`sum` 只是那些 `T` 满足 `Add[T] and Zero` 的 `LazyView` 的成员。`Pair[A, B]` 两者都不满足，因此以它为元素的管线上没有 `sum`，在那里调用它是类型错误。仍未确定的约束不算拒绝：对 `given[T: Any, R: Iterator[T]] FilterIterator[T, R]: Iterator[T]` 这样的泛型实现，`T` 仍可能变成 `Int`，所以 `sum` 依旧可用，并在每个调用点再次检查。

#### 泛型方法

`given` 块也可以定义泛型方法：

```koral
given[T: Any] Option[T] {
    public map[U: Any](self, f: (T) -> U): Option[U] = self and then as v in f(v);
};
```

#### `Never` 类型限制

`Never` 类型表示永不返回的计算（如无限循环、panic）。它是最底类型。

- `Never` 不能用作结构体字段类型。
- `Never` 不能用作枚举 payload 类型。
- `Never` 不能用作函数参数类型。
- `Never` 可以用作返回类型，表示函数永不返回。

### `Self` 类型

`Self` 是内建类型关键字，在 `trait` 定义、`given` 块及其方法签名中指代实现类型。它不是独立的类型别名——由编译器解析为正在实现 trait 的具体类型。

- 在 `trait` 定义内部，`Self` 表示未来的实现类型。
- 在 `given Type: Trait` 块内部，`Self` 等价于 `Type`。
- `Self` 可以出现在 trait/given 上下文中的方法参数类型、返回类型和字段类型里。

```koral
trait Eq {
    equals(self, other: Self): Bool;
};

type Point(x: Int, y: Int);

given Point: Eq {
    // 这里 Self 解析为 Point，所以 `other: Self` 与 `other: Point` 相同。
    equals(self, other: Point): Bool = self.x == other.x and self.y == other.y;
};
```

### 内存与资源

Koral 通过声明处类型语义与编译器管理的布局，提供高效且安全的内存管理。

#### 内存模型

- **`type`**（浅层不可变）：没有 identity，也不承诺值语义。编译器可以使用栈槽、寄存器、内联存储、隐藏堆块或引用计数——任何它能证明正确的方式——因为它引入的共享无法被观察。它的清理是合成的字段释放；不能实现 `Drop`。
- **`type mutable`**（共享对象）：identity 是语义的一部分。赋值与传参共享同一个对象。只有显式声明为 `mutable` 的字段才能原地修改。
- **`type foreign`**（可变值语义）：C 布局的值。赋值与传参按值拷贝；拷贝经 `let mutable`、`mutable` 参数、`*mutable T` 链接就地修改，`self` 是普通拷贝——没有可变 self。字段是恒可写的 C 槽位，内容限于能过 FFI 边界的类型（见[外部互操作](#6-外部互操作)）。
- **raw pointer**：指针类型是 `*T` / `*mutable T`；`&` / `&mutable` 是把它们构造出来的取址操作符，且只从可取地址的存储形成。它们是面向 FFI 的低层内存访问，仍受地址稳定性与布局稳定性约束（见[外部互操作](#6-外部互操作)）。
- **跨线程共享同样是声明处性质。** 内存模型多一条并发轴：哪些类型能跨线程共享、由谁保证它们的安全，由 `sendable` 族在声明处决定。见[并发](#并发)。
- **引用计数是实现细节。** 编译器可能在两种形态内部使用 ARC 与隐藏存储。语言契约本身见本手册的「核心理念：`type` / `type mutable`」一节。

#### `Drop`

需要清理步骤的类型声明 `type mutable` 并实现 `Drop` trait：

```koral
trait Drop {
    drop(self): Void;
};
```

`Drop.drop` 是仅由编译器调用的析构入口，运行在 finalization 上下文中。它不能作为普通用户方法调用。**只有 `type mutable` 才能实现 `Drop`**：析构在最后一个持有句柄消亡时只跑一次，属于共享对象层。`type` 承诺没有 identity——同字段的值可以互换——析构会经由 drop 计数把构造身份泄漏出来。

`type` 的清理是**合成的字段释放**——各字段自身的 release 把内层受管值推到最终释放，因此包在 `type mutable` 字段里的资源照样随合成释放归还，无需用户析构（Swift struct-around-class 的形态，例如 `type File(inner: FileBox)`）。

由于析构对每个对象只跑一次，`Drop` 类型的共享是**可观察的**——见[内存模型](#内存模型)。这正是 `Drop` 保留给 `type mutable` 的原因。

**`self` 不许逃出 `drop` 体。** 对象正在被销毁；让它跑出去等于复活垂死的值，或把字段从析构过程里搬走。在 `drop` 里，`self` **只能作为接收者**出现：字段读写（`self.x`、`self.x = v`）或方法调用（`self.close()`）。它不能被返回、绑定到新名字、存进字段/集合/全局、作为普通实参传给函数，也不能被 lambda 捕获。

```koral
trait Drop {
    drop(self): Void;
};

type mutable File(mutable fd: Int);

given File: Drop {
    drop(self): Void = {
        let n = self.fd;   // 可以：字段读
        self.fd = n;       // 可以：字段写（字段是 `mutable`）
        // stash(self);    // 错误：`self` 逃出析构
    };
};
```

`drop` 里对 `self` 的方法调用与字段读写一样可用。析构把 `self` 以指针传入，而类型系统
仍称它为 `Self`，所以调用点会解引用。普通方法按值接收，也就是会 retain 一次：对象在自身
析构期间是不可复活的，这次 retain 与方法结束时的 release 都是空操作，析构不会被重新进入。

```koral
given File {
    close(self): Int = {
        return self.fd;
    };
};

given File: Drop {
    drop(self): Void = {
        println("closed: \(self.close())");
    };
};
```


#### `clone()`

共享对象从不隐式复制。确实需要独立副本时，用 `clone()` 显式索取：

```koral
trait Clone {
    clone(self): Self;
};
```

`List`、`Set`、`Dict`、`Deque` 实现的 `clone()` 是**浅**拷贝：容器本身是新的，元素只拷贝一层，因此嵌套的 `type mutable` 元素仍然共享。

```koral
let a = [1, 2];
let b = a.clone();
b.push(3);
// a 仍是 [1, 2]
```

#### 弱引用

弱引用不维持被引用对象的存活。写作 `?T`，只对满足 `mutable` 约束的类型有效。

用 `x as ?T` 构造弱引用（句柄包装，不是位级重解释）。用 `?expr` 升级：结果是
`Option[T]`——对象存活时为 `.Some(v)`，已死时为 `.None()`。

```koral
type mutable Node(mutable value: Int);

let node = Node(42);
let weak = node as ?Node;               // ?Node
let value = when ?weak in {
    .Some(v) then v.value,              // v 是 Node，仅在存活时
    .None() then 0,
};
```

**弱引用是句柄，不是值。** 在升级之前它不携带被引用对象的任何字段、
分支或载荷，因此一切试探或利用被引用对象**形状**的操作，对 `?T` 一律拒绝：

- 成员访问，读或写 —— `w.value`、`w.value = 1`
- 方法调用 —— `w.get()`
- 解构 —— `let (a, b) = w`、`for (a, b) in ws`
- 迭代 —— `for x in w`
- 匹配分支 —— `when w in { Box(x) then ... }`

把句柄**整体**绑定是允许的，并且保留 `?T`：

```koral
let w = node as ?Node;
let w2: ?Node = w;              // 可以：复制的是句柄
let xs = List[?Node].new();
xs.push(w);
for h in xs then {             // 可以：`h` 是 `?Node`
    when ?h in {               // 唯一能到达被引用对象的途径
        .Some(v) then { /* ... */ },
        .None() then {},
    };
};
```

### 并发

Koral 的并发安全是**声明处性质**，与 `type` / `type mutable` 之分同出一辙：一个类型在声明处就定死它能否跨线程共享、由谁保证这份安全，而不是等传值时再判。`sendable` 修饰符族标明哪些类型能跨线程边界——安全形态由编译器验证并内置对象锁守护，`unsafe` 形态把同步交回开发者。这里没有借用检查器，也不引入第二套调用纪律。

#### 声明 Sendable 类型

类型修饰符槽收 `unsafe`? `sendable`? `mutable`?，共六种声明形态：

| 声明 | 字段约束 | 对象锁 | 含义 |
|---|---|---|---|
| `type` | — | 无 | 线程内值 |
| `type mutable` | 仅 `mutable` 字段可改 | 无 | 线程内共享对象 |
| `type sendable` | 全部字段 `sendable` | 无（浅层不可变） | 冻结数据，可安全共享 |
| `type sendable mutable` | 全部字段 `sendable` | **内置** | 共享可变，编译器守护 |
| `type unsafe sendable` | 不限 | 无 | 开发者承诺可共享 |
| `type unsafe sendable mutable` | 不限 | 无 | 开发者承诺，同步自管 |

```koral
type sendable Point(x: Int, y: Int);

type sendable mutable Counter(mutable hits: Int);

type unsafe sendable mutable Mutex(private handle: *UInt8);

type sendable Shape {
    Circle(r: Float64),
    Rect(w: Float64, h: Float64),
};
```

规则：

- `unsafe` 必须伴随 `sendable`，单独 `unsafe` 被拒绝。安全形态让编译器验证声明；`unsafe sendable` 关掉验证，把责任交给开发者（见 [`unsafe sendable`](#unsafe-sendable)）。
- 安全形态**验证**内容：所有字段——枚举的所有载荷——本身必须是 `sendable`。标注写错是编译错，不是洞。
- 不做推断。字段全部 `sendable` 的 `type mutable` 仍然不是 `sendable`，除非声明写明。
- 枚举只收 immutable 形态：`type sendable` 与 `type unsafe sendable`；`mutable` 仍然仅限结构体。
- `type foreign` 完全不收修饰 —— `type foreign sendable FX(a: Int32);` 报 `foreign type cannot be marked sendable`。foreign 布局是 C 的，不能承诺线程共享。foreign 值只活在 `type unsafe sendable` 的受信内部或线程内状态（见 [`unsafe sendable`](#unsafe-sendable)）。
- 类型别名与 `type intrinsic` 不能带这些修饰符。别名跟随它命名的类型。

#### 派生规则

复合类型是否 `sendable`，由各部分机械推出——封闭清单：

- **标量** —— `Bool`、各数值类型、`Rune` —— 总是 `sendable`。
- **名义类型**按声明成立。
- **泛型**：`X[A, B]` 是 `sendable` 当且仅当 `X` 声明了 `sendable`，**且**全部类型实参都是 `sendable`。这一条对 `unsafe` 形态同样执行——否则一个可共享的容器能把非 sendable 的值夹带走私过界。
- **枚举**：声明 `sendable` 且全部载荷类型 `sendable`（`unsafe` 免载荷检查）。
- **函数类型**：`sendable (A) -> R` 是独立形态。无捕获的函数值天然满足；lambda 只有**全部**捕获是 `sendable` 才成立。裸泛型参数不是当然 `sendable`——`f[T: Any]` 里把 `x: T` 捕获进 `sendable` 闭包会被拒绝（`sendable closure cannot capture non-sendable value 'x'`），`T: sendable` 约束（或 `trait sendable` 约束）才放行。`sendable` 函数值可以放宽转换为普通形态，反向不行。限定词只对函数类型成立。

```koral
let run(f: sendable () -> Void): Void = f();

let main(): Void = {
    let n = 40;
    run(() => println("plain"));           // 无捕获
    run(() => println("capture \(n)"));    // `n` 是 sendable
};
```

- **Trait object**：trait object 是否 `sendable`，由 trait 声明本身决定——声明为 `trait sendable` 的对象永远 `sendable`，普通 trait 的对象永远不是。见 [Trait 的 Sendability](#trait-的-sendability)。
- **弱引用**：`?T` 是 `sendable` 当且仅当 `T` 是。
- **定长数组**：`[N]T` 是 `sendable` 当且仅当 `T` 是。
- **永非 `sendable`**：裸指针 `*T` / `*mutable T`、foreign 函数指针 `foreign (A) -> R` 与 `type foreign` 值。跨 FFI 共享的内存改走 `unsafe sendable` 包装。

#### Trait 的 Sendability

Trait 的 sendability 声明在 trait 自己身上：`trait sendable Foo` 声明一个对象**永远** `sendable` 的 trait。这份保证的代价落在 `given` 上——**每个**实现本身必须是 `sendable`（safe 或 `unsafe` 形态），在实现声明处检查。

```koral
trait sendable Speak {
    speak(self): Int;
};

type sendable Robot(id: Int);

given Robot: Speak {
    speak(self): Int = self.id;
};

let greet(s: Speak): Int = s.speak();

let main(): Void = {
    let obj: Speak = Robot(7);    // `Speak` 对象是 sendable 的——可以跨界
    println(greet(obj));
};
```

不是 `sendable` 的实现在 `given` 处被拒绝：`Type 'Human' must be sendable to implement sendable trait 'Speak'`。泛型实现必须同样证明每个被接纳的实例——把证明写进约束位：`given[T: sendable] Box[T]: Speak`，否则 `given` 被拒绝：`Type 'Box[T]' must be sendable to implement sendable trait 'Speak'; give its generic parameters 'sendable' bounds`。声明处是唯一的证明点：装箱处不再复查 `Speak` 对象，因为每个实现都已知是 `sendable` 的。继承同样要求显式声明——扩展了 `sendable` trait 的 trait 必须自己声明 `sendable`，否则永远 sendable 的对象族会长出一个非 sendable 的分支：`Trait 'Child' extends sendable trait 'Base' and must be declared sendable`。不做推断。

不带 `sendable` 的 trait 的对象保持非 sendable，而且没有类型位置限定词能改变这一点：`sendable Trait` 会被拒绝——`'sendable' qualifier applies only to function types; declare the trait 'sendable' instead`——类型位置的 `sendable` 只限定函数类型（见[派生规则](#派生规则)）。也不存在 `unsafe sendable trait` 形态：实现类型自己带 safe / `unsafe` 形态，而 `trait sendable` 的对象无论哪种实现都是 `sendable` 的。

**混合 trait。** 需要的 trait 不是 `sendable` 时，它的对象留在本线程内，行为通过两条路之一跨过去。主流的一条是泛型参数化——用可组合的类型种类约束同时要求 trait 与 sendability（见[泛型约束](#泛型约束)）：

```koral
trait Reader {
    read(self): Int;
};

type sendable Msg(len: Int);
type Plain(len: Int);          // 非 sendable

given Msg: Reader {
    read(self): Int = self.len;
};

given Plain: Reader {
    read(self): Int = self.len;
};

let drain[T: Reader and sendable](source: T): Int = source.read();

let main(): Void = {
    println("read \(drain(Msg(3)))");
    // drain(Plain(1));
    //     错误：Type 'Plain' does not satisfy the 'sendable' constraint
};
```

第二条路是把对象包进一个为它背书的 `unsafe sendable` 类型——承诺由你给出，与所有 `unsafe` 形态一样：

```koral
type unsafe sendable SharedReader(inner: Reader);
```

**错误只有一种形态。** `Error` 声明为 `trait sendable Error`：每个错误类型都必须是 `sendable`，在它的 `given` 处检查，而 `Result` 的错误侧就是普通的 `Error` trait object——不存在另一种 sendable 拼写。错误是描述失败的值、常随 `Result` 跨线程，共享性质在错误类型声明处一次定清。

#### 跨越线程边界

一个值跨线程只有几条路——被 spawn 的闭包捕获、存进共享对象的字段、存进全局量、经通道缓冲。每条路的检查都落在值被声明或形成的地方，**绝不落在普通函数签名上**：

| 检查点 | 规则 |
|---|---|
| spawn（`run_task` / `Task`） | 闭包是 `sendable () -> Void`；非 `sendable` 捕获在调用处拒绝 |
| 闭包形成 | `sendable` 函数类型只收 `sendable` 捕获 |
| 共享对象字段 | 安全 `sendable` 形态在声明处验证每个字段 |
| 全局量 | 类型必须是 `sendable`；`let mutable` 全局的槽位按变量上锁（见[对象锁](#对象锁)） |
| 通道缓冲 | `Channel[T]` 仅当 `T` 是 `sendable` 才是 `sendable`，非 sendable 的消息类型在通道定型处拒绝 |
| trait 声明 / `given` 块 | `trait sendable` 让它的对象永远 `sendable`，每个实现本身必须是 `sendable`（见 [Trait 的 Sendability](#trait-的-sendability)） |
| 方法参数与返回 | **不检查** —— 任何类型都可以 |

表外不设约束：普通函数可以接收、返回任何类型，无论 sendable 与否；同一线程上的普通调用传值，既无代价也无要求。捕获越界的闭包在 `sendable` 函数类型形成处被拒：

```koral
type mutable Local(mutable n: Int);

let run(f: sendable () -> Void): Void = f();

let main(): Void = {
    let v = Local(1);
    // run(() => println("captured \(v.n)"));
    //     错误：sendable 闭包不能捕获非 sendable 的值 'v'
};
```

#### 对象锁

安全的 `type sendable mutable` 对象自带内建同步，按字段种类**逐访问**施加，全部顺序一致：

| 访问 | 字段种类 | 协议 |
|---|---|---|
| 读 | 非 `mutable` 字段 | 直接读（构造后不变） |
| 读 | `mutable` 标量字段（整数族、浮点、`Bool`、裸指针、无载荷枚举） | 原子 load |
| 读 | 引用类型 / 多字长字段 | 短锁内读（复制句柄的 `retain` 同在锁内） |
| 写 | 标量字段 | 原子 store |
| 写 | 引用类型 / 多字长字段 | 短锁内写；旧值在**解锁之后**释放 |

- **赋值从左到右求值：先左边路径与下标，再右边，最后写入。** 右边在所有锁之外求值；锁（或原子 store）只包住最后一次写入。普通 `type mutable` 的求值顺序与此相同。

```koral
type sendable mutable Counter(mutable hits: Int);

let main(): Void = {
    let c = Counter(0);
    c.hits = c.hits + 1;   // 一次读、一次写——跨线程不原子
};
```

- **`op=` 是两步，不原子。** `x.f += e` 读 `x.f`（按读协议），经**运算符**求 `+`——内建算术或 trait 重载，泛型处看到的是同一套实现——再写回（按写协议）。跨线程原子递增属于 `AtomicCell.update_and_get` 或 `Mutex`，不属于 `+=`。
- **锁不可重入——也永远不需要。** 任何时刻至多持一把短锁：路径中间的读各取各放，右边不持锁，旧值在解锁后释放，析构回调宿主对象不会死锁。
- **锁按对象划。** 嵌套路径 `a.b.c` 逐对象取放；RHS 中碰**其他**对象会拿它的锁——跨对象的锁序由你设计。
- **每个 `let mutable` 全局遵循字段规则**：标量槽原子读写、引用/多字长槽短锁、右边在锁外、旧值解锁后放。
- 对锁对象的字段**取址**被拒绝——裸指针会绕开协议。

对象锁刻意**不**承诺下面这些——Rust、Go、Swift 划的是同一条边界：

- **没有跨访问原子性。** 原子性单位是「一次访问」——一次读或一次写。跨访问的复合操作不具原子性：`x.f = x.f + 1` 是一次读加一次写。确实需要更宽的原子步骤时，用 `AtomicCell.update_and_get`，或把状态放进你自己管的 `Mutex`（`unsafe` 形态）。
- **没有显式锁块。** 语言不提供第二种临界区拼法。
- **没有死锁自由。** 短锁仍可能经由用户代码和 `std` 的锁互相死锁。
- **这些访问的顺序一致性与原子 API 声明之外，没有额外内存序承诺。**

#### `unsafe sendable`

`unsafe` 形态是为编译器验证不了的类型留的逃生舱：自带同步的原语、FFI 句柄、无锁设计。

```koral
type unsafe sendable mutable Mutex(private handle: *UInt8);
```

契约：**开发者承诺该类型及其可达的一切，跨线程共享时没有数据竞争。** 编译器不做字段检查，也不上锁。原子引用计数只保住计数器本身——字段上的竞争、以及可达的非 `sendable` 对象的计数器竞争，都在承诺范围内。**违背承诺是未定义行为。**

类型自带同步（`Mutex`、原子单元、线程安全的 FFI 句柄）时才用 `unsafe sendable`——不是用来消掉一个你还没有真正满足的检查。

#### 冻结集合

可变容器——`List`、`Dict`、`Set`、`Deque`、`StringBuilder` 与各种迭代器——是 `type mutable` 的线程内工作状态：全都不是 `sendable`，全都不跨界。集合**数据**的跨线程故事是：在可变容器里构建，在**边界处冻结**——`FrozenList[T]`、`FrozenDict[K, V]`、`FrozenSet[T]` 是可以跨线程的不可变快照。

快照由 `type unsafe sendable mutable` 对象承载——`mutable` 形态持有自有缓冲与析构（用户析构只住在 `type mutable` 上），「构造后不可变」承诺使快照实际上只读——且存储**独立**（不内嵌源容器）。条件规则同样适用：`FrozenList[T]` 仅当 `T` 是 `sendable` 才是，所以 `FrozenList[List[Int]]` 不能跨界。

```koral
let source = List[Int].new();
source.push(2);
source.push(4);
source.push(6);
let frozen = source.to_frozen_list();    // 拷贝进独立存储
```

- 用 `List.to_frozen_list()` / `Dict.to_frozen_dict()` / `Set.to_frozen_set()` 转换，源容器之后照常可用。用 `to_list()` / `to_dict()` / `to_set()` 拷贝回可变侧。
- 读取半边是 `count`、`is_empty`、`get`、`contains`（字典上是 `contains_key`）与 `iterator`。**没有修改方法，没有 builder**——快照在构造时写一次，此后不再动它。
- 内建下标读快照：`frozen[i]` 与 `frozen_dict[key]` 的行为与 `List[i]` / `Dict[key]` 完全一致（越界 / 缺键的 panic 相同），对它们赋值是编译错。`FrozenSet` 没有下标。
- 集合字面量经类型上下文生成冻结族成员，规则沿用可变侧——集合字面量去重、字典字面量重复键后者取胜、`[]` 需要上下文：

```koral
let f: FrozenList[Int] = [1, 2, 3];
let d: FrozenDict[String, Int] = ["a": 1];
let s: FrozenSet[Int] = [1, 2, 2];        // 去重：两个元素
let empty: FrozenList[Int] = [];
```

快照与任何 `sendable` 值一样移动——被 spawn 的闭包捕获、存进共享字段、或经通道发送：

```koral
using "std/async" { ... };
using "std/sync" { ... };

let main(): Void = {
    let source = List[Int].new();
    source.push(10);
    let frozen = source.to_frozen_list();

    let (sender, receiver) = make_channel[FrozenList[Int]](1);
    let worker = run_task(() => {
        let got = receiver.recv().unwrap();
        println("worker got \(got.count()) \(got[0])");
    });
    let _ = sender.send(frozen);
    let _ = worker.wait();
};
```

`JsonValue` 坐落在冻结树上：它是 `type sendable` 枚举，`Array` 与 `Object` 载荷是 `FrozenList[JsonValue]` 与 `FrozenDict[String, JsonValue]`，所以解析好的文档直接跨线程——`Channel[JsonValue]` 直接可用。`as_array()` 与 `as_object()` 以 `Option[FrozenList[JsonValue]]` 与 `Option[FrozenDict[String, JsonValue]]` 交出冻结载荷；解析与构建留在可变侧。

#### Worker 与 Channel

并发的推荐形态：每个线程的状态**留在本线程内**——它可以是普通的、甚至是非 `sendable` 的，反正没有别人看得见它，也就不需要锁——线程之间用通道传递 `sendable` 消息，集合数据以冻结快照随行（见[冻结集合](#冻结集合)）。通道对消息类型是条件 `sendable` 的，非 sendable 的消息类型在通道声明处就被拒，而不是等消息流动时。

```koral
using "std/async" { ... };
using "std/sync" { ... };

type sendable Msg {
    Job(id: Int),
    Quit(),
};

let main(): Void = {
    let (sender, receiver) = make_channel[Msg](16);

    // 计数留在本线程内；跨线程的只有 `Msg`。
    let worker = run_task(
        () => {
            let mutable total = 0;
            while true then {
                when receiver.recv() in {
                    .Ok(msg) then {
                        when msg in {
                            .Job(id) then {
                                total = total + id;
                            },
                            .Quit() then {
                                break;
                            },
                        };
                    },
                    .Error(_) then {
                        break;
                    },
                };
            };
            println("total \(total)");
        },
    );

    let _ = sender.send(Msg.Job(1));
    let _ = sender.send(Msg.Job(2));
    let _ = sender.send(Msg.Quit());
    let _ = worker.wait();
};
```

自带对象锁的共享可变对象是第二形态；你信任的同步原语是 `unsafe` 形态。结束 worker 的另一条路是关掉通道：最后一个 `SendChannel` 句柄析构后，缓冲消息收完，`recv()` 就报 `.Error`。

**引用计数跟随 sendability，但这不属于语言契约。** `sendable` 类型用原子引用计数，非 `sendable` 类型用非原子的；两者都不得依赖——它和布局一样是实现细节，将来可能改变。

## 4. 模式匹配

Koral 具备强大的模式匹配能力，主要通过 `when` 表达式和 `is` 操作符使用。模式也是 `if` / `while` 条件里的绑定形态，以及 `for` 循环的绑定形态（见 [for 循环](#for-循环)）。

### 模式形态

支持的模式包括：

- 通配模式：`_`（匹配任意值）
- 字面量模式：`1`、`-5`、`1.5`、`-2.25`、`"abc"`、`'a'`、`true`（支持 `-5` 这类负数字面量）
- 变量绑定模式：`x`（匹配任意值并绑定到 x）、`mutable x`（可变绑定）
- 比较模式：`> 5`、`< 0`、`>= 10`、`<= -1`、`> 1.5`、`>= 'a'`
- 结构体解构模式：`Point(x, y)`、`Rect(Point(a, b), w, h)`
- 元组解构模式：`(a, b, c)`——按位置解构字段数正好这么多的结构体（`Pair` 也是，它就是两字段结构体）；至少两个绑定位置
- 列表解构模式：`[]`、`[a, b]`、`[a, ...]`、`[a, ..., b]`、`[...]`——按长度解构 `List[T]`
- 剩余模式：`...`——忽略槽位（列表里吞掉中间，结构体/枚举变体里整段省略）；见下文
- 枚举变体模式：`.Some(v)`、`.None()`
- trait object 精确类型模式：`IoError`、`err: IoError`
- （已移除：弱绑定模式 `?v` / `?Node(v)`——取 `Option[T]` 用 `?expr`；构造是 `x as ?T`）
- 逻辑模式：`pattern and pattern`、`pattern or pattern`、`not pattern`
- `is` 链：`x is A or is B`、`x is A and is not B`——同一主体上的多个测试，用连接词 `or is` / `and is` 串起

字面量能匹配什么，等于它的 `==` 能接受什么：整数只对整型（`-5` 不匹配无符号类型），
浮点只对 `Float32` / `Float64`，`true` 只对 `Bool`，字符串只对 `String`，rune 对
`Rune`（或 ASCII 的 `UInt8`）。浮点字面量按 IEEE 等值匹配，且取主体的宽度（`Float32`
上的 `1.1` 即 `Float32(1.1)`）：因此 NaN 不匹配任何常量模式（要用守卫 `v where v != v`
接住），`0.0` 与 `-0.0` 互匹配。比较模式的界遵循同一条种类规则：`> 1` 是整数界，
`> 1.0` 是浮点界，`> 'a'` 是 rune 界（按码点比较）。比较界可以落在主体的域外
（`UInt8` 上的 `>= -1` 匹配一切）。

解构遵循与调用完全相同的标签规则：声明为命名的字段必须带标签匹配，声明为位置的字段绝不能带标签。

#### 列表模式与剩余模式

列表模式按长度解构 `List[T]`。每个槽位与 `T` 统一，绑定语义就是
`let name = subject[i]`。无剩余槽位时长度必须恰好相等；有剩余槽位时已写的
槽位数成为长度下界：

```koral
[]              // 只匹配空列表
[a, b]          // 只匹配长度 2
[a, ...]        // 长度 >= 1，首元素绑到 a
[..., b]        // 长度 >= 1，末元素绑到 b
[a, ..., b]     // 长度 >= 2，首尾各绑一个
[...]           // 任意列表，等价于 `_`
```

剩余模式 `...` 只**忽略**槽位，**不绑定**——所以 `...x` 是错误；而且它只能是
元素表里的一个槽位，每层元素表至多一个。写在其它位置（整条 arm、`not` 之下、
单独的 `( ... )`）一律拒绝。

它在两套元素表里语义不同。在**列表**元素表里，它吞掉未写出的中间槽位，可以和
已写的槽位并存（见上表）。在**结构体与枚举变体**元素表里，它是整段省略：必须是
元素表的**唯一**槽位，忽略每个字段——命名字段与位置字段一视同仁：

```koral
Point(...)      // 等价于 Point(_, _, _)
.RGB(...)       // 等价于 .RGB(_, _, _)
Button(...)     // 命名字段一样可以：等价于 Button(_, height = _, label = _)
```

要忽略的是部分字段时逐个写 `_`，不与 `...` 并存：写 `Point(x, _, y)`，不写
`Point(x, ..., y)`。元组模式不收剩余槽位（`( ... )` 是括号分组错误）。

列表模式参与穷举性判定，按长度算。只有当**所有**槽位都不可反驳时，一个模式才算
完整覆盖某个长度：因此 `[]` 与 `[x, ...]` 合起来覆盖所有列表，而 `[1, ...]` 不行
（它漏掉首元素不是 1 的列表）。在结构体、枚举变体模式里剩余标记不改变穷举性：
字段数固定，它就是整段 `_`。

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start = p, end = e) then println(p.x),
};

if b is Button(w, height = _, label = l) then println(l);
```

逻辑组合子对模式能绑定什么有约束：

- `a and b` 两侧都会执行，所以两侧不能绑定同一个名字——否则一个名字会有两个不同的值。
- `a or b` 只匹配其中一侧，所以两侧必须绑定同一批名字，且同一个名字在两侧必须是同一个类型。
- `not p` 靠「形状不存在」来匹配，所以 `p` 不能绑定任何东西。

`or` 的两侧仍然可以把同一个名字放在不同位置。每个分支读自己的布局，因此下面的 `a` 与 `b`
来自真正匹配到的那个分支。

```koral
type E {
    A(a: Int, b: Int),
    B(a: Int, mid: Int, b: Int),
};

when e in {
    .A(a, b) or .B(a, _, b) then a + b,
};
```

### `when` 表达式

`when` 表达式把一个值与一系列模式比较，并按匹配到的模式执行对应代码。它类似其他语言的 `switch`，但更强大。`when` 始终是表达式。单分支 `when` 产生 `Void`；多于一个分支时返回匹配分支的值。

```koral
let x = 5;
let result = when x in {
    1 then "one",
    2 then "two",
    _ then "other",
};
```

arm 的分支体也可以是裸控制转移——`1 then return 31` 就是 `1 then { return 31; }`（见 [分支体与控制转移](#分支体与控制转移)）。

分支可以带守卫：`pat where cond then body`。模式绑定在 `cond` 里可见，守卫先于
分支体求值，为假则落到下一个分支。守卫是 arm 级的，不进子模式——`a or b where c`
读作 `(a or b) where c`——但守卫的求值是**回溯的**：当分支模式经由 `or` 提供多组
读法时，每组读法各自绑定自己的值，守卫在这些绑定上重新求值。最左的、守卫接受的
读法胜出；被拒绝的守卫落到同一分支的下一组读法，只有全部读法都被拒，这个分支才
失败、轮到下一个分支。守卫必须是 `Bool`。
`for` 用的是同一个关键字、同一个槽位（见 [for 循环](#for-循环)）。旧拼法 `if`
会报错并指路。

```koral
let kind = when v in {
    .Some(n) where n > 0 then "positive",
    .Some(n) where n < 0 then "negative",
    .Some(n) then "zero",
    .None() then "empty",
};
```

带守卫的分支不贡献穷尽性覆盖（见[穷尽性检查](#穷尽性检查)）：上面的 `when`
之所以完整，靠的是未守卫的 `.Some(n)` 与 `.None()` 分支，不是守卫分支。

守卫里的 `is` 子句会绑定，与 `if`/`while` 条件完全一样（见 [`is` 表达式](#is-表达式)）：
`where o is .Some(w) and w > 0` 由第一步绑定 `w`，守卫的后半段读它，名字在分支体里
也可见。限制同样一致——表达式级 `or`/`not` 下的绑定、`is not` 的绑定都会被拒。

模式绑定只在它所在的分支内可见。在分支内部它指代匹配到的载荷；离开 `when` 之后它不存在，同名的外层绑定保持原义。不同分支可以自由复用同一个名字，彼此的绑定互不影响。

```koral
let f(s: Shape, radius: String): String = {
    let mutable inner = "";
    when s in {
        // 这里的 `radius` 是 `Circle` 的载荷。
        .Circle(radius) then { inner = radius.to_string(); },
        _ then { inner = "none"; },
    };
    // 这里的 `radius` 又是那个 `String` 参数了。
    return radius + "/" + inner;
};
```

与 `if` 一样，`when` 中块分支的尾表达式就是该分支的值。

```koral
let label = when score in {
    100 then {
        println("bonus");
        "perfect"
    },
    >= 90 then {
        if has_curve(score) then {
            "A+"
        } else {
            "A"
        }
    },
    _ then { "other" },
};
```

更多示例：

```koral
// 枚举类型匹配
type Shape {
    Circle(radius: Float64),
    Rectangle(width: Float64, height: Float64),
};

let area = when shape in {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
};

// 比较模式
let grade = when score in {
    >= 90 then "A",
    >= 80 then "B",
    >= 70 then "C",
    _ then "F",
};

// 逻辑模式
when x in {
    1 or 2 or 3 then println("small"),
    _ then println("big"),
};

// 结构体解构模式
type Point(x: Int, y: Int);
type Rect(origin: Point, width: Int, height: Int);

let p = Point(10, 20);
when p in {
    Point(x, y) then println(x + y),  // 30
};

// 嵌套结构体解构
let r = Rect(Point(1, 2), 30, 40);
when r in {
    Rect(Point(a, b), w, h) then println(a + b + w + h),  // 73
};

// if...is 中的结构体解构
if p is Point(x, y) then {
    println(x * y);  // 200
};

// trait object 实现类型的精确匹配
trait Problem {
    render(self): String;
};

type IoError(code: Int);

given IoError: Problem {
    render(self): String = "io";
};

let err: Problem = IoError(7);
when err in {
    io: IoError then println(io.render()),
    _ then println("other"),
};

// 通配符与字面量字段匹配
when p in {
    Point(0, y) then println(y),  // 第一个字段为 0 时匹配
    Point(_, y) then println(y),  // 忽略第一个字段
};

// 泛型结构体解构
type Box[T: Any](val: T);
let b = Box[Int](42);
when b in {
    Box(v) then println(v),  // 42
};
```

### `is` 测试

`is` 操作符检查一个值是否匹配某个模式，结果始终是 `Bool`。它是通用表达式，可以出现在 `let` 初始化、返回表达式、函数实参等表达式位置。

`is not` 是取反形式，返回相反的匹配结果。

用在 `if` 或 `while` 表达式的条件中时，成功的 `is` 匹配还可以把模式中的变量绑定到当前作用域。在这些条件上下文之外，`is` 只能做布尔测试，不能引入绑定。`when ... in` 结构使用自己对匹配值的模式匹配，不通过 `is` 绑定。

`is` 直接接受单个模式。同一主体上的多个测试用双词连接 `or is` / `and is` 串起来，合成**一个**模式：`x is A or is B` 即 `x is (A or B)`，两侧的绑定像 `when` 臂的 `or` 一样共享。`and is` 比 `or is` 紧，整条链比表达式级的 `and` / `or` 紧——所以 `a is x or is y and b > 1` 读作 `(a is x or is y) and (b > 1)`。连接词只有在后面跟着 `is` 时才算连接词；裸的 `or` / `and` 是表达式算子。

模式位置的 `(` 开的是元组模式（`is (a, b)`），绝不给单个模式分组。要组合请用 `or is` / `and is`。

```koral
let opt = Option[Int].Some(42);
let has_value = opt is .Some(_);
let is_empty = opt is not .Some(_);

if opt is .Some(v) then {
    println(v);  // 42
};

// 比较模式
if score is >= 60 then {
    println("passed");
};

// `is` 链：一个主体，多个模式
if argv is [] or is [_, ...] then {
    println("没有参数，或者只有程序名");
};

let p = Point(1, 2);
if p is Point(_, _) and is not Point(0, 0) then {
    println("是点，但不是原点");
};

if x is 0 or is 1 then {
    println("small");
};

// 条件中仍可使用标准布尔组合
if opt is .Some(v) and v > 0 then {
    println(v);
};
```

### 惰性管线

迭代分成两个角色：

- **`Iterator[T]`** 是**游标**。一次性，只有一个方法 `next(self): Option[T]`。
  上面没有任何"只问不推进"的观察方法，所以没有哪个调用能在提问的同时偷偷把它花掉。
  把游标交给 `for` 会一路走到尽头。
- **`Iterable[T, R]`** 每次调用都能给出一个**新的游标**（`iterator(self): R`）：
  容器、范围，以及每一条惰性管线。

惰性管线从 `lazy()` 进入后就不再离开：它返回 `LazyView`，每个适配器再返回一个
`LazyView`，所以一条链只写一次。容器面上不写任何惰性名字——
`dict.take(key)`、`string.find(pat)`、`list.first()` 等等各自回到类型自己的语义，
`map`、`filter`、`to_list`、`collect` 这些名字在容器面上留空，给将来的 eager API。

```koral
let view = list.lazy().filter((x) => x > 0).map((x) => x * 2);

view.count();        // 造游标、走完、丢弃
view.is_empty();     // 看一个元素，丢掉游标
view.into_list();    // [2, 4, 6]
view.count();        // 3 —— 管线从未被花掉

list.count();        // 容器自己的 O(1) count
```

`lazy()` 是一扇门，不是一层包装：它只写在容器上一次，`LazyView` 上没有第二个
`lazy()` 可以重复——拿回来的链条本身就是惰性的。
`LazyView` 是值——它内部没有任何东西被修改——所以把它绑到名字上用两次，结果总是自洽。

它的签名是 `LazyView[T, R]`：元素类型，加上管线会给出的游标类型。它持有的是
**游标工厂**而不是源，所以链条不会每多一级就多一个类型参数，也不存在逐级的视图类型。
拿出来的游标是普通的单态化 `Iterator`，`next` 是直接调用。

游标是另一回事：`list.iterator()` 指着一个位置，拉取会推进它。要对一次性源
（文件行、网络流）跑管线，先收集成 List。

### 条件与循环绑定

`if` 与 `while` 的条件整合了 `is` 绑定，这是消费迭代器和就地解构的惯用写法。

```koral
let opt = Option[Int].Some(42);
if opt is .Some(v) then {
    println(v);  // 42
} else {
    println("None");
};

let mutable iter = list.iterator();
while iter.next() is .Some(v) then {
    println(v);
};
```

多个条件使用标准的 `and` / `or` / `not` 组合。当 `and` 左侧是带绑定的 `is` 匹配时，这些绑定对后续 `and` 分句和 `then` 分支可见：

```koral
if foo() is .A(x) and bar(x) is .B(y) and y > 0 then {
    println(y);
} else {
    println("no match");
};

while iter.next() is .Some(item) and parse(item) is .Ok(v) then {
    println(v);
};
```

条件组合规则：

- 条件从左到右按常规短路求值。
- 先前 `is` 分句引入的绑定，在后续 `and` 分句和 `then` 分支中可用。
- 带绑定的 `is` 匹配不允许出现在 `or` 分支下或 `not` 之下。
- 对 `while` 条件，各分句同样从左到右短路。某分句失败时循环终止。

### 逻辑模式组合子

模式可以用 `and`、`or`、`not` 组合：

```koral
when temperature in {
    > 0 and < 100 then "liquid",
    <= 0 then "solid",
    >= 100 then "gas",
};
```

在 `is` 下，请用圆括号给组合子分组：

```koral
if x is 0 or is 1 then {
    println("small");
};
```

### 穷举性检查

`when` 表达式会检查模式是否穷尽：

- 对 `Bool` 类型，必须覆盖 `true` 与 `false`（或使用通配符）。
- 对 `enum` 类型，必须覆盖所有变体（或使用通配符）。
- 对 `Int` / `UInt` 类型，比较模式（`> 0`、`<= 0` 等）在完全覆盖整数范围时可构成穷举；否则需要通配符。
- 对浮点与 `Rune` 类型，常量与比较模式都不贡献覆盖（没有有限的值域可封闭），必须有通配符或变量绑定。
- 对结构体类型，所有字段均为通配符的 `StructName(_, _)` 形式视为穷尽。
- 重复模式在编译期被拒绝。
- 不可达模式（已被前面分支覆盖的模式）在编译期被拒绝。通配符和变量绑定模式豁免此检查。
- 带守卫的分支（`pat where cond then ...`）不覆盖任何东西：守卫可能为假，穷尽性不依赖它。同一个模式要么补一个不带守卫的分支，要么用通配符。

```koral
// 通过比较模式穷尽
let classify(x: Int): Int = when x in {
    > 0 then 1,
    <= 0 then 0,
};
```

### 精确类型模式

trait object 还支持通过模式系统做实现类型的精确测试。

```koral
trait Problem {
    render(self): String;
};

type IoError(code: Int);
type NetError(code: Int);

given IoError: Problem {
    render(self): String = "io";
};

given NetError: Problem {
    render(self): String = "net";
};

let err: Problem = IoError(7);

if err is IoError then {
    println("io");
};

if err is io: IoError then {
    println(io.render());
};

let label = when err in {
    io: IoError then io.render(),
    _ then "other",
};
```

规则：

- 精确类型模式只在主体是 trait object 时有效。
- 目标必须是具体类型名。
- 匹配按实现类型及其泛型实参精确进行。
- 主体保持为 trait object；不会自动解引用到底层实现值。`err is io: IoError` 把 `io` 绑定为 `IoError`。
- 这些模式是开放世界测试；在 `when` 中它们不算穷举覆盖，因此仍需默认 `_` 分支。

## 5. 抽象设计

Koral 用 Trait 定义共享行为，类似其他语言的接口或类型类。

### Trait 与 `given` 块

#### 定义 Trait

Trait 定义一组方法签名，任何实现类型都必须提供。

```koral
trait Printable {
    to_string(self): String;
};
```

Trait 支持用父 Trait 名称做继承：

```koral
trait Ord: Eq {
    compare(self, other: Self): Int;
};
```

多个父 Trait 用 `and` 连接：

```koral
trait MyTrait: Eq and Hash {
    my_method(self): Int;
};
```

#### 实现 Trait

用 `given Type: Trait { ... }` 实现块为特定类型实现 Trait：

```koral
trait Eq {
    equals(self, other: Self): Bool;
};

trait Ord: Eq {
    compare(self, other: Self): Int;
};

type Point(x: Int, y: Int);

given Point: Eq {
    equals(self, other: Point): Bool = self.x == other.x and self.y == other.y;
};

given Point: Ord {
    compare(self, other: Point): Int = self.x - other.x;
};
```

说明：

- `given Type: Trait` 是显式实现入口。
- 父/子 trait 逐级实现：实现 `Ord` 不会隐式实现 `Eq`。

#### Trait 与实现中的命名参数

Trait 方法支持命名参数。实现必须与 trait 的参数分类一致：

- 如果 trait 方法参数是命名的（`name: Type =`），实现也必须声明为命名（保留 `=` 标记，但不重复默认值）。
- 如果 trait 方法参数是位置的（`name: Type`），实现也必须声明为位置。

trait 与 given 的默认值规则：

- 如果 trait 为某个命名参数声明了默认值，given 实现**不得**重复声明。trait 是默认值的唯一来源。
- 如果 trait 没有声明默认值，given 实现**不能**补加。

```koral
trait Drawable {
    draw(self, color: String =, thickness: Int =): String;
};

type Circle(radius: Int);

given Circle: Drawable {
    // 'color' 与 'thickness' 是命名参数，与 trait 一致
    draw(self, color: String =, thickness: Int =): String = color + thickness.to_string();
};
```

#### 方法接收器形态

- `self` 是唯一的接收器形态。
- 对 `type`（浅层不可变），`self` 是不可变接收器。
- 对 `type mutable`（共享对象），`self` 是可以修改显式 `mutable` 字段的接收器。

### Trait 工具方法

Koral 支持用 `given Trait { ... }` 定义 trait 工具方法。

规则：

- 写在 `trait` 里的是**需求**（用于一致性检查和经由 trait object 的动态分发）。
- 写在 `given Trait` 里的是**工具方法**（便利辅助），**不是**需求的 witness。
- 工具方法不会并入具体类型的固有方法集；它们按上下文参与调用解析。

示例：

```koral
trait Eq {
    equals(self, other: Self): Bool;
};

given Eq {
    not_equals(self, other: Self): Bool = not self.equals(other);
};

type Num(x: Int);

given Num: Eq {
    equals(self, other: Num): Bool = self.x == other.x;
};

let a = Num(1);
let b = Num(2);
println(a.not_equals(b));
```

带约束的工具块示例：

```koral
trait Cursor[T: Any] {
    next(self): Option[T];
};

given[T: Ord] Cursor[T] {
    max(self): Option[T] = {
        let mutable best = self.next();
        while self.next() is .Some(v) then {
            best = when best in {
                .Some(b) then if v > b then Option[T].Some(v) else Option[T].Some(b),
                .None() then Option[T].Some(v),
            };
        };
        return best;
    };
};

// 对实现了 Cursor[Int] 的类型，max 可用
```

分发规则：

- 需求方法：在泛型与 trait object 上下文中走 witness/vtable 分发。
- 工具方法（`given Trait`）：静态分发（不是虚分发入口）。

工具方法可用在：

- 泛型约束上下文（如 `[T: Trait]`）
- trait object 上下文
- 显式实现该 trait 的具体类型

#### 覆盖与冲突规则

- 一个类型对同一 trait 只能有一个 `given` 实现，与 trait 的类型参数无关：`given Vec: Add[Int]` 与 `given Vec: Add[Vec]` 冲突，和重复的 `given Point: T` 是同一条规则。
- 工具方法默认不可覆盖其他候选。
- 类型自身方法优先于 trait 工具方法。
- 如果多个 trait 工具来源提供同名同签名方法，Koral 不会隐式选择；必须使用完全限定调用显式消歧，例如 `Type(TraitName).method(value, ...)`。
- 如果两个 trait 都定义了同名方法，且其中一个继承自另一个，则子 trait 的实现优先，不会形成歧义。
- `given Trait` 中不允许与该 trait requirement 同名同签名的方法。

#### Trait 继承规则

- trait 可以继承一个或多个父 trait：`trait Child: Parent1 and Parent2 { ... }`。
- trait 继承必须无环；环在编译期检出并拒绝。
- 实现子 trait 的类型也必须实现全部父 trait（直接实现或通过 `given` 块）。

#### 模块边界规则

边界锚定规则：

- `given Trait { ... }` 只允许出现在该 trait 的 root 模块子树内。
- `given Type { ... }` 只允许出现在该类型的 root 模块子树内。
- `given Type: Trait { ... }` 遵循孤儿规则：类型或 trait 至少一个必须是当前 root 模块的本地定义。
- 不允许跨 crate 注入。

### 完全限定调用

当出现同名候选冲突时，可使用完全限定调用。两套写法：

- `Type(TraitName).method(...)` —— 类型限定。实例方法的 receiver 作为第一个实参传入；静态 trait 方法不传 receiver。
- `expr(TraitName).method(...)` —— receiver 限定。receiver 就是左侧表达式，方法实参里不再写 receiver。仅用于实例方法。

两者都是组合节点：`expr(TraitName)` / `Type(TraitName)` 前缀必须带方法调用。

- 泛型 trait 的实参写在限定里：`Type(TraitName[Args...]).method(...)`
- 泛型方法的类型参数仍写在方法名后：`Type(TraitName).method[TypeArgs...](...)`

```
Type(TraitName).method(receiver, ...)   // 实例方法（类型限定）
Type(TraitName).static_method(...)      // 静态 trait 方法
expr(TraitName).method(...)             // 实例方法（receiver 限定）
```

```koral
trait Tag {
    value(self): Int;
};

given Tag {
    plus_ten(self): Int = self.value() + 10;
    kind(self): Int = 42;
};

type Num(x: Int);

given Num: Tag {
    value(self): Int = self.x;
};

let n = Num(7);
println(Num(Tag).plus_ten(n).to_string());  // 17
println(Num(Tag).kind(n).to_string());      // 42
```

对泛型方法，trait 限定写在方法类型参数之前。

### Trait Object

trait object 是 Koral 实现运行期多态（动态分发）的机制，表层语法就是 trait 名本身。

#### 基本语法

trait object 的构造遵循这些规则：

- 目标类型是 trait 名（泛型 trait 带上类型实参：`Transform[Int]`）。
- 源值必须实现该 trait，并转换到该 trait object 上下文。
- 不需要 `Object` 标记 trait。

```koral
trait Drawable {
    draw(self): String;
};

type Circle(radius: Int);

given Circle: Drawable {
    draw(self): String = "Drawing circle";
};

let shape: Drawable = Circle(10);   // 赋值时隐式转换
shape.draw();

let d = Drawable(Circle(10));      // 显式 upcast：恰好一个位置实参
d.draw();
Drawable(Circle(10)).draw();       // 任何需要表达式的位置都可以
```

赋值会把具体值隐式转换到 trait object 上下文。显式 upcast 是单实参调用形
`Trait(expr)`——`Drawable(c)`，泛型 trait 写 `Transform[Int](c)`。
trait 目标遵循构造规则，`c as Drawable` 作为强转拼写会被拒绝
（`Construction is written 'Type(args)', not 'expr as Type'`）。
从一个 trait object 转到另一个 trait object 是被拒绝的
（`Cannot cast a trait object to another trait object`），upcast 恰好接受一个
位置实参（`A cast takes exactly one positional argument: write 'Type(expr)'`）。

重要规则：

- trait object 分发使用具体值的语义，不在公开表层暴露内部包装。
- 任何 object-safe 的 trait 都可用作 trait object 目标。
- trait object 不支持直接解引用；请通过动态分发使用 trait 方法。

#### 对象安全性

只有满足以下条件的 Trait 才能用作 trait object：

- 方法不能有泛型参数。
- 接收器（如果有）必须是 `self`。
- `Self` 不能出现在方法参数或返回类型中。

```koral
// object-safe——可用作 trait object
trait Error {
    message(self): String;
};

// 非 object-safe——不能用作 trait object
trait Eq {
    equals(self, other: Self): Bool;
};
```

trait object 上的实现类型精确测试见[精确类型模式](#精确类型模式)。

### 运算符重载

Koral 支持基于 trait 的算术、位与比较运算符重载。下标是内建的，不可由用户重载。

内建运算符映射为：

- `+` -> `Add[R]`，经由 `add(self, other: R): Self`
- `-`（二元）-> `Sub[R]`，经由 `sub(self, other: R): Self`
- `-`（一元）-> `Neg`，经由 `neg(self): Self`
- `*` -> `Mul[R]`，经由 `mul(self, other: R): Self`
- `/` -> `Div[R]`，经由 `div(self, other: R): Self`
- `%` -> `Rem[R]`，经由 `rem(self, other: R): Self`
- `&` -> `BitAnd[R]`，经由 `bit_and(self, other: R): Self`
- `|` -> `BitOr[R]`，经由 `bit_or(self, other: R): Self`
- `^` -> `BitXor[R]`，经由 `bit_xor(self, other: R): Self`
- `~`（一元）-> `BitNot`，经由 `bit_not(self): Self`
- `<<` -> `ShiftLeft[R]`，经由 `shift_left(self, other: R): Self`
- `>>` -> `ShiftRight[R]`，经由 `shift_right(self, other: R): Self`
- `==` / `!=` -> `Eq`，经由 `equals(self, other: Self): Bool`
- `<` / `>` / `<=` / `>=` -> `Ord`，经由 `compare(self, other: Self): Int`

同方向链式序比较（如 `a < b < c`）是这些既有比较运算符的语法糖。编译器把它们降级为两两比较，具备单次求值和短路语义；不会引入独立的 trait 或分发机制。

同宽整数对（含 `Wrapping` 家族）走算术与位运算符的内建路径——常规家族为 checked 算术与移位，`Wrapping` 为模算术与掩码移位量——其余一律经上述 trait 分发。

位运算符（`&`、`|`、`^`、`~`、`<<`、`>>`）经 `BitAnd`/`BitOr`/`BitXor`/`BitNot`/`ShiftLeft`/`ShiftRight` 分发，规则与算术一致。

```koral
type Vec2(x: Int, y: Int);

given Vec2: Add[Vec2] {
    add(self, other: Vec2): Vec2 = Vec2(self.x + other.x, self.y + other.y);
};

given Vec2: Neg {
    neg(self): Vec2 = Vec2(-self.x, -self.y);
};

given Vec2: Eq {
    equals(self, other: Vec2): Bool = self.x == other.x and self.y == other.y;
};

given Vec2: Ord {
    compare(self, other: Vec2): Int =
        if self.x != other.x then self.x.compare(other.x) else self.y.compare(other.y);
};

let sum = Vec2(1, 2) + Vec2(3, 4);
let flipped = -sum;
let same = sum == Vec2(4, 6);
let ordered = Vec2(1, 0) < Vec2(2, 0);
```

位运算符的重载方式相同：

```koral
type Bits(mask: UInt32);

given Bits: BitAnd[Bits] {
    bit_and(self, other: Bits): Bits = Bits(self.mask & other.mask);
};

given Bits: BitNot {
    bit_not(self): Bits = Bits(~self.mask);
};

// 右操作数的类型是 trait 的 `R`：移位计数写成 `Int` 最自然。
given Bits: ShiftLeft[Int] {
    shift_left(self, other: Int): Bits = Bits(self.mask << UInt32(other));
};

let both = Bits(0xF0) & Bits(0x33);
let complement = ~both;
let wide = Bits(1) << 8;
```

复合赋值（`&=`、`|=`、`^=`、`<<=`、`>>=`）与[复合赋值](#复合赋值)一节写明的两步解糖形相同：每个
`op=` 读目标、经**运算符**求值——内建算术或 trait（`Add`、`ShiftLeft` 等）——再写回，
右操作数取运算符自己的操作数类型。所以 `ShiftLeft[Int]` 实现让 `m <<= 2` 收 `Int`
计数，泛型 `T` 与内建类型表现一致。该步骤跨线程不原子。

#### 内建下标规则

- `value[key]` 与 `value[key] = expr` 只支持 `String`、`List[T]`、`Deque[T]`、`Dict[K, V]`、`FrozenList[T]`、`FrozenDict[K, V]`、定长数组 `[N]T`、`*T` 与 `*mutable T`。
- `String[key]` 返回 `UInt8` 字节值。只读且不可取址。
- `List[T]` 与 `Deque[T]`（均为 `type mutable`）支持值读取、赋值与嵌套 place 更新。
- `FrozenList[T]` 与 `FrozenDict[K, V]` 的下标只读：`frozen[i]` 与 `frozen_dict[key]` 的读取与 `List[i]` / `Dict[key]` 完全一致（越界 / 缺键的 panic 相同），对它们赋值是编译错。`FrozenSet[T]` 没有下标。
- 定长数组 `[N]T` 支持值读取、赋值与复合更新，带越界检查（见[定长数组](#定长数组)）。
- `*T` 只支持 `*expr` 读取。`*mutable T` 同时支持 `*expr` 读写。
- 用户自定义类型不能通过 trait 实现 `[]`，泛型约束也不能增加下标能力。

```koral
let list = [10, 20, 30];
println(list[0]);
list[1] = 99;

let text = "abc";
let b: UInt8 = text[1];

let p: *mutable Int = alloc_memory[Int](2);
p[0] = list[0];
let first = p[0];
dealloc_memory(p);
```

### 扩展方法

`given` 块也可以直接为类型添加方法：

```koral
given Point {
    public distance(self): Float64 = {
        let dx = Float64(self.x);
        let dy = Float64(self.y);
        return dx + dy; // ...
    };

    // 不带 self 的方法通过类型名调用
    public origin(): Point = Point(0, 0);
};

let p = Point.origin();
```

### 标准库核心 Trait

最常用的核心 trait 有：

- `Add[R]` / `Sub[R]` / `Neg` / `Mul[R]` / `Div[R]` / `Rem[R]`：算术运算符 trait。
- `BitAnd[R]` / `BitOr[R]` / `BitXor[R]` / `BitNot` / `ShiftLeft[R]` / `ShiftRight[R]`：位运算符 trait。
- `Eq` / `Ord`：相等与排序。
- `Hash`：dict/set 键的哈希支持。
- `ToString`：转换为字符串。
- `Clone`：显式浅拷贝（`clone(self): Self`）。
- `Iterator[T]`：迭代协议——一次性游标，只有 `next(self): Option[T]` 一个方法，再无其它。
- `Iterable[T, R]`：每次调用都能给出一个新游标（`iterator(self): R`）。惰性管线从 `lazy()` 进入，返回 `LazyView`。
- `Error`：错误消息接口（`message(self): String`）。声明为 `trait sendable Error`——每个错误类型都必须是 `sendable`，`Result` 的错误侧就是普通的 `Error` trait object。
- `Drop`：析构钩子（`drop(self): Void`）。

算术、位与比较运算符在内部会降级为 trait 方法（例如 `+` 对应 `Add`、`&` 对应 `BitAnd`）。下标由内建编译器规则解析，不走公开 trait。

### 模块与可见性

Koral 提供两层组织单位，用来把代码分到多个文件和目录里：

| 概念 | 是什么 | 稳定身份 | 例子 |
| --- | --- | --- | --- |
| **package** | 外部可使用单元：一份 `koral.json`、一个版本、一组依赖 | `source` | `httpr`、`std` |
| **module** | 包内的构建单元：一个入口文件 + 若干合并文件 | `(source, 子路径)` | `httpr/conn`、`std/io` |

**模块全名 = `包名[/子路径]`**，源码里一律写全名。主模块是子路径为空的那个，
它的全名就是包名本身。主模块不是「根」——它与子模块平级，没有 re-export 语义。

#### manifest

一份 `koral.json` 五个字段：

```json
{
  "package": "httpr",
  "version": "0.4.1",
  "modules": {
    ".":    { "entry": "client.koral",    "links": [] },
    "conn": { "entry": "conn/conn.koral", "links": [] }
  },
  "dependencies": {
    "slug": { "source": "path:../slug", "version": "^1.2" }
  },
  "exclude": ["test/cases"]
}
```

- **`package`**：本包的源码名——自引用前缀，也是消费方的默认名。**它不是身份**，身份是 `source`。
- **`version`**：版本。
- **`modules`**：**包内名** → `{ entry, links }`。主模块的 key 是 `"."`，子模块写子路径（`"conn"`、`"compiler/parser"`）。
  `entry` 是相对包根的入口文件。
- **`dependencies`**：**源码名** → `{ source, version }`。`source` 是获取位置也是身份，不含 ref；
  `version` 是 semver 约束。改名就是换 key，没有额外字段。
- **`exclude`**：**不是包源码**的包根相对路径——格式化器夹具、生成输入，任何不该被模块认领的
  `.koral`。可选。**编译器不读它**，`koral lint` 读。

`koral lint` 检查工程布局，与编译分开。今天只查一条：包根下每个 `.koral` 文件必须属于
恰好一个模块的闭包。没人认领的文件不在任何编译单元里、不被任何检查覆盖——最常见的原因是
少写了一行 `using`。`koral build` 与 `koral check` 会先跑同一条检查。

没有顶层 `entry`（默认构建目标 = 主模块）、没有 `name`（与 `package` 重复）、
没有 `requires`（模块图从 `using` 派生）、没有 `module_aliases`（改名即换 key）。

#### Using 声明

`using` 只有一种写法。**操作**由有无括号决定，specifier 只回答目标在哪：

| 形态 | 操作 | 边界 |
| --- | --- | --- |
| `using "spec";` | **合并**——目标并进当前模块 | 消掉 |
| `using "spec" { … };` | **导入**——取目标的名字 | 保留 |

| specifier | 指什么 |
| --- | --- |
| `./x.koral`、`../y/z.koral` | 以该入口文件为根的那个模块 |
| `pkg`、`pkg/sub` | 已登记模块的 `package[/subpath]` |

所有 `using` 必须位于文件顶部，在任何其它顶层声明之前。同一模块在同一文件内只 `using` 一次。

**单文件即模块**——它是最小尺寸。「文件合并」不是独立概念：裸形式合并的是模块，
而一个什么都不合并的模块恰好只有一个文件。

##### 合并

```koral
using "./helpers.koral";
using "./util.koral";          // 一个自己还合并了别的模块
```

目标的整个闭包并进当前模块，边界消失：它的 `internal` 名字变成当前模块的。

1. 本地路径必须以 `.koral` 结尾，按当前文件所在目录解析，允许 `.` / `..`；
2. 一个被合并的模块最多被合并进一个模块，且合并后不得再被导入——
   每个源文件恰好属于一个模块；
3. 合并本包内已登记的模块（`using "mypkg/util";`）同样合法，行为一致；这很少是你想要的。

##### 导入

```koral
using "std/os" { };                          // 什么都不带
using "std/io" { Reader, Writer };           // 只带一部分
using "std/io" { Reader as IoReader };       // 逐项别名
using "std/os" { ... };                      // 全部可见成员
using "std/os" { Config as OsConfig, ... };  // 全部，`Config` 改名
using "std/os" { !Config, !Builder, ... };   // 全部，除去这几个
```

| 形态 | 名字面 |
| --- | --- |
| `{ }` | 无——改代码时的占位符，同 Go 的 `import _` |
| `{ a, b }` | 恰好这些 |
| `{ a as b }` | 恰好这些，其中一个改名 |
| `{ ... }` | 全部可见成员 |
| `{ a as b, ... }` | 全部，`a` 记作 `b` |
| `{ !a, !b, ... }` | 全部，除去 `a` 与 `b` |

1. `...` 是基集并收尾清单。与它同表的条目只能是改名或排除（`!`），不得混写；
   `...` 旁边不带 `as` 的正面条目是多余的，报错；`{ !a }` 不带 `...` 也报错。
2. 条目是 `Name` 或 `Name as Alias`，允许尾逗号。别名必须与被引标识符的大小写类一致：
   `Reader as IoReader` 合法，`Reader as reader` 报错。条目可以是 trait：`Tag as AlphaTag`
   把 `AlphaTag` 绑成 trait 名，可用于泛型约束或 trait object 类型。别名只是拼写，
   它指向的 trait 是同一个声明。
3. `as` 只改单个符号的拼写，永远不改模块——模块名不是命名空间，导入 `Reader` 后
   写 `Reader`，不写 `io.Reader`。本地路径也可以导入：`using "./util.koral" { a };`
   指以 `util.koral` 为入口的模块，不需要 manifest 登记。
4. 导入的名字是文件局部绑定，不会被再导出。
5. 撞名报错；`as` 改名、`!` 排除。诊断会说该用哪个。

##### 撞名

一个拼写只有一个属主。第二个**不同**声明占同一个拼写才是冲突——身份是声明不是名字，
同一声明经两条路径到达不算冲突。

| 导入名 vs… | 结果 |
| --- | --- |
| 本模块的顶层声明 | **报错** |
| 本文件另一条 import 的不同声明 | **报错** |
| prelude（`std` 主模块的 `List`、`Eq`、`Clone`…）的不同声明 | **报错** |
| 同一声明再次到达（同模块两个文件各写 `using "std" { ... };`） | 放行 |
| 函数内的局部 `let` | 放行——嵌套遮蔽合法 |

修法看形态：裸名字可以用 `as` 改名；`{ ... }` 清单可以用 `as`（改名）或 `!`（排除）。
诊断会说该用哪个。

```koral
using "game/render" { List };              // 报错：prelude 已占着 `List`
using "game/render" { List as RList };     // 可以
using "game/render" { ... };               // 若 render 导出 `List` 则报错
using "game/render" { !List, ... };        // 可以——丢掉它的那个
using "game/render" { Sprite };            // 可以
```

##### 方法面

导入带进来两样东西：**名字**（清单挑的）与**方法面**（这里可派发的 `given` 方法）。
方法面跟**被点名的东西**走，不跟「碰巧装着它的模块」走：

| 调用形态 | 准入 |
| --- | --- |
| `x.m(…)`，`m` 来自 `given X { … }` | **无**——有 `X` 的值即可 |
| `x.m(…)`，`m` 来自 `given X: T { … }` 或 `given T { … }` | **`T` 在作用域内** |
| `X.m(…)`（关联 / 限定形式） | **`X` 在作用域内** |

**点名类型不带来任何 trait 方法。点名 trait 在所有实现类型上打开它的方法。**

`T` 在作用域内，指下面之一：`T` 在当前文件所属模块里声明（合并进来的也算——合并消掉边界）；
`{ T }` 或 `{ T as A }` 显式导入；从 `T` 所在模块批导入且未被 `!` 排除；在 prelude 里；
出现在当前声明的泛型界里。改名仍然算：`{ T as A }` 让 `T` 不可写，但 trait 本身在作用域内，
它的方法照旧用自己的名字调。

不算的：`{ }` · 导入了模块里别的名字（`{ env }`）· **导入了类型（`{ Path }`）** · 什么都没写。

泛型**界**与导入不同：`[T: Leaf]` 让 `Leaf` 的方法对这个参数可用，**含它的超 trait**。
所以 `fn go[T: Leaf](x: T) = x.r() + x.l()` 在 `Leaf: Root` 下两个方法都能调；
而具体接收者只导入 `Leaf` 时，`x.r()` 不行。

```koral
using "std/os" { open_file, File };         // 点名了 `File`
f.read(into = buf, span = ...);               // 报错：`Reader` 不在作用域

using "std/io" { Reader };                  // 用哪个能力就点名哪个 trait
f.read(into = buf, span = ...);               // 可以

using "std/os" { read_file };               // 自由函数不需要 trait
read_file("/etc/hosts");
```

方法存在但它的 trait 不在作用域时，诊断会直说，并写出该补的那一行 `using`。

#### 解析

`using "X"` 切在第一个 `/`：

```
head = 第一段      （无 "/" 时 head = 整串）
tail = 其余        （无 "/" 时 tail = ""）
```

`head` 必须是已注册包名——**本包的 `package`、某个 `dependencies` 的键名、保留名 `std`**；
否则报「未知包名」。然后在该包的 `modules` 里查**包内名**：`tail` 为空查 `"."`，否则查 `tail`。

> **每个包用自己的表解析自己的源码**：编译 `httpr` 的文件时用 `httpr` 自己的 `package`
> 与 `dependencies`，与消费方给它起什么名字无关。所以 `dep_utils` 自己写
> `using "dep_utils/…"`，消费方写 `using "game_utils/…"`，落到同一个包。

模块图由各模块 `using` 语句的并集派生——**没有 `requires`，一处真相**。
由它得到构建排序、可达性；模块图必须无环；`links` 沿模块图传递。

**`std` 主模块是 prelude**：对非 `std` 模块，它是编译器隐式编进来并放进作用域的，
不需要写 `using`。其余模块（含 `std/io`、`std/time`）一律要显式导入。
`using "std";` 仍然合法——它是 `std` 子模块文件取得 prelude 的方式。

#### 入口文件名约束

- 模块入口文件名（不含扩展名）必须以小写字母开头；
- 其余字符只能是小写字母、数字或 `_`；
- 模块全名的每一段沿用语言标识符规则（小写开头，字母数字下划线），且不得是保留字；
- 包名是**单段**标识符，不含 `/`、不含 `.`；`/` 只用于分子路径，所以第一个 `/` 就是包 / 模块边界。

#### 访问修饰符

Koral 提供四个访问级别控制符号可见性：

| 修饰符 | 可见性 |
|----------|------------|
| `private` | 仅同一文件内可访问 |
| `internal` | 当前逻辑模块内可访问（缺省值） |
| `protected` | 同一包内任意模块可访问 |
| `public` | 任何位置可访问 |

包作用域跟随 manifest 图：root 包、`std` 和每个依赖包是彼此独立的包边界。

> **`protected` 是「包内可见」，不是「子类可见」。** Java、C++、C#、Kotlin 的
> `protected` 给子类放行；Koral 的 `protected` 给同一包内的所有模块放行——那是
> 分发边界。Koral 没有继承，子类的读法在这里不成立。（早期 Koral 材料的读者注意：
> `protected` 在本语言早期曾是模块级拼写；那个角色现在叫 `internal`。）

##### 默认访问级别

未标注的声明一律是 `internal`（模块可见）。访问修饰符只用来标注偏离缺省的声明：
`private` 收窄缺省，`protected` / `public` 放宽缺省。

| 声明 | 默认 |
|-------------|---------|
| 全局 `let`/变量、函数、类型、trait、类型别名 | `internal` |
| 结构体字段 | `internal` |
| 成员函数（`given` 块中） | `internal` |
| Trait 需求 | trait 声明的级别 |
| 枚举 case 与 case 字段 | enum 声明的级别 |
| `using` 声明 | 文件局部（导入的绑定不会被再导出） |

Trait 需求与枚举 case 是接口件：它们自己不接受访问修饰符（写了报
`Access modifier on trait method is not supported`），有效可见性随包含它们的声明。
`given` 头本身也不接受访问修饰符（写了报
`Access modifier on given declaration is not supported`），但它的成员方法可以标。

直接的结构体构造 `Type(...)` 只有在调用点所有被引用字段都可见时才允许。字段缺省是
`internal`，跨模块直接构造会报
`Cannot directly construct type 'X' because field 'a' is internal. Use a public factory method instead.`
请改用公开的工厂方法——或者像 std 的 `Pair` 这类值载体类型那样，把字段显式标成
`public`，让调用方可以直接构造。

### 项目结构示例

```
my_project/
├── koral.json;
├── main.koral           # 主模块（"."）入口;
├── utils.koral          # 合并进主模块;
├── models/
│   ├── models.koral     # "models" 入口;
│   └── user.koral       # 合并进 "models";
└── services/
    └── services.koral   # "services" 入口;
```

```json
{
  "package": "app",
  "version": "0.1.0",
  "modules": {
    ".":        { "entry": "main.koral",              "links": [] },
    "models":   { "entry": "models/models.koral",     "links": [] },
    "services": { "entry": "services/services.koral", "links": [] }
  }
}
```

```koral
// main.koral
using "./utils.koral";
using "app/models" { User };
using "app/services" { authenticate };

public let main(): Void = {
    let user = User.new("Alice");
    if authenticate(user) then {
        println("Welcome!");
    };
};
```

## 6. 外部互操作

本章汇总低层表层：raw pointer、不安全取址，以及 C 外部函数接口。

### 指针类型 (Pointer)

raw pointer 是面向 FFI 与系统编程的低层内存访问：

- `*T` —— 只读指针。支持 `*expr` 解引用读取，但**不**支持 `*expr` 赋值或 `p[i]` 赋值。
- `*mutable T` —— 可变指针。支持 `*expr` 解引用读取、`*expr = value` 赋值、`p[i]` 读取与 `p[i] = value` 赋值。
- `*mutable T` 可隐式转换为 `*T`。反向不允许。

空指针是字面量 `null`。它加入期望类型为 `*T` 或 `*mutable T` 的位置——元素类型任意，
包括类型参数——并可与指针做 `==` / `!=` 比较：

```koral
let p: *Int = null;
let m: *mutable Int = null;
if p == null then { ... };
if m != null then { *m = 42; };
```

`null` 也可以作为字面量模式匹配——`p is null`、`p is not null`，或 `when` 分支
`null then …`（字面量模式本身不穷尽，`when` 仍需兜底分支）——并可填充指针类型的
默认值（`let f(p: *Int = null): Int = …`、`type Node(p: *Int = null)`）。
在 `as` 下，`null as UInt` 是零地址；`null as *Int` / `null as *mutable T`
把空指针转成对应指针类型，而 `null as ?Box` 报错——弱句柄没有空拼写。
没有指针类型可加入的 `null` 报 `Cannot infer a pointer type for 'null': add a
type annotation`；期望类型不是指针时报 `Type mismatch: expected <T>, got null`。
`null` 是硬关键字（与 `true` / `false` 同级），不能作为标识符重新绑定。

指针重解释写作 `expr as Type`。`*mutable T` 可以直接看作 `*T`（`p as *T`），
指针也可以一步换元素类型重读（`p as *UInt`），指针与整数地址双向互通
（`p as UInt` / `u as *Int`）。强转结果调用方法要加括号：
`(self as *T).equals(other as *T)`。

括号类型头在表达式位置命名同一个目标：`(*Foo).f()` 在 `*Foo` 的方法面上找 `f`，
正如 `(Point).origin()` 就是 `Point.origin()`、`(Point)(1, 2)` 就是 `Point(1, 2)`。
类型位的括号是恰好一个类型的透明分组——`let p: (*Int)` 就是 `let p: *Int`，
`let f: ((Int) -> Int) = g` 标注函数值——写在括号外的前缀作用于整组：`*(Int)` 是
`*Int`，而 `*(Int) -> Int` 是函数类型 `(Int) -> Int` 的指针。

旧的类型构造拼写一律拒绝。`*Int(u)` 现在读作算子链 `*(Int(u))`，`?Box(b)` 读作
`?(Box(b))`，只报算子语义的自然错误；括号 / 别名调用形 `(*Int)(u)`、`(?Box)(b)`、
`MyPtr(u)` 报 `Pointer and weak casts are written 'expr as Type', not 'Type(expr)'`，
`UInt(p)` 报 `Pointer and integer casts are written 'expr as Type', not 'Type(expr)'`。

### 不安全取址与解引用

`&` / `&mutable` 是 raw 取址操作符。它们要求可取地址的存储；字面量和临时值会被拒绝。

```koral
let p: *Int = &value;
let mp: *mutable UInt8 = &mutable bytes[0];

let x = *p;       // raw 解引用读取
*mp = 42;         // raw 解引用写入
let q = &value as *Int;   // (&value) as *Int：as 覆盖整个前缀表达式

// let bad = & 42  // error: raw 取址需要可取地址的存储
```

规则：

- `&` 产生 `*T`；`&mutable` 产生 `*mutable T`。
- `*expr` 读取与 `*expr = value` 写入是 raw 解引用形态。
- `as` 松于前缀算子：`&x as *T` 是 `(&x) as *T`，`*p as *Int` 是 `(*p) as *Int`。
- raw pointer 不是「任意类型到 `*T`」的通用桥：标准库中交出 raw pointer 的辅助接口要求元素类型满足 `foreign` 形状约束（见「泛型约束」一节）。

### 外部函数接口

Koral 通过 `foreign` 关键字支持与 C 互操作。

#### 链接外部库

原生库在 `koral.json` / `std/koral.json` 的包或模块 `links` 中声明：

```json
{
  "modules": {
    ".": { "entry": "main.koral", "links": ["m"] }
  }
}
```

编译器从解析出的 manifest 图添加链接参数。`libc` 默认隐式链接，无需声明。

> **限定词写在哪。** `foreign` 与 `intrinsic` 写在**关键字紧后**——`let foreign`、
> `type foreign`、`type intrinsic`、`given intrinsic`——也就是 `type mutable` 与
> `let mutable` 已经占住的那个位置。访问修饰符是唯一的**前缀**修饰符：它们说的是
> 「谁看得见这个声明」，不是「声明的是个什么东西」。两者互斥，且排在 `mutable` 之前
> （`mutable` 描述绑定）：`let foreign mutable errno: Int32;`。

#### Foreign 函数

声明外部 C 函数。foreign 函数只使用位置参数；不支持命名参数（`=` 标记）。
**体的存在性定方向**：无体是引用（extern 链接），有体是定义——C ABI 导出函数。

```koral
let foreign sin(x: Float64): Float64;                    // 引用：链接 C 的 sin
let foreign "CreateFileA" create_file(path: *UInt8): UInt32;  // 引用 + C 名
let foreign add_one(x: Int32): Int32 = {                 // 定义：导出给 C
    return x + Int32(1);
};
```

- **C 名槽位**：字符串写在 `foreign` 之后、Koral 名之前，是这条声明**在 C 世界的名字**。
  标识符只属于 Koral 名字空间；外来词汇（C 符号名、宏名）是字符串。不写即 Koral 名逐字——
  此时 Koral 名本身必须是合法 C 标识符，否则编译器报错并指路槽位。给了槽位，两个名字
  就各归各：Koral 名保持值命名法，撞 C 关键字也无妨——各叫各的。
- 有体（导出）的签名限制与无体**完全相同**：封闭集合、位置参数、无泛型。
  它在 Koral 侧可直接调用，名字作值的类型是 `foreign (A) -> R`——可作为回调传给 C。
- 可见性（`public` / `internal` / …）只管 Koral 侧名字；**C 符号恒导出**（C 没有模块可见性）。
- panic 跨导出边界不展开栈：打印 + `abort()`。

#### Foreign 变量

体/初值的存在性 + `mutable` 定形态：

```koral
let foreign mutable errno: Int32;            // 引用：extern 可变量
let foreign stdin: *CFile;                   // 引用：裸 `extern`（Koral 侧可变性是语言层检查，不写 `const`）
let foreign mutable counter: Int32 = 0;      // 定义：C 变量（静态初始化器）
let foreign "AF_INET6" af_inet6: Int32 = 10; // 宏常量：值绑定，无存储、无符号
```

- 初值只收**常量字面量**（可带负号 / `null`）——C 的静态初始化器必须是常量表达式。
- 有初值 + 无 `mutable` 是 **C 宏常量**的值绑定：值从 C 头文件复制，不产生 C 实体
  （宏无链接符号）；C 名槽位记宏名，仅作对应标注。值是**手抄**的——没有任何机制
  核对它与宏的真实值，头文件改值不会有任何信号；头文件变了要人手复核这条绑定。

#### 边界类型

能过 `let foreign` 函数边界的类型是编译器定的封闭集合——参数与返回类型必须是：

- 内建标量；`Void` / `Never` 只在**返回位**合法——C 没有
  void 值，参数位不收它们；`foreign (Void) -> R` 也只是把零参指针写错了拼写；
- raw pointer `*T` / `*mutable T`，**且 pointee 也得在集合内**——`*Box`、`*Void`
  可以，`*Bad`、`*(closure)` 不行：raw pointer 能过边界只到它指向的东西为止；
- 藏在 `*` 后面的 `type foreign` 句柄（不透明 `type foreign CFile {}` 只以
  `*CFile` 出现——它没有布局，字段、全局量、函数指针组件都不能按值持有它）；
- 组件同规则的 `foreign (A) -> R` 函数指针。

Koral `type`、闭包、托管引用永远不跨界——按值或隔着指针都不行。`type foreign`
结构体与 `[N]T` 数组**只在全局量位按值跨界**（`let foreign v: KoralTimespec;`）：
foreign 全局量是 C 直接读取的布局对象，而函数参数/返回写 `*T`（C 数组参数的真身
就是指针）。

> **`*Void` 就是 `void*`。** `*Void` / `*mutable Void` 是 C `void*` 的拼写，在
> 每个边界上都合法——参数、返回、函数指针组件、全局量与 `type foreign` 字段。

#### Foreign 类型

声明外部 C 类型：

```koral
// 不透明类型（无字段）
type foreign CFile {};

// 同一类东西，用它在 C 世界的名字
type foreign "FILE" CFileHandle {};

// 与 C 布局对齐的 FFI 结构体
type foreign "timespec" KoralTimespec(tv_sec: Int64, tv_nsec: Int64);
```

规则就是 C 的规则，用 Koral 的拼写：

- **C 名槽位**与 `let foreign` 完全同一条规则（同一拼写、同一校验）：它是这条类型
  **在 C 世界的名字**——结构体形态是 C 的 struct tag（`"timespec"` 就让它是
  `struct timespec`），不透明形态是 C 类型自己的拼写（`"FILE"` 就让它是 `FILE`）。
  真实 C 类型由此原样过界：include 属主头文件的 shim 遇到的是同一个 tag、同一个类型。
  带 C 名的不透明类型归 C 侧声明——导出头**不**代为声明，因此要在 `koral_exports.h`
  之前 include 属主头文件。不写即 Koral 名逐字，且 Koral 名本身必须是合法 C 标识符。
- foreign 类型不能声明为 `mutable`——可变性属于 Koral 自己的 nominal 声明——也不接受泛型参数。
- 字段只收裸 `name: Type`：位置字段，没有访问修饰符、`mutable` 标记、命名字段、默认值。C 布局是公开且恒可写的；改不了什么的标记只会撒谎。
- 每个字段类型都必须能过 FFI 边界——内建标量、指向它们（或 `Void`，即 C 的 `void*`）的 `*` / `*mutable` 指针、或另一个 `type foreign` 声明：与 `foreign` 约束那组封闭集合相同。不透明 `type foreign X {}` 仍只出现在 `*` 后——它没有可存储的布局。禁止直接自递归（写 `*Self`）。
- foreign 值是**可变值语义**：赋值与传参按值拷贝。方法里的 `self` 就是这样一个拷贝，所以没有可变 self——要改接收者就收 `*mutable T` 参数。
- 显式 `Drop` 被拒绝：C 值没有析构（代码生成用纯 C 赋值拷贝它、drop 是空操作）。

就地写入（`x.v = value`、`x.a.b = value`）与所有值类型同一套矩阵：

| 写入路径 | 允许 |
| --- | --- |
| `let mutable` 绑定 | ✓ |
| `mutable` 参数（本地拷贝——**不写回**） | ✓ |
| `*mutable T` 链接（指针的**类型**说了算，不是绑定） | ✓ |
| `type mutable` 对象的 `mutable` 字段（任何够到对象的路径） | ✓ |
| `let` 绑定、普通参数、`self`、`*T` 链接、临时值 | ✗ |

链中段出现只读句柄（`*T`）会重置其后整段的写权限。`&mutable` / `&mutable expr` 构造 `*mutable T`，要求目标属于上面可写的形式。

#### 定长数组

`[N]T` 是 C 布局的 N 元定长数组：可变值语义（赋值与传参按值拷贝；`a[i] = v` 与上面同一套写入矩阵）。数字下标做越界检查：下标只求值一次，越界时 panic，不会读到相邻内存。元素 `T` 必须过 FFI 边界——内建标量、`*` / `*mutable` 指针、另一个 `type foreign` 等封闭集合内的类型。

```koral
type foreign Buf(data: [4]Int32, len: Int32);

let main(): Int = {
    let mutable a: [4]Int32 = [1, 2, 3, 4];   // 恰好 N 个元素
    let mutable z: [4]Int32 = [];             // 全零缓冲
    a[2] = Int32(9);                          // 下标写入存储
    let p: *Int32 = &a[0];                    // 元素地址
    return 0;
};
```

- 非空字面量恰好 N 个元素；`[]` 是全零缓冲。
- `a[i]` 读写都做越界检查（`*T` 的下标才是不查边界的 C 下标）；`[N]T` 不能过 FFI 函数边界
  （`let foreign` 的参数/返回写 `*T`——那才是 C 数组参数的真身）。

#### Foreign 函数类型

`foreign (T) -> R` 是裸 C 函数指针。它**不是** Koral 闭包：只有 `let foreign` 函数和同类型值能住进它，`null` 与 `*T` 同款加入。

```koral
let foreign abs(x: Int32): Int32;

let main(): Int = {
    let f: foreign (Int32) -> Int32 = abs;    // `let foreign` 函数
    let cb: foreign (Int32) -> Int32 = null;  // 可为 null，同 *T
    if cb != null then {
        println(f(Int32(-1)).to_string());
    };
    return 0;
};
```

- 调用只用位置参数、直呼 C。签名的每个组件都必须按 `let foreign` 参数/返回的同一套规则过 FFI 边界（见[边界类型](#边界类型)）。
- lambda 或 Koral 函数值是闭包，不做转换；赋值进去就是普通的类型不匹配。

### Intrinsic 声明

`intrinsic` 关键字声明编译器内建的类型和函数：

```koral
type intrinsic Int;
```

intrinsic 保留给标准库使用。

## 附录：标准库最小常用示例

把这些作为日常编程的最小积木：

```koral
// List（共享对象——独立副本用 clone()）
let nums: List[Int] = [1, 2, 3];

// Dict
let scores: Dict[String, Int] = ["alice": 10, "bob": 8];

// Set
let tags: Set[String] = ["koral", "lang"];

// Option + or else / and then
let port = Option[Int].Some(8080) or else 80;
let doubled = Option[Int].Some(21) and then as v in v * 2;

// or return
let read_number(path: String): Result[Int] = {
    let text = read_text_file(path) or return;
    return Int.parse(text);
};

// Result（错误侧是 Error trait object）
let ok = Result[Int].Ok(42);
let err = Result[Int].Error("failed");

// 增量构建 String
let sb = StringBuilder.new();
sb.push_string("built");
let s = sb.to_string();

// 闭包的共享可变状态
let counter = Cell(0);
counter.value = counter.value + 1;
```

完整 API 参考见 `docs/api/std/` 下的文档。
