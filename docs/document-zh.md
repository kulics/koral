# Koral 编程语言

Koral 是一个专注于性能、可读性和实用跨平台开发的开源编程语言。

通过精心设计的语法规则，这门语言可以有效降低读写负担，让你能够把真正的注意力放在解决问题上。

规范说明：

- 本文档是面向用户的语言参考手册。
- 涉及文法细节时，请配合 `docs/grammar.bnf` 一起阅读。
- 如果本文档、BNF 与实现出现不一致，请更新实现和/或文档，使三者收敛。

本手册按学习路线组织：**语言基本元素**，到**控制流**，到**自定义类型**，到**模式匹配**，到**抽象设计**，最后是**外部互操作**。

## 概述

### 关键特性

- 现代、易扫读的语法：显式分号 + 表达式化的控制流，`if`、`when`、`while`、`for` 都使用表达式形态的表层语法。`if` 与 `when` 可以产生值；`while` 与 `for` 总是产生 `Void`。
- 由声明处类型语义驱动的自动内存管理：浅层不可变的 `type` 与共享的 `type mutable` 对象。布局与生命周期细节由编译器负责。
- 带 trait 约束的泛型与单态化，实现零成本抽象。
- 代数数据类型（结构体与枚举）配合穷举性模式匹配。
- 基于 trait 的多态，trait object 提供运行期分发。
- 一等函数、lambda 与闭包。
- 多范式编程（函数式与命令式结合）。
- 带访问控制的模块系统（`public` / `package_private` / `module_private` / `file_private`）。
- 外部函数接口（FFI），与 C 平滑互操作。
- C 后端，具备广泛的平台兼容性。

### 核心理念：`type` / `type mutable`

Koral 的 nominal 类型只有两种形态，在声明处决定。语言里的其他一切——别名、可变性与布局——都由这一个决定推导而来。

**`type` —— 浅层不可变的 nominal 类型。**

- 构造后字段不可修改，也不能声明 `mutable` 字段。
- **没有 identity**：字段相同的两个值可以互换。
- **内存布局由编译器决定**。内联存储、隐藏间接层、共享 backing 都是实现细节，版本之间可能不同。
- **值语义不属于语言契约**。复制、传参与存储可以共享 backing。正因该类型浅层不可变，这种共享不可观察——所以编译器可以自由地把它优化掉。

**`type mutable` —— 共享对象类型。**

- 有 identity：赋值与传参交出的是**同一个**对象的句柄。
- 字段默认不可变；只有显式声明为 `mutable` 的字段才能原地修改，而且只能经由共享句柄进行。

```koral
type Point(x Int, y Int);

type mutable Counter(mutable value Int, id UInt);

let p = Point(1, 2);
// p.x = 3;      // error: Point 是 `type`，字段不可变

let c = Counter(0, 1);
c.value = 5;      // ok: Counter 是 `type mutable` 且 `value` 是 mutable 字段
// c.id = 2;     // error: `id` 不是 mutable 字段
```

编译器可能在内部对两种形态使用引用计数与隐藏存储。这些都不是用户可见语义：语言契约是 `type` 与 `type mutable` 之分，绝不是某种托管引用语法。

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
    koralc build --package-config koral.json --target-module app::main;
    ```
3.  **仅做类型检查**：
    ```bash
    koralc check --package-config koral.json --target-module app::main;
    ```
4.  **编译并运行**：用 `run` 一步完成编译与执行。
    ```bash
    koralc run --package-config koral.json --target-module app::main;
    ```
5.  **仅生成 C**：用 `emit-c` 生成 C 源码。
    ```bash
    koralc emit-c --package-config koral.json --target-module app::main -o out;
    ```

常用选项：

- `-o, --output <dir>`：输出目录
- `--package-config <path>`：从包 manifest 构建
- `--target-module <name>`：选择 manifest 中的目标模块
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

let fib(n Int) Int = {
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
let main() Void = {};
```

这里声明了一个名为 `main` 的函数。`=` 右侧是函数体，`{}` 表示空的块表达式，返回 `Void`。

`main` 函数必须：

- 没有参数。
- 返回 `Int` 或 `Void`。

```koral
let main() Int = {
    println("Hello");
    return 0;
};
```

#### 显示信息

标准库提供 `println` 函数，把一行文本打印到标准输出。

```koral
let main() Void = println("Hello, world!");
```

试着执行这个程序，就能在控制台看到 `Hello, world!`。

#### 注释

注释是编译器忽略的代码部分，用来给读代码的人提供说明。

