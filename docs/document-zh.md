# Koral 编程语言

Koral 是一个专注于性能、可读性和实用跨平台开发的开源编程语言。

通过精心设计的语法规则，这门语言可以有效降低读写负担，让你能够把真正的注意力放在解决问题上。  

## 关键特性

- 现代化、易于辨识的语法，支持可选分号和表达式导向设计。
- 基于引用计数、所有权分析和逃逸分析的自动内存管理。
- 带有 Trait 约束的泛型系统，通过单态化实现零成本抽象。
- 代数数据类型（结构体与联合体）配合穷尽式模式匹配。
- 基于 Trait 的多态，支持 Trait 对象实现运行时分发。
- 一等函数、Lambda 表达式和闭包。
- 多范式编程（函数式与命令式结合）。
- 模块系统，支持访问控制（`public` / `protected` / `private`）。
- 外部函数接口（FFI），与 C 语言无缝互操作。
- C 后端，广泛的平台兼容性。

## 安装与使用

目前 `Koral` 编译器支持将源代码编译为 C 语言代码，因此在使用前请确保系统中已安装了 C 编译器（如 `gcc` 或 `clang`）。

### 编译与运行

假设你有一个名为 `hello.koral` 的文件。

1.  **编译**：执行编译器命令（假设编译器名为 `koralc`）来编译输入文件。
    ```bash
    koralc hello.koral
    ```
2.  **编译并运行**：使用 `run` 命令一步完成编译与执行。
    ```bash
    koralc run hello.koral
    ```  

## 基础语法

### 基本语句与分号

在 Koral 内，语句是最小的组成单位。

语句的基本形式如下，通常是由一小段代码组成，以分号 `;` 结尾。

```koral
let a = 0;
let b = 1;
```

一个语句通常以显式的分号结尾，但如果语句的最后一个表达式紧接着换行符，那么分号可以省略。这使得像 `if`, `while` 等结构看起来更加整洁。

```koral
// 结尾是换行，省略分号
let a = { 
    1 + 1 
} 

// 结尾是换行，省略分号
let b = 1
let c = 2
```

### 入口函数

每个可执行程序都需要一个入口点。在 Koral 中，这个入口点是 `main` 函数。一个典型的 `main` 函数声明如下。

```koral
let main() = {}
```

这里我们声明了一个名称为 `main` 的函数。`=` 右边是函数体，`{}` 表示一个空的块表达式，返回 `Void`。

`main` 函数也可以接受参数（命令行参数）并返回整数（状态码），但这取决于具体的运行环境支持。关于函数的更多细节将在之后的章节中说明。

### 显示信息

现在让我们的程序输出一些内容看看，标准库提供了 `print_line` 函数，用于向标准输出打印一行文本。

```koral
let main() = println("Hello, world!")
```

现在尝试执行这个程序，我们可以看到控制台上显示了 `Hello, world!`。

### 注释

注释是代码中被编译器忽略的部分，用于向阅读代码的人提供解释。

例如：

```koral
// 这是一个单行注释，从双斜杠开始直到行尾

/*
    这是一个块注释。
    它可以跨越多行。
    /* Koral 支持嵌套的块注释 */
*/
```

### 变量

Koral 的变量是一种绑定语义，相当于是把一个变量名和一个值绑定在一起，从而建立起了关联关系，类似于键值对。为了安全性的考虑，变量默认是不可以改变的，当然我们也提供了另一种变量——可变变量。

#### 只读变量

在 Koral 中是通过 `let` 关键字来声明只读变量的，变量遵循先声明后使用的原则。

Koral 通过静态类型确保类型安全。变量绑定可以在声明时显式标注类型。在上下文中有足够的信息时，我们也可以省略类型，编译器会从上下文中推断出变量的类型。

示例代码如下：

```koral
let a Int = 5   // 显式标注类型
let b = 123     // 自动推断类型
```

一旦只读变量被声明之后，它的值在当前作用域内就不会再被改变。

如果我们尝试对只读变量赋值，编译器会报错。

```koral
let a = 5
a = 6 // 错误
```

#### 可变变量

如果我们需要一个可以被重新赋值的变量，可以使用可变变量声明。

在 Koral 中通过 `let mut` 关键字来声明可变变量，同样遵循先声明后使用的原则。

示例代码如下：

```koral
let mut a Int = 5   // 显式标注类型
let mut b = 123     // 自动推断类型
```

### 赋值

对于可变变量，我们可以在需要的时候多次改变它的值。

Koral 的赋值语句与大多数语言一样，都使用 `=` 声明，`=` 左边必须是可以被赋值的变量，程序会将 `=` 右边的值赋值给左边的变量。

示例代码如下：

```koral
let mut a = 0
a = 1  // 合法
a = 2  // 合法
```

### 块表达式

在 Koral 中，`{}` 表示一个块表达式，块表达式可以包含一系列语句。要从块中产生一个值，需要使用 `yield` 关键字作为块的最后一条语句。如果没有 `yield`，块的类型为 `Void`。

通过块表达式可以组合一系列操作，比如多步初始化某个复杂的值。

```koral
let a Void = {}
let b Int = {
    let c = 7
    let d = c + 14
    yield (c + 3) * 5 + d / 3  // 使用 yield 显式指定块的值
}
```

`yield` 必须是块中的最后一条语句。以 `return`、`break` 或 `continue` 结尾的块类型为 `Never`。没有 `yield` 或控制转移的块类型为 `Void`。

### 标识符

标识符就是给变量、函数、类型等指定的名字。构成标识符的字母均有一定的规范，这门语言中标识符的命名规则如下：

