# Koral `ref` 生命周期整改方案

## 状态

- 状态：当前阶段已完成
- 范围：语言语法、sema、MIR/lowering、std、bootstrap、测试、samples、toolchain、文档
- 目标：用显式的“托管 ref / 借用 ref”语义，替换当前依赖逃逸分析决定 `ref` 行为的隐式双态模型

## 本轮实施结论

本轮整改已经按既定范围落地完成，当前 compiler、bootstrap、std、tests、samples、toolchain 已对齐到新的 borrowed `ref` 固定语义：

- 生命周期语法采用 `'a` / `'_`
- `ref 'a T` / `ref 'a mut T` 作为借用引用类型接入前端类型系统
- `self ref` / `self ref mut` 解释为 borrowed receiver sugar（等价于 `self ref '_ Self` / `self ref '_ mut Self`）
- `self ref Self` / `self ref mut Self` 保留为显式托管 receiver
- `.ref` 改成借用优先，只有当前局部上下文明确要求托管 `ref` 时才发生局部提升
- compiler 与 bootstrap 中旧的跨函数逃逸分析兼容路径已删除
- borrowed `ref` 与托管 `ref` 继续共用同一套 runtime 布局和 retain / release 机制

## 本轮已完成的实际改动

### 前端与类型系统

- lexer / parser 支持 `'a`、`'_`、`ref 'a T`、`ref 'a mut T`
- AST、Type、type resolver、monomorphizer、method lookup、trait dispatch 已识别 borrowed `ref`
- receiver 语义完成切换：
  - `self ref` => `self ref '_ Self`
  - `self ref mut` => `self ref '_ mut Self`
  - `self ref Self` / `self ref mut Self` 继续表示托管 receiver
- borrowed `ref` 的非法位置限制已接入：
  - 禁止返回
  - 禁止字段存储
  - 禁止 enum payload 存储
  - 禁止全局存储
  - 禁止闭包捕获

### `.ref` / lowering / codegen

- `.ref` 已改成 borrow-first 固定语义
- 传给托管 `ref` / `ref mut` 形参时，会在当前函数内做局部托管提升
- `ref mut` 与 `ref 'a mut` 的规则保持对称
- MIR lowering、promotion、verifier、codegen 已按 borrowed / managed 分流后的语义刷新
- lambda capture 被视为逃逸边界，禁止把 borrowed forwarding 错误回退成 stack borrow

### runtime 与内存管理修复

- borrowed `ref` 与托管 `ref` 继续共用现有 `__koral_Ref` ABI
- retain / release 行为保持一致，不新增 borrow-only runtime object
- 新增 slot drop 路径，修复这轮变更引入的泄漏：
  - `__koral_ref_slot_drop`
  - `__koral_weakref_slot_drop`
  - `__koral_closure_slot_drop`

### 标准库、自举与测试迁移

- std 中依赖旧 receiver / `.ref` 隐式行为的 API 已迁到 borrowed 语义
- bootstrap parser / sema / MIR / codegen 已同步到新语义
- samples 与 toolchain 已完成语法和语义适配
- compiler tests 已补齐 borrowed `ref` 正反例，并更新旧用例到新语法

## 背景

今天的 Koral 里，`ref T` / `ref mut T` 实际上有两种实现语义：

- 当前函数内的非逃逸借用
- 可逃逸的托管引用

这两种语义目前由逃逸分析隐式决定。问题在于：

- `x.ref` 到底只是临时借用，还是会变成可逃逸的托管引用，不能只靠当前语句看出来
- 读一个函数签名，不能直接知道参数和返回值的所有权语义
- compiler 和 bootstrap 都要维护跨函数逃逸分析
- std 和测试里已经出现了不少“先借用，后面再看是否逃逸”的隐式依赖

这次整改的核心方向是：

- 把“托管 ref”和“借用 ref”拆成两套显式前端类型语义
- 删除跨函数逃逸分析
- 让大多数所有权判断都能只看当前函数、局部上下文和直接调用目标

## 核心结论

Koral 后续将有两套 `ref` 语义：

- `ref T` / `ref mut T`
  - 托管 ref
  - 允许逃逸
  - 可以存字段、存容器、存枚举 payload、返回、跨函数长期持有