```koral
// 这是单行注释，从双斜杠开始直到行尾

/*
    这是块注释。;
    它可以跨越多行。;
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

### 值与字面量

完成大部分工作只需要少数几种基本类型。

#### 布尔

布尔指逻辑值，只能是 true 或 false。默认布尔类型是 `Bool`。

```koral
let b1 Bool = true;
let b2 Bool = false;
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
let i Int = 3987349;
let f Float64 = 3.14;
let b UInt8 = 255;
```

数值字面量支持用下划线 `_` 作分隔符以提高可读性：

```koral
let million = 1_000_000;
let pi = 3.141_592_653;
```

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

注意：指数写法只支持小写 `e`，与 `0b`/`0o`/`0x` 前缀的约定一致。

#### Duration 字面量

Duration 支持整数字面量后缀：

```koral
let a = 10s;
let b = 250ms;
let e = 150us;
let f = 42ns;
```

支持的后缀为 `s`、`ms`、`us`、`ns`。时长字面量是 `Duration` 构造的语法糖——`10s` 等价于 `Duration.new(seconds: 10, nanoseconds: 0)`——并且结果已自动解包。负时长保持一元负号语义（例如 `-5s` 解析为对 `5s` 施加一元 `-`）。

#### 数值转换

不同数值类型之间需要显式转换，使用 `expr(Type)` 语法：

```koral
let a Int = 42;
let b Float64 = a(Float64);    // Int -> Float64
let c Int32 = a(Int32);        // Int -> Int32
let d UInt8 = 255(UInt8);      // Int -> UInt8
```

#### 字符串

在 Koral 中，字符串用于表示文本数据。`String` 类型是 UTF-8 编码的字符序列。

字符串字面量只使用双引号 `""`。

```koral
let s1 String = "Hello, world!";
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
    """
// 等价于 "Hello, Koral!\nWelcome to multiline strings."

let name = "World";
let greeting = """
    Hello, \(name)!
    Have a great day.
    """
// 等价于 "Hello, World!\nHave a great day."
```

结尾 `"""` 的缩进决定剥离量：

```koral
let s = """
        indented content
        second line
    """
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
s.replace_all("World", with: "Koral"); // "Hello, Koral!"
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
let r Rune = 'A';
let nl Rune = '\n';
let smile Rune = '\u{1F600}';
```

Rune 字面量的类型规则：

- 默认类型是 `Rune`。
- 在显式的 `UInt8` 上下文中，如果它是单个 ASCII 字符，可以推断为字节（`UInt8`）。

#### 集合字面量

Koral 为三种内建集合类型提供字面量：`List[T]`、`Set[T]`、`Dict[K, V]`。

```koral
let a = [1, 2, 3];                    // 推断为 List[Int]
let b Set[Int] = [1, 2, 3];           // 由上下文推断为 Set[Int]
let c = ["x": 1, "y": 2];             // 推断为 Dict[String, Int]
let empty List[Int] = [];             // 空字面量需要类型上下文
```

规则：

- `[e1, e2, ...]` 是集合字面量。没有类型上下文时推断为 `List[T]`。
- 在 `Set[T]` 上下文中，同样语法推断为 Set。
- `[k1: v1, k2: v2, ...]` 是字典字面量，推断为 `Dict[K, V]`。
- `[]` 没有类型上下文时无法推断，必须标注类型。
- 集合字面量和字典字面量都允许尾随逗号。
- 集合字面量只面向内建的 `List` / `Set` / `Dict`，不面向第三方容器类型。

`List`、`Set`、`Dict`、`Deque` 是 `type mutable` 的共享对象：不使用写时复制。修改容器对每个句柄都可见，需要独立副本时必须显式使用 `clone()`。

### 变量与绑定

Koral 的变量采用绑定语义，相当于把变量名和值绑定在一起。出于安全考虑，变量默认不可变，同时也提供可变变量。

#### 只读绑定

在 Koral 中，只读变量用 `let` 关键字声明，遵循先声明后使用的原则。

Koral 通过静态类型保证类型安全。变量绑定可以在声明时显式标注类型。当上下文信息足够时，也可以省略类型，由编译器推断变量类型。

```koral
let a Int = 5;   // 显式类型标注
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
let mutable a Int = 5;   // 显式类型标注
let mutable b = 123;     // 自动类型推断
```

#### Pair 解构绑定

当右侧表达式是 `Pair` 时，可以用圆括号语法把每个元素绑定到独立变量。每个绑定位置支持 `_`（丢弃）、`mutable`（可变）和可选的类型标注。

```koral
let (a, b) = (1, 2);                  // 类型推断
let (c Int, d String) = (3, "hello");  // 显式类型标注
let (mutable e, f) = (10, 20);             // 可变绑定
let (_, g) = (1, 2);                   // 丢弃第一个元素
```

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
- 块可以在末尾带一个不写分号的尾表达式。
- 如果块带有尾表达式，块的类型和值就是该表达式的类型和值。
- 如果块没有尾表达式，或最后一个表达式写了分号，块的类型是 `Void`。
- `return`、`break`、`continue` 可以提前结束块，因此让该块的类型是 `Never`。
- 裸 `break`（不带表达式）退出最近的 `while` 或 `for` 循环。
- 以 `return`、`break` 或 `continue` 结尾的块类型为 `Never`。

示例：

```koral
let load(path String) Result[Int] = {
    let text = read_text_file(path) or return;
    return parse_int(text);
};

let increment() Int = {
    let base = 41;
    base + 1
};