1. 区分大小写。Myname 与 myname 是两个不同的标识符。
2. **类型**（Type）和**构造器**（Constructor）必须以**大写字母**开头（如 `Int`, `String`, `Point`）。
3. **变量**、**函数**、**成员**必须以**小写字母**或下划线开头（如 `main`, `print_line`, `x`）。
4. 标识符中其他字符可以是下划线 `_` 、字母或数字。
5. 在同一个 `{}` 内，不能重复定义相同名称的标识符。
6. 在不同 `{}` 内，可以定义重名的标识符，语言会优先选择当前范围内定义的标识符。

## 基础类型

我们只需要一些简单的基础类型，就可以开展大部分工作。

### 数值类型

由于我们目前的计算机结构比较擅长计算整数，因此一个独立的整数类型有助于提升程序的运行效率。

Koral 提供了丰富的数值类型来满足不同的需求。
在 Koral 中，默认的整数为 `Int` 类型，它可以表示有符号整数类型数据。
在 Koral 中，浮点数使用 `Float64` 类型（64 位）或 `Float32` 类型（32 位）。

- `Int`: 平台相关的有符号整数（通常是 64 位）。
- `UInt`: 平台相关的无符号整数（通常是 64 位）。
- `Int8`, `Int16`, `Int32`, `Int64`: 固定宽度的有符号整数。
- `UInt8`, `UInt16`, `UInt32`, `UInt64`: 固定宽度的无符号整数。
- `Float32`: 32 位浮点数。
- `Float64`: 64 位浮点数。

```koral
let i Int = 3987349
let f Float64 = 3.14
let b UInt8 = 255
```

数值字面量支持使用下划线 `_` 分隔数字以提高可读性：

```koral
let million = 1_000_000
let pi = 3.141_592_653
```

Koral 还支持二进制、八进制和十六进制整数字面量，分别使用 `0b`、`0o`、`0x` 前缀：

```koral
let bin = 0b1010          // 二进制，值为 10
let oct = 0o755           // 八进制，值为 493
let hex = 0xFF            // 十六进制，值为 255
```

非十进制字面量同样支持下划线分隔符：

```koral
let mask = 0xFF_FF        // 十六进制，值为 65535
let flags = 0b1010_0101   // 二进制，值为 165
```

注意：非十进制字面量仅支持整数，不支持浮点数。十六进制字母大小写均可（`0xABcd` 等价于 `0xabCD`）。

### 类型转换

不同数值类型之间需要显式转换，使用 `(Type)expr` 语法：

```koral
let a Int = 42
let b Float64 = (Float64)a    // Int -> Float64
let c Int32 = (Int32)a        // Int -> Int32
let d UInt8 = (UInt8)255      // Int -> UInt8
```

### 字符串

我们并不是生活在一个只有数字的世界，所以我们也非常需要使用文字来显示我们需要的信息。

在本语言中，字符串用于表示文本数据。 `String` 类型，它是一个 UTF-8 编码的字符序列数据。

你可以使用双引号 `""` 或单引号 `''` 包裹一段文字内容，它就会被识别为字符串值。

```koral
let s1 String = "Hello, world!"
let s2 String = 'Hello, world!' // 和 s1 相同
```

Koral 支持字符串插值，允许在字符串中嵌入表达式，使用 `\(expr)` 语法：

```koral
let name = "Koral"
let count = 3
println("Hello, \(name)!")                    // Hello, Koral!
println("Count: \(count)")                    // Count: 3
println("Mixed \(name) has \(count) messages") // Mixed Koral has 3 messages
println("Sum \(1 + (2 * 3))")                 // Sum 7
```

转义字符使用反斜杠 `\`：

```koral
"\n"   // 换行
"\t"   // 制表符
"\r"   // 回车
"\v"   // 垂直制表符
"\f"   // 换页
"\0"   // 空字符
"\\"   // 反斜杠
"\""   // 双引号
"\'"   // 单引号
```

常用的 String 方法：

```koral
let s = "Hello, World!"
s.count()                    // 13 - 字节长度
s.is_empty()                 // false
s.contains("World")          // true
s.starts_with("Hello")       // true
s.ends_with("!")             // true
s.to_ascii_lowercase()       // "hello, world!"
s.to_ascii_uppercase()       // "HELLO, WORLD!"
s.trim_ascii()               // 去除首尾空白
s.slice(0..<5)               // "Hello" - 切片
s.find("World")              // Some(7)
s.replace_all("World", "Koral") // "Hello, Koral!"
s.split(",")                 // 按分隔符分割
s.lines()                    // 按行分割