- `ref 'a T` / `ref 'a mut T`
  - 借用 ref
  - 只允许出现在函数参数和 receiver 语义位置
  - 不允许逃逸
  - 不允许存字段、不允许作为构造结果的一部分返回、不允许存入闭包环境

这里的差异是**前端语义差异**，不是运行时表示差异。

## 最重要的运行时约束

### 运行时布局不区分借用/托管

本方案明确规定：

- 借用 ref 与托管 ref 使用**相同的内存布局**
- 借用 `ref 'a T` 与托管 `ref T` 的 ABI 形状一致
- 借用 `ref 'a mut T` 与托管 `ref mut T` 的 ABI 形状一致
- codegen / runtime 仍然沿用当前 Koral `ref` 的 retain / release 行为

也就是说：

- 不引入新的 borrow-only runtime object
- 不引入新的 borrow-only C ABI
- 不引入新的“无 retain/release 的轻量引用”后端表示
- 不在运行时区分“这是借用 ref，还是托管 ref”

借用 ref 与托管 ref 的区别只体现在**前端静态语义**：

- 哪些位置允许出现
- 是否允许逃逸
- 是否允许存储
- receiver sugar 如何解释
- 调用点是否允许重借用
- `.ref` 在当前上下文里被推断成哪一类 ref

这条约束很重要，因为它意味着：

- 后端和 runtime 不需要引入一整套新的生命周期对象模型
- bootstrap 与 Swift compiler 的对齐成本明显更低
- 生命周期整改主要集中在 parser / sema / API surface，而不是 runtime 重写

### retain / release 行为保持一致

本方案进一步规定：

- 借用 ref 与托管 ref 产生相同的 retain / release 行为
- 不因为类型写成 `ref 'a`，就生成另一套特殊 retain / release 路径
- 生命周期限制只由前端检查保证，而不是由运行时对象种类保证

可以把它理解为：

- `ref 'a T` 和 `ref T` 在运行时都是同一种 “Koral ref”
- 只是 `ref 'a T` 在语义上被禁止逃逸、禁止存储、禁止升级成长期所有权

因此本方案不是“新增一套 borrow runtime”；
而是“在保留现有 runtime ref 机制的前提下，收紧语言前端语义”。

## 目标

- 让 `ref` 语义能从当前函数签名和局部上下文直接理解
- 删除 compiler 和 bootstrap 中的跨函数逃逸分析
- 保留可逃逸托管 ref 作为一等类型
- 为 receiver 和普通参数引入显式借用 ref 语义
- 在不重做 runtime 布局的前提下完成这次语言整改

## 非目标

- 不完整复制 Rust 的 borrow checker
- phase 1 不支持借用返回值
- phase 1 不支持把借用 ref 存进字段、枚举 payload、全局、闭包环境
- 不重定义 raw pointer 语义
- 不在 phase 1 引入 HRTB 一类更高阶生命周期系统

## 类型模型

### 托管 ref

`ref T` / `ref mut T` 是可逃逸的托管 ref。

属性：

- 可返回
- 可存字段
- 可存容器
- 可存枚举 payload
- 可转 `weakref`
- `ref mut T` 可宽化为 `ref T`

### 借用 ref

`ref 'a T` / `ref 'a mut T` 是不可逃逸的借用 ref。

属性：

- 只能绑定到当前函数声明的生命周期参数
- 只能在前端受限位置出现
- phase 1 不允许返回
- phase 1 不允许存字段 / 枚举 payload / 全局 / 闭包环境
- 不允许转 `weakref`
- `ref 'a mut T` 可宽化为 `ref 'a T`

再次强调：这些限制是**静态语义限制**，不是运行时对象差异。

## 语法决策

### 最终选择：前导 `'` + 严格小写

生命周期语法采用 Rust / OCaml 风格的前导 `'`，严格小写：

```koral
let f['a](x ref 'a Int) Int
let swap['a](x ref 'a mut Int, y ref 'a mut Int) Void
```

匿名生命周期使用 `'_`：

```koral
self ref                // sugar for self ref '_ Self
self ref mut            // sugar for self ref '_ mut Self
```

### 为什么用 `'a` 而不是 `$a`

`$a` 工程上稳定但可读性差——`$` 在主流语言里的语义是变量展开（shell / PHP / 模板），用它表示 lifetime 不自然。`'a` 在 Rust / OCaml / SML / F# 里都有类型参数/lifetime 的语义基础，用户直觉上更容易接受。