let a Void = {};
let main() Void = {
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

比较操作符比较两个值，结果是 `Bool` 类型。注意不等于写作 `<>`。

```koral
let a = 4;
let b = 2;
println( a == b );     // == 等于
println( a <> b );     // <> 不等于
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
1..;      // 1 <= x（右无界，含起点）
1<..;     // 1 < x（右无界，不含起点）
..5;      // x <= 5（左无界，含终点）
..<5;     // x < 5（左无界，不含终点）
..;       // 全范围
```

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

#### 运算符优先级

运算符优先级从高到低：

1. 后缀：调用 `()`、下标 `[]`、成员访问 `.`、限定路径 `Type(Trait)`、泛型方法后缀
2. 前缀 / 控制流：一元 `-`、`~`、解引用 `*`、raw 取址 `&unsafe`、`&unsafe mutable`；`if`、`while`、`for`、`when`
3. 乘除：`*`、`/`、`%`
4. 加减：`+`、`-`
5. 移位：`<<`、`>>`
6. 按位与：`&`
7. 按位异或：`^`
8. 按位或：`|`
9. 比较：`==`、`<>`、`<`、`>`、`<=`、`>=`
10. 范围：`..`、`..<`、`<..`、`<..<`
11. 模式测试：`is`、`is not`
12. 逻辑非：`not`
13. 可选链：`and then`
14. 逻辑与：`and`
15. 值合并 / 早返回传播：`or else`、`or return`
16. 逻辑或：`or`

在同一表达式中混用 `and then`、`or else` 与 `or return` 时，请用圆括号让意图明确。

### 函数

函数是完成特定任务的独立代码块。

#### 定义

函数用 `let` 关键字定义。函数名后跟 `()` 表示参数，圆括号后跟返回类型。具名函数和方法必须显式写出返回类型。

`=` 右侧必须是表达式，该表达式的值就是函数的返回值。

```koral
let f1() Int = 1;
let f2(a Int) Int = a + 1;
let f3(a Int) Int = a + 1;
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

声明为 `name Type`（无冒号）。位置参数必须**按位置**传入——绝不能带标签。

```koral
let add(x Int, y Int) Int = x + y;
let a = add(1, 2); // a == 3
```

##### 命名参数

声明为 `name: Type`（带冒号）。命名参数必须**带标签**调用。

```koral
let connect(host String, port: Int) Void = {};
connect("localhost", port: 8080);
```

##### 混合规则

参数的声明形态唯一决定调用形态，没有例外：

- 声明为命名（`name: Type`）→ 调用时**必须**带标签。
- 声明为位置（`name Type`）→ 调用时**绝不能**带标签。

不存在「可选命名」的中间态：声明二选一，调用形态就唯一确定。声明中位置参数必须排在命名参数之前；调用时先按位置匹配位置参数，再按标签匹配命名参数。

```koral
type Window(title String, width: Int, height: Int);

// 位置填 'title'；命名的 'width' / 'height' 必须带标签
let w = Window("hello", width: 900, height: 600);
// Window("hello", 900, 600)                        // error: 'width' 必须带标签
// Window("hello", width: 900, height: 600, title: "x")  // error: 'title' 是位置参数
```

##### 默认值

只有命名参数可以有默认值。默认值在 `=` 之后以字面量给出：

```koral
type Config(
    count: Int = 42,
    name: String = "hello",
    enabled: Bool = true,
    ratio: Float64 = 3.14,
    ch: Rune = 'A',
    items: List[Int] = [],
    flags: Dict[String, Int] = [],
    span: Range[Int] = ..,
);
```

支持的默认值字面量：

| 种类 | 示例 |
|------|----------|
| 整数 | `0`、`42`、`-1` |
| 浮点 | `3.14`、`0.0` |
| 布尔 | `true`、`false` |
| 字符串 | `"hello"` |
| Rune | `'A'` |
| 空集合 | `[]`（List、Set 或 Dict，由类型上下文推断） |
| 空范围 | `..`（解析为 `Range[T].Full()`） |

默认值类型必须与参数类型匹配。例如 `name: String = 42` 会报错。

可变参数使用 `mutable` 关键字：

```koral
let increment(mutable x Int) Int = { x += 1; return x };
```

对普通参数而言，`mutable` 只是让函数体内的局部绑定可写。它不是函数签名的一部分，不改变函数类型，在检查 trait/given 方法兼容性时会被忽略。

##### 构造器调用

结构体、枚举和函数调用遵循同样的位置/命名规则——声明决定形态，调用照做：

```koral
type Shape {
    Circle(radius Float64),            // 位置变体参数
    Line(start: Point, end: Point),    // 命名变体参数
}

// 位置参数：按位置传入，绝不能带标签
let s1 = Shape.Circle(1.0);

// 命名参数：必须带标签（实参顺序可以重排）
let s2 = Shape.Line(end: Point(1, 1), start: Point(0, 0));
// Shape.Line(Point(0, 0), Point(1, 1))   // error: 'start' 必须带标签
```

模式匹配的解构遵循完全相同的标签规则：声明为命名的字段必须带标签匹配，声明为位置的字段绝不能带标签。

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start: p, end: e) then println(p.x),
}

if b is Button(w, height: _, label: l) then println(l);
// Button 的 `width` 是位置字段，`height` / `label` 是命名字段
```

#### 函数类型

在 Koral 中，函数也是类型。函数类型用 `Func(T1, T2, ...) R` 语法声明，其中 `T1, T2, ...` 是参数类型，`R` 是返回类型。

```koral
let square(x Int) Int = x * x;        // Func(Int) Int
let f Func(Int) Int = square;
let a = f(2);                         // a == 4
```

也可以把函数类型用作参数类型或返回类型：

```koral
let hello() Void = println("Hello, world!");
let run(f Func() Void) Void = f();
let toRun() Func(Func() Void) Void = run;

let main() Void = toRun()(hello);
```

### Lambda 与闭包

#### Lambda 表达式

Lambda 表达式与函数定义非常相似，只是把 `=` 换成 `->`，且没有函数名和 `let` 关键字。

```koral
let f1(x Int) Int = x + 1;            // Func(Int) Int
let f2 = (x Int) Int -> x + 1;        // Func(Int) Int
let a = f1(1) + f2(1);                // a == 4
```

当 lambda 的类型可以从上下文推断时，可以省略参数类型和返回类型：

```koral
let f Func(Int) Int = (x) -> x + 1;
```

Lambda 支持多种形式：

```koral
() -> 42;                           // 无参数
(x) -> x * 2;                      // 单参数，类型推断
(x Int) -> x * 2;                  // 单参数带类型
(x, y) -> x + y;                   // 多参数，类型推断
(x Int, y Int) Int -> x + y;       // 完整类型标注
(x) -> { let y = x * 2; return y + 1 };  // 块体
```

#### 闭包

Lambda 表达式可以从周围作用域捕获变量，这被称为闭包。

```koral
let make_adder(base Int) Func(Int) Int = {
    return (x) -> base + x;
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
let make_counter() Func() Int = {
    let counter = Cell(0);              // 共享可变状态
    return () -> {
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
let add = () -> { xs.push(30) };   // ok: `xs` 是共享句柄
```

#### 柯里化

闭包支持柯里化：

```koral
let add Func(Int) Func(Int) Int = (x) -> (y) -> x + y;

let add10 = add(10);
let result = add10(32);  // result == 42
let sum = add(20)(22);   // sum == 42
```

## 2. 控制流

### 条件表达式

选择结构用于判断给定条件并控制程序流程。

在 Koral 中，选择结构使用 `if` 语法。`if` 后跟判断条件。条件为 `true` 时执行 `then` 分支，为 `false` 时执行 `else` 分支。`if` 始终是表达式。同时有 `then` 和 `else` 时产生值；没有 `else` 时，单分支 `if` 产生 `Void`。

```koral
let main() Void = if 1 == 1 then println("yes") else println("no");
```

带 `else` 的 `if` 也是表达式。`then` 和 `else` 分支后必须是表达式。

```koral
let main() Void = println(if 1 == 1 then "yes" else "no");
```

由于 `if` 本身也是表达式，`else` 后自然可以再跟一个 `if` 表达式形成链式条件。

```koral
let x = 0;
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less";
```

不需要处理 `else` 分支时可以省略它。此时该结构是语句，不产生值；它的块分支仍默认为 `Void`。

```koral
let main() Void = if 1 == 1 then println("yes");
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

### 循环

#### while 语句

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

每次迭代中，迭代器产出的下一个值会尝试匹配 `pattern`。匹配成功则执行 `then` 后的语句 body。`for` 是产生 `Void` 的表达式。

```koral
let nums List[Int] = [10, 20, 30];
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

循环绑定位置接受与 `let` 相同的形态：单个绑定或 `Pair` 解构绑定。每个元素可使用 `_`、`mutable` 和可选类型标注。

```koral
let pairs List[Pair[Int, Int]] = [Pair(1, 2), Pair(3, 4)];

for (left, right) in pairs then {
    println((left + right).to_string());
};
```

#### break 和 continue

- `break`：退出循环。不能穿透最内层可退出结构（循环或分支）。
- `continue`：跳过当前迭代。

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
- 裸 `break`（不带表达式）退出最近的 `while` / `for` 循环。

`break` 不能穿透最内层可退出结构：它不能跨越分支边界到达外层循环目标。

### 用 `defer` 做清理

`defer` 语句声明一个在当前块作用域退出时执行的清理表达式。无论作用域是正常退出，还是经由 `return`、`break`、`continue` 早退，延迟表达式都会执行。

当执行走上 `Never` 终止路径（例如 `panic()`、`abort()` 或 `exit()`）并立即终止程序时，不保证执行作用域内的 `defer`。

`defer` 后跟一个表达式，其返回值被丢弃。

```koral
let main() Void = {
    println("start");
    defer println("cleanup");
    println("work");
    // 输出：start, work, cleanup
};
```

同一作用域内多条 `defer` 按声明的逆序执行（LIFO）：

```koral
let main() Void = {
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
- `and then`：可选链 / 值变换。左侧为 `Some` 或 `Ok` 时施加右侧变换。若右侧本身产出相同 kind 的 `Option` / `Result`，结果会自动拍平一层。
- `or return`：早返回传播语法糖。它解包 `Some` / `Ok`，遇到 `None` / `Error` 则从所在函数返回。

在 `and then` 与 `or else` 表达式中，关键字 `it` 指代被解包的值：对 `and then`，`it` 是内层的 `Some` 或 `Ok` 值；对作用于 `Result` 的 `or else`，`it` 是 `Error` 值。

其优先级与解析器一致：`and then` 高于逻辑 `and`；`or else` / `or return` 高于逻辑 `or`，但低于逻辑 `and`。

```koral
let opt = Option[Int].Some(42);
let val = opt or else 0;           // 42（因为 opt 是 Some）

let none = Option[Int].None();
let val2 = none or else 0;         // 0（因为 none 是 None）

let mapped = opt and then it * 2;  // Some(84)

let load_port(path String) Result[Int] = {
    let text = read_text_file(path) or return;
    return parse_int(text);
};
```

`or return` 等价于固定的 `or else` 早返回模式：

- 对 `Result`：`expr or return` 等价于 `expr or else { return .Error(it) }`
- 对 `Option`：`expr or return` 等价于 `expr or else { return .None() }`

它必须用在返回种类与被传播值匹配的函数内：

- `Result` 传播要求所在函数返回 `Result`
- `Option` 传播要求所在函数返回 `Option`

## 3. 自定义类型

Koral 提供强大的类型系统，允许你定义自己的数据结构。用 `type` 关键字定义浅层不可变的 nominal，用 `type mutable` 定义共享对象。

### `type`：浅层不可变的 Nominal

`type` 声明引入字段全部不可变的 nominal 类型。`type` 的值**没有 identity**，布局由编译器决定——内联、隐藏间接层或共享 backing 均可。不承诺值语义：拷贝可以共享存储，正因该类型浅层不可变，这种共享不可观察。

结构体字段可以是位置字段或命名字段。命名字段用冒号语法，可以带默认值。

#### 定义

```koral
type Empty();
type Point(x Int, y Int);

type Config(
    name String,               // 位置字段
    width: Int,                // 命名字段（无默认值）
    height: Int = 600,         // 带默认值的命名字段
    title: String = "Untitled" // 带默认值的命名字段
);
```

规则：

- 位置字段必须排在命名字段之前。
- 只有命名字段可以有默认值。
- 默认值必须是字面量：整数、浮点、布尔、字符串、rune、`[]`（空集合）或 `..`（空范围）。
- `type` 不能声明 `mutable` 字段，自身也不能声明为 `mutable`（`type mutable` 是另一种声明形态）。

#### 构造

使用 `()` 语法调用构造器：

```koral
let a Point = Point(0, 0);

// 命名字段带标签调用；位置字段不带标签
let c1 Config = Config("main", width: 800);
let c2 Config = Config("main", width: 800, height: 900, title: "App");
// height 与 title 使用默认值：600 与 "Untitled"
```

#### 字段访问

使用 `.` 语法访问成员变量。`type` 的字段只读：

```koral
type Point(x Int, y Int);

let main() Void = {
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
type mutable Counter(mutable value Int, id UInt);

let main() Void = {
    let c = Counter(0, 1);
    c.value = 5;  // ok，因为 Counter 是 `type mutable` 且 `value` 是 mutable 字段
    // c.id = 2;  // error: `id` 不是 mutable 字段
};
```

成员变量的可变性由类型定义决定，而不是由绑定决定：绑定到 `type mutable` 对象的只读绑定，仍可修改该对象的 `mutable` 字段。

```koral
type mutable Counter(mutable value Int);

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
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
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
let a Option[Int] = .Some(42);
let b Option[Int] = .None();

// 函数实参中
let process(opt Option[Int]) Void = when opt in {
    .Some(v) then println(v.to_string()),
    .None() then println("none"),
};
process(.Some(10));

// 赋值中
let mutable x Option[Int] = .None();
x = .Some(100);

// 条件表达式分支中
let c Option[Int] = if true then .Some(1) else .None();

// 静态方法调用——省略 List[Int] 前缀
let list List[Int] = .new();
let list2 List[Int] = .with_capacity(10);
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

let distance Meters = 100;
let add_meters(a Meters, b Meters) Meters = a + b;
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
file_private type InternalId = Int;  // 仅文件内
```

限制：

- 类型别名不支持泛型参数（如 `type Alias[T] = List[T]` 无效），但目标类型可以是泛型实例（如 `type IntList = List[Int]`）。
- 不允许循环引用（如 `type A = A`）。
- 类型别名必须以大写字母开头。
- 类型别名不能声明为 `mutable`——可变性属于 nominal 声明，而不属于别名。

### 泛型

泛型允许你编写适用于多种类型的代码，提升代码复用性。

#### 泛型数据类型

泛型数据类型用 `TypeName[T Constraint]` 语法定义泛型参数：

```koral
type Pair[T1 Any, T2 Any](left T1, right T2);
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

Pair 还支持字面量形式：

```koral
let p1 = (1, 2);               // 等价于 Pair(1, 2)
let p2 = (true, "hello");     // 等价于 Pair(true, "hello")
```

#### 泛型函数

泛型函数把类型参数写在函数名之后：

```koral
let identity[T Any](x T) T = x;

println(identity(42));       // 42
println(identity("hello"));  // hello
```

#### 泛型约束

泛型参数可以用 Trait 约束限定可接受的类型：

```koral
let max_val[T Ord](a T, b T) T = if a > b then a else b;
let contains[T Eq](list List[T], value T) Bool = list.contains(value);
```

多个约束用 `and` 连接：

```koral
let describe[T ToString and Hash](value T) String = value.to_string();
```

约束也可以使用泛型 trait 形式（例如 `Iterator[T]`），以及弱引用使用的特殊 `mutable` 约束（它要求 `type mutable` 类型，`downgrade` / `upgrade` 亦然）：

```koral
let consume[I Iterator[Int]](iter I) Void = {};
```

#### 泛型方法

`given` 块也可以定义泛型方法：

```koral
given[T Any] Option[T] {
    public map[U Any](self, f Func(T) U) Option[U] = self and then f(it);
}
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
- 在 `given Type as Trait` 块内部，`Self` 等价于 `Type`。
- `Self` 可以出现在 trait/given 上下文中的方法参数类型、返回类型和字段类型里。

```koral
trait Eq {
    equals(self, other Self) Bool;
};

type Point(x Int, y Int);

given Point as Eq {
    // 这里 Self 解析为 Point，所以 `other Self` 与 `other Point` 相同。
    equals(self, other Point) Bool = self.x == other.x and self.y == other.y;
};
```

### 内存与资源

Koral 通过声明处类型语义与编译器管理的布局，提供高效且安全的内存管理。

#### 内存模型

- **`type`**（浅层不可变）：没有 identity，也不承诺值语义。编译器可以使用栈槽、寄存器、内联存储、隐藏堆块或引用计数——任何它能证明正确的方式——因为它引入的共享无法被观察。
- **`type mutable`**（共享对象）：identity 是语义的一部分。赋值与传参共享同一个对象。只有显式声明为 `mutable` 的字段才能原地修改。
- **raw pointer**：`&unsafe` / `&unsafe mutable` 只从可取地址的存储形成 raw pointer。它们是面向 FFI 的低层内存访问，仍受地址稳定性与布局稳定性约束（见[外部互操作](#6-外部互操作)）。
- **引用计数是实现细节。** 编译器可能在两种形态内部使用 ARC 与隐藏存储。语言契约是 `type` 与 `type mutable` 之分，绝不是某种托管引用语法。

#### `Drop`

需要清理步骤的类型实现 `Drop` trait：

```koral
trait Drop {
    drop(self) Void;
};
```

`Drop.drop` 是仅由编译器调用的析构入口，运行在 finalization 上下文中。它不能作为普通用户方法调用。实现 `Drop` 的类型必然是引用计数的，其 `drop` 在最后一个持有句柄消亡时触发。

#### `clone()`

共享对象从不隐式复制。确实需要独立副本时，用 `clone()` 显式索取：

```koral
trait Clone {
    clone(self) Self;
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

用 `downgrade(T)` 生成 `?T`，用 `upgrade(?T)` 尝试升级回 `Option[T]`。

```koral
type mutable Node(mutable value Int);

let node = Node(42);
let weak = downgrade(node);      // ?Node
let upgraded = upgrade(weak);    // Option[Node]
```

## 4. 模式匹配

Koral 具备强大的模式匹配能力，主要通过 `when` 表达式和 `is` 操作符使用。模式也是 `if` / `while` 条件和 `for` 循环里的绑定形态。

### 模式形态

支持的模式包括：

- 通配模式：`_`（匹配任意值）
- 字面量模式：`1`、`-5`、`"abc"`、`'a'`、`true`（支持 `-5` 这类负整数字面量）
- 变量绑定模式：`x`（匹配任意值并绑定到 x）、`mutable x`（可变绑定）
- 比较模式：`> 5`、`< 0`、`>= 10`、`<= -1`
- 结构体解构模式：`Point(x, y)`、`Rect(Point(a, b), w, h)`
- Pair 解构模式：`(a, b)`（等价于 `Pair(a, b)` 模式）
- 枚举变体模式：`.Some(v)`、`.None()`
- trait object 精确类型模式：`IoError`、`err IoError`
- 逻辑模式：`pattern and pattern`、`pattern or pattern`、`not pattern`

解构遵循与调用完全相同的标签规则：声明为命名的字段必须带标签匹配，声明为位置的字段绝不能带标签。

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start: p, end: e) then println(p.x),
};

if b is Button(w, height: _, label: l) then println(l);
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
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
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
type Point(x Int, y Int);
type Rect(origin Point, width Int, height Int);

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
    render(self) String;
};