// 拼接字符串列表
join_strings(list, ", ")     // 用分隔符拼接 [String]List
```

### 布尔

布尔指逻辑上的值，它们只能是真或者假。它经常用以辅助判断逻辑。

在本语言中，默认的布尔为 `Bool` 类型，它是一个只有两个可能的值 `true`（真）和 `false`（假）的类型。

```koral
let b1 Bool = true
let b2 Bool = false
let isGreater = 5 > 3 // 结果为 true
```

### 引用类型 (Reference)

引用类型用于引用另一个值，而不是持有它。这在需要共享数据或避免复制时非常有用。在类型名称后加上 `ref` 关键字即可声明引用类型。

使用 `ref` 表达式可以创建一个引用：

```koral
let a = ref 42           // 创建一个 Int ref
let b = deref a          // 解引用，得到 42
println(ref_count(a)) // 引用计数
```

引用使用引用计数自动管理内存。当引用计数降为零时，内存自动释放。

#### 弱引用

弱引用不会增加引用计数，用于打破循环引用。使用 `weakref` 类型后缀声明：

```koral
let strong = ref 42
let weak = downgrade_ref(strong)   // 降级为弱引用
let upgraded = upgrade_ref(weak)   // 尝试升级，返回 Option
```

### 内存管理

Koral 旨在提供高效且安全的内存管理。它结合了自动内存管理和手动控制的优点。

- **值语义（Value Semantics）**：默认情况下，Koral 中的类型（如 `Int`, 结构体）具有值语义。这意味着在赋值或传递参数时，数据会被复制。
- **引用（Reference）**：使用 `ref` 关键字可以创建引用。Koral 使用引用计数和所有权分析来自动管理引用的生命周期，防止悬垂指针和内存泄漏。
- **所有权转移（Move Semantics）**：对于没有执行复制操作的变量，赋值和传参操作会导致所有权转移（Move）。一旦所有权被转移，原来的变量就不能再被使用了。

## 操作符

操作符是一种告诉编译器执行特定的数学或逻辑操作的符号。

### 算术操作符

算数操作符主要被使用在数字类型的数据运算上，大部分声明符合数学中的预期。

```koral
let a = 4
let b = 2
println( a + b )    // + 加
println( a - b )    // - 减
println( a * b )    // * 乘
println( a / b )    // / 除
println( a % b )    // % 取余
```

### 比较操作符

比较操作符用于比较两个值的大小关系，结果为 `Bool` 类型。注意不等于使用 `<>` 表示。

```koral
let a = 4
let b = 2
println( a == b )     // == 等于
println( a <> b )     // <> 不等于 
println( a > b )      // > 大于
println( a >= b )     // >= 大于或等于
println( a < b )      // < 小于
println( a <= b )     // <= 小于或等于
```

### 逻辑操作符

逻辑操作符主要被用来对两个 Bool 类型的操作数进行逻辑运算（与、或、非）。

```koral
let a = true
let b = false
println( a and b )       // 与，两者同时为真才为真
println( a or b )        // 或，两者其中一者为真就为真
println( not a )         // 非，布尔值取反
```

其中，`and` 和 `or` 具有短路语义。

```koral
let a = false and f() // 不会执行 f()
let b = true or f()   // 不会执行 f()
```

### 位操作符

位操作符主要用于对两个整数类型的操作数进行位运算。

```koral
let a = 4
let b = 2
println( a & b )    // 按位与
println( a | b )    // 按位或
println( a ^ b )    // 按位异或
println( ~a )       // 按位取反
println( a << b )   // 左移
println( a >> b )   // 右移
```

### 范围操作符

范围操作符用于生成一个范围（Range），常用于循环或模式匹配。

```koral
1..5     // 1 <= x <= 5 (闭区间)
1..<5    // 1 <= x < 5  (右开区间)
1<..5    // 1 < x <= 5  (左开区间)
1<..<5   // 1 < x < 5   (开区间)
1...     // 1 <= x      (右无界，包含起始)
1<...    // 1 < x       (右无界，不含起始)
...5     // x <= 5      (左无界，包含结束)
...<5    // x < 5       (左无界，不含结束)
....     // 全范围
```

### 复合赋值

Koral 支持常见的算术复合赋值，而且同时支持位运算复合赋值。

```koral
let mut x = 10
x += 5       // x = x + 5
x -= 2       // x = x - 2
x *= 3       // x = x * 3
x /= 2       // x = x / 2
x %= 4       // x = x % 4

let mut y = 12
y &= 10     // y = y & 10
y |= 1      // y = y | 1
y ^= 15     // y = y ^ 15
y <<= 1     // y = y << 1
y >>= 2     // y = y >> 2
```

### 值合并与可选链

Koral 提供了两个特殊的操作符用于处理 `Option` 和 `Result` 类型：

- `or else`：值合并，当左侧为 `None` 或 `Error` 时返回右侧的默认值。
- `and then`：可选链/值变换，当左侧为 `Some` 或 `Ok` 时对内部值应用右侧的变换。

```koral
let opt = [Int]Option.Some(42)
let val = opt or else 0           // 42（因为 opt 是 Some）

let none = [Int]Option.None()
let val2 = none or else 0         // 0（因为 none 是 None）

