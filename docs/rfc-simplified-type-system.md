# RFC: 简化类型系统 — 移除托管引用，采纳 `type` / `type mutable` 二分模型

> 状态：草案
> 日期：2026-09-16
> 作者：调研阶段

## 1. 摘要

本提案建议对 Koral 的类型系统进行一次重大简化，但保留语言最关键的高层语义：

- **移除**托管引用系统（`*T`、`*mutable T`、`?*T`、`?*mutable T`、`&`、`&mutable`、`box()`）
- **保留** unsafe pointer 系统（`*unsafe T`、`*unsafe mutable T`）用于 FFI / 系统编程
- **保留** `foreign type` 语法；其语义继续等价于 C 兼容外部类型
- **采用**声明处二分模型：`type A` / `type mutable B`
- **保留**字段级 `mutable`，但规则为：非 `type mutable` 类型的字段必须全部不可变；只有 `type mutable` 类型允许显式声明 `mutable` 字段；默认仍然不可变
- **规定** `mutable` 只出现在声明形态中：`let mutable`、`type mutable`、字段声明、unsafe pointer pointee mutability；不存在通用的 `mutable expr` 或使用处 `mutable T`
- **移除** `Deref` trait 及其在泛型约束中的传播
- **移除** method receiver 的 auto-ref / auto-deref
- **移除**标准库容器的默认 COW 语义，改为共享语义 + 显式 `clone()`
- **去掉** `Object` 标记 trait；弱引用能力改为约束处的 `mutable` 语法（如 `[T mutable]`），trait object 直接使用 trait 名作为 type position
- **保留** raw pointer 指向普通 Koral 类型的能力，但必须明确它对布局自由、地址稳定性与优化边界的约束
- **允许**不带 `mutable` 的类型也由编译器按需使用 ARC、隐藏间接层、隐藏堆分配、递归布局和 `Drop`

这个提案的核心不是“所有非 mutable 类型都必须是栈值”，而是：

- **用户可见语义**只区分“不可变类型”与“可变类型”
- **底层布局与所有权实现**由编译器根据能力和优化需要决定，而不是暴露给开发者推理
- **raw pointer 的能力边界必须单独成文规定**，不能在简化用户模型的同时引入新的系统级裂缝

## 2. 设计目标

本提案的目标是同时满足以下几点：

1. **去掉事故高发区**：移除 escape analysis、托管引用提升、COW uniqueness 检查、receiver ref adaptation 等高耦合机制
2. **保留清晰的表层语义**：让开发者只需要理解 `type` 和 `type mutable` 两类 nominal type
3. **不引入 borrow checker**：避免把语言复杂度推到 Rust 同级
4. **不引入使用处 mutability**：避免 `mutable T` / `T` 两套 use-site 类型空间
5. **保留 FFI 能力**：unsafe pointer 继续存在，但不再和普通内存管理模型混用
6. **让编译器接管布局细节**：递归、trait object、closure capture、drop storage、hidden sharing 由编译器实现
7. **保留字段级可变性表达**：类型的共享语义与字段能否赋值是两个独立概念
8. **审慎保留 raw pointer 的通用性**：如果继续允许 `*unsafe T` 指向普通 Koral 类型，必须明确它对布局自由、地址稳定性和优化边界的约束
9. **让 weak 成为显式能力约束**：只有带 `mutable` 约束的类型才承担 weak 运行时成本

## 3. 动机

当前 Koral 的类型系统围绕托管引用构建，主要复杂度集中在以下几类机制：

1. **托管引用与值之间的双系统**：`T` 与 `*T` / `*mutable T` 同时存在，且 receiver 有特殊转换规则
2. **escape analysis**：`&` 得到的托管引用到底走栈还是堆，需要跨前端、MIR、codegen 推理
3. **borrow / owned promotion 链**：局部引用、返回引用、字段存储、闭包捕获、容器存储彼此影响
4. **COW 容器**：`ensure_unique`、`is_unique`、retain/release 时机与容器写路径耦合
5. **`Deref` trait 扩散**：std 中大量泛型 API 被迫写 `T Deref`
6. **receiver auto-ref / auto-deref**：方法解析和实参适配都需要围绕 ref family 做特殊逻辑
7. **raw pointer 与普通类型混用**：一旦任意 `T` 都能进入 `*unsafe T`，类型布局约束会再次外泄到用户层

这些问题在 bootstrap 和 std 中已经反复成为真实故障来源。主案的目标就是把这些复杂度从**用户模型**和**编译器结构**中一起移除。

## 4. 核心语法与语义

### 4.1 类型声明语法

本提案统一使用 `type` 关键字，`mutable` 放在 `type` 之后，和 `let mutable` 保持同样的声明节奏：

```koral
// 不可变类型
type Point(x Float64, y Float64)

// 可变类型
type mutable Buffer(mutable data List[UInt8], mutable len UInt)

// 枚举仍然使用 type
type Option[T] {
    Some(value T),
    None(),
}
```

建议的语法骨架：

```koral
TypeDecl ::= "type" ["mutable"] TypeName GenericParams? StructBody
         | "type" TypeName GenericParams? EnumBody
```

本 RFC 当前范围内：

- `type mutable` **仅用于结构体 / nominal object 类型**
- **枚举不引入 mutable 版本**
- **类型别名不能写成 `type mutable`**

也就是说，以下形式是非法的：

```koral
type mutable Result[T] {
    Ok(value T),
    Error(error Error),
}

type mutable Path = String
```

### 4.2 `mutable` 的出现位置

本提案中，`mutable` 不是通用表达式修饰符。

合法位置：

```koral
let mutable counter = 0;

type mutable Counter(mutable value Int, id UInt)

type Vec(x Int, y Int)

let p *unsafe mutable UInt8 = ...;
let raw = &unsafe mutable some_local;
```

非法位置：

```koral
let x = mutable Counter(0);     // 非法：不存在 mutable expr
foo(mutable value);             // 非法：不存在这种实参形式
let x mutable Counter = ...;    // 非法：不存在使用处 mutable T

type Vec(mutable x Int)  // 非法：非 mutable type 的字段必须全部不可变
```

这条规则是本 RFC 的重要边界：

- **变量可变性**用 `let mutable`
- **类型可变性**用 `type mutable`
- **字段可变性**用字段上的 `mutable`
- **非 `type mutable` 类型的字段必须全部不可变**
- **只有 `type mutable` 类型允许显式声明 `mutable` 字段**
- **不存在**第三类“表达式可变性”或“使用处可变性”

### 4.3 构造语法

`type mutable` 的构造语法和普通 `type` 一样，不需要也不允许在表达式上再写 `mutable`：

```koral
type Point(x Int, y Int)

type mutable Counter(mutable value Int)

let p = Point(1, 2);
let c = Counter(0);
let mutable current = Counter(10);
```

这里：

- `Counter(0)` 已经是在构造一个 `type mutable Counter`
- `let mutable current` 只表示变量 `current` 可以被重新赋值
- 它**不**表示“current 才是 mutable Counter，其他变量不是”

### 4.4 `type` 与 `type mutable` 的用户可见语义

#### `type`

`type` 表示**不可变类型**：

- 字段全部不可变，不允许声明 `mutable` 字段
- 没有用户可见的 identity
- 赋值 / 传参 / 返回不会暴露共享可变别名
- 编译器可以自由决定底层布局与所有权实现

