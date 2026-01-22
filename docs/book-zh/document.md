# Koral 编程语言

Koral 是一个专注于效率的开源编程语言，它可以帮你轻松构建跨平台软件。

通过精心设计的语法规则，这门语言可以有效降低读写负担，让你能够把真正的注意力放在解决问题上。  

## 关键特性

- 容易分辨、现代化的语法。
- 自动管理内存（基于引用计数与所有权）。
- 泛型与 Trait 系统。
- 多范式编程（函数式与命令式结合）。
- 跨平台。

## 安装与使用

目前 `Koral` 编译器支持将源代码编译为 C 语言代码，因此在使用前请确保系统中已安装了 C 编译器（如 `gcc` 或 `clang`）。

### 编译与运行

假设你有一个名为 `hello.koral` 的文件。

1.  **编译**：执行编译器命令（假设编译器名为 `koralc`），它会扫描当前文件夹下的所有 `.koral` 文件，并自动转译为同名的目标文件（如 `hello` 可执行文件）。
    ```bash
    koralc .
    ```
2.  **运行**：直接运行生成的可执行文件。
    ```bash
    ./hello
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

现在让我们的程序输出一些内容看看，标准库提供了 `printLine` 函数，用于向标准输出打印一行文本。

```koral
let main() = printLine("Hello, world!");
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

Koral 的变量是一种绑定语义，相当于是把一个变量名和一个值绑定在一起，从而建立起了关联关系，类似于键值对。为了安全性的考虑，变量默认是不可以改变的，当然 我们也提供了另一种变量——可变变量。

#### 只读变量

在 Koral 中是通过 `let` 关键字来声明只读变量的，变量遵循先声明后使用的原则。

Koral 通过静态类型确保类型安全，变量绑定可以在声明时显式通过 `type` 标注类型，在上下文中有足够的信息时，我们也可以省略类型，编译器回从上下文中推断出变量的类型。

示例代码如下：

```koral
let a Int = 5; // 显式标注类型
let b = 123;   // 自动推断类型
```

一旦只读变量被声明之后，它的值在当前作用域内就不会再被改变。

如果我们尝试对只读变量赋值，编译器会报错。

```koral
let a = 5;
a = 6; // 错误
```

#### 可变变量

如果我们需要一个可以被重新赋值的变量，可以使用可变变量声明。

在 Koral 中通过 `let mut` 关键字来声明可变变量，同样遵循先声明后使用的原则。

示例代码如下：

```koral
let mut a Int = 5; // 显式标注类型
let mut b = 123; // 自动推断类型
```

### 赋值

对于可变变量，我们可以在需要的时候多次改变它的值。

Koral 的赋值语句与大多数语言一样，都使用 `=` 声明，`=` 左边必须是可以被赋值的变量，程序会将 `=` 右边的值赋值给左边的变量。

示例代码如下：

```koral
let mut a = 0;
a = 1;  // 合法
a = 2;  // 合法
```

### 块表达式

在 Koral 中，`{}` 表示一个块表达式，块表达式可以包含一系列语句以及一个可选的最后一个表达式，块表达式的结果也是一个表达式。

块表达式中**最后一个表达式的值**就是整个块的值。如果没有最后一个表达式，那么块的值就是 Void。

通过块表达式可以组合一系列操作，比如多步初始化某个复杂的值。

```koral
let a Void = {}
let b Int = {
    let c = 7;
    let d = c + 14;
    (c + 3) * 5 + d / 3  // 块的返回值
}
```

### 标识符

标识符就是给变量、函数、类型等指定的名字。构成标识符的字母均有一定的规范，这门语言中标识符的命名规则如下：

1. 区分大小写。Myname 与 myname 是两个不同的标识符。
1. **类型**（Type）和**构造器**（Constructor）必须以**大写字母**开头（如 `Int`, `String`, `Point`）。
1. **变量**、**函数**、**成员**必须以**小写字母**或下划线开头（如 `main`, `printLine`, `x`）。
1. 标识符中其他字符可以是下划线 `_` 、字母或数字。
1. 在同一个 `{}` 内，不能重复定义相同名称的标识符。
1. 在不同 `{}` 内，可以定义重名的标识符，语言会优先选择当前范围内定义的标识符。

## 基础类型

我们只需要一些简单的基础类型，就可以开展大部分工作。

### 数值类型

由于我们目前的计算机结构比较擅长计算整数，因此一个独立的整数类型有助于提升程序的运行效率。

Koral 提供了丰富的数值类型来满足不同的需求。
在 Koral 中，默认的整数为 `Int` 类型，它可以表示有符号整数类型数据。
在 Koral 中，默认的小数为 `Float` 类型，它可以表示浮点型数据。