type IoError(code Int);

given IoError as Problem {
    render(self) String = "io";
};

let err Problem = IoError(7);
when err in {
    io IoError then println(io.render()),
    _ then println("other"),
};

// 通配符与字面量字段匹配
when p in {
    Point(0, y) then println(y),  // 第一个字段为 0 时匹配
    Point(_, y) then println(y),  // 忽略第一个字段
};

// 泛型结构体解构
type Box[T Any](val T);
let b = Box[Int](42);
when b in {
    Box(v) then println(v),  // 42
};
```

### `is` 测试

`is` 操作符检查一个值是否匹配某个模式，结果始终是 `Bool`。它是通用表达式，可以出现在 `let` 初始化、返回表达式、函数实参等表达式位置。

`is not` 是取反形式，返回相反的匹配结果。

用在 `if` 或 `while` 语句的条件中时，成功的 `is` 匹配还可以把模式中的变量绑定到当前作用域。在这些条件上下文之外，`is` 只能做布尔测试，不能引入绑定。`when ... in` 结构使用自己对匹配值的模式匹配，不通过 `is` 绑定。

`is` 直接接受单个模式。如果需要在 `is` 下使用逻辑模式组合子，请显式加圆括号，以便解析器将其与表达式级的 `and` / `or` / `not` 区分开。

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

if x is (0 or 1) then {
    println("small");
};

// 条件中仍可使用标准布尔组合
if opt is .Some(v) and v > 0 then {
    println(v);
};
```

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
if x is (0 or 1) then {
    println("small");
};
```

### 穷举性检查

`when` 表达式会检查模式是否穷尽：

- 对 `Bool` 类型，必须覆盖 `true` 与 `false`（或使用通配符）。
- 对 `enum` 类型，必须覆盖所有变体（或使用通配符）。
- 对 `Int` / `UInt` 类型，比较模式（`> 0`、`<= 0` 等）在完全覆盖整数范围时可构成穷举；否则需要通配符。
- 对结构体类型，所有字段均为通配符的 `StructName(_, _)` 形式视为穷尽。
- 重复模式在编译期被拒绝。
- 不可达模式（已被前面分支覆盖的模式）在编译期被拒绝。通配符和变量绑定模式豁免此检查。

```koral
// 通过比较模式穷尽
let classify(x Int) Int = when x in {
    > 0 then 1,
    <= 0 then 0,
};
```

### 精确类型模式

trait object 还支持通过模式系统做实现类型的精确测试。

```koral
trait Problem {
    render(self) String;
};