#### `type mutable`

`type mutable` 表示**可变类型**：

- 字段默认仍不可直接修改；只有显式写 `mutable` 的字段可以原地修改
- 有用户可见的 identity
- 赋值 / 传参 / 返回传递的是同一个对象的共享句柄
- 语义上是共享对象，不是值拷贝

例子：

```koral
type Point(x Int, y Int)

type mutable Counter(mutable value Int)

let p1 = Point(1, 2);
let p2 = p1;
// p1 / p2 是不可变类型，不应表现为共享同一可变对象

let c1 = Counter(0);
let c2 = c1;
c2.value = 5;
// c1.value 也变成 5，因为 c1 / c2 共享同一个 Counter 对象
```

### 4.5 变量绑定语义

`let` / `let mutable` 与 `type` / `type mutable` 是正交的：

| | `type` | `type mutable` |
|---|---|---|
| `let` | 绑定不可重赋值；字段全部不可变 | 绑定不可重赋值；仅显式 `mutable` 字段可改 |
| `let mutable` | 绑定可重赋值；字段全部不可变 | 绑定可重赋值；仅显式 `mutable` 字段可改 |

#### 4.5.1 嵌套字段写入语义

当通过非 `mutable` 字段访问 `type mutable` 类型的值时，该值的 `mutable` 字段仍然可以写入。这与 Java/Kotlin 的语义一致：可变性是对象的属性，而不是绑定或中间字段的属性。

```koral
type mutable Inner(mutable x Int);
type Wrap(inner Inner);

let mutable w = Wrap(Inner(1));
w.inner.x = 2;    // 合法：Inner 是 type mutable，其 mutable 字段 x 总是可写
```

规则：
- 如果中间字段的类型是 `type mutable`，则可以通过该字段访问并写入其 `mutable` 字段
- 如果中间字段的类型是 `type`（不可变），则不能通过该字段写入任何嵌套字段
- 这条规则递归适用于任意深度的字段链

示例：

```koral
type Point(x Int, y Int)

type mutable Counter(mutable value Int)

let mutable p = Point(1, 2);
p = Point(3, 4);     // 合法：重绑定
// p.x = 5;          // 非法：字段 x 不是 mutable

let c = Counter(0);
c.value = 1;         // 合法：Counter.value 是 mutable 字段
// c = Counter(2);   // 非法：绑定本身不可重赋值

let mutable d = Counter(10);
d.value = 11;        // 合法
d = Counter(100);    // 合法
```

#### 参数中的 `mutable`

函数参数上的 `mutable` 规则保持和当前语言一致：

```koral
let normalize(mutable path Path) Path = {
    path = path.normalize();
    return path;
};
```

这里的 `mutable`：

- 只表示**函数体内这个形参绑定可重新赋值**
- **不是函数签名的一部分**
- **不会改变函数类型**
- **不会参与 trait / given 方法满足性检查**

它与 `type mutable` 完全不同：

- `mutable parameter` 作用在局部绑定
- `type mutable` 作用在类型定义

### 4.6 内存模型与布局

这是本 RFC 与“朴素值/引用二分”最大的不同点之一。

#### 对 `type` 的规则

不带 `mutable` 的 `type`：

- **没有用户可见 identity**
- **语义上是值**
- **布局不确定**
- **实现不受“必须栈上 / 必须内联 / 必须不走 ARC”限制**

编译器可以按需选择以下任意实现策略，只要不改变用户可见语义：

- 栈上值
- 寄存器值
- 内联布局
- 隐藏堆对象
- ARC 管理的隐藏共享 backing storage
- 为递归而插入的隐藏间接层
- 为 trait object / closure capture / large aggregate / ABI 需要而插入的隐藏 box

因此，**不能**把 `type` 解释成“绝不参与 ARC”。更准确的说法是：

- `type` **不暴露 ARC 作为用户可见语义**
- 但编译器 / runtime **可以为实现它而使用 ARC**

#### 对 `type mutable` 的规则

`type mutable`：

- 语义上是共享对象
- 有用户可见 identity
- 字段修改具有别名可见性
- 实现上通常表现为受所有权管理的对象句柄

实现上通常会使用堆分配 + ARC，但这是一种实现手段；语言规范要求的是：

- **共享对象语义必须成立**
- **identity 必须稳定且可观察**

#### ARC 的定位

ARC 在新模型里是**实现层能力**，不是用户必须直接操作的类型系统轴：

- `type mutable` 通常需要 ARC / ownership management
- 普通 `type` 在递归、隐藏共享、trait object 封装、closure capture、drop storage 等场景下也可能需要 ARC

结论是：

- **“是否写 `mutable`”不再等于“是否会用 ARC”**
- **“是否写 `mutable`”只决定用户可见的共享对象语义与字段可赋值边界**

### 4.7 `Drop` 语义

`Drop` 不再只属于可变类型，但它必须建立在 ARC 语义之上。

规则：

- 任何类型都可以实现 `Drop`
- `Drop` 的表面签名统一为 `drop(self) Void`
- 对 plain `type`，编译器可以在隐藏 ARC / hidden ownership backing 上实现 drop；如果逃逸分析证明该值可以不必堆分配或共享，就可以优化掉额外 ARC，多数实现仍然以 ARC-backed finalization 作为基础模型
- 对 `type mutable`，drop 在最后一个 owning handle 死亡时触发
- `Drop` 实现类型必然是 ARC-backed 的对象语义；其运行时表示必须保有最终ization / retain-release 生命周期
- drop 发生在受控 finalization context 中，不再向用户暴露析构期 raw pointer

这意味着：

- 开发者不需要因为“这类型要 drop”就强制把它设计成 `type mutable`
- 编译器要负责用隐藏布局 / hidden ownership 保证 drop 行为正确
- `Drop` 不是一个“值语义的 destructor”，而是“拥有对象的 finalizer”

#### `drop(self)` 的析构上下文规则

`drop(self)` 的表面签名虽然和普通方法一致，但它不应被理解成普通方法调用。RFC 需要明确以下边界：

1. `drop(self)` 只由编译器在对象生命周期终点自动调用，用户代码不能显式调用
2. `self` 在析构上下文中是只读访问视图；可以读取字段并执行清理逻辑，但不能把当前对象重新发布为可用值
3. `drop(self)` 内不允许把 `self` 或其内部需要销毁的对象重新存入全局、闭包环境或长期存活容器
4. 编译器可以限制 `drop(self)` 内调用某些可能观察“对象仍然活着”的普通方法，以避免析构期重入或对象复活语义

也就是说，`drop(self)` 是更安全的表面签名，但语义上仍然处于特殊 finalization context。

为了避免歧义，本 RFC 进一步规定：

1. `drop(self)` 内禁止显式调用 `drop(...)`
2. `drop(self)` 内禁止把 `self` 作为返回值、yield 值或闭包捕获值导出
3. `drop(self)` 内允许读取字段、调用 pure / observation-style helper、释放外部资源、释放内部子对象引用
4. `drop(self)` 内是否允许调用普通 trait / given 方法，由编译器按“不得导致对象复活或重入析构”规则判定；保守实现可以只允许直接字段访问和白名单 intrinsic

如果未来需要更强表达力，可以单独为析构上下文设计更明确的 effect 规则；本 RFC 不在这里展开。