- `Int`: 平台相关的有符号整数（通常是 64 位）。
- `UInt`: 平台相关的无符号整数（通常是 64 位）。
- `Int8`, `Int16`, `Int32`, `Int64`: 固定宽度的有符号整数。
- `UInt8`, `UInt16`, `UInt32`, `UInt64`: 固定宽度的无符号整数。
- `Float`: 默认的浮点数类型（64 位，等同于 `Float64`）。
- `Float32`: 32 位浮点数。
- `Float64`: 64 位浮点数。
- `Byte`: 等同于 `UInt8`。

```koral
let i Int = 3987349;
let f Float = 3.14;
let b UInt8 = 255;
```

### 字符串

我们在并不是生活在一个只有数字的世界，所以我们也非常需要使用文字来显示我们需要的信息。

在本语言中，字符串用于表示文本数据。 `String` 类型，它是一个不限长度的字符序列数据。

你可以使用双引号 `""` 或单引号 `''` 包裹一段文字内容，它就会被识别为字符串值。

```koral
let s1 String = "Hello, world!";
let s2 String = 'Hello, world!'; // 和 s1 相同
```

Koral 支持字符串插值，允许在字符串中嵌入表达式。

```koral
let name = "Koral";
let s1 String = "Hello, \{name}!"; // 插值
let s2 String = 'Hello, \{"world"}!'; // 插值
```

### 布尔

布尔指逻辑上的值，它们只能是真或者假。它经常用以辅助判断逻辑。

在本语言中，默认的布尔为 `Bool` 类型，它是一个只有两个可能的值 `true`（真）和 `false`（假）的类型。

```koral
let b1 Bool = true;
let b2 Bool = false;
let isGreater = 5 > 3; // 结果为 true
```

### 列表类型

列表是一种泛型（后文介绍）的数据类型，它可以存储一组相同类型的数据元素，每个元素都有一个索引来表示它在列表中的位置。列表的长度不是固定的，它可以动态添加或删除元素，也可以通过索引快速访问元素。

我们使用 `[T]List` 来表示列表类型，其中 `T` 可以是任意类型。

列表类型可以使用列表字面量(`[elem1, elem2, …]`)的方式来初始化，其中 `elem1` 和 `elem2` 表示对应位置的元素，不同的元素之间使用 (`,`) 分割，我们可以传入任何表达式，但所有的元素必须是相同的类型。 

```koral
let x [Int]List = [1, 2, 3, 4, 5];
```

如上面的代码所示，我们使用数组字面量语法创建了一个 `[Int]List`，它的元素就像字面量表示的那样是 `1, 2, 3, 4, 5`。

除了这种列举元素的字面量以外，我们也可以用另一种创建一个指定大小和默认值的列表字面量(`[default; size]`)来构造，`default` 是默认值，`size` 是元素的个数。

```koral
let y [Int]List = [0; 3];
// y == [0, 0, 0]
```

我们可以使用数组的 `size` 成员函数（后文介绍）来获取它的元素个数。

```koral
printLine(x.size()); // 5
```

我们可以使用下标语法 `[index]` 的方式来访问指定索引的元素，`index` 只能是 `Int` 类型的值。下标的起始是 0，`[0]` 对应第一个元素，后续元素以此类推。

```koral
printLine(x[0]); // 1
printLine(x[2]); // 3
printLine(x[4]); // 5
```

对列表元素的修改和对成员变量（后文介绍）进行赋值是类似的，只不过需要使用下标语法。

```koral
let main() = {
    let x = [1, 2, 3, 4, 5];
    printLine(x[0]); // 1
    x[0] = 5;
    printLine(x[0]); // 5
}
```

如上面的代码所示，我们将 x 声明为列表，然后就可以使用 `[index] = value` 的方式对指定下标的元素进行赋值。

### 引用类型 (Reference)

引用类型用于引用另一个值，而不是持有它。这在需要共享数据或避免复制时非常有用。在类型名称后加上 `ref` 关键字即可声明引用类型。

```koral
// 声明一个接受 Int 引用作为参数的函数
let printList(x [Int]List ref) = printLine(x);
```

引用类型有两种创建方式。

#### ref 表达式

如果我们需要获取一个现有变量的引用，可以使用 `ref` 关键字。这通常用于将栈上的变量以引用的方式传递给函数，避免发生值拷贝。

```koral
let a [Int]List = [1,2,3];
printList(ref a); // 传递引用
```

#### new 函数

如果我们需要直接创建一个引用类型的值，可以使用 `new` 函数。它会在堆上分配内存并返回一个指向该数据的引用。

```koral
let a [Int]List ref = new([1,2,3]);
printList(a); // 传递引用
```

#### 内存管理

Koral 旨在提供高效且安全的内存管理。它结合了自动内存管理和手动控制的优点。