let mapped = opt and then _ * 2   // Some(84)
```

### 运算符优先级

操作符优先级从高到低如下：

1. 前缀: `not`, `~`, 类型转换 `(Type)expr`
2. 乘除: `*`, `/`, `%`
3. 加减: `+`, `-`
4. 移位: `<<`, `>>`
5. 关系: `<`, `>`, `<=`, `>=`
6. 相等: `==`, `<>`
7. 按位与: `&`
8. 按位异或: `^`
9. 按位或: `|`
10. 范围: `..`, `..<`, `<..`, `<..<`, `...`, `<...`, `...<`, `....`
11. 逻辑与: `and`
12. 可选链: `and then`
13. 逻辑或: `or`
14. 值合并: `or else`

## 选择结构

选择结构用于判断给定的条件，根据判断的结果来控制程序的流程。

在 Koral 中选择结构使用 `if` 语法表示，`if` 后面紧跟判断条件，在条件为 `true` 时执行条件后面的 `then` 分支，在条件为 `false` 时执行 `else` 关键字后面的 `else` 分支。

例如：

```koral
let main() = if 1 == 1 then println("yes") else println("no")
```

执行上面的程序会看到 `yes`。

`if` 同样也是表达式，`then` 和 `else` 分支后面都必须是表达式，根据 `if` 的条件，`if` 表达式的值可能是 `then` 或 `else` 分支其中的一个。

因此上面那段程序我们也可以这样写，两种写法结果等价。

```koral
let main() = println(if 1 == 1 then "yes" else "no")
```

由于 `if` 本身也是表达式，因此 `else` 后面自然也可以接另外一个 `if` 表达式，这样我们就可以实现连续的条件判断。

```koral
let x = 0
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less"
```

当我们不需要处理 `else` 分支时，可以省略 `else` 分支，这时它的值是 `Void`。

```koral
let main() = if 1 == 1 then println("yes")
```

### if is 模式匹配

`if` 还支持 `is` 模式匹配语法，可以在条件判断的同时解构值：

```koral
let opt = [Int]Option.Some(42)
if opt is .Some(v) then {
    println(v)  // 42
} else {
    println("None")
}
```

### let 表达式

`let` 也可以作为表达式使用，它允许你在计算后面的表达式之前绑定一个变量。这个变量的作用域仅限于 `then` 后面的表达式。

```koral
// val 仅在 if 表达式中可见
let val = get_value() then if val > 0 then {
    // val > 0 时的代码
} else {
    // val <= 0 时的代码
}
```

## 循环结构

循环结构是指在程序中需要反复执行某个功能而设置的一种程序结构。

### while 表达式

在 Koral 中循环结构使用 `while` 语法表示，`while` 后面紧跟判断条件，在条件为 `true` 时执行后面表达式，然后重新回到判断条件处进行判断进入下一轮循环，在条件为 `false` 结束循环。`while` 也是一个表达式。

```koral
let mut i = 0
while i < 10 then {
    println(i)
    i += 1
}
```

#### while is 模式匹配

`while` 也支持 `is` 模式匹配，常用于迭代器循环：

```koral
let mut iter = list.iterator()
while iter.next() is .Some(v) then {
    println(v)
}
```

### break 和 continue

- `break`: 退出循环。
- `continue`: 跳过当前迭代。

```koral
let mut i = 0
while true then {
    if i > 20 then break
    if i % 2 == 0 then { i += 1; continue }
    println(i)
    i += 1
}
```

### for 循环

`for` 循环用于遍历任何实现了迭代器接口的对象（如列表、Map、Set、范围等）。

每次迭代，迭代器产生的下一个值会尝试匹配 `pattern`，如果匹配成功，则执行 `then` 后面的表达式。

```koral
// 遍历列表
let mut list = [Int]List.new()
list.push(10)
list.push(20)
list.push(30)

for x = list then {
    println(x)
}

// 遍历 Map
let mut map = [String, Int]Map.new()
map.insert("a", 1)
map.insert("b", 2)

for entry = map then {
    print(entry.key)
    print(" -> ")
    println(entry.value)
}

// 遍历 Set
let mut set = [Int]Set.new()
set.insert(100)
set.insert(200)

for v = set then {
    println(v)
}
```

### defer 语句

`defer` 语句用于声明在当前块作用域退出时执行的清理表达式。无论作用域是正常退出还是通过 `return`、`break`、`continue` 提前退出，`defer` 表达式都会被执行。

当执行 `Never` 终止路径（例如 `panic()`、`abort()`、`exit()`）并导致程序直接终止时，不保证执行当前作用域中的 `defer`。

`defer` 后面跟一个表达式，该表达式的返回值会被丢弃。

```koral
let main() = {
    println("start")
    defer println("cleanup")
    println("work")
    // 输出: start, work, cleanup
}
```

同一作用域内的多个 `defer` 按声明的逆序（LIFO）执行：

```koral
let main() = {
    defer println("first")
    defer println("second")
    defer println("third")
    // 输出: third, second, first
}
```

`defer` 绑定到声明它的块作用域，而非函数作用域。在循环中，`defer` 会在每次迭代结束时执行：

```koral
let mut i = 0
while i < 3 then {
    i += 1
    defer println("cleanup")
    println(i)
    // 每次迭代输出: i 的值, cleanup
}
```

`defer` 表达式也可以是块表达式：

```koral
defer {
    println("cleaning up")
    close(handle)
}
```

#### 限制

- `defer` 表达式内部不允许使用 `return`、`break`、`continue`。
- `defer` 表达式内部不允许嵌套 `defer`。
- `defer` 不是异常栈展开机制；在 `panic/abort/exit` 等 `Never` 终止路径上不保证执行。
- 以上限制不穿透 Lambda 边界——Lambda 内部拥有独立的作用域。

## 模式匹配

Koral 拥有强大的模式匹配功能，主要通过 `when` 表达式和 `is` 操作符使用。

### when 表达式

`when` 表达式允许你将一个值与一系列模式进行比较，并根据匹配的模式执行相应的代码。它类似于其他语言中的 `switch` 语句，但功能更为强大。`when` 也是一个表达式，会返回匹配分支的值。

```koral
let x = 5
let result = when x is {
    1 then "one",
    2 then "two",
    _ then "other",
}
```

支持的模式包括：

- 通配符模式：`_`（匹配任意值）
- 字面量模式：`1`, `"abc"`, `true`
- 变量绑定模式：`x`（匹配任意值并绑定到 x），`mut x`（可变绑定）
- 比较模式：`> 5`, `< 0`, `>= 10`, `<= -1`
- 结构体解构模式：`Point(x, y)`, `Rect(Point(a, b), w, h)`
- 联合类型模式：`.Some(v)`, `.None`
- 逻辑模式：`pattern and pattern`, `pattern or pattern`, `not pattern`

```koral
// 联合类型匹配
type Shape {
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
}

let area = when shape is {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
}

// 比较模式
let grade = when score is {
    >= 90 then "A",
    >= 80 then "B",
    >= 70 then "C",
    _ then "F",
}

// 逻辑模式
when x is {
    1 or 2 or 3 then println("small"),
    _ then println("big"),
}

// 结构体解构模式
type Point(x Int, y Int)
type Rect(origin Point, width Int, height Int)

let p = Point(10, 20)
when p is {
    Point(x, y) then println(x + y),  // 30
}

// 嵌套结构体解构
let r = Rect(Point(1, 2), 30, 40)
when r is {
    Rect(Point(a, b), w, h) then println(a + b + w + h),  // 73
}