### 4.8 递归类型

任何类型都可以递归。

```koral
type Tree[T] {
    Node(T, Tree[T], Tree[T]),
    Leaf(),
}

type JsonValue {
    Null(),
    Bool(value Bool),
    Number(value Float64),
    String(value String),
    Array(elements List[JsonValue]),
    Object(entries Dict[String, JsonValue]),
}
```

如果布局因此不再有限，编译器自动插入所需的隐藏间接层。开发者不需要写 `*T`、不需要写 `indirect`，也不需要为递归单独设计“引用 break edge”。

### 4.9 约束处的 mutable 与 weak

弱引用语法保留为 `?T`，但它只对“满足 mutable 约束”的类型参数和具体类型有意义。

```koral
let downgrade[T mutable](value T) ?T = ...
let upgrade[T mutable](value ?T) Option[T] = ...
```

规则：

- `?T` 只对满足 `mutable` 约束的类型合法
- `mutable` 不是布局差异，而是语义能力约束：它表示该类型支持 weak graph 语义
- 普通 `type` 默认不满足 `mutable` 约束
- `type mutable` 类型可以满足 `mutable` 约束
- `downgrade()` 和 `upgrade()` 只接受满足 `mutable` 约束的类型
- `upgrade_mutable` / `downgrade_mutable` 不再存在；弱引用 API 只保留一套名字

`mutable` 约束可以和其它泛型约束并列出现，例如：

```koral
type mutable Node[T mutable](mutable parent ?T)
```

这条规则把 weak 成本显式绑定到“可变类型能力”上，而不是单独引入一个 `Weak` 标记 trait。

### 4.10 方法接收者

移除 `*self` 和 `*mutable self`，统一为：

```koral
given Point {
    public x_value(self) Int = self.x;
}

given Counter {
    public bump(self) Int = {
        self.value += 1;
        return self.value;
    };
}
```

规则：

- `self` 是唯一 receiver 形式
- 对 `type`，`self` 表示不可变类型 receiver
- 对 `type mutable`，`self` 表示可变类型 receiver
- 不再有 auto-ref / auto-deref
- 调用语义只依赖类型本身，不依赖 receiver 特判

这里还需要额外强调：

- “不可变类型”只是用户可见语义，不等于“总是按固定值布局传递”
- 编译器仍可为不可变类型选择隐藏共享、隐藏堆分配或其它实现策略，只要不暴露可变别名

### 4.11 Trait 与 trait object

trait 方法签名统一改为 `self` receiver：

```koral
trait Iterator[T Any] {
    next(self) Option[T];
}

trait ToString {
    to_string(self) String;
}

trait Drop {
    drop(self) Void;
}

任意普通 trait 都可以在 type position 中充当 trait object 目标；前提是它满足 object safety：

```koral
trait Drawable {
    draw(self) String;
}

type Circle(radius Int);

given Circle as Drawable {
    draw(self) String = "Drawing circle";
}

let shape Drawable = Circle(10);
shape.draw();
```

trait object 的表面语法直接写 trait 名：

```koral
let shape Drawable = Circle(10);
let drawables List[Drawable] = ...;
```

规则：

- trait object 不再依赖 `Object` 标记 trait
- `Drop`、`Error` 或任何其它普通 trait 都可以参与 trait object 语义，只要 object-safe
- trait object 的实现层可以按需：
  - 盒装 concrete value
  - 持有 concrete shared object
  - 用 ARC 管理 erased storage

这些都不再以 managed-reference 语法暴露给用户。

object safety 规则保持原本方向，但签名表面更新为：

- 不允许泛型 requirement 方法进入 trait object vtable
- 除 receiver 之外，参数和返回值中不应使用未擦除的 `Self`
- receiver 使用 `self`，不再出现 `*self` / `*mutable self`

#### trait object 的类型测试与模式匹配

当前语言里，trait object 的精确实现类型匹配直接使用 concrete type 名。

建议规则：

- trait object subject 仍然允许做“精确实现类型测试”
- 模式直接写 concrete type 名

```koral
if err is IoError then {
    ...
}

if err is io IoError then {
    println(io.message());
}
```

这里：

- `err is IoError` 测试 trait object 当前承载的具体实现类型是否为 `IoError`
- `err is io IoError` 把 `io` 绑定为已下转后的 concrete value / object view

绑定变量的具体传递方式由编译器根据 concrete type 决定：

- 如果实现类型是 plain `type`，绑定结果按不可变类型语义工作
- 如果实现类型是 `type mutable`，绑定结果按可变类型语义工作

这部分不再暴露 `*ConcreteType` 或 `*mutable ConcreteType`。

### 4.12 表达式语法变更

#### 移除的表达式形式

以下表达式形式从语言表面移除：

```koral
&x
&mutable x
box(x)
*managed_ref
*managed_ref = value
mutable SomeExpr
```

解释：

- 不再有安全托管引用的取址表达式
- 不再有安全托管引用的解引用表达式
- 不再有 `mutable expr` 这样的构造方式

#### 保留的表达式形式

unsafe pointer 相关表达式保留，用于 FFI：

```koral
let p *unsafe Int = &unsafe value;
let mp *unsafe mutable UInt8 = &unsafe mutable bytes[0];

let x = *p;
*mp = 42;
```

这里的 `mutable` 是 raw pointer pointee mutability 的一部分，不是“表达式可变性”系统。

### 4.13 类型语法变更

#### 移除的类型形式

以下类型形式从语言表面移除：

```koral
*T
*mutable T
?T
Trait
mutable T        // 使用处 mutable 类型
```

#### 保留和新增的类型形式

```koral
type Point(...)
type mutable Counter(...)

?Counter              // 仅在 Counter 满足 mutable 约束时合法
Drawable              // trait object

*unsafe UInt8
*unsafe mutable UInt8
*unsafe KoralTimespec
```

重点规则：

- `mutable` 不是 use-site type qualifier
- 一个类型是否 mutable，由它自己的声明决定
- 使用时直接写类型名本身，不再写 `mutable T`
- `*unsafe T` / `*unsafe mutable T` 对任何 Koral type 都可接受，但必须满足地址稳定性和布局稳定性的实现约束；编译器不能将已进入 raw pointee 语义的类型重新做布局上偷偷改变
- raw pointer 不再视为“只允许 primitive / foreign type”这一类狭窄能力；它是底层内存观察能力，必须服从稳定布局承诺

### 4.14 额外语义影响

#### 字段声明语法

字段级 `mutable` 语法保留，但字段默认仍不可变。

```koral
type Vec(x Int, y Int)

type mutable Counter(mutable value Int, id UInt)
```

也就是说：

- `type` 的字段全部不可变，不允许声明 `mutable` 字段
- `type mutable` 的字段默认不可变，但允许显式声明 `mutable` 字段
- 是否能原地修改字段，只由该字段自己是否写了 `mutable` 决定
- `type mutable` 决定的是共享对象语义，不是字段自动可写

#### 闭包捕获

没有托管引用语法之后，闭包捕获由编译器隐藏实现：

- 捕获 plain `type` 值时，编译器可复制、共享 backing storage 或提升到隐藏 box
- 捕获 `let mutable` 局部时，编译器可自动生成隐藏 capture cell
- 捕获 `type mutable` 对象时，闭包共享同一对象

这些机制是实现细节，不再暴露为用户可写的安全引用类型。

#### 相等性、哈希与 identity

`type mutable` 有 identity，但这**不自动等于**“默认按 identity 做 `Eq` / `Hash`”。

规则保持：

- `==` / `Eq` 仍由 trait 语义决定
- `Hash` 仍由 trait 语义决定

这能避免“对象可变，所以等号自动变成指针等号”的混乱。

#### `is` 的语义边界

`is` 保持原有方向：

- `is` 用于模式匹配与类型测试
- 本 RFC **不**让 `is` 额外承担 identity 比较

示例：

```koral
let ok = result is .Ok(_);