- **值语义（Value Semantics）**：默认情况下，Koral 中的类型（如 `Int`, 结构体）具有值语义。这意味着在赋值或传递参数时，数据会被复制（除非编译器优化掉）。这类似于 C 语言中的结构体。
- **引用（Reference）**：使用 `ref` 关键字可以创建引用。引用存储的不是普通的值，而是另一个变量的索引。通过引用，我们可以间接访问和修改被指向的变量。Koral 使用引用计数和所有权分析来自动管理引用的生命周期，防止悬垂指针和内存泄漏。
- **Copy 与 Drop Trait**：
    - **Copy**：如果一个类型实现了 `Copy` trait，那么它的值在赋值和传参时可以被执行 `copy` 函数来复制。基本类型（如 `Int`, `Float`）默认实现了 `Copy`。
    - **Drop**：如果一个类型实现了 `Drop` trait，那么当该类型的值超出作用域或不再被使用时，编译器会自动调用 `drop` 方法。这用于释放非内存资源（如文件句柄、网络连接）。
- **所有权转移（Move Semantics）**：对于没有执行 `copy` 操作的变量，赋值和传参操作会导致所有权转移（Move）。一旦所有权被转移，原来的变量就不能再被使用了。

## 操作符

操作符是一种告诉编译器执行特定的数学或逻辑操作的符号。

我们可以简单地理解成数学中的计算符号，但是编程语言有它不同的地方。

### 算术操作符

算数操作符主要被使用在数字类型的数据运算上，大部分声明符合数学中的预期。

Koral 支持标准的算术运算，包括加减乘除和取余。此外，还提供了幂运算操作符 `**`。

```koral
let a = 4;
let b = 2;
printLine( a + b );    // + 加
printLine( a - b );    // - 减
printLine( a * b );    // * 乘
printLine( a / b );    // / 除
printLine( a % b );    // % 取余，意思是整除后剩下的余数
printLine( a ** b );   // ** 幂
```

### 比较操作符

比较操作符用于比较两个值的大小关系，结果为 `Bool` 类型，结果符合预期的为 `true`，不符合的为 `false`。注意不等于使用 `<>` 表示。

```koral
let a = 4;
let b = 2;
printLine( a == b );     // == 等于
printLine( a <> b );     // <> 不等于 
printLine( a > b );      // > 大于
printLine( a >= b );     // >= 大于或等于
printLine( a < b );      // < 小于
printLine( a <= b );     // <= 小于或等于
```

### 逻辑操作符

逻辑操作符主要被用来对两个 Bool 类型的操作数进行逻辑运算（与、或、非）。

```koral
let a = true;
let b = false;
printLine( a and b );       // 与，两者同时为真才为真
printLine( a or b );        // 或，两者其中一者为真就为真
printLine( not a );         // 非，布尔值取反
```

其中，`and` 和 `or` 具有短路语义。短路逻辑运算的可以跳过部分不必要的计算，以节省计算资源或避免副作用。

当 `and` 操作符左侧表达式的值为 `false` 时，`and` 操作符右侧的表达式计算将会被跳过。

```koral
let a = false and f(); // 不会执行 f()
```

当 `or` 操作符左侧表达式的值为 `true` 时，`or` 操作符右侧的表达式计算将会被跳过。

```koral
let a = true or f(); // 不会执行 f()
```

### 位操作符

位操作符主要用于对两个整数类型的操作数进行位运算（与、或、异或、取反、左移、右移）。

```koral
let a = 4;
let b = 2;
printLine( a bitand b );    // 按位与
printLine( a bitor b );     // 按位或
printLine( a bitxor b );    // 按位异或
printLine( bitnot a );      // 按位取反
printLine( a bitshl b );    // 左移
printLine( a bitshr b );    // 右移
```

### 范围操作符

范围操作符用于生成一个范围（Range），我们可以在范围操作符的两端分别填入需要的整数类型值来表示一个范围，常用于循环或模式匹配。

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
let mut x = 10;
x += 5;       // x = x + 5
x -= 2;       // x = x - 2
x *= 3;       // x = x * 3
x /= 2;       // x = x / 2
x %= 4;       // x = x % 4
x **= 2;      // x = x ** 2 (幂运算)