// 在 if...is 中使用结构体解构
if p is Point(x, y) then {
    println(x * y)  // 200
}

// 通配符和字面量字段匹配
when p is {
    Point(0, y) then println(y),       // 第一个字段为 0 时匹配
    Point(_, y) then println(y),       // 忽略第一个字段
}

// 泛型结构体解构
type [T Any]Box(val T)
let b = [Int]Box(42)
when b is {
    Box(v) then println(v),  // 42
}
```

### is 操作符

`is` 操作符用于检查一个值是否匹配某个模式，结果为 `Bool` 类型。

当在 `if` 或 `while` 等条件表达式中使用时，如果匹配成功，它还可以将模式中的变量绑定到当前作用域。

```koral
let opt = [Int]Option.Some(42)
if opt is .Some(v) then {
    println(v)  // 42
}

// 比较模式
if score is >= 60 then {
    println("passed")
}
```

## 函数

函数是用来完成特定任务的独立的代码块。

### 定义

函数通过 `let` 关键字定义，函数的名字后面使用 `()` 表示这个函数接受的参数，括号后面是这个函数的返回类型。返回类型在上下文明确时可以省略，由编译器推断返回类型。

函数的 `=` 右边必须声明一个表达式，这个表达式的值就是函数的返回值。

```koral
let f1() Int = 1
let f2(a Int) Int = a + 1
let f3(a Int) = a + 1     // 返回类型推断
```

### 调用

使用 `()` 语法调用函数：

```koral
let a = f1()
let b = f2(1)
```

### 参数

参数是函数执行时能够接收的数据。使用 `参数名 类型` 声明参数。

```koral
let add(x Int, y Int) = x + y
let a = add(1, 2) // a == 3
```

可变参数使用 `mut` 关键字标记：

```koral
let increment(mut x Int) = { x += 1; return x }
```

### 函数类型

在 Koral 中，函数也是一种类型。函数的类型使用 `[T1, T2, ..., R]Func` 语法声明，其中 `T1, T2, ...` 是参数类型，`R` 是返回类型。

```koral
let sqrt(x Int) = x * x          // [Int, Int]Func
let f [Int, Int]Func = sqrt
let a = f(2)                      // a == 4
```

利用这个特性，我们也可以定义函数类型的参数或者返回值。

```koral
let hello() = println("Hello, world!")
let run(f [Void]Func) = f()
let toRun() = run

let main() = toRun()(hello)
```

### Lambda 表达式

Lambda 表达式与函数定义很相似，只是 `=` 换成了 `->`，并且没有函数名和 let 关键字。

```koral
let f1(x Int) Int = x + 1            // [Int, Int]Func
let f2 = (x Int) Int -> x + 1        // [Int, Int]Func
let a = f1(1) + f2(1)                // a == 4
```

在上下文中可以得知 lambda 的类型时，可以省略参数类型和返回类型：

```koral
let f [Int, Int]Func = (x) -> x + 1
```

Lambda 支持多种形式：

```koral
() -> 42                           // 无参数
(x) -> x * 2                      // 单参数，类型推断
(x Int) -> x * 2                  // 单参数，显式类型
(x, y) -> x + y                   // 多参数，类型推断
(x Int, y Int) Int -> x + y       // 完整类型标注
(x) -> { let y = x * 2; return y + 1 }  // 块体
```

### 闭包

Lambda 表达式可以捕获其周围作用域中的变量，这被称为闭包。

```koral
let make_adder(base Int) [Int, Int]Func = {
    return (x) -> base + x
}

let add10 = make_adder(10)
let result = add10(32)  // result == 42
```

#### 捕获规则

Koral 只允许捕获**不可变**变量。尝试捕获可变变量会导致编译错误。

```koral
let x = 10
let f = () -> x + 1  // OK: x 是不可变的

let mut y = 20
let g = () -> y + 1  // 错误: 不能捕获可变变量 'y'
```

#### 柯里化

闭包使柯里化成为可能：

```koral
let add [Int, [Int, Int]Func]Func = (x) -> (y) -> x + y

let add10 = add(10)
let result = add10(32)  // result == 42
let sum = add(20)(22)   // sum == 42
```

## 数据类型

数据类型是由一系列具有相同类型或不同类型的数据构成的数据集合，它是一种复合数据类型。

Koral 提供了强大的类型系统，允许你定义自己的数据结构。使用 `type` 关键字来定义。

### 结构体 (Product Type)

结构体用于将多个相关的值组合在一起。每个字段都有一个名称和类型。

#### 定义

```koral
type Empty()
type Point(x Int, y Int)
```

#### 构造

使用 `()` 语法调用构造器：

```koral
let a Point = Point(0, 0)
```

#### 使用成员变量

使用 `.` 语法访问成员变量：

```koral
type Point(x Int, y Int)

let main() = {
    let a = Point(64, 128)
    println(a.x)  // 64
    println(a.y)  // 128
}
```

#### 可变成员变量

成员变量默认是只读的。使用 `mut` 关键字标注可变成员变量：

```koral
type Point(mut x Int, mut y Int)

let main() = {
    let a = Point(64, 128)
    a.x = 2  // ok，因为 x 是 mut
    a.y = 0  // ok，因为 y 是 mut
}
```

成员变量的可变性跟随类型定义，与实例变量是否可变无关。

### 联合类型 (Sum Type)

联合类型允许你定义一个类型，它可以是几个不同变体（Variant）中的一个。每个变体可以携带不同类型的数据。

```koral
type Shape {
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
}

