# 简化类型系统迁移状态

日期：2026-09-23

本文档跟踪 `docs/rfc-simplified-type-system.md` 的迁移进度，只保留对当前阶段（bootstrap 对齐）仍有指导价值的信息。历史逐日进展与已修复问题的根因分析见 git 历史。

## 基本规则

- 迁移顺序：Swift `compiler/`、`std/`、测试 → runner、samples、toolchain → bootstrap 对齐 Swift。
- 不保留兼容垫片：旧托管引用表层语法、旧 receiver 适配、COW、逃逸分析提升路径一律删除。
- 阶段状态、验证结果和剩余阻塞以本文档为准。

## 设计约束（已确认）

- 移除托管引用表层：`*T`、`*mutable T`、`?*T`、托管 `&` / `&mutable`、`box()`、托管解引用。
- 保留 raw pointer：`*unsafe T`、`*unsafe mutable T`、`&unsafe`、`&unsafe mutable` 及其解引用。
- 声明处可变性：`type A` / `type mutable B`；枚举和类型别名不能声明为 `type mutable`。
- receiver 只保留 `self`；trait object 表层直接写 trait 名。
- 弱引用表层为 `?T`，类型参数约束显式写 `mutable`；公开入口只有 `downgrade` / `upgrade`。
- 删除目标已完成：`Deref`、ref blanket conformance、逃逸分析、托管引用分配提升、`Weak`、`Object`、COW uniqueness。
- 容器与有状态迭代器为共享语义 `type mutable` 对象；需要独立副本时显式 `clone()`。
- `Drop` 签名只接受 `drop(self) Void`。

## 布局判定结论（关键）

- `self` 按拷贝传递；ARC / 隐藏间接层由类型布局分析决定，与 method call receiver 适配无关。
- `type mutable` 恒为 managed（共享对象语义）。
- plain `type` 只暴露浅层不可变、无 identity、且不承诺值语义；底层是 inline value 还是 managed wrapper 由编译器按语义属性决定，已确认的触发条件：
  - 值递归
  - 显式 `Drop` conformance
- managed nominal 的 copy 必须对嵌套 managed 字段逐个 retain，与外层 control block 的 retain 配套；否则参数 drop 会造成 use-after-free。

## 阶段状态

| 阶段 | 范围 | 状态 | 验证 |
|---|---|---|---|
| 0 | RFC、文档与实现锚点梳理 | 已完成 | — |
| 1–2 | Swift 表层与语义清理 | 已完成 | 聚焦 parser / type 用例 |
| 3 | Swift MIR / codegen / runtime 对齐 | 已完成 | managed 布局直接决定表示 |
| 4 | `std/` 迁移 | 已完成 | toolchain/koral 构建成功 |
| 5 | 测试迁移 | 已完成 | — |
| 6 | runner、samples、toolchain 迁移 | 已完成 | — |
| 7 | bootstrap 对齐 | 进行中 | 334/506 |
| 8 | 最终审阅报告 | 进行中 | — |
| 9 | 遗留问题修复（仅 Swift 编译器） | 已完成 | Swift 526/526 |

Swift 主线基线：**526/526 全部通过**。运行方式见 `tests/compiler-runner/`。

## 遗留问题修复（2026-09-23，仅 Swift 编译器）

范围：`compiler/`、`std/`、`tests/`、文档；bootstrap 未改动。功能缺陷均补了对应测试。

1. **命名参数统一规划器**：新增 `planCallArguments` / `planCallArgumentExpressions`，自由函数、实例方法、静态方法、泛型方法、trait 方法全部改为携带 `CallArg` 经统一规划器（标签匹配、重排、默认值填充、标签错误）。此前仅构造器校验标签，其余路径把标签静默丢弃后按位置匹配。顺带修正了 `std` 中被误写成位置实参的调用（`replace_all(pat, with:)` 等），并把默认值键统一为「方法名.参数名」（原 trait 侧键为 trait 名，与 sema 查找不一致）。
2. **容器 `clone()`**：新增 `trait Clone`（浅拷贝语义），`List` / `Set` / `Dict` / `Deque` 实现 `clone(self) Self`。
3. **闭包捕获只剩拷贝语义**：禁止捕获 `let mutable`（此前按 `byMutReference` 取栈地址，可逃逸闭包会悬垂）；新增 `std::Cell[T]`（`type mutable`）承载共享可变状态。
4. **泛型 nominal / trait object 携带 defId**：`Type.genericStruct` / `genericEnum` / `traitObject` 与 `ConformanceTypeKey` 改为携带 `templateDefId` / `traitDefId`；模板注册表按模块限定查找；布局名（含 C 结构体与 copy/drop 辅助名）统一携带声明身份，跨模块同名实例化不再坍缩到同一 C 类型；导入别名绑定原符号 defId。同名声明在不同用户模块中是不同声明，std 名称仍保留不可重定义。
5. **README 旧描述**：default-fill、static positional-only 重写；`when` 零字段模式补 `()`。托管引用 / 逃逸分析 / 旧 receiver 的过时描述位于 `tests/README.md`，一并清理。
6. **`when` 示例语法**：`docs/document.md` / `docs/document-zh.md` 共 10 处 `,;` 分隔符按 `docs/grammar.bnf` 修正。
7. **拒绝 `mutable type alias` / `mutable type enum`**：parser 明确报错（声明处可变性仅适用于 nominal）。
8. **收紧 `borrow_ptr` / `borrow_mut_ptr`**：新增 `Pod` 标记 trait，`List` 的两个入口限定 `[T Pod]`，不再是「任意 T → `*unsafe T`」的通用桥；删除泄漏内部 bucket 类型的 `Dict.borrow_ptr`。
9. **旧机制清理**：删除已死的 COW / 旧托管引用 intrinsic 及其全管线（`is_unique_mutable`、`ref_count`、`make_ref`、`make_mut_ref`、`downgrade_mut_ref`、`upgrade_mut_ref` 及名称匹配入口）。`.reference` / `.mutableReference` 类型与隐式解引用是 managed nominal 的内部布局表示，非用户表层遗留，保留。
10. **旧的 `yield` 术语记录已过时**：当前实现没有表层 `yield` 语法；value-producing `if` / `when` 直接取分支最后一个表达式，先前的“branch/break → yield”记录不再代表现状。
11. **全局同名自由函数查重**：`NameCollector` 按模块限定查重，重复定义报 `Duplicate definition`。