let mut y = 0b1100;
y bitand= 0b1010; // y = y bitand 0b1010
y bitor=  0b0001; // y = y bitor 0b0001
y bitxor= 0b1111; // y = y bitxor 0b1111
y bitshl= 1;      // y = y bitshl 1
y bitshr= 2;      // y = y bitshr 2
```

### 运算符优先级

操作符优先级从高到低如下：

1. 前缀: `not`, `bitnot`, `+`(一元), `-`(一元)
2. 幂: `**` (右结合)
3. 乘除: `*`, `/`, `%`
4. 加减: `+`, `-`
5. 移位: `bitshl`, `bitshr`
6. 关系: `<`, `>`, `<=`, `>=`
7. 相等: `==`, `<>`
8. 按位与: `bitand`
9. 按位异或: `bitxor`
10. 按位或: `bitor`
11. 模式检查: `is`
12. 逻辑与: `and`
13. 逻辑或: `or`

## 选择结构

选择结构用于判断给定的条件，根据判断的结果判断某些条件，根据判断的结果来控制程序的流程。

在 Koral 中选择结构使用 `if` 语法表示，`if` 后面紧跟判断条件，在条件为 `true` 时执行条件后面的 `then` 分支，在条件为 `false` 时执行 `else` 关键字后面的 `else` 分支。

例如：

```koral
let main() = if 1 == 1 then printLine("yes") else printLine("no");
```

执行上面的程序会看到 `yes`。

`if` 同样也是表达式，`then` 和 `else` 分支后面都必须是表达式，根据 `if` 的条件，`if` 表达式的值可能是 `then` 或 `else` 分支其中的一个。

因此上面那段程序我们也可以这样写，两种写法结果等价。

```koral
let main() = printLine(if 1 == 1 then "yes" else "no");
```

由于 `if` 本身也是表达式，因此 `else` 后面自然也可以接另外一个 `if` 表达式，这样我们就可以实现连续的条件判断。

```koral
let x = 0;
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less";
```

当我们不需要处理 `else` 分支时，可以省略 `else` 分支，这时它的值是 `Void`。

```koral
let main() = if 1 == 1 then printLine("yes");
```

### let 表达式

`let` 也可以作为表达式使用，它允许你在计算后面的表达式之前绑定一个变量。这个变量的作用域仅限于 `then` 后面的表达式。这常用于在 `if` 或 `while` 之前引入临时变量。

在不使用 `let` 表达式的情况下我们可能会这样写，来达到缩小作用域的效果：

```koral
{
    let val = getValue();
    if val > 0 then {
        // some codes if is true
    } else {
        // some codes if is false
    }
}
```

可以看出，val 属于一个单独的一个块表达式中，这样不会将 val 暴露在 `if` 之外的作用域中。

使用 `let` 表达式的话我们可以这样写：

```koral
// val 仅在 if 表达式中可见
let val = getValue() then if val > 0 then {
    // some codes if is true
} else {
    // some codes if is false
}
```

如此一来，val 就只能在 `if` 和 `else` 中可见，不会泄露到其它作用域中去了。

## 循环结构

循环结构是指在程序中需要反复执行某个功能而设置的一种程序结构。它由循环体中的条件，判断继续执行某个功能还是退出循环。

### while 表达式

在 Koral 中循环结构使用 `while` 语法表示，`while` 后面紧跟判断条件，在条件为 `true` 时执行后面表达式，然后重新回到判断条件处进行判断进入下一轮循环，在条件为 `false` 结束循环。`while` 也是一个表达式。

```koral
let mut i = 0;
while i < 10 then {
    printLine(i);
    i += 1;
}
```

执行以上程序会打印 0 到 10。

### break 和 continue

- `break`: 退出循环。
- `continue`: 跳过当前迭代。

当我们需要在循环中主动退出循环时，可以使用 break 语句。程序会在执行到 break 时退出当前最近的一层循环。

```koral
let main() = {
    let mut i = 0;
    while true then {
        if i > 20 then break;
        printLine(i);
        i = i + 1;
    }
}
```

执行以上程序会打印 0 到 20。

如果我们需要在循环中跳过某些轮，可以使用 continue 语句。程序会在执行到 continue 时跳过当前一轮循环，继续执行下一次循环。

```koral
let main() = {
    let mut i = 0;
    while i <= 10 then {
        if i % 2 == 0 then continue;
        printLine(i);
        i = i + 1;
    }
}
```

执行以上程序会打印 0 到 10 之间的奇数。

### for 循环

`for` 循环用于遍历任何实现了迭代器接口的对象（如列表、数组、范围等）。

每次迭代，迭代器产生的下一个值会尝试匹配 `pattern`，如果匹配成功，则执行 `then` 后面的表达式。

```koral
// 遍历范围
for i = 0..10 then {
    printLine(i);
}
```

执行以上程序会打印 0 到 10。

```koral
let list = [1,2,3,4,5];

// 遍历列表
for item = list then {
    printLine(item);
}