let s = Shape.Circle(1.0)
```

#### 使用联合类型值

通过模式匹配来提取联合类型变体中携带的数据：

```koral
let area = when s is {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
}
```

#### 隐式成员表达式

当期望类型已知时（例如变量声明有类型标注、函数参数有类型签名），可以省略类型名，直接使用 `.成员名` 语法构造联合类型值或调用静态方法：

```koral
// 联合类型构造 — 省略 [Int]Option 前缀
let a [Int]Option = .Some(42)
let b [Int]Option = .None()

// 函数参数中使用
let process(opt [Int]Option) Void = when opt is {
    .Some(v) then println(v.to_string()),
    .None then println("none"),
}
process(.Some(10))

// 赋值中使用
let mut x [Int]Option = .None()
x = .Some(100)

// 条件表达式分支中使用
let c [Int]Option = if true then .Some(1) else .None()

// 静态方法调用 — 省略 [Int]List 前缀
let list [Int]List = .new()
let list2 [Int]List = .with_capacity(10)
```

> 隐式成员表达式要求编译器能从上下文推断出期望类型。如果没有类型标注，编译器会报错。

### 类型别名 (Type Alias)

类型别名允许你为已有类型定义一个新名称，提高代码可读性。使用 `type AliasName = TargetType` 语法声明。

```koral
type Meters = Int
type Coord = Point
type IntList = [Int]List
```

类型别名在编译时被完全消除，别名与目标类型完全等价：

```koral
type Meters = Int

let distance Meters = 100
let add_meters(a Meters, b Meters) Meters = a + b
let result = add_meters(distance, 50)  // result == 150
```

别名可以链式定义：

```koral
type Meters = Int
type Distance = Meters  // Distance 最终解析为 Int
```

类型别名支持访问修饰符：

```koral
public type Meters = Int       // 公开
private type InternalId = Int  // 仅文件内可见
```

限制：
- 类型别名不支持泛型参数（如 `type [T]Alias = [T]List` 不合法），但目标类型可以是泛型实例化类型（如 `type IntList = [Int]List`）。
- 不允许循环引用（如 `type A = A`）。

## Trait 与 Given

Koral 采用 Trait（特征）来定义共享的行为。这类似于其他语言中的接口（Interface）或类型类（Type Class）。

### 定义 Trait

Trait 定义了一组方法签名，任何实现了该 Trait 的类型都必须提供这些方法的具体实现。

```koral
trait Printable {
    to_string(self) String
}
```

Trait 支持继承，使用父 Trait 名称声明：

```koral
trait Ord Eq {
    compare(self, other Self) Int
}
```

多个父 Trait 使用 `and` 连接：

```koral
trait MyTrait Eq and Hashable {
    my_method(self) Int
}
```

### 实现 Trait (Given)

使用 `given` 关键字为特定类型实现 Trait：

```koral
given Point {
    equals(self, other Point) Bool = self.x == other.x and self.y == other.y
    compare(self, other Point) Int = self.x - other.x
}
```

### 扩展方法

`given` 块不仅可以用于实现 Trait，还可以直接用于为类型添加方法：

```koral
given Point {
    public distance(self) Float64 = {
        let dx = (Float64)self.x
        let dy = (Float64)self.y
        return dx + dy // ...
    }
    
    // 不包含 self 的方法，通过类型名调用
    public origin() Point = Point(0, 0)
}

let p = Point.origin()
```

### 标准库核心 Trait

Koral 标准库定义了以下核心 Trait：

| Trait | 说明 | 方法 |
|-------|------|------|
| `Eq` | 相等比较 | `equals(self, other Self) Bool` |
| `Ord` | 排序比较（继承 Eq） | `compare(self, other Self) Int` |
| `Hashable` | 哈希（继承 Eq） | `hash(self) UInt` |
| `ToString` | 字符串转换 | `to_string(self) String` |
| `[T]Iterator` | 迭代器 | `next(self ref) [T]Option` |
| `[T, R]Iterable` | 可迭代 | `iterator(self) R` |
| `Add` | 加法 | `add(self, other Self) Self`, `zero() Self` |
| `Sub` | 减法（继承 Add） | `sub(self, other Self) Self`, `neg(self) Self` |
| `Mul` | 乘法 | `mul(self, other Self) Self`, `one() Self` |
| `Div` | 除法（继承 Mul） | `div(self, other Self) Self` |
| `Rem` | 取余（继承 Div） | `rem(self, other Self) Self` |
| `[K, V]Index` | 下标读取 | `at(self, key K) V` |
| `[K, V]MutIndex` | 下标写入（继承 Index） | `set_at(self ref, key K, value V) Void` |
| `Error` | 错误接口 | `message(self) String` |
| `Deref` | 解引用控制（内置） | *（阻止对 trait object 解引用）* |

算术操作符会自动降级为对应的 Trait 方法调用：
- `+` → `Add.add`
- `-` → `Sub.sub`
- `*` → `Mul.mul`
- `/` → `Div.div`
- `%` → `Rem.rem`
- `a[k]` → `Index.at`
- `a[k] = v` → `MutIndex.set_at`

### Trait Object

Trait Object 是 Koral 中实现运行时多态（动态派发）的机制。通过 `TraitName ref` 语法，可以将实现了某个 Trait 的任意类型擦除为统一的引用类型。

#### 基本语法

使用 `ref` 关键字将具体类型转换为 trait object：

```koral
trait Drawable {
    draw(self) String
}

type Circle(radius Int)
type Square(side Int)

given Circle { public draw(self) String = "Drawing circle" }
given Square { public draw(self) String = "Drawing square" }

// 创建 trait object
let shape Drawable ref = ref Circle(10)

// 通过 trait object 调用方法（动态派发）
shape.draw()  // "Drawing circle"
```

#### 对象安全性

只有满足以下条件的 Trait 才能用作 trait object：

- 方法不能有泛型参数
- 方法的参数和返回值中不能出现 `Self` 类型（接收者 `self` 除外）

```koral
// 对象安全 — 可以用作 trait object
trait Error {
    message(self) String
}

