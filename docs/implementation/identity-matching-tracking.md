# 身份匹配（DefId）—— 模型与演进

> **状态**：两个编译器按同一套身份模型实现，全链绿 + 自举不动点。
> 带 `§N` 的节号是设计文档与代码注释的引用锚点，改节号前先 grep。

## 0. 目标

把「按名字匹配」换成「按声明身份匹配」。身份是**声明的 `DefId`**；名字只在三个地方合法：
**解析边界、显示、C 改编（mangling）**。解析完成后只比身份，不比名字。

正本见 [`../design/name-resolution.md`](../design/name-resolution.md)。
（共同前提在 [`../design/README.md`](../design/README.md) 也有一份，不在此复述。）

## 1. 硬性约束（用户规则，一直在生效）

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

## 2. 验证链

权威定义在 `scripts/verify.sh`，不要在这里维护第二份计数。

```
0) swift build seed + 用 seed 编测试 harness（信任边界）
1) 种子自检
2) 种子编出 bootstrap（stage1）
3) stage1 全量
4) 自举两轮 + 不动点（cmp emit-c 产物）+ 悬空符号扫描必须为 0
5) stage2 全量
6) 差分预言机（两编译器对拍，含诊断文本）
```

**不变量**：诊断文本逐字相同、顺序相同；生成 C **故意不对拍**（两边 `DefId` 编号规则不同）。

## 3.1 模块级类型身份 —— 键是 `(module, name)`

模块级符号的键是 **`(module, name)`**，不是裸名。正本：
[`../design/name-resolution.md`](../design/name-resolution.md)「作用域符号是 `(module, name)`」。

## 3.2 类型身份不能依赖声明顺序