// 配合解构使用
for (index, value) = list.enumerate() then {
    printLine("Index: \{index}, Value: \{value}");
}
```

执行上面的程序会先输出 1 到 5，然后再输出带 index 的 1 到 5。

## 模式匹配

Koral 拥有强大的模式匹配功能，主要通过 `match` 表达式和 `is` 操作符使用。

### match 表达式

`match` 表达式允许你将一个值与一系列模式进行比较，并根据匹配的模式执行相应的代码。它类似于其他语言中的 `switch` 语句，但功能更为强大。`match` 也是一个表达式，会返回匹配分支的值。

```koral
when x is {
    1 then "one";
    2 then "two";
    _ then "other";
}
```

支持的模式包括：

- 字面量模式：`1`, `"abc"`, `true`
- 范围模式：`0..9`
- 变量绑定模式：`x` (匹配任意值并绑定到 x)
- 解构模式：`Point(x, y)`
- 枚举模式：`.Some(v)`
- 类型检查模式：`x Int`

### is 操作符

`is` 操作符用于检查一个值是否匹配某个模式，结果为 `Bool` 类型。

当在 `if` 等条件表达式中使用时，如果匹配成功，它还可以将模式中的变量绑定到当前作用域，供后续代码使用。

```koral
if op is 0..9 then {
    printLine(v);
}
```

## 函数

函数是用来完成特定任务的独立的代码块。

通常我们会将一系列需要重复使用的任务处理封装成为函数，方便在其它地方重复使用。

### 定义

之前我们已经见过了入口函数，它使用了固定名称 main 来定义。

当我们需要定义其它函数时，我们可以使用同样的语法定义其它名称的函数。

函数通过 `let` 关键字定义，函数的名字后面使用 `()` 表示这个函数接受的参数，括号后面是这个函数的返回类型。返回类型在上下文明确时可以省略，由编译器推断返回类型。

函数的 `=` 右边必须声明一个表达式，这个表达式的值就是函数的返回值。

```koral
let f1() Int = 1;
let f2(a Int) Int = a + 1;
let f3(a Int) = a + 1;
```

### 调用

那么怎么使用这些定义好的函数呢？我们只需要在函数表达式后面使用 `()` 语法就可以调用函数，从而得到函数的返回值。

`()` 必须按函数定义的参数要求传入对应类型的参数。

```koral
let a = f1();
let b = f2(1);
```

### 参数

参数是函数执行时能够接收的数据，通过这些不同的参数我们就可以让函数输出不同的返回值。

比如我们可以实现一个平方函数，每次调用可以返回参数的平方值。

非常简单的，我们只需要使用 `参数名 类型` 就可以声明参数。

```koral
let sqrt(x Int) = x * x;
let a = sqrt(x); // a == 4
```

sqrt 接收一个 Int 类型的参数 x，然后返回它的平方值。调用 sqrt 的时候我们需要给出对应 Int 类型的表达式，就可以完成调用。

如果我们需要多个参数，可以按顺序逐个声明它们，中间使用 `,` 分割。调用也需要按同样的顺序给出表达式。

```koral
let add(x Int, y Int) = x + y;
let a = add(1, 2); // a == 3
```

### 函数类型

在 Koral 中，函数与 Int、Float 等类型一样，也是一种类型，同理函数也可以作为表达式使用。

函数的类型使用 `[T1, T2, T3,... R]Func` 语法声明，跟函数定义一样需要声明参数和返回类型。其中，`T1, T2, T3, ...` 部分是参数类型序列，当没有参数时为空，否则按顺序排列直到列举完所有参数类型。R 是返回类型。

函数定义之后，这个函数名就可以作为表达式使用，可以赋值给其它变量或者作为参数和返回值。

函数类型的变量跟函数一样使用 `()` 语法调用。

```koral
let sqrt(x Int) = x * x; // [Int, Int]Func
let f [Int, Int]Func = sqrt;
let a = f(2); // a == 4
```

利用这个特性，我们也可以定义函数类型的参数或者返回值。

```koral
let hello() = printLine("Hello, world!");
let run(f [Void]Func) = f();
let toRun() = run;