type IoError(code Int);
type NetError(code Int);

given IoError as Problem {
    render(self) String = "io";
};

given NetError as Problem {
    render(self) String = "net";
};

let err Problem = IoError(7);

if err is IoError then {
    println("io");
};

if err is io IoError then {
    println(io.render());
};

let label = when err in {
    io IoError then io.render(),
    _ then "other",
};
```

规则：

- 精确类型模式只在主体是 trait object 时有效。
- 目标必须是具体类型名。
- 匹配按实现类型及其泛型实参精确进行。
- 主体保持为 trait object；不会自动解引用到底层实现值。`err is io IoError` 把 `io` 绑定为 `IoError`。
- 这些模式是开放世界测试；在 `when` 中它们不算穷举覆盖，因此仍需默认 `_` 分支。

## 5. 抽象设计

Koral 用 Trait 定义共享行为，类似其他语言的接口或类型类。

### Trait 与 `given` 块

#### 定义 Trait

Trait 定义一组方法签名，任何实现类型都必须提供。

```koral
trait Printable {
    to_string(self) String;
};
```

Trait 支持用父 Trait 名称做继承：

```koral
trait Ord Eq {
    compare(self, other Self) Int;
};
```

多个父 Trait 用 `and` 连接：

```koral
trait MyTrait Eq and Hash {
    my_method(self) Int;
};
```

#### 实现 Trait

用 `given Type as Trait { ... }` 实现块为特定类型实现 Trait：

```koral
trait Eq {
    equals(self, other Self) Bool;
};

