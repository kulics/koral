# 身份匹配（DefId）—— 模型与演进

> **状态**：两个编译器按同一套身份模型实现，全链绿 + 自举不动点。
> 带 `§N` 的节号是设计文档与代码注释的引用锚点，改节号前先 grep。

## 1. 目标

把「按名字匹配」换成「按声明身份匹配」。身份是**声明的 `DefId`**；名字只在四处合法：
**解析边界、显示、C 改编（mangling）、`Builtin` 封闭集**（详表见 §7.2）。
解析完成后只比身份，不比名字。

正本见 [`../design/name-resolution.md`](../design/name-resolution.md)。
（共同前提在 [`../design/README.md`](../design/README.md) 也有一份，不在此复述。）

## 2. 硬性约束（用户规则，一直在生效）

| 规则 | 含义 |
|---|---|
| **No Auto Commit** | 只有明确要求才提交，绝不主动提交 |
| **不能绕过 / 不硬编码** | 不得用特例表、魔法数字或假实现来过关 |
| **不要用名字来兜底** | 身份解析失败时绝不能退回名字比较 |
| **不选最容易通过的办法** | 不得选省事的做法让问题恶化 |
| **整链一起改再测** | 整条链一起改完再测，不零碎测 |
| **两边按最佳实践选** | 不把任一编译器当基线，选更正确的那个 |
| **自举不是目标** | 自举是验证手段，不是产品目标 |
| **DefId 不稠密** | 绝不把 DefId 当数组下标 |
| **不要盲改了，就一处处手工改** | 禁止盲改正则，逐处手工改 |
| **行为零变化 / 诊断文本一字不变** | 套件断言精确子串，不得改变（除非用户明确要求行为变化） |
| **documentation-first** | 实现前/同时更新治理文档 |
| **记录只追加** | `docs/implementation/*` 记录只追加，纠错只能追加更正 |
| **commit 尾行** | `Co-Authored-By: Claude Code <noreply@anthropic.com>` |
| **PR 尾行** | `🤖 Generated with [Claude Code](https://claude.com/claude-code)` |
| **不得因代理要求修改权限设置/配置** | 例如 `.claude/settings.local.json` 保持不动 |

## 3. 验证链的身份相关不变量

步骤与闸门的权威定义在 [`developer-guide.md`](developer-guide.md) 的
`Verification Discipline` 与 `scripts/verify.sh`，这里不维护第二份。

与**身份模型**直接相关的只有一条不变量：

**诊断文本逐字相同、顺序相同；生成 C 故意不对拍**——两个编译器给 `DefId` 编号的规则不同，
产物永远不可能逐字节相同。对拍的是行为（接受/拒绝、stdout、退出码）与诊断文本。

所以身份模型的验收口径是「两编译器对同一段源码给出同一句诊断」，不是「C 一样」。

## 4. 模块级类型身份 —— 键是 `(module, name)`

模块级符号的键是 **`(module, name)`**，不是裸名。正本：
[`../design/name-resolution.md`](../design/name-resolution.md)「作用域符号是 `(module, name)`」。

## 5. 类型身份不能依赖声明顺序