### 为什么严格小写

遵循 Rust / OCaml 的惯例：类型参数大写（`T`、`U`），lifetime 参数小写（`'a`、`'b`）。这样在泛型列表里两者一目了然：

```koral
let f['a, T](x ref 'a T) T
//    ^^  ^
//    |   └─ type parameter (大写)
//    └──── lifetime parameter (小写 + ' 前缀)
```

### 为什么不和字符字面量冲突

Koral 的 rune literal 是 `'X'`（两个引号闭合），lifetime 是 `'a`（只有前导引号）。Lexer 只需要一个字符的 lookahead：

```
遇到 '
 ├─ 下一个是字母 → 读 identifier
 │   ├─ 后面紧跟 ' → rune literal: 'X'
 │   └─ 后面不是 ' → lifetime: 'a
 │
 └─ 下一个是 \ → 读转义 → rune literal: '\n'
```

这和 OCaml / F# / Rust 的 lexer 是同一种状态机，没有歧义。

### 为什么不用大写 `'A`

Koral 的惯例是类型层面统一大写，但 `'a` 选择小写是因为：

- 前导 `'` 已经在 lexer 层区分了 lifetime 和 type parameter，大小写不需要再重复做这件事
- 小写 lifetime + 大写 type parameter 在泛型列表里视觉对比更强
- 与 Rust / OCaml 用户的肌肉记忆一致

### 其他备选方案的排除

| 方案 | 排除原因 |
|---|---|
| `'a` | `$` 语义是变量展开，可读性差 |
| `` `a `` | 键入不顺手，markdown / 终端噪音大 |
| 裸 `a` | 与泛型 / 下标语法冲突，靠大小写约定不稳 |
| 独立参数通道 `<'a, T>` | 需要新增一整套参数列表语法，改动面偏大 |

## receiver 语法

### 借用 receiver sugar

保留：

- `self ref`
- `self ref mut`

语义糖解释为：

- `self ref` => `self ref '_ Self`
- `self ref mut` => `self ref '_ mut Self`

这里的 `'_` 表示匿名生命周期参数，仅作为 receiver sugar 使用。

### 显式托管 receiver

如果需要可逃逸的 receiver，必须显式写全：

- `self ref Self`
- `self ref mut Self`

这样可以强制把“借用 receiver”和“可逃逸 receiver”在源码层区分开。

## 调用规则

### 借用参数

对于参数类型 `ref 'a T`：

- 可从不可变值或可变值重借用只读引用
- 可从 `ref T` / `ref mut T` 重借用只读借用 ref
- 可对右值做只读临时物化

对于参数类型 `ref 'a mut T`：

- 只能从可写位置借用
- 可从 `ref mut T` 重借用为 `ref 'a mut T`
- 不接受右值

### 托管参数

对于参数类型 `ref T` / `ref mut T`：

- 调用方必须提供托管 ref
- 不再做“跨函数逃逸分析后隐式决定要不要升级”的全局推导
- 如果需要从值构造托管 ref，应通过 `.ref` / `box(...)` 这类显式入口完成

## `.ref` 规则

`.ref` 继续保留，但语义改成**借用优先**。

规则：

- 只允许从“值路径”出发
- 允许形式：
  - `x.ref`
  - `self.field.ref`
  - `node.left.right.ref`
- 不允许形式：
  - `make_value().ref`
  - `list[i].ref`
  - `ptr.val.ref`
  - `some_ref.field.ref`

解释规则：

- 默认优先构造成借用 ref
- 如果当前局部上下文明确要求托管 ref，则在本地完成隐式提升
- 这个决定只能依赖当前函数、局部存储方式、直接 callee 签名，不允许再做跨函数逃逸分析

### `ref mut` 也允许同样的局部提升

这条必须与 `ref` 保持对称：

- 可写值路径既可以满足 `ref 'a mut T`
- 也可以在需要时局部提升满足 `ref mut T`

这样规则更统一：

- “值路径上的 `.ref` 可以满足借用 ref，也可以在当前局部上下文需要时提升成托管 ref”

## 允许与禁止的位置

### phase 1 允许

- 函数参数
- 方法参数
- trait requirement 的参数
- receiver sugar 对应的借用 receiver

### phase 1 禁止

