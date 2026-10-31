# 标准流句柄 Stdin / Stdout / Stderr

> Status: Implemented · 2026-10-31 · 无单独实现记录（随 `std/io` 落地）
>
> 用户可见的用法见 [`../guide/document.md`](../guide/document.md)；本文只讲
> **为什么是这样**，以及否决了什么。

## 摘要

`std/io` 提供三个专用的零字段句柄类型 `Stdin` / `Stdout` / `Stderr`，以自由函数
`stdin()` / `stdout()` / `stderr()` 取用；句柄是**无缓冲、字节保真**的字节流，
按流挂 `Reader` / `Writer` 面，缓冲与行式消费归 `BufReader` / `BufWriter` 组合。

## 背景

`print` / `println` / `scanln` 之前的 stdio 面只有两档：行级输入（`scanln`）与
`ToString` 输出（`print` 家族，逐次 fwrite + fflush）。字节级复制（`cat`）、
流式错误传播、与 `Reader` / `Writer` 泛型的组合都表达不了——`File` 有完整的
字节面，唯独标准三流没有。

对 Go / Rust / Zig / Swift / Kotlin 五家的 stdio 面做过对照调研（2026-10-30，
以各家官方文档核对），可迁移的经验：

- **两层切分是共识**：便利层（print 家族）与字节句柄层分开，便利层不进句柄面。
- **缓冲策略必须全流统一**：Swift 的 `FileHandle.standardOutput.write` 与 `print()`
  混用会乱序（句柄走 syscall、print 走 libc 缓冲）；JVM 的 autoflush 规则同类。
  Rust 只有让 print 也走同一缓冲才自洽。统一策略下「全写穿」是最简单的一档。
- **stderr 无缓冲是普世约定**（Rust 明说、Go 干脆全不缓冲）。
- **EOF 是一等设计岔路**（Kotlin 被 `readLine()!!` 坑了六年才补 `readln` /
  `readlnOrNull` 分叉）。
- **专用类型按流挂 trait**（Rust）比与 `File` 同型（Go / Zig）更能表达
  「stdin 不可写」；跨流统一由 `Reader` / `Writer` 泛型承担。
- **TTY 探测是句柄的本职**（Rust `IsTerminal`、Zig `isTty`）；Go 缺了就全员手搓。

## 非目标

- **锁守卫 / 多写原子性**（Rust 的 `StdoutLock`）——Koral 的并发安全整体压在
  `Send` / `Sync` 缺口上，随那个议题一起定。
- **改变 `print` 家族的既有契约**——它们保持逐次 flush 的现状。
- **TTY 面除 `is_terminal` 之外的一切**（着色、ANSI、终端尺寸）归调用方。
- **`Seeker`、`close` / 重开**——管道与终端不可寻址；三流是进程级生命周期。
- **句柄与 `proc` 的 `IoRedirect` 互通**（Rust 的 `From<Stdout> for Stdio` 形态），
  等有样本需要再定。

## 方案

```koral
public type mutable Stdin(private handle: Int32);    // fd 0，只挂 Reader
public type mutable Stdout(private handle: Int32);   // fd 1，只挂 Writer
public type mutable Stderr(private handle: Int32);   // fd 2，只挂 Writer

public let stdin(): Stdin = ...;
public let stdout(): Stdout = ...;
public let stderr(): Stderr = ...;
```

| 契约 | 裁定 |
|---|---|
| 字节保真 | 不做换行翻译，`\n` 就是 `\n`；文本约定归调用方（Windows 上取用时把三流切到二进制模式） |
| 缓冲 | 三句柄都不缓冲，每次 `read` / `write` 就是一次 OS 调用；`flush` 恒 `Ok`（满足 `Writer` 面，`BufWriter` 组合无缝） |
| 短读 / 短写 | 是常态，返回本次转移字节数；写全 / 读全归 `write_all` / `read_all` 扩展 |
| EOF / 错误 | `Ok(0)` = EOF（不是错误）；错误走 `Result` + `last_error_message()` |
| 互操作 | `fd()` 暴露 0/1/2，契约同 `File.fd`；`is_terminal()` 回答「是不是控制台」 |
| 取用 | 自由函数 `stdin()` / `stdout()` / `stderr()`，每次返回新句柄（多份共享同一条流）；`private` 句柄字段让**字面量构造被语言规则拒绝**，取用函数是唯一入口 |
| 并发 | 无承诺：单次 `write` 是交错粒度，行级原子性不保证 |

`print` / `println` / `eprint` / `eprintln` / `scanln` 保持现状——便利层与句柄层
共用同一条流、同一套不缓冲策略，混用天然有序。

## 替代方案

- **名字拼 `StdIn`（按组成部分大写）。否掉。** 五家没有一家现行 API 拼 `StdIn`
  （Go / Rust 是一词 `Stdin`；Zig 0.14 曾拼 `getStdIn`，0.15 已删除该形态；
  Swift 全词 `standardInput`；Kotlin 是小写字段）。POSIX 的 `stdin` 是一个词位，
  按 Koral 的折叠规则（`BufReader`、`Ipv4Addr`）得 `Stdin`；仓内 `StdinPipe`
  同此。
- **取用用 `Stdin.new()` 静态构造。否掉，改自由函数**（用户裁定）。
  `stdin()` 是取流不造物，读起来是访问器；`args()` 是既有先例。
  代价是与「自由函数动词在前」的裁定有张力——接受，因为这是访问器不是动作。
- **单一 `StdStream` 类型（同时 `Reader + Writer`）。否掉**——往 stdin 写会变成
  可表达的，类型上就该堵死。
- **零字段句柄（`type mutable Stdin()`）。否掉**——外部可直接写字面量构造，
  绕过取用函数（丢二进制模式切换、伪造 fd）。改为 `private handle: Int32`：
  「隐藏字段强制工厂方法」的语言规则把字面量构造挡在声明文件之外。
- **与 `File` 同型（Go / Zig 形态），`File.stdout()` 取用。否掉**——同型丢掉
  「stdin 不可写」的编译期保障；跨流统一已经由 `Reader` / `Writer` 泛型承担，
  不需要靠同型。
- **句柄内置缓冲 + 锁（Rust 形态）。否掉**——Rust 的自洽前提是 print 也走同一
  全局缓冲；Koral 的 `print` 是逐次 flush，句柄写穿才是全流一个策略。混用乱序
  的坑在 Swift 文档里有明文警告。批量输出显式包 `BufWriter`。

## 风险与未决

1. **Windows 文本模式。** CRT 的 `_read` / `_write` 对 0/1/2 默认换行翻译，
   与字节保真冲突；取用函数里切二进制模式（`__koral_set_binary_mode`）。
   句柄字段是 `private`，字面量构造在别的文件被语言规则拒绝，取用只走
   `stdin()` / `stdout()` / `stderr()`——二进制模式切换不会被绕过。
2. **测试覆盖的形状。** 编译器用例不读 stdin（测试进程继承 stdin，消费会破坏
   差分对拍的确定性）；stdin 读路径由 `samples/grep` 的测试用
   `IoRedirect.File` 喂入覆盖。
3. **并发写交错**——见「非目标」的锁守卫；`Send` / `Sync` 落地时一并看。