if err is IoError then {
    ...
}
```

#### foreign type 与 FFI 边界

本 RFC 保留当前的 `foreign type` 语法，不新增额外的 C layout 标注语法：

```koral
foreign type CFile {};
foreign type KoralTimespec(tv_sec Int64, tv_nsec Int64);
```

规则：

- `foreign type` 继续表示与 C ABI 对齐的外部类型
- `foreign type` 在 Koral 中保持当前的外部值类型语义，等价于 C struct 或 opaque foreign handle
- 原生 Koral `type` / `type mutable` 是否允许进入 raw pointer pointee 语法，需要结合实现风险单独定义

raw pointer 的 pointee 当前建议保持兼容，但需要补齐风险说明：

- primitive 类型始终可以作为 pointee：整数、浮点、`Rune`、`Bool`
- `foreign type` 始终可以作为 pointee
- 如果继续允许普通 Koral 类型作为 pointee，则 RFC 必须明确对应的布局、地址稳定性和优化约束

为避免含糊，本 RFC 把“普通 Koral 类型可作为 raw pointee”的规则进一步收口为：

1. `*unsafe T` / `*unsafe mutable T` 可以继续指向普通 Koral 类型
2. 一旦某个 `T` 进入 raw pointee 语义，编译器就必须把该 `T` 视为具有稳定、可寻址、可重定位定义的物理布局
3. 对已进入 raw pointee 语义的 `T`，编译器不得再使用会破坏地址稳定性的隐藏表示变换
4. 对递归类型、trait object backing、closure capture cell、隐藏共享 backing 等依赖特殊布局的实现，如果无法满足第 2 条和第 3 条，就不得形成对应的 `*unsafe T`
5. 任何公开 API 一旦暴露 `*unsafe T`，就等价于把 `T` 的某种物理布局承诺暴露给低层代码

这意味着：

- raw pointer generality 可以保留
- 但它不是零成本能力，而是一种会反向约束优化自由的低层承诺

合法示例：

```koral
let p *unsafe Int = ...;
let q *unsafe mutable UInt8 = ...;
let t *unsafe KoralTimespec = ...;
```

#### 下标 / 成员访问

没有安全托管引用后：

- 成员访问直接以不可变类型或可变类型语义工作
- 下标赋值直接由容器 API / 编译器 lowering 支持
- 不再暴露 `__index_ref` / `__index_mut_ref` / `__index_mut_ptr` 这类面向 ref/ptr 的旧用户模型
- 对 plain `type`，`a[i].field = ...` 不做隐式 get-modify-set 回写；需要时用户应显式先取临时值、改写、再 `a[i] = tmp`
- 对 `type mutable`，`a[i]` 得到的是共享句柄，因此成员写入与 mutating method call 可以自然工作


#### 泛型约束

`Deref` 被移除后：

- 容器和算法不再因为内部存储策略而要求 `T Deref`
- 泛型约束只表达真正的语义能力，如 `Eq`、`Hash`、`Ord`、`Clone`
#### 泛型容器内部表示与 raw pointer 风险

如果保留“`*unsafe T` 可以指向普通 Koral 类型”的设计，最大的直接收益是：

1. `List[T]`、`Dict[K, V]`、`Deque[T]` 等泛型容器可以继续使用当前这套基于 typed raw storage 的实现路径
2. `alloc_memory[T]` / `copy_memory` / `move_memory` / `init_memory` / `deinit_memory` 这类现有 intrinsic 的设计更自然
3. std 与 bootstrap 不需要为了容器内部存储再发明第二套特殊抽象

这条路线在工程上是自洽的，也更贴近当前 Koral 的实现习惯。

但它带来的风险需要在 RFC 中明确写出来：

1. **布局泄漏风险**：一旦普通 Koral 类型可以进入 `*unsafe T`，语言事实上承认了“该类型存在可被 raw pointer 观察的稳定物理布局”
2. **递归类型风险**：如果某些 plain `type` 依赖编译器插入隐藏间接层或隐藏共享 backing，raw pointee 语义必须定义清楚 pointer 实际指向什么
3. **trait object / erased storage 风险**：如果某类型在某些上下文下需要 erased 或 hidden storage，`*unsafe T` 是否还能指向它、如何构造它，需要额外规则
4. **`Drop` / move 风险**：一旦普通 Koral 类型可以被 raw pointer 直接观察，析构、搬移、重定位、临时物化后的地址稳定性都需要更严格定义
5. **优化约束风险**：编译器对 plain `type` 的布局自由会被明显压缩，某些本来可以做的隐藏优化将受 raw pointee 可观测性约束

因此，如果维持当前设计，RFC 至少要补上以下边界条件：

1. `*unsafe T` 指向普通 Koral 类型时，`T` 必须被视为具有可寻址、可重定位定义的物理布局
2. 编译器不得对已进入 raw pointee 语义的 `T` 再做会破坏地址稳定性的隐藏表示变换
3. 对递归类型、trait object backing、closure capture cell 这类依赖隐藏布局的实现，要么禁止形成 `*unsafe T`，要么单独规定其 raw layout 规则
4. 任何依赖 raw pointee 的 API 都必须被视为比普通类型语义更底层的承诺，它会反向约束编译器优化空间

这条路不是不能走，但它的代价必须在 RFC 中明确，而不能继续假设“任意 T 都能指针化”是零成本的。

从内部一致性角度，RFC 在这里更好的表述不是直接替你拍死方案，而是：

- 当前 Koral 风格更偏向保留 `*unsafe T` 对普通类型的支持
- 如果保留，就要把它视为编译器布局自由的一项显式约束
- 这项约束尤其会影响递归类型、trait object backing、closure capture cell、以及任何依赖 hidden storage 的实现

#### 可变枚举

本 RFC **不引入 mutable enum**。

原因：

- 当前没有足够强的真实使用场景
- mutable enum payload 原地修改会引入新的 pattern / projection / tag consistency 规则
- 可以单独做后续 RFC，而不应混入本次简化

## 5. 标准库影响

### 5.1 容器：去掉 COW，统一共享语义

以下标准库容器改为 `type mutable`：

| 类型 | 新设计 |
|---|---|
| `List[T]` | `type mutable List[T]` |
| `Dict[K, V]` | `type mutable Dict[K, V]` |
| `Set[T]` | `type mutable Set[T]` |
| `Deque[T]` | `type mutable Deque[T]` |
| `Queue[T]` | `type mutable Queue[T]` |
| `Stack[T]` | `type mutable Stack[T]` |
| `PriorityQueue[T]` | `type mutable PriorityQueue[T]` |
| `ByteBuffer` | `type mutable ByteBuffer` |

语义变化：

- **移除** `ensure_unique` / `is_unique` / COW 检查
- **赋值 = 共享对象**
- **独立副本 = 显式 `clone()`**
- **`clone()` 的语义必须声明为浅拷贝**：复制的是对象句柄/共享 backing，而不是递归 deep-copy 结构体内容

示例：

```koral
let a = List[Int].new();
a.push(1);