- 借用 ref 返回值
- 字段类型里出现借用 ref
- 枚举 payload 里出现借用 ref
- 全局类型里出现借用 ref
- 闭包捕获环境里出现借用 ref
- `weakref` 的借用版本

## trait object 与借用 ref

phase 1 的原则是：

- 允许 `ref 'a TraitObject` 这类借用 trait object 参数形态
- 但它的运行时表示仍然与当前 trait object ref 保持一致
- 不为 borrowed trait object 设计新的 runtime 布局

仍然禁止：

- 返回借用 trait object
- 存储借用 trait object

## 语义收益

这套方案的主要好处：

- 看签名就知道是不是借用语义
- 删除跨函数逃逸分析后，compiler 和 bootstrap 的语义复杂度会明显下降
- receiver 语义更稳定：`self ref` 就是借用，`self ref Self` 才是可逃逸托管
- `.ref` 的行为更局部，不再需要“调用完整个调用链之后才知道这里是不是堆分配”
- runtime 不需要重做一套 borrow-only 实现

## 代价与风险

- 需要迁移 std / bootstrap / tests / samples / toolchain 上大量 receiver 与参数签名
- 需要为编辑器高亮补上 `$` 生命周期 token 支持
- 如果继续用 `'a`，编辑器生态成本会上升
- 如果未来改成独立生命周期参数通道，需要再做一次表面语法升级

## 实施顺序

推荐顺序：

1. 先确定生命周期表面语法
2. parser 支持借用 ref 类型与生命周期参数
3. sema 增加借用 ref 位置限制与重借用规则
4. 把 `self ref` / `self ref mut` 重解释为借用 sugar
5. 删除跨函数逃逸分析
6. 迁移 std
7. 迁移测试
8. 迁移 bootstrap
9. 迁移 samples / toolchain
10. 更新用户文档与开发文档

## 架构整改总览

这轮 borrow ref 整改，不是单点 parser 改动，而是一次跨前端到后端的“语义重新分层”：

1. 词法与语法层
   - 目标：把 `'a` 生命周期和 `ref 'a T` / `self ref` sugar 稳定落成语法事实
   - 涉及：
     - lexer 新 token：`'a`、`'_`
     - parser 支持借用 ref type node
     - parser 支持 receiver sugar：`self ref` => `self ref '_ Self`
     - parser 允许生命周期参数进入 `[]`，但与普通类型参数分开处理

2. AST / 类型表示层
   - 目标：把“托管 ref”和“借用 ref”在前端类型系统里显式区分
   - 涉及：
     - `TypeNode.borrowedReference`
     - `Type.borrowedReference` / `Type.mutableBorrowedReference`
     - debug name / layout key / pretty printer / substitution / equality / canonicalization

3. 声明签名收集层
   - 目标：所有函数、given、trait、receiver 在 collect-signature 阶段就拿到正确借用语义
   - 涉及：
     - 方法 receiver 解析
     - trait requirement 签名
     - given method 签名
     - generic template 签名
     - 生命周期参数不能污染普通泛型模板注册

4. 语义检查层
   - 目标：把借用 ref 的“可出现位置”和“不可逃逸规则”收紧成静态规则
   - 涉及：
     - 允许位置：函数参数、method 参数、trait 参数、receiver
     - 禁止位置：返回、字段、enum payload、全局、闭包捕获、构造器结果
     - `self ref` 与 `self ref Self` 的语义分流
     - `ref 'a mut T` 的可写性检查
     - `ref mut T -> ref T`、`ref 'a mut T -> ref 'a T` 宽化

5. 调用点与隐式构造层
   - 目标：把今天“靠逃逸分析决定 ref 行为”的逻辑，替换成局部可解释规则
   - 涉及：
     - `.ref` 借用优先
     - 值路径 / 字段路径的局部托管提升
     - borrowed receiver 的自动重借用
     - rvalue `self ref` 的临时物化
     - `ref 'a` 与托管 `ref` 的禁止升级边界

6. trait / method dispatch 层
   - 目标：保证借用 receiver 不会把方法分派链打断
   - 涉及：
     - concrete method lookup
     - generic extension method lookup
     - trait placeholder 解析
     - trait object method call
     - receiver base 对齐
     - object safety 中 receiver 识别