let main() = toRun()(hello);
```

执行上面的代码我们会看到 `Hello, world!`。

### Lambda 表达式

如上面那种方式先定义一个函数再传入使用有时候显得比较啰嗦，因为我们仅仅只是希望执行一小段功能而已，未必想定义一个函数提供给其它地方使用。

这时我们可以使用 Lambda 表达式 的语法来简化我们的代码。

Lambda 表达式与函数定义很相似，只是 `=` 换成了 `->`，并且没有函数名和 let 关键字。

如下面的代码所示，f2 的值是一个 lambda，它们的类型与 f1 一样，语法上也非常相似，lambda 的同样需要声明参数和返回类型，并且需要一个表达式作为返回值。

```koral
let f1(x Int) Int = x + 1; // [Int, Int]Func
let f2 = (x Int) Int -> x + 1; // [Int, Int]Func
let a = f1(1) + f2(1); // a == 4
```

在我们的上下文中可以得知 lambda 的类型时，我们可以省略它的参数类型和返回类型。

```koral
let f [Int, Int]Func = (x) -> x + 1;
```

## 数据类型

数据类型是由一系列具有相同类型或不同类型的数据构成的数据集合，它是一种复合数据类型。

显而易见，数据类型适合用来将不同数据包装到一起，形成一个新类型，便于操作复杂的数据。

Koral 提供了强大的类型系统，允许你定义自己的数据结构。使用 `type` 关键字来定义。

### 结构体 (Product Type)

结构体用于将多个相关的值组合在一起。每个字段都有一个名称和类型。

#### 定义

我们可以使用 `type` 关键字声明一个新数据类型，数据类型需要使用 `()` 声明它所拥有的成员变量，与函数的参数类似。

```koral
type Empty();
```

上面我们声明了一个名叫 Empty 的新数据类型，这个数据类型什么数据都不包含。

接下来让我们定义一些更有意义的数据类型试试。

```koral
type Point(x Int, y Int);
```

Point 是一个具有 x 和 y 两个成员变量的数据类型，它可以用来表示二维坐标系中的某一个点。这样我们就可以使用 Point 这个类型表示我们在坐标系中的数据，而不用总是使用两个独立的 Int 数据。

#### 构造

那么我们怎么构造一个新的 Point 数据呢？

和函数类型类似，我们同样使用 `()` 语法来调用我们的构造器，就可以得到我们需要的数据。

```koral
let a Point = Point(0, 0);
```

#### 使用成员变量

现在我们已经有了一个 Point 数据，我们要怎么使用里面的 x 和 y 呢？

很简单，我们只需要使用 `.` 语法，就能访问它们了。

```koral
type Point(x Int, y Int);

let main() = {
    let a = Point(64, 128);
    printLine(a.x);
    printLine(a.y);
}
```

执行上面的程序，我们可以看到 64 和 128。

#### 可变成员变量

成员变量与变量一样，默认都是只读的。所以我们不能对 Point 中的 x 和 y 再次赋值。如果我们尝试这么做，编译器会报错。

```koral
type Point(x Int, y Int);

let main() = {
    let a = Point(64, 28);
    a.x = 2; // 错误
}
```

我们可以在类型定义的时候对成员变量标注 mut 关键字，这样它就会被定义为是一个可变成本变量。对于可变成员变量，我们可以对其进行赋值。

成员变量的可变性是跟随类型的，与实例变量是否可变没有关系，所以我们即使声明了只读变量也可以修改可变成员变量。

```koral
type Point(mut x Int, mut y Int);

let main() = {
    let a Point = Point(64, 128); // `a` 不需要声明为 mut
    a.x = 2; // ok
    a.y = 0; // ok
}
```

当我们将一个类型的变量赋值给另一个变量使用时，两个变量并不是同一个实例，所以我们对成员变量的修改不会影响其它变量。换句话说，`Point` 类型可以被认为是其它语言中的值类型。

```koral
type Point(mut x Int, mut y Int);

let main() = {
    let a Point = Point(64, 128); 
    let b Point = a; // ok
    printLine(a.x); // 64
    printLine(b.x); // 64
    a.x = 128;
    printLine(a.x); // 128
    printLine(b.x); // 64
}
```

#### 成员函数

除了成员变量以外，数据类型还可以定义成员函数。成员函数能让我们的类型直接提供丰富的功能，而不需要依赖外部函数。

定义成员函数很简单，在类型定义的后面声明一个包含成员函数的块即可。

```koral
type Rectangle(length Int, width Int) {
    area(self) Int = self.length * self.width;
}
```

如上面的代码展示的，我们定义了一个成员函数 `area`，它用来计算 Rectangle 的面积。

跟普通的函数定义有差别的是，成员函数不需要使用 `let` 开头，而且通常第一个参数是 `self`。它用来表示当前类型的实例参数。

也许你已经注意到，在成员函数中我们访问成员变量跟在外部访问成员变量类似，只是我们需要使用 `self` 来表示实例的变量名。

和成员变量的访问一样，我们只需要使用 `.` 语法，就能访问成员函数了。

```koral
let main() = {
    let r = Rectangle(2, 4);
    printLine(r.area());
}
```

执行上面的程序，我们可以看到 8。

除了包含 `self` 的成员函数以外，我们还可以定义不包含 `self` 的成员函数。

这一类函数不能使用实例访问，只能使用类型名称访问。它可以让我们定义一些与类型关联性很高的函数但不需要实例作为参数的函数。

```koral
type Point(x Int, y Int) {
    default() Point = Point(0, 0);
}