let b = a;
b.push(2);
// a / b 现在都看到 [1, 2]

let c = a.clone();
c.push(3);
// a 仍是 [1, 2]
```

容器 API 也同步简化：

```koral
given[T Any] List[T] {
    public new() Self;
    public push(self, value T) Void;
    public pop(self) Option[T];
    public get(self, index UInt) Option[T];
    public count(self) UInt;
    public clone(self) Self;
}
```

附加说明：

- 容器内部不应继续以公开可见的 `*unsafe T` 作为任意 `T` 的通用存储表示
- `borrow_ptr` / `borrow_mut_ptr` 若继续存在，应缩小到 primitive / foreign-compatible 用途

### 5.2 String：不可变值 + StringBuilder

`String` 改为真正的不可变值类型：

```koral
type String(...)
type mutable StringBuilder(...)
```

原则：

- `String` 不做原地修改
- 所有变换返回新 `String`
- 增量构造使用 `StringBuilder`

```koral
let s = "hello";
let upper = s.to_ascii_uppercase();
let combined = s + " world";

let sb = StringBuilder.new();
sb.push_string("hello");
sb.push_string(" world");
let result = sb.to_string();
```

### 5.3 迭代器

所有有内部游标状态的迭代器改为 `type mutable`：

| 类型 | 新设计 |
|---|---|
| `ListIterator[T]` | `type mutable ListIterator[T]` |
| `DictIterator[K, V]` | `type mutable DictIterator[K, V]` |
| `SetIterator[T]` | `type mutable SetIterator[T]` |
| `DequeIterator[T]` | `type mutable DequeIterator[T]` |
| `StringSplitIterator` | `type mutable StringSplitIterator` |
| `DirIterator` | `type mutable DirIterator` |
| `WalkDirIterator` | `type mutable WalkDirIterator` |

相关 trait：

```koral
trait Iterator[T Any] {
    next(self) Option[T];
}

trait Iterable[T Any, R Iterator[T]] {
    iterator(self) R;
}
```

### 5.4 核心枚举与递归值

以下类型保持 `type`：

| 类型 | 新设计 |
|---|---|
| `Option[T]` | `type Option[T]` |
| `Result[T]` | `type Result[T]` |
| `Range[T]` | `type Range[T]` |
| `JsonValue` | `type JsonValue` |
| `IpAddr` | `type IpAddr` |
| `FileType` | `type FileType` |
| `OpenMode` | `type OpenMode` |
| `SeekOrigin` | `type SeekOrigin` |
| `Shutdown` | `type Shutdown` |

`Result[T]` 改为：

```koral
type Result[T Any] {
    Ok(value T),
    Error(error Error),
}
```

这里的 `Error` 是 trait object 表面类型，内部如何表示由编译器决定。

`JsonValue` 递归边不再显式写 `*JsonValue`：

```koral
type JsonValue {
    Null(),
    Bool(value Bool),
    Number(value Float64),
    String(value String),
    Array(elements List[JsonValue]),
    Object(entries Dict[String, JsonValue]),
}
```

### 5.5 I/O、OS、Net、Sync、Async、Proc、Text、Time

关键标准库类型建议如下：

| 模块 | `type mutable` | `type` |
|---|---|---|
| `std::io` | `ByteBuffer`, `BufReader`, `BufWriter` | `IoError`, `SeekOrigin` |
| `std::os` | `File`, `DirIterator`, `WalkDirIterator` | `Path`, `FileInfo`, `FileType`, `OpenMode`, `Permission`, `DirEntry` |
| `std::net` | `TcpListener`, `TcpSocket`, `UdpSocket` | `Ipv4Addr`, `Ipv6Addr`, `IpAddr`, `SocketAddr`, `Shutdown` |
| `std::sync` | `Mutex`, `Semaphore`, `SharedMutex`, `AtomicBool`, `AtomicInt`, `AtomicUInt`, `SendChannel[T]`, `RecvChannel[T]` | channel result / status snapshots |
| `std::async` | `Task`, `Thread`, `Timer`, `Ticker` | immutable task output / status values |
| `std::proc` | `Process`, `Command`, `StdinPipe`, `StdoutPipe`, `StderrPipe` | `CommandOutput`, `ExitStatus`, `IoRedirect` |
| `std::text` | `Regex`, all stateful iterators | `Match`, `Captures`, `RegexFlag` |
| `std::time` | `TimeZone`（如包含共享缓存） | `Duration`, `Date`, `DateTime`, `MonoTime`, `ClockTime` |
| `std::rand` | `Random[R]`, `DefaultRandomSource` | immutable random result values |
| `std::json` | none | `JsonValue`, `JsonError` |

### 5.6 trait 签名调整

典型 trait 签名统一改成：

```koral
trait Iterator[T Any] {
    next(self) Option[T];
}

trait Iterable[T Any, R Iterator[T]] {
    iterator(self) R;
}

trait ToString {
    to_string(self) String;
}

trait Error {
    message(self) String;
}

trait Drop {
    drop(self) Void;
}