7. monomorphization 层
   - 目标：在模板实例化后，把借用 ref receiver / 参数重新绑定到正确 concrete method
   - 涉及：
     - borrowed ref 参与 expected-method-type 匹配
     - reference-like wrapper lookup 扩展到 `BorrowRef` / `BorrowMutRef`
     - placeholder -> methodReference / traitMethodCall 的转换
     - generic struct / enum 上的借用 receiver 方法重解

8. MIR lowering 层
   - 目标：borrowed ref 在 MIR 中既保持“运行时与托管 ref 同布局”，又保持前端语义差异
   - 涉及：
     - borrowed ref 参数 / receiver 的 lowering
     - `when self in` 等 pattern lowering
     - borrowed call argument lowering
     - borrowed receiver call lowering
     - trait object / enum / generic enum 上的 borrowed pattern access

9. CodeGen / runtime 接口层
   - 目标：后端继续复用现有 `__koral_Ref` ABI，但不能再假设所有 `self ref` 都来自旧 managed 语义
   - 涉及：
     - function symbol type 刷新
     - direct call argument packaging
     - generic struct / enum C type name 生成
     - borrowed stack ref / heap-owned ref 的统一 C ABI
   - 约束：
     - 不新增新 runtime borrow object
     - 不新增新 retain/release 机制

10. 标准库与自举编译器层
   - 目标：`std`、`bootstrap` 上千处 `self ref` 默认切成借用后，行为仍保持稳定
   - 涉及：
     - std 方法 receiver 批量切到借用 sugar
     - bootstrap parser / sema / MIR / codegen 全面对齐
     - 必须先让 Swift compiler 路径稳定，再迁 bootstrap

## 分阶段任务清单

下面的清单按“先打通 Swift compiler，再迁上层生态”的依赖关系组织。
这部分保留为历史实施计划；当前实际完成状态以下文“落地结果与验收”一节为准。

### 阶段 A：语法与类型骨架

- [ ] lexer 支持 `'a` / `'_`
- [ ] parser 支持 `ref 'a T` / `ref 'a mut T`
- [ ] parser 支持生命周期参数列表
- [ ] AST / Type 增加 borrowed ref 类型表示
- [ ] pretty-print / debug / substitution / equality 全部识别 borrowed ref

验收：

- `swift build` 通过
- 最小 borrowed 参数 smoke case 能过

### 阶段 B：receiver 语义切换

- [ ] `self ref` -> `self ref '_ Self`
- [ ] `self ref mut` -> `self ref '_ mut Self`
- [ ] `self ref Self` / `self ref mut Self` 保留为显式托管写法
- [ ] receiver 错误消息更新
- [ ] trait object safety / receiver type check 更新

验收：

- receiver 语法测试更新并通过
- `self ref` 方法在语义层被视为 borrowed receiver

### 阶段 C：借用位置限制与局部构造规则

- [ ] 禁止 borrowed ref 返回
- [ ] 禁止 borrowed ref 存字段 / enum payload / 全局 / 闭包环境
- [ ] `.ref` 借用优先规则定型
- [ ] 值路径局部托管提升规则定型
- [ ] `ref mut` / `ref 'a mut` 的对称提升和宽化打通

验收：

- 新增负例测试：返回 borrowed ref、存储 borrowed ref、非法提升
- 删除旧跨函数逃逸分析前，局部规则已能表达现有合法代码

### 阶段 D：方法分派与泛型实例化

- [ ] concrete method lookup 识别 borrowed receiver
- [ ] generic extension lookup 识别 `BorrowRef` / `BorrowMutRef`
- [ ] trait placeholder 解析识别 borrowed receiver
- [ ] trait object dispatch 保持可用
- [ ] method reference base 对齐识别 borrowed ref

验收：

- `to_string`、`join`、`iterator` 这类 trait/extension/generic 方法在 borrowed receiver 下能重绑定成功

### 阶段 E：MIR / CodeGen 打通

- [ ] borrowed receiver call lowering 正确生成 `__koral_Ref`
- [ ] borrowed 普通参数 call lowering 正确生成 `__koral_Ref`
- [ ] generic enum / struct 的 borrowed pattern lowering 打通
- [ ] function symbol type / concrete method symbol 在 codegen 前全部刷新
- [ ] generic instantiation 的 C type name 不再被当成 unresolved

验收：

- Swift compiler 能完整编译 `std`
- C 后端不再出现“值实参传给 `struct __koral_Ref` 形参”的系统性错误