// 不是对象安全 — 不能用作 trait object
trait Eq {
    equals(self, other Self) Bool  // Self 出现在参数中
}
```

#### Error Trait 与 Result

标准库定义了 `Error` trait，任何实现了 `message(self) String` 方法的类型都可以作为错误类型使用：

```koral
trait Error {
    message(self) String
}

// String 默认实现了 Error trait
given String {
    public message(self) String = self
}
```

`Result` 类型使用 `Error ref`（trait object）作为错误端，只需要一个泛型参数：

```koral
type [T Any] Result {
    Ok(value T),
    Error(error Error ref),
}

// 使用字符串作为错误
let result = [Int]Result.Error(ref "something went wrong")

// 读取错误信息
when result is {
    .Ok(v) then println(v.to_string()),
    .Error(e) then println(e.message()),
}

// 便捷方法
result.unwrap_error().message()  // "something went wrong"
```

#### Deref Trait

`Deref` 是内置 trait，用于控制解引用行为。Trait object（`TraitName ref`）不实现 `Deref`，因此不能被解引用，这保证了 trait object 始终通过引用使用。

## 泛型

泛型允许你编写适用于多种类型的代码，从而提高代码的复用性。

### 泛型数据类型

泛型数据类型在标识符的前面使用 `[T Constraint]` 语法定义泛型参数：

```koral
type [T1 Any, T2 Any]Pair(left T1, right T2)
```

构造泛型数据类型时，在泛型参数的位置传入实际的类型：

```koral
let a1 = [Int, Int]Pair(1, 2)
let a2 = [Bool, String]Pair(true, "hello")
```

当上下文类型明确时，可以省略泛型类型参数：

```koral
let a1 = Pair(1, 2)           // 推断为 [Int, Int]Pair
let a2 = Pair(true, "hello")  // 推断为 [Bool, String]Pair
```

### 泛型函数

泛型函数在函数名前面使用相同的语法定义泛型参数：

```koral
let [T Any]identity(x T) T = x

println(identity(42))       // 42
println(identity("hello"))  // hello
```

### 泛型约束

泛型参数可以指定 Trait 约束，限制可接受的类型：

```koral
let [T Ord]max_val(a T, b T) T = if a > b then a else b
let [T Eq]contains(list [T]List, value T) Bool = list.contains(value)
```

多个约束使用 `and` 连接：

```koral
let [T ToString and Hashable]describe(value T) String = value.to_string()
```

### 泛型方法

`given` 块中也可以定义泛型方法：

```koral
given [T Any] [T]Option {
    public [U Any]map(self, f [T, U]Func) [U]Option = self and then f(_)
}
```

## 标准库集合类型

### List

`[T]List` 是动态数组类型，支持泛型。

```koral
// 创建
let mut list = [Int]List.new()
let mut list2 = [Int]List.with_capacity(100)

// 添加和删除
list.push(1)
list.push(2)
list.push(3)
list.pop()              // 返回 Option.Some(3)
list.insert(0, 0)       // 在索引 0 处插入
list.remove(0)          // 移除索引 0 处的元素

// 访问
list[0]                  // 下标访问（越界会 panic）
list.get(0)              // 安全访问，返回 Option
list.first()             // 第一个元素，返回 Option
list.last()              // 最后一个元素，返回 Option

// 信息
list.count()             // 元素个数
list.is_empty()          // 是否为空
list.contains(1)         // 是否包含（需要 Eq）

// 变换
list.slice(1..3)         // 切片
list.filter((x) -> x > 1)   // 过滤
list.map((x) -> x * 2)      // 映射
list.sort()                  // 排序（需要 Ord）
list.sort_by((x) -> x)      // 按键排序

// 连接
let combined = list + other_list  // 列表连接
```

### Map

`[K, V]Map` 是哈希映射类型，键类型需要实现 `Hashable`。

```koral
let mut map = [String, Int]Map.new()

// 插入和删除
map.insert("a", 1)      // 返回 Option（旧值）
map.remove("a")         // 返回 Option（被删除的值）

// 访问
map["a"]                 // 下标访问（键不存在会 panic）
map.get("a")             // 安全访问，返回 Option

// 信息
map.count()
map.is_empty()
map.contains_key("a")

// 遍历
for entry = map then {
    println(entry.key)
    println(entry.value)
}

// 键和值
for k = map.keys() then { println(k) }
for v = map.values() then { println(v) }
```

### Set

`[T]Set` 是哈希集合类型，元素类型需要实现 `Hashable`。

```koral
let mut set = [Int]Set.new()

// 添加和删除
set.insert(1)            // 返回 Bool（是否为新元素）
set.remove(1)            // 返回 Bool（是否存在）

// 信息
set.count()
set.is_empty()
set.contains(1)

// 集合运算
let union = set1.union(set2)
let inter = set1.intersection(set2)
let diff = set1.difference(set2)
```

### Option

`[T]Option` 是可选类型，表示一个值可能存在也可能不存在。

```koral
type [T Any] Option {
    None(),
    Some(value T),
}

let opt = [Int]Option.Some(42)
let none = [Int]Option.None()

opt.is_some()            // true
opt.is_none()            // false
opt.unwrap()             // 42（None 时 panic）
opt.unwrap_or(0)         // 42（None 时返回默认值）
opt.map((x) -> x * 2)   // Some(84)

// or else 和 and then
let val = opt or else 0
let mapped = opt and then _ * 2
```

### Result

`[T]Result` 是结果类型，表示操作可能成功也可能失败。错误端固定为 `Error ref`（trait object）。

```koral
type [T Any] Result {
    Ok(value T),
    Error(error Error ref),
}