let main() = {
    let a = Point.default();
    printLine(a.x); // 0
    printLine(a.y); // 0
}
```

例如上面的例子，我们为 Point 定义一个构造默认值的成员函数。然后使用 `Point.default` 的方式调用了它。

### 枚举 (Sum Type)

枚举允许你定义一个类型，它可以是几个不同变体（Variant）中的一个。每个变体可以携带不同类型的数据。这在处理状态机或错误处理时非常有用。

```koral
type Shape {
    Circle(radius Float);
    Rectangle(width Float, height Float);
}

// 实例化枚举变体
let s = Shape.Circle(1.0);
```

#### 使用枚举值

我们可以通过模式匹配（Pattern Matching）来提取枚举变体中携带的数据。这是处理枚举最常见也是最安全的方式。

```koral
let area = when s is {
    .Circle(r) then 3.14 * r * r;
    .Rectangle(w, h) then w * h;
}
```

在 `when` 表达式中，我们使用 `.VariantName` 的形式来匹配具体的变体，并解构其中的数据。

## Trait 与 Given

Koral 采用 Trait（特征）来定义共享的行为。这类似于其他语言中的接口（Interface）或类型类（Type Class）。

### 定义 Trait

Trait 定义了一组方法签名，任何实现了该 Trait 的类型都必须提供这些方法的具体实现。

```koral
trait Show {
    toString(self ref) String;
}
```

### 实现 Trait (Given)

使用 `given` 关键字为特定类型实现 Trait。这种机制允许你为已有的类型添加新的行为，而无需修改类型的定义（扩展性）。

```koral
given Point Show {
    toString(self ref) String = "Point(\(self.x), \(self.y))";
}
```

### 扩展方法

`given` 块不仅可以用于实现 Trait，还可以直接用于为类型添加方法。这些方法就像是类型自带的一样。

```koral
given Point {
    // 为 Point 类型添加 distance 方法
    distance(self ref) Float = { ... }
}
```

## 泛型

泛型允许你编写适用于多种类型的代码，从而提高代码的复用性。

### 泛型数据类型

让我们来想想这样一个场景，当我们想在函数的返回类型上返回两个值该怎么做？

对于简单的情况，我们可以定义出一个固定的类型来包装两个值。

```koral
type Pair(left Int, right Int);

let f() Pair = Pair(1, 2);
```

但如果我们有很多不同的类型需要包装，以上这种方式就显得不够通用了。

我们需要一种能表示容纳任意类型的 Pair，我们可以借助泛型数据类型定义它。

泛型数据类型与数据类型的区别在于它需要额外声明类型参数，这些类型参数表示将来会由实际传入的类型替换，从而让成员变量或成员函数的类型可以在后续实例化的时候替换为具体的类型。

```koral
type [T1 Any, T2 Any]Pair(left T1, right T2);
```

如上代码所示，我们在 `Pair` 的左边用另一种参数的形式声明了 T1 和 T2 两个类型参数，它们右侧的 Any 表示 T1 和 T2 的特征，这里 Any 可以是任意类型。Any 也可以换成其它特征。

如果我们需要多个类型参数，可以按顺序逐个声明它们，中间使用 `,` 分割。调用也需要按同样的顺序给出实际类型。

和普通参数不一样的是，类型参数的标识符总是以大写字母开头，并且没有类型标注。

接下来我们看看如何构造泛型数据类型。

```koral
let main() = {
    lef a1 [Int, Int]Pair = [Int, Int]Pair(1, 2);
    // a1.left Int, a1.right Int
    lef a2 [Bool, Bool]Pair = [Bool, Bool]Pair(true, false);
    // a2.left Bool, a2.right Bool
    lef a3 [Int, String]Pair = [Int, String]Pair(1, "a");
    // a3.left Int, a3.right String
}
```

如上代码所示，当我们使用泛型 Pair 的时候，需要在泛型参数的位置传入实际的类型。根据我们传入的类型不同，对应变量的 left 和 right 的类型也会有所不同。

这样我们就实现了一个足够通用的 Pair 类型，对于任意类型的两个值，我们都可以使用它来作为我们的返回类型，大大简化了我们需要定义的类型数量。

上面的代码写起来还是比较繁琐，实际上当上下文类型明确的时候，我们可以省略泛型类型构造时的类型参数。所以我们可以使用更简洁的方式来实现上面的功能。

就像下面的代码这样，它和上面的代码是等价的。

```koral
let main() = {
    lef a1 = Pair(1, 2);
    // a1 [Int, Int]Pair
    lef a2 = Pair(true, false);
    // a2 [Bool, Bool]Pair
    lef a3 = Pair(1, "a");
    // a3 [Int, String]Pair
}
```

### 泛型函数

现在我们已经拥有了强大的泛型数据类型，但我们还没有办法对一个任意类型的泛型类型实现功能，比如说合并任意两个相同类型的列表。

是的，我们需要具备泛型的函数才能实现它。

泛型函数和泛型类型很类似，都是在标识符的前面使用相同的语法定义泛型参数。

```koral
let [T]mergeList(a [T]List, b [T]List) [T]List = {
    let c [T]List = [];
    for v = a then {
        c.pushBack(v);
    }
    for v = b then {
        c.pushBack(v);
    }
    c
}
```

如上代码所示，我们在 `mergeList` 的左边用同样的泛型语法声明了 T 这个类型参数。

接下来我们看看如何调用泛型函数。

```koral
let main() = {
    let x = [1, 2, 3];
    let y = [4, 5, 6];
    let z = [Int]mergeList(x, y);
    // z == [1, 2, 3, 4, 5, 6]
}
```

如上代码所示，它跟普通的函数调用差不多，不同的只是在函数名的前面增加了类型参数，就像泛型数据类型的构造一样。

同样的道理，在上下文明确的时候，我们也可以省略类型参数，下面的代码等价于上面的代码。

```koral
let main() = {
    let x = [1, 2, 3];
    let y = [4, 5, 6];
    let z = mergeList(x, y);
}
```


## 模块系统

Koral 提供了强大的模块系统，用于在多个文件和目录中组织代码。模块系统支持代码复用、封装和清晰的关注点分离。

### 模块概念

Koral 中的**模块**由入口文件及其通过 `using` 声明依赖的所有文件组成。模块边界由入口文件和依赖链决定。

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

合并的文件共享同一作用域 - 它们的 `public` 和 `protected` 符号互相可见，无需额外导入。

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
using self.models.*            // 批量导入所有 public 符号（变为 private）
```