在模板注册之前构造的 `Type` 会带着无效的 `templateDefId`，身份判定静默失败。
正本：[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

## 4. 方法表按声明身份键（rustc 模型）

### 4.1 rustc 怎么做的

rustc 把 inherent impl 与 trait impl 都按 **`DefId`** 索引（`inherent_impls` /
`incoherent_impls`），不按类型名。名字只在 resolve 阶段出现一次。

### 4.2 Koral 对应设计

**声明表按 `MethodOwner`，实例表按 `MethodInstanceKey`。** 这是铁律，见 §5.2。
正本：[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

### 4.3 为什么名字键不够

同名声明会塌进一个槽：两个模块各一个 `trait Tag`、两个类型各一个 `Box` 时，
名字键会让它们互相继承对方的方法、约束与诊断。

## 5. 方法表的身份键

### 5.2 两张表的键不许混

**声明表按 `MethodOwner`、实例表按 `MethodInstanceKey`。** 声明表回答「谁声明了这个方法」，
实例表回答「这个具体实例是哪一个」。曾经把两者当一张表处理，结果是同一个名字的两个
声明互相继承约束与诊断。
正本：[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

### 5.4 保留名字的地方（合法，不是漏改）

名字在四处合法：**解析边界、显示、C 改编（mangling）、`Builtin` 封闭集**。
`primitive_extension_template_name` **保留** —— 标量没有声明，身份就是封闭集槽位
（rustc `SimplifyType` / `incoherent_impls`），不是身份意义上的名字匹配。

### 5.5 踩过的坑

- `file_private` 是**文件作用域**，不是模块作用域。
- **enum variant 的模式不是字符串字面量**：`when x in { .Ok(v) then ... }` 是模式，
  不能拿字符串比。
- `Dict` 的键类型必须有 `Eq` 与 `Hash`，否则编译期就报。
- **位置构造实参不带标签**：`Foo(1, 2)`，不是 `Foo(a: 1, b: 2)`。

## 6. Koral 语法备忘

- `type` 值语义、`type mutable` 引用语义；受管集合赋值**别名**，不拷贝。
- 小写标识符是值名/参数名，大写是类型名。
- `given X { ... }` 给已有类型加方法；`given X as Trait { ... }` 声明遵循。

## 7. 演进：方法表重键

方法表从名字键换成声明身份键，两侧（bootstrap 与 Swift）都做了。同名泛型扩展方法
一度会共用一个模板槽——根因正是「按名字找模板」，修法是模板表按声明身份键、缓存键
带 `owner_args`（§7.6）。

### 7.6 同名泛型扩展方法的塌陷

根因是「按名字找模板」：两个同名泛型扩展方法会共用一个模板槽。
修法是模板表按声明身份键，缓存键带 `owner_args`。

### 7.8 名字匹配保留处（都有注释 + 出处）

| 保留处 | 为什么合法 |
|---|---|
| `lookupGenericStructTemplate` | 解析边界 |
| `MethodOwner.Builtin` 封闭集 | 无声明者，名字即槽位 |
| `stdStringDefId` 等 lang item | 按声明身份记一次，见 §16.3 |
| `generateCIdentifier` 等 mangling | 目标语言要合法标识符 |

## 10. `drop` 的 mangle 与 ABI 解耦

**踩过的坑**：泛型类型的用户 `drop` 一度不被调用。`ownerDefId` 解析到**模板**，
而 C 名是**实例化层**——名字比较的两侧必须同层，跨层比会误判。
（正本：[`../design/name-resolution.md`](../design/name-resolution.md)「名字比较必须同层」。）

## 12. `Type` 去名字字段

**教训**：Koral 的 `when` / `is` 分支是**绑定**，`is` 不允许再绑名字。
盲改正则必须按语言分别处理，不能拿一套脚本跨语言跑。

## 14. 显示上下文与 niche

**教训**：只写 reader 不写 writer —— 显示上下文的接线漏了一半，读出来的永远是默认值。

### 14.2 niche 判定读实例化后的 case 列表

niche 判定必须读**实例化后**的 case 列表，不是模板的。「查不到 niche」≠「真没有」。

## 15. 名字兜底全部拆除

### 15.1 无效 `DefId` 是错误态

名字找不回来。留名字兜底「教坏后来人」——查不到就是 bug，不是回退的信号。

### 15.2 不做 `DefId → 名 → DefId` 往返

查不到就铸新 `DefId`，等于给同一个类型铸**第二个身份**。标量 / 集合这类**无声明者**
可以铸占位 DefId，名字只作显示（§19.4）。

### 15.3 身份键里不许出现名字

键里多一个名字，永远只能把一个声明拆成几个键。

## 16.3 `Drop` 收敛成一个 lang item

`set_std_drop_trait_def_id` 在**首次识别时**解析一次声明身份，之后所有「这是不是 Drop
协议？」都比这个身份。**用户自定义的 `trait Drop` 不得被当成 std 的。**
正本：[`../design/traits-and-givens.md`](../design/traits-and-givens.md)。

## 17.2 解析顺序四层，裸名不是解析

> 解析顺序 = **本模块声明 → 符号导入 → 批量/模块导入 → 裸名**。

裸名排在最后，**不是解析**：它只服务「Import it explicitly」这条诊断。
正本：[`../design/name-resolution.md`](../design/name-resolution.md)。

### 17.3 导入图是共享环境状态

不是每个 `DefIdMap` 各一份；import 边带 `sourceFile`，匹配必须比文件。

## 18.2 裸名回退会混淆两种情况

「此处没声明也没导入」与「导入了 mod_a 的同名符号」会被裸名回退混成一件事——
所以必须插一层 import，而不是在查不到时退回裸名。

## 19.2 `Type.==` 的名字兜底是恒真式

左比左。改成比身份，不恢复名字比较。

## 19.4 `primitive_extension_template_name` 保留

见 §5.4。rustc 用 `SimplifyType` / `incoherent_impls` 处理同一问题。

## 20.2 模式遮蔽造成恒真式

`when` 分支**绑定**新名字，内层同名遮蔽外层。拿外层值与内层绑定比恒为真。
这类恒真式不是「比较逻辑写错」，是**作用域看错了**。

## 21. 名字 → 身份的边界

### 21.1 边界只有一个

名字必须在**边界处**变成身份：`resolve_type_node_identity`（形状解析，不做实例化）。
之后的匹配器吃 `Type`、比 DefId。

### 21.5 不给 `TypeNode` 加 `DefId` 字段

`TypeNode` 是**语法**，解析期没有 scope；身份是 sema 产出的 `Type` 的职责。
把身份塞进语法节点，会在错误的阶段分配它。
正本：[`../design/name-resolution.md`](../design/name-resolution.md)。

## 22.4 `Drop` 的类型擦除析构走 vtable

见 §16.3。正本：[`../design/traits-and-givens.md`](../design/traits-and-givens.md)。

## 23.1 类型身份不得依赖声明顺序（`ParentTraitConstraint`）

约束在构造时拿不到完整上下文，**链接期回填**。正本：
[`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md)。

## 24. 名字键递归助手

### 24.2 禁止「查不到就退名字」

这是 §1 的硬性约束在代码里的形态。查不到就是 bug。

### 24.3 「字符串当键」本身无罪

**键由谁决定才是问题。** 键里带声明即可；键里带拼写才会把一个声明拆成几个键。

## 25.3 vtable 身份

**身份 =（具体类型, trait 声明 `DefId`, trait 类型实参）**。C 符号带 `_d<id>` 消歧。
正本：[`../design/traits-and-givens.md`](../design/traits-and-givens.md)。

## 26. import 别名与 trait 名

**坑**：import 别名只进名字表、不进类型表。给 trait 别名再加一条类型绑定，
会让 `Result[T].Error(...)` 里的 `Error` 解析到一个合成的 trait object。

## 27.1 导入绑定键

键是 **（导入方模块, 本地拼写）**。裸键等于没修；不能用环境里的 `currentModulePath`；
没改名的导入**不能跳过**。正本：[`../design/name-resolution.md`](../design/name-resolution.md)。

## 28.2 未限定回退 = prelude

prelude 是一条**显式绑定**（std 根模块的 public trait 绑进每个模块的键空间），
不是一个回退。解析只走限定键。正本：
[`../design/name-resolution.md`](../design/name-resolution.md)。

## 28.4 未决

1. **裸名索引仍在**，且与空模块路径的限定键共用一个槽（`qualified_symbol_key([],
   name) == name`）。真正的键拆分未做。
2. **prelude 边界是「模块路径 == `["Std"]`」**。std 一拆包这条要改成按包身份。

## 28.5 验证口径

权威计数在 `tests/README.md` 与 `scripts/verify.sh` 的运行输出，这里不维护第二份。
当前形状：seed 自检 / 主闸 / stage2 / 差分四道全绿，自举 `FIXED POINT`、悬空 0。