trait Clone {
    clone(self) Self;
}
```

`Deref` 从 std 和语言语义中移除。

与之配套，所有原本依赖 receiver mutability 语法区分的 trait / given 实现，都要改为由 concrete type 本身决定语义：

- 对 plain `type`，trait 方法不能修改任何字段（`type` 不允许声明 `mutable` 字段）
- 对 `type mutable`，trait 方法可以修改共享对象上的显式 `mutable` 字段
- 调用者不再通过 `*self` / `*mutable self` 观察这种差异

### 5.7 raw pointer 相关 API

虽然 managed ref 体系移除，但以下 FFI 辅助 API 可以继续存在：

- `borrow_ptr`
- `borrow_mut_ptr`
- `from_ptr` / `from_owned_ptr` 一类受控构造

它们的参数签名同步改成 `self` receiver，不再依赖 `*self`。

但要增加一个关键限制：

- 这些 API 不能再作为“任意 Koral 类型 -> `*unsafe T`”的通用桥
- generic 容器上的 `borrow_ptr` / `borrow_mut_ptr` 若返回 `*unsafe T`，将不再适用于任意 `T`
- 它们只应保留在 primitive / foreign-compatible 场景

## 6. 编译器与运行时影响

### 6.1 可以移除的编译器机制

1. 托管引用类型节点：`*T`、`*mutable T`
2. 托管 weak ref 类型节点：`?*T`、`?*mutable T`
3. managed `&` / `&mutable` 表达式
4. `box()` 语言级托管构造
5. escape analysis / reference allocation promotion 这整条托管引用决策链
6. 栈安全借用检查
7. receiver auto-ref / auto-deref
8. `Deref` trait 特判及 blanket conformance 扩散
9. COW uniqueness 路径（`ensure_unique`、`is_unique` 等）
10. `upgrade_mutable` / `downgrade_mutable`

### 6.2 需要新增或强化的编译器责任

1. 根据类型能力自动选择 plain `type` 的布局
2. 在递归类型上自动插入隐藏间接层
3. 为 trait object 自动生成 erased storage 表示
4. 为 closure capture 自动生成隐藏 capture storage
5. 为实现 `Drop` 的 plain `type` 选择合适的 hidden ownership 模型，并以 `drop(self)` 语义触发析构
6. 跟踪哪些类型满足 `mutable` 约束，仅为这些类型生成 weak count / downgrade / upgrade 支持
7. 为共享容器 / shared object 语义实现 `clone()` 等显式复制能力
8. 为泛型容器提供 opaque raw storage + typed slot intrinsic 支持

### 6.3 运行时影响

运行时层面：

- **保留** ARC / retain / release 作为实现工具
- **保留** weak reference 运行时支持，但仅用于满足 `mutable` 约束的类型
- **保留** trait object vtable / erased storage 支持
- **保留** unsafe pointer 相关运行时或 ABI 支持
- **移除**为 managed `&` / `box()` / promotion / COW uniqueness 服务的专门表层机制

重要的是：运行时仍可能大量使用 ARC，但这不再意味着语言表面保留 `*T` 用户模型。

## 7. 需要同步更新的文法与语义点

本 RFC 落地时，以下所有地方都需要同步更新：

1. 类型声明语法：`mutable type` -> `type mutable`
2. 字段声明语义：保留字段级 `mutable`，但改为“默认不可变”
3. 类型表达式文法：移除 managed ref / managed weak ref / use-site mutable type
4. 表达式文法：移除 managed `&` / `&mutable` / `box()` / managed deref
5. method receiver 文法：移除 `*self` / `*mutable self`
6. trait object 文法：`*Trait` / `*mutable Trait` -> `Trait`
7. weak ref 文法：`?*T` / `?*mutable T` -> `?T`
8. weak API：移除 `upgrade_mutable` / `downgrade_mutable`，统一为 `upgrade` / `downgrade`
9. raw pointer pointee 规则：primitive / `foreign type` 永远合法；普通 Koral 类型若允许作为 pointee，则自动对其布局自由施加约束
10. 泛型约束：移除 `Deref`
11. 标准库文档：容器、String、I/O、sync、trait API 全部改签名
12. 测试用例：所有 escape analysis / COW / managed ref / receiver adaptation 相关 case 需要替换为新语义测试

### 7.1 文法 diff（旧 -> 新）

本节给出需要同步修改的关键 grammar surface，重点是让 parser / AST / typed AST / 文档可以对齐到同一套新表面语法。

#### 类型声明

旧：

```koral
TypeDecl ::= "type" TypeName GenericParams? TypeBody
           | "mutable" "type" TypeName GenericParams? TypeBody
```

新：

```koral
TypeDecl ::= "type" ["mutable"] TypeName GenericParams? StructBody
         | "type" TypeName GenericParams? EnumBody
```

影响：

- `mutable type Foo` 改为 `type mutable Foo`
- parser 只保留一种声明顺序
- 文档、formatter、printer、diagnostic message 一起切换

#### 字段声明

旧：

```koral
FieldDecl ::= ["mutable"] Name Type
```

新：

```koral
FieldDecl ::= ["mutable"] Name Type
```

语义变化：

- 字段级 `mutable` 保留
- `type mutable` 不再隐含“全部字段可写”
- 无论宿主类型是否是 `type mutable`，字段默认都是不可变，只有显式标注 `mutable` 的字段可原地赋值

#### 类型表达式

旧：

```koral
TypeNode ::= Name
           | "*" TypeNode
           | "*mutable" TypeNode
           | "?*" TypeNode
           | "?*mutable" TypeNode
           | "*unsafe" TypeNode
           | "*unsafe mutable" TypeNode
           | GenericType
           | FuncType
```

新：

```koral
TypeNode ::= Name
           | "?" TypeNode
           | "*unsafe" TypeNode
           | "*unsafe mutable" TypeNode
           | GenericType
           | FuncType
```

额外约束：

- `?T` 只在 `T` 满足 `mutable` 约束时合法
- `mutable T` 不再是合法类型表达式
- trait object 直接写 trait 名，不再走 `*Trait`
- `*unsafe T` / `*unsafe mutable T` 始终允许 primitive 与 `foreign type`，普通 Koral 类型是否允许作为 pointee 由其布局约束是否可满足决定

#### 表达式

旧：

```koral
Expr ::= ...
       | "&" Expr
       | "&mutable" Expr
       | "box" "(" Expr ")"
       | "*" Expr              // managed deref 与 raw deref 共用表面
       | ...
```

新：

```koral
Expr ::= ...
       | "&unsafe" Expr
       | "&unsafe mutable" Expr
       | "*" Expr              // 仅 raw pointer deref
       | ...
```

影响：

- 移除 managed `&`
- 移除 managed `box()`
- `*expr` 只剩 raw pointer deref 语义

#### receiver 参数

旧：

```koral
SelfParam ::= "self"
            | "*self"
            | "*mutable self"
```

新：

```koral
SelfParam ::= "self"
```

影响：

- trait / given / inherent method 的 receiver 形式统一
- 不再为 receiver 做单独的 ref family parsing

#### trait object 类型

旧：

```koral
TraitObjectType ::= "*" TraitName
                  | "*mutable" TraitName
```

新：

```koral
TraitObjectType ::= TraitName
```

影响：

- trait name 在 type position 下既可能是约束名，也可能是 trait object 表面类型
- parser 不需要新语法，但 sema 需要基于上下文区分

#### trait object 精确类型模式

旧：

```koral
TypePattern ::= "*" ConcreteType
              | "*mutable" ConcreteType
              | Binding "*" ConcreteType
```

新：

```koral
TypePattern ::= ConcreteType
              | Binding ConcreteType
```

影响：

- `if err is *IoError` -> `if err is IoError`
- `if err is io *IoError` -> `if err is io IoError`

#### 弱引用类型

旧：

```koral
WeakType ::= "?" TypeNode
```

影响：

- 弱引用不再编码 pointee mutability
- 是否能被弱引用由该类型是否满足 `mutable` 约束决定，而不是由写法是否带 `*` 决定

#### foreign type

旧：

```koral
ForeignTypeDecl ::= "foreign" "type" Name ForeignBody
```

新：

```koral
ForeignTypeDecl ::= "foreign" "type" Name ForeignBody
```

语义保持：

- `foreign type` 继续是 FFI 类型声明语法
- 不新增额外的 C layout 标注语法
- `foreign type` 继续承担与 C 兼容的值布局职责

### 7.2 AST / Typed AST 层面的对应变化

落地实现时，除了 surface grammar，还需要同步精简内部节点：

1. 删除 managed `Reference` / `MutableReference` 类型节点
2. 删除 managed `WeakReference` / `MutableWeakReference` 类型节点
3. 删除 managed address-of 表达式节点
4. 删除 managed deref 表达式节点
5. 删除 receiver mutability / receiver ref-shape 节点分支
6. 保留 `Weak(Type)` 语义节点，改为记录该类型是否满足 `mutable` 约束
7. trait object 从 `Ref<Trait>` 风格内部表示转为“erased trait object”直接节点
8. 对泛型容器内部表示，引入 opaque raw storage / typed slot 级内部节点或 intrinsic 对接层

实现上可以仍然保留 lower-level ownership/runtime nodes，但不应再与用户表面 AST 一一对应。

## 8. 标准库迁移清单

本节面向 std 文档、实现文件和测试用例迁移，重点不是列出所有方法，而是列出**需要系统性变更的类别**。

### 8.1 `Std` 根模块

#### 自由函数

- 删除 `box[T Any](mutable v T) *mutable T`
- 保留 `make_bytes` / `make_uninitialized_bytes`，但其返回值现在是 `type mutable List[UInt8]`
- 保留 `upgrade` / `downgrade`，删除 `upgrade_mutable` / `downgrade_mutable`
- `print` / `println` / `eprint` / `eprintln` 无需表面签名变化，但 `ToString` 的 receiver 会变

#### 核心 trait

旧：

```koral
trait Iterator[T Any] {
    next(*mutable self) Option[T];
}