### 阶段 F：删除旧逃逸分析

- [ ] compiler 删除旧跨函数逃逸分析逻辑
- [ ] bootstrap 删除同类逻辑
- [ ] 所有 `.ref` 决策只依赖当前局部上下文和直接签名

验收：

- 行为回归测试通过
- 不再存在“调用链后验决定 ref 语义”的路径

### 阶段 G：生态迁移

- [ ] std
- [ ] tests
- [ ] bootstrap
- [ ] samples
- [ ] toolchain
- [ ] 文档

验收：

- 全量测试通过
- bootstrap compiler 构建通过
- samples / toolchain 构建通过

## 架构改造总览

为了把 borrowed `ref` 真正落地，这轮整改不是“只加一个生命周期类型分支”就结束，而是要同时收口五条链路：

1. 语法链
   - 负责把 `'a` / `'_`、`ref 'a T`、`self ref` sugar 解析成稳定 AST

2. 类型与约束链
   - 负责让 borrowed `ref` 成为一等类型，并在 sema 中限制它的出现位置与逃逸边界

3. 方法分派链
   - 负责把 `self ref` / `self ref mut` 全量重解释为 borrowed receiver sugar
   - 同时保留 `self ref Self` / `self ref mut Self` 作为显式托管 receiver

4. 引用构造与 lowering 链
   - 负责把 `.ref` 改成“借用优先，局部逃逸才提升到托管 ref”
   - 这是删除旧跨函数逃逸分析的关键前提

5. 后端与生态链
   - 负责 borrowed / managed 共用当前 runtime 布局与 retain/release 行为
   - 再把 std、bootstrap、samples、toolchain 逐层迁完并验收

## 需要改动的架构点

### 1. Parser / AST

- lexer 需要把 `'a`、`'_` 识别成独立 lifetime token
- parser 需要支持：
  - `ref 'a T`
  - `ref 'a mut T`
  - `self ref`
  - `self ref mut`
  - `self ref Self`
  - `self ref mut Self`
- AST 需要同时容纳：
  - borrowed receiver sugar
  - 显式托管 receiver
  - 生命周期参数表

### 2. Type / Sema

- `Type` 需要把 borrowed ref 纳入：
  - equality / hash
  - debug / pretty-print
  - generic substitution
  - layout key / stable key
- sema 需要明确三类限制：
  - borrowed `ref` 只能绑定到当前函数声明的生命周期参数
  - borrowed `ref` 不能返回
  - borrowed `ref` 不能进入字段、enum payload、全局、闭包环境等可存储位置
- `.ref` 的类型决定方式要从“后验逃逸分析”切到“局部先定型”：
  - 默认构造 borrowed `ref`
  - 只有值或值的 field 访问形式允许局部托管提升
  - 不允许 `ref 'a T` 直接隐式升级成 `ref T`

### 3. Method Lookup / Trait Dispatch

- 需要统一以下路径的 receiver 语义：
  - concrete method lookup
  - given / extension lookup
  - trait requirement matching
  - trait object dispatch
  - method reference / placeholder 重绑定
- 目标是：
  - 只要签名写 borrowed receiver，后续任何阶段都不能再偷偷回退到旧 managed receiver 假设

### 4. MIR / Reference Promotion

- MIR 与 codegen 仍复用当前 `__koral_Ref` ABI
- 但 lowering 必须继续保留 borrowed / managed 的前端类型差异，供 verifier 与 promotion 判断
- 这层要重点核对：
  - direct call argument packaging
  - receiver 调用 lowering
  - `when self in` / alias pattern / payload projection
  - generic enum / trait object 上的 borrowed pattern access
- `MIRReferenceAllocationPromoter` 需要改造成新的局部语义：
  - 不再依赖跨函数逃逸分析决定 `.ref` 是借用还是托管
  - 只在当前函数里，对确定要逃逸的值路径做托管提升
  - `box(expr)` 保持显式托管构造

### 5. CodeGen / Runtime

- borrowed `ref` 与托管 `ref`：
  - 运行时布局相同
  - retain / release 行为相同
  - C ABI 相同
- 因此前端和 codegen 需要保证：
  - 不会把值实参误传给 `struct __koral_Ref` 形参
  - borrowed receiver 不会走旧 receiver wrapper 假设
  - generic instantiation 的具体函数签名在 codegen 前已经完全刷新