trait Ord Eq {
    compare(self, other Self) Int;
};

type Point(x Int, y Int);

given Point as Eq {
    equals(self, other Point) Bool = self.x == other.x and self.y == other.y;
};

given Point as Ord {
    compare(self, other Point) Int = self.x - other.x;
};
```

说明：

- `given Type as Trait` 是显式实现入口。
- 父/子 trait 逐级实现：实现 `Ord` 不会隐式实现 `Eq`。

#### Trait 与实现中的命名参数

Trait 方法支持命名参数。实现必须与 trait 的参数分类一致：

- 如果 trait 方法参数是命名的（`name: Type`），实现也必须声明为命名。
- 如果 trait 方法参数是位置的（`name Type`），实现也必须声明为位置。

trait 与 given 的默认值规则：

- 如果 trait 为某个命名参数声明了默认值，given 实现**不得**重复声明。trait 是默认值的唯一来源。
- 如果 trait 没有声明默认值，given 实现**不能**补加。

```koral
trait Drawable {
    draw(self, color: String, thickness: Int) String;
};

type Circle(radius Int);

given Circle as Drawable {
    // 'color' 与 'thickness' 是命名参数，与 trait 一致
    draw(self, color: String, thickness: Int) String = color + thickness.to_string();
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
    equals(self, other Self) Bool;
};

given Eq {
    not_equals(self, other Self) Bool = not self.equals(other);
};

type Num(x Int);

given Num as Eq {
    equals(self, other Num) Bool = self.x == other.x;
};

let a = Num(1);
let b = Num(2);
println(a.not_equals(b));
```

带约束的工具块示例：

```koral
trait Cursor[T Any] {
    next(self) Option[T];
};