trait Iterable[T Any, R Iterator[T]] {
    iterator(*self) R;
}

trait ToString {
    to_string(*self) String;
}

trait Error {
    message(*self) String;
}

trait Drop {
    drop(source *unsafe mutable Self) Void;
}
```

新：

```koral
trait Iterator[T Any] {
    next(self) Option[T];
}

trait Iterable[T Any, R Iterator[T]] {
    iterator(self) R;
}

trait ToString {
    to_string(self) String;
}

trait Error {
    message(self) String;
}

trait Drop {
    drop(self) Void;
}
```

#### 核心类型分类

改为 `type mutable`：

- `List[T]`
- `Deque[T]`
- `Dict[K, V]`
- `Set[T]`
- 所有 stateful iterator
- `StringBuilder`（新增）

保持 `type`：

- `Option[T]`
- `Result[T]`
- `Range[T]`
- `SliceSpec`
- `Duration`
- `Rune`
- `Pair[T, U]`
- `String`

#### 关键签名变化

- `Result[T].Error(error * Error)` -> `Result[T].Error(error Error)`
- 所有 `given[T Deref] ...` / `given[T Eq and Deref] ...` / `given[T Hash and Deref] ...` 移除 `Deref`
- 所有 iterator adaptor 类型的 `next(*mutable self)` 统一改为 `next(self)`
- 所有 `given ... as Drop { drop(source *unsafe mutable Self) ... }` 统一改为 `drop(self)`

### 8.2 `Std.Container`

以下类型全部改为 `type mutable`：

- `PriorityQueue[T]`
- `PriorityQueueIterator[T]`
- `Queue[T]`
- `QueueIterator[T]`
- `Stack[T]`
- `StackIterator[T]`

签名迁移规则：

- `count(*self)` -> `count(self)`
- `peek(*self)` -> `peek(self)`
- `push(*mutable self, value T)` -> `push(self, value T)`
- `pop(*mutable self)` -> `pop(self)`
- `iterator(*self)` -> `iterator(self)`
- `next(*mutable self)` -> `next(self)`
- 所有 `T Deref` 约束移除

### 8.3 `Std.Io`

#### trait

旧：

```koral
trait Reader {
    read(*self, into: *mutable List[UInt8], span: Range[UInt] = ..) Result[UInt];
}

trait Writer {
    write(*self, from: List[UInt8], span: Range[UInt] = ..) Result[UInt];
    flush(*self) Result[Void];
}

trait Seeker {
    seek(*self, pos SeekOrigin) Result[UInt64];
}
```

新：

```koral
trait Reader {
    read(self, into: List[UInt8], span: Range[UInt] = ..) Result[UInt];
}

trait Writer {
    write(self, from: List[UInt8], span: Range[UInt] = ..) Result[UInt];
    flush(self) Result[Void];
}