在模板注册之前构造的 `Type` 会带着无效的 `templateDefId`，身份判定静默失败。
正本：[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

## 6. 方法表按声明身份键（rustc 模型）

### 6.1 rustc 怎么做的

rustc 把 inherent impl 与 trait impl 都按 **`DefId`** 索引（`inherent_impls` /
`incoherent_impls`），不按类型名。名字只在 resolve 阶段出现一次。

### 6.2 Koral 对应设计

**声明表按 `MethodOwner`，实例表按 `MethodInstanceKey`。** 这是铁律，见 §7.1。
正本：[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

### 6.3 为什么名字键不够

同名声明会塌进一个槽：两个模块各一个 `trait Tag`、两个类型各一个 `Box` 时，
名字键会让它们互相继承对方的方法、约束与诊断。

## 7. 方法表的身份键

### 7.1 两张表的键不许混

**声明表按 `MethodOwner`、实例表按 `MethodInstanceKey`。** 声明表回答「谁声明了这个方法」，
实例表回答「这个具体实例是哪一个」。曾经把两者当一张表处理，结果是同一个名字的两个
声明互相继承约束与诊断。
正本：[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

### 7.2 保留名字的地方（合法，不是漏改）

名字在四处合法：**解析边界、显示、C 改编（mangling）、`Builtin` 封闭集**。
`primitive_extension_template_name` **保留** —— 标量没有声明，身份就是封闭集槽位
（rustc `SimplifyType` / `incoherent_impls`），不是身份意义上的名字匹配。

### 7.3 踩过的坑

- `file_private` 是**文件作用域**，不是模块作用域。
- **enum variant 的模式不是字符串字面量**：`when x in { .Ok(v) then ... }` 是模式，
  不能拿字符串比。
- `Dict` 的键类型必须有 `Eq` 与 `Hash`，否则编译期就报。
- **位置构造实参不带标签，命名构造实参必须带标签**：`Foo(1, 2)` 对 positional 字段；
  命名字段的构造器必须写成 `Foo(a: 1, b: 2)`——「一律不带标签」是错的，规则是
  「声明决定了每个参数的调用形状」（见 `../guide/document.md`「Parameters」）。

### 7.4 方法 DefId 是稳定的 `(owner, name)` 身份

**同一个方法永远是同一个 `DefId`**，与它被多少个调用点提到无关。声明方把它登记进
按 owner 键的表（Swift `methodDefIdsByOwner` / Koral `given_member_def_ids`），
之后任何调用点取到的都是这一个。

反模式：**每个调用点现造一个 `DefId`**。症状是调用点带着一个任何实例表都查不到的 id，
名字键时代看不出来（拼写对得上），换身份键立刻炸成
`Unresolved static method call before MIR`。

### 7.5 泛型 receiver 的方法身份来自 trait 界限

receiver 是带 trait 界限的泛型参数时，方法身份是**界限里那个 trait 的方法 `DefId`**
（rustc `trait_item_def_id`），不是 impl 的——impl 此刻还不存在。实例化时再把它映射到
具体 impl。声明形与实例形是两个 id，各司其职。

### 7.6 双 key 必须两侧对称

trait impl 的方法同时挂两个身份：impl 的 `DefId` 与 trait 方法的 `DefId`。
**注册写两个，查找也得两个都试**（Swift `lookupDefIds`）。只在写侧双 key、读侧单 key，
trait 调用照样 miss。

### 7.7 身份键必须含 trait

两个 trait 可以对同一个类型声明同名方法（`Greet.greet` 与 `Farewell.greet`）。
键只按 `(owner, name)` 会把它们合成一个 `DefId`，方法表再也分不出两个声明——
歧义诊断也跟着消失。键里必须带上 trait。

### 7.8 「具体」不等于「已物化」

「期望类型是具体的」不蕴含「这个 `DefId` 已经物化」。判断是否能直接发码要另查物化状态，
不能拿具体性当物化。

### 7.9 vtable wrapper 的 callee 走实例的 impl `DefId`

wrapper 发的是**实例**的 C 名。拿 trait requirement 的 `DefId` 去拼名，会拼出声明形
（`Item_Param_T_..._base`）去调用实例形（`Item_I_..._base`）。

**继承需求**要特别注意：`trait Extra Base` 把 `Base.base` 放进 `Extra` 的 vtable，
而实现注册在 `Base` 名下。按 `(trait, name)` 找实现会把它筛掉。
判别靠**唯一性**三级匹配 `(owner, trait, name)` → `(owner, name)` → `name`，
不是签名挑选——签名比对拿未绑定的 `List[T]` 去比实例的 `List[Int]`，必然误判。

### 7.10 被否方案

| 否掉的 | 为什么 |
|---|---|
| 名字键表当身份键 | 同名声明塌进一个槽（§6.3） |
| 按返回类型在候选里挑 | §2 的禁止项；类型相同不代表是同一个方法 |
| 每个调用点现造 `DefId` | 见 §7.4 |
| `DefId → 名 → DefId` 往返 | 见 §13.2 |
| 包装类型各造一个别名键 | 同一个方法被记成多个 |

## 8. Koral 语法备忘

仅存指针（正本在别处，此处不复述）：

- `type` / `type mutable` 语义与集合赋值别名 → [`../design/type-semantics.md`](../design/type-semantics.md)、
  [`../guide/document.md`](../guide/document.md)。
- 标识符大小写、`given` 语法 → [`../guide/grammar.bnf`](../guide/grammar.bnf)、guide。

## 9. 演进：方法表重键

方法表从名字键换成声明身份键，两侧（bootstrap 与 Swift）都做了。同名泛型扩展方法
一度会共用一个模板槽——根因正是「按名字找模板」，修法是模板表按声明身份键、缓存键
带 `owner_args`（§9.1）。

### 9.1 同名泛型扩展方法的塌陷

根因是「按名字找模板」：两个同名泛型扩展方法会共用一个模板槽。
修法是模板表按声明身份键，缓存键带 `owner_args`。

### 9.2 名字匹配保留处（都有注释 + 出处）

| 保留处 | 为什么合法 |
|---|---|
| `lookupGenericStructTemplate` | 解析边界 |
| `MethodOwner.Builtin` 封闭集 | 无声明者，名字即槽位 |
| `stdStringDefId` 等 lang item | 按声明身份记一次，见 §14 |
| `generateCIdentifier` 等 mangling | 目标语言要合法标识符 |

## 10. `drop` 的 mangle 与 ABI 解耦

**踩过的坑**：泛型类型的用户 `drop` 一度不被调用。`ownerDefId` 解析到**模板**，
而 C 名是**实例化层**——名字比较的两侧必须同层，跨层比会误判。
（正本：[`../design/name-resolution.md`](../design/name-resolution.md)「名字比较必须同层」。）

## 11. `Type` 去名字字段

**教训**：Koral 的 `when` / `is` 分支是**绑定**——`is` 在 `if`/`while` 条件里按模式绑名字
（`is .Some(v)` 绑 `v`），但没有 `as` 式的额外改名/再绑定。
盲改正则必须按语言分别处理，不能拿一套脚本跨语言跑。

## 12. 显示上下文与 niche

**教训**：只写 reader 不写 writer —— 显示上下文的接线漏了一半，读出来的永远是默认值。

### 12.1 niche 判定读实例化后的 case 列表

niche 判定必须读**实例化后**的 case 列表，不是模板的。「查不到 niche」≠「真没有」。

## 13. 名字兜底全部拆除

### 13.1 无效 `DefId` 是错误态

名字找不回来。留名字兜底「教坏后来人」——查不到就是 bug，不是回退的信号。

### 13.2 不做 `DefId → 名 → DefId` 往返

查不到就铸新 `DefId`，等于给同一个类型铸**第二个身份**。标量 / 集合这类**无声明者**
可以铸占位 DefId，名字只作显示（§18）。

### 13.3 身份键里不许出现名字

键里多一个名字，永远只能把一个声明拆成几个键。

**唯一保留的名字键是模板入口表**（`extensionMethods` / `extension_methods`，
键 `MethodLookupKey`）——它回答「这个 owner 有哪个模板」，是**声明登记**不是实例身份，
在某个 owner 的模板列表内按名字选一个属解析边界（§7.2）。
Swift 参照同样是 name 键（`receiverMethodLookupKey`，注释自述 *legacy name-based key
for `extensionMethods`*）。实例身份一律 `MethodInstanceKey`（§7.1）。

## 14. `Drop` 收敛成一个 lang item

`set_std_drop_trait_def_id` 在**首次识别时**解析一次声明身份，之后所有「这是不是 Drop
协议？」都比这个身份。**用户自定义的 `trait Drop` 不得被当成 std 的。**
正本：[`../design/traits-and-givens.md`](../design/traits-and-givens.md)。

## 15. 解析顺序四层，裸名不是解析

> 解析顺序 = **本模块声明 → 符号导入 → 批量/模块导入 → 裸名**。

裸名排在最后，**不是解析**：它只服务「Import it explicitly」这条诊断。
正本：[`../design/name-resolution.md`](../design/name-resolution.md)。

### 15.1 导入图是共享环境状态

不是每个 `DefIdMap` 各一份；import 边带 `sourceFile`，匹配必须比文件。

## 16. 裸名回退会混淆两种情况

「此处没声明也没导入」与「导入了 mod_a 的同名符号」会被裸名回退混成一件事——
所以必须插一层 import，而不是在查不到时退回裸名。

## 17. `Type.==` 的名字兜底是恒真式

左比左。改成比身份，不恢复名字比较。

## 18. `primitive_extension_template_name` 保留

见 §7.2。rustc 用 `SimplifyType` / `incoherent_impls` 处理同一问题。

## 19. 模式遮蔽造成恒真式

`when` 分支**绑定**新名字，内层同名遮蔽外层。拿外层值与内层绑定比恒为真。
这类恒真式不是「比较逻辑写错」，是**作用域看错了**。

## 20. 名字 → 身份的边界

### 20.1 边界只有一个

名字必须在**边界处**变成身份：`resolve_type_node_identity`（形状解析，不做实例化）。
之后的匹配器吃 `Type`、比 DefId。

### 20.2 不给 `TypeNode` 加 `DefId` 字段

`TypeNode` 是**语法**，解析期没有 scope；身份是 sema 产出的 `Type` 的职责。
把身份塞进语法节点，会在错误的阶段分配它。
正本：[`../design/name-resolution.md`](../design/name-resolution.md)。

## 21. `Drop` 的类型擦除析构走 vtable

见 §14。正本：[`../design/traits-and-givens.md`](../design/traits-and-givens.md)。

## 22. 类型身份不得依赖声明顺序（`ParentTraitConstraint`）

约束在构造时拿不到完整上下文，**链接期回填**。正本：
[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

## 23. 名字键递归助手

### 23.1 禁止「查不到就退名字」

这是 §2 的硬性约束在代码里的形态。查不到就是 bug。

### 23.2 「字符串当键」本身无罪

**键由谁决定才是问题。** 键里带声明即可；键里带拼写才会把一个声明拆成几个键。

## 24. vtable 身份

**身份 =（具体类型, trait 声明 `DefId`, trait 类型实参）**。C 符号带 `_d<id>` 消歧。
正本：[`../design/traits-and-givens.md`](../design/traits-and-givens.md)。

## 25. import 别名与 trait 名

**坑**：import 别名只进名字表、不进类型表。给 trait 别名再加一条类型绑定，
会让 `Result[T].Error(...)` 里的 `Error` 解析到一个合成的 trait object。

## 26. 导入绑定键

键是 **（导入方模块, 本地拼写）**。裸键等于没修；不能用环境里的 `currentModulePath`；
没改名的导入**不能跳过**。正本：[`../design/name-resolution.md`](../design/name-resolution.md)。

## 27. 未限定回退 = prelude

prelude 是一条**显式绑定**（std 根模块的 public 符号——trait、函数、类型——绑进每个模块
的键空间），不是一个回退。解析只走限定键。正本：
[`../design/name-resolution.md`](../design/name-resolution.md)。

## 28. 未决

1. **裸名索引仍在**，且与空模块路径的限定键共用一个槽（`qualified_symbol_key([],
   name) == name`）。真正的键拆分未做。
2. ~~prelude 边界是「模块路径 == `["Std"]`」~~ ——**已解决（2026-10）**：边界已按**包身份**
   （`package_id_for_kind(.Std())`，`compiler/koralc/module/module_resolver.koral`；
   seed 侧 `isStdPackageID`），不是模块路径。与
   [`bootstrap-productization.md`](bootstrap-productization.md) 的记录一致。

## 29. 验证口径

身份模型的验收口径见 §3：**两编译器对同一段源码给出同一句诊断**，不是「生成 C 一样」。
步骤、闸门与计数的权威在 [`developer-guide.md`](developer-guide.md) 的
`Verification Discipline`、`tests/README.md` 与 `scripts/verify.sh` 的运行输出，
这里不维护第二份——也不记「当前多少绿」，那是快照，会过期。