let ok = [Int]Result.Ok(42)
let err = [Int]Result.Error(ref "failed")

ok.is_ok()               // true
ok.is_error()            // false
ok.unwrap()              // 42（Error 时 panic）
ok.unwrap_or(0)          // 42（Error 时返回默认值）
ok.map((x) -> x * 2)    // Ok(84)
err.unwrap_error().message()      // "failed"
```

## 模块系统

Koral 提供了强大的模块系统，用于在多个文件和目录中组织代码。

### 模块概念

Koral 中的**模块**由入口文件及其通过 `using` 声明依赖的所有文件组成。

- **根模块**：由编译入口文件及其依赖组成的模块
- **子模块**：子目录中的模块，以 `index.koral` 作为入口文件
- **外部模块**：当前编译单元之外的模块（如标准库）

### Using 声明

`using` 关键字用于导入模块和符号。所有 `using` 声明必须出现在文件开头，在任何其他声明之前。

#### 文件合并

使用字符串字面量语法将同目录的文件合并到当前模块：

```koral
using "utils"      // 将 utils.koral 合并到当前模块
using "helpers"    // 将 helpers.koral 合并到当前模块
```

合并的文件共享同一作用域，它们的 `public` 和 `protected` 符号互相可见。

#### 子模块导入

使用 `self.` 前缀从子目录导入子模块：

```koral
using self.models              // 导入 models/ 子目录作为子模块（私有）
protected using self.models    // 导入并在当前模块内共享
public using self.models       // 导入并对外部模块公开
```

使用点号访问子模块成员：

```koral
using self.models
let user = models.User("Alice")
```

也可以导入特定符号或批量导入：

```koral
using self.models.User         // 导入特定符号
using self.models.*            // 批量导入所有 public 符号
```

#### 父模块访问

使用 `super.` 前缀访问同一编译单元内的父模块：

```koral
using super.sibling            // 从父模块导入
using super.super.uncle        // 从祖父模块导入
```

#### 外部模块导入

导入外部模块不需要任何前缀：

```koral
using std                      // 导入 std 模块
using std.collections          // 从 std 导入 collections
using txt = std.text           // 使用别名导入
```

#### 显式限定类型（`module.Type` / `module.[T]Type`）

在类型位置可以使用模块前缀来显式限定类型：

```koral
using self.models

let user models.User = models.User("Alice")
let boxes models.[Int]Box = [Int]Box.new()
```

合法性规则：

1. `module` 必须能解析为已导入的模块符号。
2. `Type` 必须归属于该模块（归属校验）。
3. 该类型必须对当前位置可见（`private` 类型不可访问）。
4. 对 `module.[T]Type`，在通过归属校验后，再校验泛型参数个数与约束。

统一报错口径：

- 模块不存在/未导入：`Undefined variable: <module>`
- 类型不属于或未公开于该模块：`Type '<Type>' is not a public type of module '<module>'` 或
    `Type '<Type>' does not belong to module '<module>'`
- 泛型参数不匹配：沿用现有泛型参数个数/约束错误

#### Foreign Using

使用 `foreign using` 声明需要链接的外部共享库（`.so` / `.dylib` / `.dll`）。编译器会在链接阶段自动添加 `-l` 参数：

```koral
foreign using "m"       // 链接 libm（数学库），等价于 -lm
foreign using "pthread"  // 链接 libpthread
```

> 注意：`foreign using` 不是导入头文件，而是告诉链接器需要链接哪个库。C 函数的声明通过 `foreign let` 完成。

### 访问修饰符

Koral 提供三种访问级别来控制符号可见性：

| 修饰符 | 可见性 |
|--------|--------|
| `public` | 任何地方都可访问 |
| `protected` | 当前模块及所有子模块内可访问 |
| `private` | 仅在同一文件内可访问 |

#### 默认访问级别

| 声明类型 | 默认值 |
|----------|--------|
| 全局函数、变量、类型 | `protected` |
| 结构体字段 | `protected` |
| 联合类型构造器字段 | `public` |
| 成员函数（`given` 块内） | `protected` |
| Trait 方法 | `public` |
| Using 声明 | `private` |

### 项目结构示例

```
my_project/
├── main.koral           # 根模块入口
├── utils.koral          # 合并到根模块
├── models/
│   ├── index.koral      # models 子模块入口
│   ├── user.koral       # 合并到 models 模块
│   └── post.koral       # 合并到 models 模块
└── services/
    ├── index.koral      # services 子模块入口
    └── auth.koral       # 合并到 services 模块
```

```koral
// main.koral
using std
using "utils"
using self.models
using self.services

public let main() = {
    let user = models.User.new("Alice")
    if services.authenticate(user) then {
        println("Welcome!")
    }
}
```

## FFI (外部函数接口)

Koral 支持通过 `foreign` 关键字与 C 语言互操作。

### Foreign Using（链接外部库）

使用 `foreign using` 声明需要链接的共享库：

```koral
foreign using "m"  // 链接 libm（数学库）
```

编译器在链接阶段会自动添加 `-lm` 参数。`libc` 默认隐式链接，无需声明。

### Foreign 函数

声明外部 C 函数：

```koral
foreign using "m"

foreign let sin(x Float64) Float64
foreign let exit(code Int) Never
foreign let abort() Never
```

### Foreign 类型

声明外部 C 类型：

```koral
// 不透明类型（无字段）
foreign type CFile

// 带字段的 FFI 结构体（与 C 布局对齐）
foreign type KoralTimespec(tv_sec Int64, tv_nsec Int64)
```

### Intrinsic

`intrinsic` 关键字用于声明由编译器内置实现的类型和函数：

```koral
public intrinsic type Int
public intrinsic let [T Any]ref_count(r T ref) Int
```