trait Seeker {
    seek(self, pos SeekOrigin) Result[UInt64];
}
```

#### 类型分类

改为 `type mutable`：

- `BufReader[R]`
- `BufWriter[W]`
- `ByteBuffer`

保持 `type`：

- `IoError`
- `SeekOrigin`

#### 迁移说明

- `into: *mutable List[UInt8]` -> `into: List[UInt8]`
- 因为 `List` 现在是 `type mutable`，不再需要再包一层托管 mutable ref
- `IoError as Error` 的 `message(*self)` -> `message(self)`
- `Reader.read_all(*self)` -> `read_all(self)`
- `Writer.write_all(*self, ...)` -> `write_all(self, ...)`
- 任何基于 generic `borrow_ptr() -> *unsafe T` 的公开接口都需要缩小适用范围或改设计

### 8.4 `Std.Os`

#### 类型分类

改为 `type mutable`：

- `File`
- `DirIterator`
- `WalkDirIterator`

保持 `type`：

- `Path`
- `DirEntry`
- `OpenMode`
- `FileType`
- `Permission`
- `FileInfo`

#### 关键签名变化

- `File.read(*self, into: *mutable List[UInt8], ...)` -> `File.read(self, into: List[UInt8], ...)`
- `File.write(*self, from: List[UInt8], ...)` -> `File.write(self, from: List[UInt8], ...)`
- `File.seek(*self, pos SeekOrigin)` -> `File.seek(self, pos SeekOrigin)`
- `DirIterator.next(*mutable self)` -> `DirIterator.next(self)`
- `WalkDirIterator.next(*mutable self)` -> `WalkDirIterator.next(self)`
- `DirEntry` / `Path` / `FileInfo` 这类值对象保留 `type`，receiver 统一改成 `self`

#### 设计备注

- `Path` 是不可变类型，路径操作返回新值
- `File` 是可变类型，文件句柄状态共享
- `DirEntry` 更适合作为只读快照值，而不是共享对象
- `foreign type` 继续承担真正 C ABI 对象的 pointer 互操作

### 8.5 `Std.Sync`

以下类型全部改为 `type mutable`：

- `AtomicBool`
- `AtomicInt`
- `AtomicUInt`
- `SendChannel[T]`
- `RecvChannel[T]`
- `LatchGate`
- `Lazy[T]`
- `Mutex`
- `MutexCondvar`
- `Semaphore`
- `SharedMutex`
- `SharedMutexCondvar`

签名迁移规则：

- 所有 `load(*self)` / `store(*self)` / `lock(*self)` / `unlock(*self)` 改为 `self`
- channel 的 `send(*self)` / `recv(*self)` 改为 `send(self)` / `recv(self)`
- `Lazy.get(*self)` -> `Lazy.get(self)`

这些类型都带共享同步状态，是 `type mutable` 最典型的目标。

弱引用不是自动获得的：

- 如果某个同步类型需要参与 weak graph，必须满足 `mutable` 约束
- 否则不生成 weak count 支持

### 8.6 `Std.Proc`

改为 `type mutable`：

- `Command`满足 `mutable` 约束
- `Process`
- `StdinPipe`
- `StdoutPipe`
- `StderrPipe`

保持 `type`：

- `CommandOutput`
- `ExitStatus`
- `IoRedirect`

关键变化：

- `Command` 继续保留 builder 风格，但其语义现在由 `type mutable` 承担
- `CommandOutput.is_success(*self)` -> `is_success(self)`
- `ExitStatus.code(*self)` -> `code(self)`
- `StdoutPipe.read(*self, into: *mutable List[UInt8], ...)` -> `read(self, into: List[UInt8], ...)`
- `Process` / pipe / command 类型若需要 weak 引用，也必须满足 `mutable` 约束

### 8.7 `Std.Text`

改为 `type mutable`：

- `Regex`
- `MatchIterator`
- `CapturesIterator`
- `RegexSplitIterator`

保持 `type`：

- `RegexFlag`
- `Match`
- `Captures`

关键变化：

- `Formattable` / `Parseable` / `RadixParseable` 表面不需要 mutability 额外语法
- 所有 iterator `next(*mutable self)` -> `next(self)`
- `Regex` 作为编译后的共享对象，适合 `type mutable`

### 8.8 `Std.Net`

改为 `type mutable`：

- `TcpListener`
- `TcpSocket`
- `UdpSocket`

保持 `type`：

- `Ipv4Addr`
- `Ipv6Addr`
- `IpAddr`
- `Shutdown`
- `SocketAddr`

签名迁移模式和 `Std.Os` / `Std.Io` 一致：

- receiver 全部改为 `self`
- 任何 `into: *mutable List[UInt8]` 风格参数改为 `List[UInt8]`

### 8.9 `Std.Async`

改为 `type mutable`：

- `Task`
- `Thread`
- `Timer`
- `Ticker`

保持 `type`：

- 结果值、状态值、配置快照

原因：

- 这类类型有共享运行时状态或句柄身份
- receiver 语法统一后，其 API 应全面切到 `self`

### 8.10 `Std.Rand`

改为 `type mutable`：

- `Random[R]`
- `DefaultRandomSource`

保持 `type`：

- 纯值结果、seed snapshot、distribution parameter value

原因：

- RNG 本质上维护可变内部状态

### 8.11 `Std.Time`

保持 `type`：

- `ClockTime`
- `Date`
- `DateTime`
- `MonoTime`
- `Duration`

条件性使用 `type mutable`：

- `TimeZone`，如果其实现需要共享缓存或外部句柄，则使用 `type mutable`

说明：

- 时间点、时间跨度更适合作为不可变类型
- 带缓存或系统句柄语义的时区对象可升级为可变类型

### 8.12 `Std.Json`

保持 `type`：

- `JsonValue`
- `JsonError`

关键变化：

- `JsonValue` 的递归 payload 直接写成 `List[JsonValue]` / `Dict[String, JsonValue]`
- `JsonError as Error` 的 `message(*self)` 改为 `message(self)`

### 8.13 generic 容器内部表示与当前指针设计

当前 `ListStorage[T]` / `DictStorage[K, V]` 这类实现大量依赖：

- `*unsafe mutable T`
- `*unsafe mutable DictBucket[K, V]`
- `alloc_memory[T]`
- `copy_memory` / `move_memory` / `init_memory` / `deinit_memory`

在当前 Koral 实现中，这种“任意 `T` 都能被 raw pointer 化”的设计直接支撑了泛型容器实现。

因此，如果你决定保留当前指针 generality，RFC 这里更合适的写法应该是风险说明而不是迁移要求：

1. `List[T]` / `Dict[K, V]` / `Deque[T]` 可以继续使用 typed raw storage
2. 这能保持现有 intrinsic 与 std 实现模式的一致性
3. 代价是 plain `type` 的布局自由会受到 raw pointee 语义约束

换句话说，这里不是“必须重构容器内部表示”，而是：

- 若保留当前指针设计，则容器内部实现可以基本延续
- 但 RFC 必须承认这是以缩小一部分隐藏布局自由为代价换来的

规范级收口后，这一节应被理解为：

1. 泛型容器延续当前 typed raw storage 实现是允许的
2. 一旦这样做，相关元素类型就进入了 raw pointee 语义约束面
3. 编译器若希望对某类类型继续保留更强的隐藏布局自由，就需要禁止这些类型进入对应容器的 raw storage 路径，或为其提供单独规则

也就是说，这不是语言表面的新限制，而是实现层必须正视的一组代价交换。

### 8.14 需要集中清理的 std 模式

无论具体模块如何分类，以下模式需要全库统一清理：

1. `given[T Deref] ...` 约束
2. `given[T Eq and Deref] ...` / `given[T Hash and Deref] ...`
3. 所有 `*self` / `*mutable self` receiver
4. 所有 `*Trait` / `*mutable Trait` public surface
5. 所有 `Result[T].Error(* Error)` 风格 payload
6. 所有 `into: *mutable List[UInt8]` / `read(*self, into: *mutable ...)`
7. 所有以 `ensure_unique` / `is_unique` 为前提的 COW 实现
8. 所有 `upgrade_mutable` / `downgrade_mutable`
9. 所有面向任意 `T` 的 `*unsafe T` raw storage 假设，都需要在实现章节明确它们对布局自由的约束

## 9. 额外说明与边界

### 9.1 这不是 borrow checker 方案

本 RFC 明确**不**引入：

- borrow type
- use-site mutability
- lifetime annotation
- Rust 风格 aliasing/exclusivity 规则

### 9.2 这不是“所有非 mutable 类型都必须是纯栈值”的方案

plain `type` 只是用户看来是不可变类型，不代表：

- 它必须不走 ARC
- 它必须不做 hidden sharing
- 它必须不递归
- 它必须不能 `Drop`

### 9.3 这不是 mutable enum 方案

可变枚举暂时完全不纳入本 RFC，避免扩大设计面。

## 10. 总结

| 维度 | 当前 | 本提案 |
|---|---|---|
| nominal type 声明 | `type` + 字段级 `mutable` + managed refs | `type` / `type mutable` + 字段级 `mutable` |
| 安全引用 | `*T` / `*mutable T` / `&` / `box()` | 移除 |
| 弱引用 | `?*T` / `?*mutable T` | `?T`（仅满足 `mutable` 约束的类型） |
| receiver | `self` / `*self` / `*mutable self` | 统一 `self` |
| trait object | `*Trait` / `*mutable Trait` | `Trait` |
| 容器语义 | COW | 共享语义 + `clone()` |
| `Deref` | 广泛存在 | 移除 |
| 递归 | 显式引用 break edge | 编译器自动隐藏间接层 |
| `Drop` | `drop(*unsafe mutable Self)` | `drop(self)` |
| ARC | 用户可见地绑定到托管引用模型 | 编译器 / runtime 实现细节，不再暴露为用户可见的类型系统轴 |
| unsafe pointer | 与托管引用并存 | 保留；若继续支持指向普通 Koral 类型，则会约束布局自由与优化边界 |
| `foreign type` | 与 C 互操作 | 保留，继续承担 C ABI 值布局 |

这个提案的本质是：

- **把“类型可变性”和“字段可变性”都保留在语言表面**
- **把“布局与所有权细节”收回到编译器实现层**
- **把当前最脆弱的托管引用 + escape analysis + COW 联动链整体删除**
- **把 weak 能力做成显式 opt-in，而不是所有可变类型默认承担成本**
- **如果保留 raw pointer 对普通 Koral 类型的支持，就必须接受它会反向约束布局自由与优化边界**

规范层面的最终含义是：

- 弱引用能力是否可用，由类型是否满足 `mutable` 约束决定
- `drop(self)` 虽然表面简洁，但仍是受限析构上下文
- `*unsafe T` 若继续支持普通 Koral 类型，就不再是“纯实现细节”，而是对布局与优化边界有约束力的语言承诺

这样可以在不引入 borrow checker、也不引入使用处 mutability 的前提下，显著降低 Koral 类型系统与实现的复杂度。