### 6. Std / Bootstrap / Samples / Toolchain

- `std` 最容易暴露 receiver sugar、`.ref` 提升、trait dispatch 的真实兼容性
- `bootstrap` 需要同步删除旧 parser / sema / promotion 兼容逻辑
- `samples` / `toolchain` 负责最终真实代码面的回归，而不是语义试验场

## 实施顺序调整

为了完成 borrowed `ref` 固定语义，执行顺序需要收紧成下面这条主线：

1. 先稳定 Swift compiler 的 borrowed receiver 全链路
2. 再稳定 `.ref` 的“借用优先、局部逃逸才提升”规则
3. 然后补 borrowed `ref` 的非法位置限制
4. 再删除 Swift compiler 中旧跨函数逃逸分析残留
5. 之后迁 std 与 compiler tests
6. Swift 路径稳定后再迁 bootstrap
7. 最后跑 samples、toolchain 与文档回归

这样调整的原因是：

- receiver 链和 `.ref` 提升链是这轮整改最底层的两根承重梁
- 如果这两层没收口，越早迁 std / bootstrap，排查成本越高
- bootstrap 不应该在 Swift compiler 语义还漂移时并行推进

## 当前任务清单

### P0：收口 Swift compiler 当前主线

- [ ] 修完 borrowed receiver 相关的全量测试失败
- [ ] 同步 receiver 错误消息与测试样例
- [ ] 确认 `self ref` / `self ref mut` 在 method lookup、trait dispatch、MIR、codegen 上已经完全按 borrowed sugar 处理
- [ ] 用 std 高频路径持续回归：
  - `Range.iterator`
  - `Error.message`
  - `ToString.to_string`
  - `BufReader.fill_buf`

### P1：落实 `.ref` 的新固定语义

- [ ] `.ref` 在没有显式托管期望类型时，默认构造 borrowed `ref`
- [ ] 仅当当前局部上下文已经要求托管 `ref` 时，才做局部提升
- [ ] 限制允许自动托管提升的源表达式：
  - 值
  - 值的 field 访问
- [ ] 同步 `ref mut` / `ref 'a mut` 的对应规则
- [ ] 把这套规则落到 MIR promotion / lowering，而不是跨函数逃逸分析

### P2：补完 borrowed `ref` 的静态限制

- [ ] 禁止 borrowed `ref` 返回
- [ ] 禁止 borrowed `ref` 存字段
- [ ] 禁止 borrowed `ref` 进入 enum payload
- [ ] 禁止 borrowed `ref` 进入全局
- [ ] 禁止 borrowed `ref` 捕获进闭包环境
- [ ] 补齐诊断文案与负例测试

### P3：删除旧逃逸分析模型

- [ ] Swift compiler 删除旧跨函数逃逸分析入口、summary 传播与依赖
- [ ] MIR / 文档去掉“后验决定 ref 语义”的描述
- [ ] bootstrap 删除对应旧逻辑
- [ ] 回归验证 `box` 成为唯一显式托管构造器

## 当前实现策略

这一轮实现先采用一套更容易落地、也更符合“只看当前函数上下文就能理解”的固定策略：

1. `.ref` 的前端定型
   - 如果期望类型是 `ref T` / `ref mut T`，则 `.ref` 直接定型成托管 ref
   - 如果期望类型是 `ref 'a T` / `ref 'a mut T`，则 `.ref` 直接定型成 borrowed ref
   - 如果没有期望类型，则 `.ref` 默认定型成 `ref '_ T` / `ref '_ mut T`

2. 托管提升的判定位置
   - 不再根据“callee 后续会不会存起来”做跨函数传播
   - 只看当前 MIR 语句已经显式暴露出来的托管位置：
     - 赋值给托管 ref 类型本地变量
     - 写入字段 / payload / 全局等可存储位置
     - 传给签名里写成 `ref T` / `ref mut T` 的参数
     - 作为托管 ref 返回值返回
   - 命中这些位置时，把当前值树里的直接 `.ref(stackBorrow)` 提升成 `.ref(heapOwned)`

3. 不做的事情
   - 不做“先推成 borrowed，稍后再跨语句回溯改成 managed”的二次推断
   - 不做跨函数逃逸摘要
   - 不允许把已经形成的 `ref 'a T` 再隐式转成 `ref T`

