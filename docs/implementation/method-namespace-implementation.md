# method-namespace 实现记录

> **Status**：Implemented · 2026-11-24 · 设计正本 [`../design/method-namespace.md`](../design/method-namespace.md)

## 落地了什么

声明期撞名判定收敛为**一个注册漏斗 + 冲突代数**（两个编译器同批）：

- **koralc**：`MethodScope` / `MethodDeclKind` / `MethodDeclRecord` / `DeclConflict`
  与漏斗 `MethodTable.declare_method`（`compiler/koralc/sema/method_table.koral`）；
  `collect_given_signatures` 成员循环与 `.IntrinsicGivenDecl` 泛型注册循环是调用点。
- **种子**：同名镜像 `TypeChecker.MethodScope/…/DeclConflict` 与 `declareMethod`
  （`Sema/TypeCheckerMethods.swift`）；调用点在 `collectGivenSignatures` 的
  泛型/非泛型/intrinsic 成员循环，外加 `.givenTraitDecl` 的 **skip 分支**。

kind 判定：无 trait = `Inherent`；trait 声明了该成员 = `Requirement(trait)`；
trait 未声明（工具副本、conformance helper）= `Tool`——工具行永不占名。

## 查重对照表（旧行为 → 代数行）

| 旧行为（散在各注册点） | 代数行 |
|---|---|
| `collect_given_signatures` 的 `seen_names`（同块同名） | 同 scope `Inherent×Inherent` |
| inherent 撞名检查（inherent/见证占名，双分支） | 同 scope `Inherent×{Inherent,Requirement}` |
| pass-2 conformance 的 requirement-vs-inherent 检查 | 同上（双向同判） |
| 实例/通用两本名册（2026-11-23 禁止重叠修复） | `Instance×Family` 跨 scope 毯式 `Duplicate` |
| pass-3 `made_ambiguous` 报告（templates.koral 两处） | 同 scope `Requirement×Requirement` |
| 种子 `existsInGeneric/existsInIntrinsic`（4 处） | 对应行（模板名撞名并入） |
| 种子 `extensionMethodTraitSources` 的 ambiguous 报告 | `Requirement×Requirement` |
| 种子 `hasExistingMethodSignature` skip 路径不入册 | skip 分支补漏斗（key/scope 与 collect 分支同源） |

工具块（`given T { … }`）不入册：其让位语义在 `materialize_trait_tool_members_for_conformance`
的 (a)(b)(b')(c)(d) 跳过规则里，即代数的 `Tool` 行。

## 角落统一（未测角落的行为收拢）

1. **同一实例两个要求见证同名**：旧种子走 `Duplicate`（见证占名规则）、旧自举走
   `Ambiguous`（pass-3）——分叉。统一为 `Ambiguous`，与 Family 侧的钉子
   （`trait_same_name_method_conflict`）一致。
2. **泛型族 `Inherent×Requirement` 撞名**：旧种子顺序相关（一序静默丢块、一序
   `Duplicate`）。统一为双向 `Duplicate`。
3. **泛型族 `Requirement×Requirement`**（两泛型 conformance 同名成员）：旧双侧静默。
   统一为 `Ambiguous`。
4. **conformance helper 同名**（trait 未声明的成员）：旧 pass-3 报 `Ambiguous`。
   归 `Tool` 行——让位于 inherent/见证、彼此合法共存，可调性交方法面（§3.4）。
5. **自举缺失的模板撞名检查**（同块方法级泛型同名、跨块同名等，`upsert` 静默合并）：
   并入代数，向种子看齐。

以上角落均无既有测试钉子；差分预言机对改动后的双侧逐字一致背书。

## 施工中修正的一个坑

漏斗初版带「重注册静默」（同 `source_def_id` 再到达判为同一声明、静默替换）——
但两侧的成员 defId **按名派生/共享**（种子 `methodSymbolDefId(ownerKey,name,access)`；
koralc `members_with_def_ids` 的 map key 含成员名），同块/跨块同名成员被误判为
同一声明而吞掉冲突（`duplicate_given_method` 双侧漏报、重叠钉子种子漏报）。
修法：**删除静默**——重构后每个成员恰好漏斗一次（skip 路径与 collect 互斥），
每次到达都是声明、都过代数；同块同名、跨块同名、跨 scope 重叠统一一个谓词。

## 保真核对

- 四套件（种子/自举/stage2/差分预言机）各 **1519/1519**，差分行为+诊断逐字一致。
- `scripts/verify.sh` 全链 ALL GREEN：自举不动点（s2 == s3）、悬空调用扫描 0、
  内存钉、冷 panic 钉、运行时压力（RC/对象锁/字符串区）、RC 计数钉、样例、
  `koral_doc --check`、项目布局 lint。
- 已删的死代码：两本名册（storage 字段 + `note_given_*` / `noteGiven*`）与
  `slot_owned_by_inherent_or_requirement` / `instance_slot_owned_by_inherent_or_requirement`
  （种子同名对偶）。

## 未尽（模型的后续吸收）

查找侧的派生存储（实例槽/通用槽/模板条目、`inherent_keys`、`method_sources`）
仍按旧布局各自写入——设计正本「派生索引」的**语义**已成立（撞名判定不再读它们），
把写入点机械收拢进漏斗、并把 `inherent_keys` 等并入记录字段，是下一笔。