## 当前 bootstrap 状态

- host 编译、self-host `build`、package 级 `emit-c` 均已恢复；可稳定生成完整 `koralc.c`，原始后端 crash 链已切断。
- MIR lowering 已绕过 legacy `MIRReferenceAllocationPromoter`，不再停在旧 ref-promotion 崩溃点。
- `codegen` 类型声明排序的 `integer overflow in subtraction` 已修复。
- 性能基线：host 编译约 `336s`；package self-check 约 `136s` / `395MB RSS`。
- `hello.koral` 编译运行成功；`weak_sigils_basic_test.koral`、`and_then_flatten.koral`、`closure_capture_let_mut.koral` 等已通过。

## 当前阻塞（334/506）

| 类别 | 数量 | 说明 |
|------|------|------|
| unexpected_nonzero_exit | 96 | 编译期 crash 或 C 编译/链接错误 |
| timeout | 54 | 编译超时（>30 秒） |
| missing_expected_error | 21 | 期望的错误诊断未产生 |
| missing_expected_output | 1 | 输出不匹配 |

主要问题：

1. **monomorphizer 传递依赖追踪**（13 个链接错误）：实例化 `List[UInt8].push_sublist` 时，内部调用的 `List[UInt8].ensure_capacity` 未入队。已在 `mono.koral` 主循环后加传递依赖解析循环但未生效；对照 Swift `Monomorphizer.swift` 的 `while let request = popNextPendingRequest()`，需检查 `resolve_types_in_expression` 是否正确触发 `instantiate_function_impl`。
2. **下标 helper 缺失**（2 个）：`List[struct#108]`、`Dict[Int, struct#108]` 等类型的 `__index_mut_ptr` 未注册，需对齐 Swift 的 subscript helper 注册逻辑。
3. **trait object / managed nominal 交叉**（约 10 个）：参数类型不匹配、类型推断错误、`use trait as type`。
4. **编译超时**（54 个）：bootstrap 编译速度慢，需 profiling 定位瓶颈。

## 未完成事项

- C 生成顺序问题集中在以下类型簇，wrapper/container 需排到 payload 之前：
  - `List_Koralc_Token` / `Koralc_Token` / `Koralc_TokenKind`
  - `List_Koralc_InterpolatedStringTokenPart` / `Koralc_InterpolatedStringTokenPart`
  - `List_Koralc_f543_PatternSpace` / `Pair_...` / `Dict_...` / `Koralc_f2735_PatternSpace`
  - `Std_Json_JsonValue` 与其字典 / option / pair wrapper
- 生成 C 中仍有 `Koralc_MIRScopeID.tag` 误发射：`MIRScopeID` 在 C 里是普通 wrapper struct，不是 tagged union，与类型排序无关。
- `MIRReferenceAllocationPromoter` 及 `StackBorrow` / `HeapOwned` 后置链已被绕过但仍在树上，需决定彻底删除还是按 Swift 结构重写。
- 排查过程中加入的阶段性 probe / 调试痕迹待清理。
- `codegen_mir.koral` 的 managed nominal 分支尚未通过最小 self-host 完整验证；与 trait object、closure capture、subscript / writable-base、drop 交叉的路径仍需整体对齐。

## 下一步顺序

1. 收紧 `codegen_types.koral` 的 nominal / container 依赖提取，解决剩余类型簇声明顺序。
2. 单独修复 `Koralc_MIRScopeID.tag` 误发射。
3. 修 monomorphizer 传递依赖追踪与 subscript helper 注册。
4. 在 `emit-c` / `build` 全链路打通后，重新测量时间与 RSS，再清理 `MIRReferenceAllocationPromoter` 旧链路并继续 RFC 剩余行为对齐。