这意味着：

- 直接写在托管上下文里的 `.ref` 仍然可以自动得到托管行为
- 没有托管期望类型的中间绑定，会先得到 borrowed 类型
- 如果后续确实要长期持有，应当在当前局部上下文里显式落到托管签名、托管变量或 `box(...)` 构造上

## 编译器改造清单

为了完成上面的固定语义，Swift compiler 当前需要按下面顺序收口：

### A. Sema 定型层

- [ ] `TypeCheckerExpressions.refExpression` 改成“borrowed 默认、托管按期望类型显式落位”
- [ ] 保持 `weakref` 只接受托管 ref
- [ ] `self ref` / `self ref mut` 继续只作为 borrowed sugar，不回退成 managed 默认

### B. MIR 本地提升层

- [ ] 删除 `MIRReferenceAllocationPromoter` 中的 interprocedural summary 固定点求解
- [ ] 改成按当前语句目的位置做局部提升
- [ ] 以 callee 形参类型而不是 callee 行为摘要决定 call-site 是否要求 heap-owned ref
- [ ] 保证 aggregate / enum payload / trait object 包装里的直接 `.ref` 也能递归提升

### C. 非法位置限制层

- [ ] 函数返回类型禁止 borrowed ref
- [ ] struct / foreign struct 字段禁止 borrowed ref
- [ ] enum payload 禁止 borrowed ref
- [ ] global / foreign let 类型禁止 borrowed ref
- [ ] closure capture 禁止 borrowed ref 进入环境

### D. 后续同步层

- [ ] bootstrap parser / sema / promotion 逻辑同步删旧模型
- [ ] std / tests 按新局部语义修正
- [ ] samples / toolchain 全量编译回归

### P4：生态迁移与验收

- [ ] std 全量适配
- [ ] tests 全量适配
- [ ] bootstrap 适配
- [ ] samples 构建通过
- [ ] toolchain 构建通过
- [ ] 中文文档补全最终语义

## 落地结果与验收

### 最终语义结论

- 生命周期语法采用 `'a` / `'_`，遵循 Rust / OCaml 风格，严格小写
- `ref T` / `ref mut T` 表示可逃逸托管引用
- `ref 'a T` / `ref 'a mut T` 表示不可逃逸借用引用
- `self ref` / `self ref mut` 是 borrowed receiver sugar
- `self ref Self` / `self ref mut Self` 是显式托管 receiver
- `.ref` 不是“永远构造托管引用”，而是优先构造借用引用；当当前局部上下文要求托管类型时，再在本地完成提升
- borrowed `ref` 与托管 `ref` 的运行时布局完全一致，retain / release 行为也一致；区别只在前端静态语义

### 已完成的迁移范围

- compiler：parser、sema、MIR、codegen、runtime 适配完成
- std：核心 IO、JSON、时间等受影响路径已完成适配
- tests：新增 borrowed `ref` 正反例，并更新旧语法与 receiver 相关用例
- bootstrap：语法、类型语义、lowering、codegen 对齐完成
- samples：全量编译通过
- toolchain：全量编译通过
- 文档：设计文档和中文语言文档已刷新到固定语义

### 验证结果

已完成以下验证：

1. compiler 全量测试通过

```bash
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc -j 6 --timeout 120
```

结果：`473/473` 通过。

2. bootstrap 编译通过

```bash
rm -rf bin/bootstrap
mkdir -p bin/bootstrap
compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap
```

结果：成功产出 bootstrap 编译器。

3. samples / toolchain 编译通过

```bash
compiler/.build/debug/koralc build samples/cat/src/cat.koral
compiler/.build/debug/koralc build samples/expr-eval/expr_eval.koral
compiler/.build/debug/koralc build toolchain/koralfmt/koralfmt.koral
compiler/.build/debug/koralc build toolchain/koral/koral.koral
compiler/.build/debug/koralc build toolchain/doc/generate_std_api_docs.koral
```

结果：全部成功。

### 后续可选工作

- 编辑器语法高亮补充 `'a` / `'_` 生命周期 token 支持
- 如果未来要让生命周期进入更宽的泛型位置，再单独评估是否需要独立参数通道
- 若后续继续扩展 borrow 语义，再评估是否需要更高阶生命周期能力，但这不属于当前阶段的整改范围