given[T Ord] Cursor[T] {
    max(self) Option[T] = {
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

- 泛型约束上下文（如 `[T Trait]`）
- trait object 上下文
- 显式实现该 trait 的具体类型

#### 覆盖与冲突规则

- 工具方法默认不可覆盖其他候选。
- 类型自身方法优先于 trait 工具方法。
- 如果多个 trait 工具来源提供同名同签名方法，Koral 不会隐式选择；必须使用完全限定调用显式消歧，例如 `Type(TraitName).method(value, ...)`。
- 如果两个 trait 都定义了同名方法，且其中一个继承自另一个，则子 trait 的实现优先，不会形成歧义。
- `given Trait` 中不允许与该 trait requirement 同名同签名的方法。

#### Trait 继承规则

- trait 可以继承一个或多个父 trait：`trait Child Parent1 and Parent2 { ... }`。
- trait 继承必须无环；环在编译期检出并拒绝。
- 实现子 trait 的类型也必须实现全部父 trait（直接实现或通过 `given` 块）。

#### 模块边界规则

边界锚定规则：

- `given Trait { ... }` 只允许出现在该 trait 的 root 模块子树内。
- `given Type { ... }` 只允许出现在该类型的 root 模块子树内。
- `given Type as Trait { ... }` 遵循孤儿规则：类型或 trait 至少一个必须是当前 root 模块的本地定义。
- 不允许跨 crate 注入。

### 完全限定调用

当出现同名候选冲突时，可使用完全限定调用。写法等价于 Rust 的限定路径 `<Type as Trait>::method`：

- `Type(TraitName).method(...)` 选取 `Type` 上 `TraitName` 的方法
- 泛型 trait 的实参写在限定里：`Type(TraitName[Args...]).method(...)`
- 泛型方法的类型参数仍写在方法名后：`Type(TraitName).method[TypeArgs...](...)`

写法只有一种：实例方法的 receiver 就是第一个实参，因此实例方法与静态 trait 方法的写法完全一致：

```
Type(TraitName).method(receiver, ...)   // 实例方法
Type(TraitName).static_method(...)      // 静态 trait 方法
```

```koral
trait Tag {
    value(self) Int;
};

given Tag {
    plus_ten(self) Int = self.value() + 10;
    kind(self) Int = 42;
};

type Num(x Int);

given Num as Tag {
    value(self) Int = self.x;
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

- 目标类型是 trait 名。
- 源值必须实现该 trait，并转换到该 trait object 上下文。
- 不需要 `Object` 标记 trait。

```koral
trait Drawable {
    draw(self) String;
};

type Circle(radius Int);

given Circle as Drawable {
    draw(self) String = "Drawing circle";
};

let shape Drawable = Circle(10);
shape.draw();
```

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
    message(self) String;
};

// 非 object-safe——不能用作 trait object
trait Eq {
    equals(self, other Self) Bool;
};
```

trait object 上的实现类型精确测试见[精确类型模式](#精确类型模式)。

### 运算符重载

Koral 支持基于 trait 的算术与比较运算符重载。下标是内建的，不可由用户重载。

内建运算符映射为：

- `+` -> `Add[R]`，经由 `add(self, other R) Self`
- `-`（二元）-> `Sub[R]`，经由 `sub(self, other R) Self`
- `-`（一元）-> `Neg`，经由 `neg(self) Self`
- `*` -> `Mul[R]`，经由 `mul(self, other R) Self`
- `/` -> `Div[R]`，经由 `div(self, other R) Self`
- `%` -> `Rem[R]`，经由 `rem(self, other R) Self`
- `==` / `<>` -> `Eq`，经由 `equals(self, other Self) Bool`
- `<` / `>` / `<=` / `>=` -> `Ord`，经由 `compare(self, other Self) Int`

同方向链式序比较（如 `a < b < c`）是这些既有比较运算符的语法糖。编译器把它们降级为两两比较，具备单次求值和短路语义；不会引入独立的 trait 或分发机制。

位运算符（`&`、`|`、`^`、`~`、`<<`、`>>`）目前是内建的，不通过公开运算符 trait 定制。

```koral
type Vec2(x Int, y Int);

given Vec2 as Add[Vec2] {
    add(self, other Vec2) Vec2 = Vec2(self.x + other.x, self.y + other.y);
};

given Vec2 as Neg {
    neg(self) Vec2 = Vec2(-self.x, -self.y);
};

given Vec2 as Eq {
    equals(self, other Vec2) Bool = self.x == other.x and self.y == other.y;
};

given Vec2 as Ord {
    compare(self, other Vec2) Int =
        if self.x <> other.x then self.x.compare(other.x) else self.y.compare(other.y);
};

let sum = Vec2(1, 2) + Vec2(3, 4);
let flipped = -sum;
let same = sum == Vec2(4, 6);
let ordered = Vec2(1, 0) < Vec2(2, 0);
```

#### 内建下标规则

- `value[key]` 与 `value[key] = expr` 只支持 `String`、`List[T]`、`Deque[T]`、`*unsafe T` 与 `*unsafe mutable T`。
- `String[key]` 返回 `UInt8` 字节值。只读且不可取址。
- `List[T]` 与 `Deque[T]`（均为 `type mutable`）支持值读取、赋值与嵌套 place 更新。
- `*unsafe T` 只支持 `*expr` 读取。`*unsafe mutable T` 同时支持 `*expr` 读写。
- 用户自定义类型不能通过 trait 实现 `[]`，泛型约束也不能增加下标能力。

```koral
let list = [10, 20, 30];
println(list[0]);
list[1] = 99;

let text = "abc";
let b UInt8 = text[1];

let p *unsafe mutable Int = alloc_memory[Int](2);
p[0] = list[0];
let first = p[0];
dealloc_memory(p);
```

### 扩展方法

`given` 块也可以直接为类型添加方法：

```koral
given Point {
    public distance(self) Float64 = {
        let dx = self.x(Float64);
        let dy = self.y(Float64);
        return dx + dy; // ...
    };

    // 不带 self 的方法通过类型名调用
    public origin() Point = Point(0, 0);
};

let p = Point.origin();
```

### 标准库核心 Trait

最常用的核心 trait 有：

- `Add[R]` / `Sub[R]` / `Neg` / `Mul[R]` / `Div[R]` / `Rem[R]`：算术运算符 trait。
- `Eq` / `Ord`：相等与排序。
- `Hash`：dict/set 键的哈希支持。
- `ToString`：转换为字符串。
- `Clone`：显式浅拷贝（`clone(self) Self`）。
- `Iterator[T]`：迭代协议（`next(self) Option[T]`）。
- `Error`：错误消息接口（`message(self) String`）。
- `Drop`：析构钩子（`drop(self) Void`）。

算术与比较运算符在内部会降级为 trait 方法（例如 `+` 对应 `Add`）。下标由内建编译器规则解析，不走公开 trait。

### 模块与可见性

Koral 提供强大的模块系统，用于跨多个文件和目录组织代码。

#### 模块概念

Koral 中的**模块**是声明在 `koral.json`（标准库则是 `std/koral.json`）中的显式构建单元。模块由入口文件，加上经 `using "path"` 合并进来的所有文件组成。

- **目标模块**：由 `--target-module` 选定的模块
- **同级模块**：同一包内由 manifest 声明的另一个模块
- **外部模块**：来自 std 或其他包依赖的模块
- 顶层 manifest 的 `entry`：默认目标模块名，例如 `app::main`

入口文件名约束：

- 模块入口文件名（不含扩展名）必须以小写字母开头。
- 其余字符只能是小写字母、数字或 `_`。
- 源码层模块名来自 manifest，使用 `::` 分隔（例如 `app::models`、`std::io`）。

#### Using 声明

`using` 关键字用于文件合并和显式符号导入。所有 `using` 声明必须出现在文件开头，在任何其他声明之前。

##### 文件合并

用字符串语法把另一个文件合并进当前模块作用域：

```koral
using "utils";        // 把 utils.koral 合并进当前模块
using "./helpers";    // 允许相对路径
using "../shared/format";
```

文件合并规则：

1. 路径相对于当前文件所在目录解析。
2. 字符串命名不带 `.koral` 后缀的源文件。
3. 允许 `.`、`..` 这类相对片段。
4. 文件合并不创建命名空间、别名或导出面。
5. 合并进来的文件共享同一模块作用域，因此 `module_private` 声明在该模块的各文件间可见。

##### 模块符号导入

用显式花括号从其他模块导入可见符号：

```koral
using std::io { Reader };
using std::json { parse, Value };
using std::io { Reader as IoReader, Writer };
using std::io { .. };
```

说明：

1. `using module { symbol-list }` 导入对导入文件可见的符号：来自任意包的 `public`，以及导入方同包时的 `package_private`。
2. `as` 作用于每个被导入符号，而不是模块本身。导入别名绑定的是原声明——不会创建新实体。
3. `using module { .. }` 导入对导入文件可见的全部符号，且 `..` 必须单独出现。
4. 被导入的名字是文件局部绑定，不会自动再导出。
5. 模块合法性对照 manifest 的 `requires` 检查；编译器不从目录结构推断模块。
6. 非 `std` 包会自动获得 `std`；不要在应用/测试包的 manifest 里手动列出 `std`。
7. 模块导入从不把模块名绑定为命名空间对象。用 `using std::io { Reader }` 导入 `Reader` 后写 `Reader`，而不是 `std.io.Reader` 或 `io.Reader`。

#### 访问修饰符

Koral 提供四个访问级别控制符号可见性：

| 修饰符 | 可见性 |
|----------|------------|
| `public` | 任何位置可访问 |
| `package_private` | 同一包内任意模块可访问 |
| `module_private` | 当前逻辑模块内可访问 |
| `file_private` | 仅同一文件内可访问 |

包作用域跟随 manifest 图：root 包、`std` 和每个依赖包是彼此独立的包边界。

##### 默认访问级别

| 声明 | 默认 |
|-------------|---------|
| 全局函数、变量、类型 | `module_private` |
| 结构体字段 | `public` |
| 枚举构造器字段 | `public` |
| 成员函数（`given` 块中） | `module_private` |
| Trait 方法 | `public` |

直接的结构体构造 `Type(...)` 只有在调用点所有被引用字段都可见时才允许。
如果类型含有不可访问的 `file_private`/`module_private`/`package_private` 字段，请使用公开的工厂方法。

### 项目结构示例

```
my_project/
├── koral.json;
├── main.koral           # app::main 入口;
├── utils.koral          # 合并进 app::main;
├── models/
│   ├── models.koral     # app::models 入口;
│   └── user.koral       # 合并进 app::models;
└── services/
    └── services.koral   # app::services 入口;
```

```json
{
  "name": "MyProject",
  "version": "0.1.0",
  "entry": "app::main",
  "modules": {
    "app::main": {
      "entry": "main.koral",
      "requires": ["app::models", "app::services"],
      "links": [];
    },
    "app::models": {
      "entry": "models/models.koral",
      "requires": [],
      "links": [];
    },
    "app::services": {
      "entry": "services/services.koral",
      "requires": ["app::models"],
      "links": [];
    }
  }
}
```

```koral
// main.koral
using "utils";
using app::models { User };
using app::services { authenticate };
using std { .. };

public let main() Void = {
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

- `*unsafe T` —— 只读指针。支持 `*expr` 解引用读取，但**不**支持 `*expr` 赋值或 `p[i]` 赋值。
- `*unsafe mutable T` —— 可变指针。支持 `*expr` 解引用读取、`*expr = value` 赋值、`p[i]` 读取与 `p[i] = value` 赋值。
- `*unsafe mutable T` 可隐式转换为 `*unsafe T`。反向不允许。

### 不安全取址与解引用

`&unsafe` / `&unsafe mutable` 是 raw 取址操作符。它们要求可取地址的存储；字面量和临时值会被拒绝。

```koral
let p *unsafe Int = &unsafe value;
let mp *unsafe mutable UInt8 = &unsafe mutable bytes[0];

let x = *p;       // raw 解引用读取
*mp = 42;         // raw 解引用写入

// let bad = &unsafe 42  // error: raw 取址需要可取地址的存储
```

规则：

- `&unsafe` 产生 `*unsafe T`；`&unsafe mutable` 产生 `*unsafe mutable T`。
- `*expr` 读取与 `*expr = value` 写入是 raw 解引用形态。
- raw pointer 不是「任意类型到 `*unsafe T`」的通用桥：标准库中交出 raw pointer 的辅助接口只对 plain-of-data 元素类型开放。

### 外部函数接口

Koral 通过 `foreign` 关键字支持与 C 互操作。

#### 链接外部库

原生库在 `koral.json` / `std/koral.json` 的包或模块 `links` 中声明：

```json
{
  "modules": {
    "app::main": {
      "entry": "main.koral",
      "requires": [],
      "links": ["m"];
    }
  }
}
```

编译器从解析出的 manifest 图添加链接参数。`libc` 默认隐式链接，无需声明。

#### Foreign 函数

声明外部 C 函数。foreign 函数只使用位置参数；不支持命名参数（冒号语法）。

```koral
foreign let sin(x Float64) Float64;
foreign let exit(code Int) Never;
foreign let abort() Never;
```

#### Foreign 类型

声明外部 C 类型：

```koral
// 不透明类型（无字段）
foreign type CFile {};

// 与 C 布局对齐的 FFI 结构体
foreign type KoralTimespec(tv_sec Int64, tv_nsec Int64);
```

foreign 类型不能声明为 `mutable`——可变性属于 Koral 自己的 nominal 声明。

### Intrinsic 声明

`intrinsic` 关键字声明编译器内建的类型和函数：

```koral
public intrinsic type Int;
```

intrinsic 保留给标准库使用。

## 附录：标准库最小常用示例

把这些作为日常编程的最小积木：

```koral
// List（共享对象——独立副本用 clone()）
let nums List[Int] = [1, 2, 3];

// Dict
let scores Dict[String, Int] = ["alice": 10, "bob": 8];

// Set
let tags Set[String] = ["koral", "lang"];

// Option + or else / and then
let port = Option[Int].Some(8080) or else 80;
let doubled = Option[Int].Some(21) and then it * 2;

// or return
let read_number(path String) Result[Int] = {
    let text = read_text_file(path) or return;
    return parse_int(text);
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

完整 API 参考见 `docs/std/` 下的文档。