#### 父模块访问

使用 `super.` 前缀访问同一编译单元内的父模块：

```koral
using super.sibling            // 从父模块导入
using super.super.uncle        // 从祖父模块导入（链式 super）
```

#### 外部模块导入

导入外部模块（如标准库）不需要任何前缀：

```koral
using std                      // 导入 std 模块
using std.collections          // 从 std 导入 collections
using std.collections.List     // 导入特定符号
using std.collections.*        // 批量导入所有 public 符号
```

使用别名重命名导入：

```koral
using txt = std.text           // 使用别名导入
let builder = txt.StringBuilder.new()
```

### 访问修饰符

Koral 提供三种访问级别来控制符号可见性：

| 修饰符 | 可见性 |
|--------|--------|
| `public` | 任何地方都可访问 |
| `protected` | 当前模块及所有子模块内可访问 |
| `private` | 仅在同一文件内可访问 |

#### 默认访问级别

不同声明有不同的默认访问级别：

| 声明类型 | 默认值 |
|----------|--------|
| 全局函数、变量、类型 | `protected` |
| 结构体字段 | `protected` |
| 枚举构造器字段 | `public` |
| 成员函数（`given` 块内） | `protected` |
| Trait 方法 | `public` |
| Using 声明 | `private` |

#### 使用访问修饰符

在声明前添加访问修饰符：

```koral
public type User(
    public name String,           // 任何地方都可访问
    protected email String,       // 模块及子模块内可访问
    private passwordHash String,  // 仅本文件可访问
)

public let greet(user User) String = "Hello, " + user.name

protected let validateEmail(email String) Bool = email.contains("@")

private let hashPassword(password String) String = { /* ... */ }
```

#### 重导出规则

可以重导出同一编译单元内的符号：

```koral
public using self.helpers      // 重导出子模块
public using super.sibling     // 重导出父模块的符号
```

但是，不允许重导出外部模块的符号：

```koral
public using std.Option        // 错误：不能重导出外部符号
```

### 项目结构示例

典型的多文件项目结构：

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
using "utils"                  // 合并 utils.koral
using self.models              // 导入 models 子模块
using self.services            // 导入 services 子模块

public let main() = {
    let user = models.User.new("Alice")
    if services.authenticate(user) then {
        printLine("Welcome!")
    }
}
```

```koral
// models/index.koral
using "user"                   // 合并 user.koral
using "post"                   // 合并 post.koral
// User 和 Post 类型现在是 models 模块的一部分
```

```koral
// models/user.koral
public type User(
    public name String,
    public email String,
)

given User {
    public new(name String) User = User(name, "")
}
```

### 同目录多程序

多个独立程序可以共享公共代码：

```
scripts/
├── tool1.koral          # 独立程序 1
├── tool2.koral          # 独立程序 2
└── common.koral         # 共享工具
```

```koral
// tool1.koral
using "common"
public let main() = helper()

// tool2.koral  
using "common"
public let main() = helper()
```

每个程序独立编译：
- `koralc tool1.koral` → tool1 模块 = tool1.koral + common.koral
- `koralc tool2.koral` → tool2 模块 = tool2.koral + common.koral
