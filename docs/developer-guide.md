# Koral 编译器开发者指南

## 快速开始

### 构建编译器

```bash
cd compiler
swift build
```

### 运行测试

```bash
# 运行所有测试
swift test

# 运行集成测试
swift test --filter IntegrationTests

# 并行运行（加速）
swift test --parallel

# 运行特定测试
swift test --filter IntegrationTests/test_hello
```

### 编译 Koral 程序

```bash
# 编译为可执行文件（默认 build 命令）
swift run koralc hello.koral

# 编译并运行
swift run koralc run hello.koral

# 仅生成 C 代码
swift run koralc emit-c hello.koral -o output/

# 不链接标准库
swift run koralc hello.koral --no-std

# 输出逃逸分析报告
swift run koralc hello.koral --escape-analysis-report
```

## 添加新类型

### 1. 在 Type.swift 中添加类型 case

```swift
public indirect enum Type {
    // ... 现有类型
    case myNewType(/* 参数 */)
}
```

同时更新 `Type` 的以下属性/方法：
- `description` — 可读名称
- `stableKey` — 稳定的哈希键
- `canonical` — 规范化形式
- `Equatable` 实现

### 2. 在 TypeHandlerKind 中添加种类

```swift
public enum TypeHandlerKind: Hashable {
    // ... 现有种类
    case myNewType
}
```

更新 `TypeHandlerKind.from(_ type: Type)` 映射。

### 3. 实现 TypeHandler

```swift
public class MyNewTypeHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.myNewType]
    }
    
    public init() {}
    
    public func generateCTypeName(_ type: Type) -> String {
        return "my_new_type_t"
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        return "\(dest) = \(source);"
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        return ""
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        return "MyNewType"
    }
}
```

### 4. 注册到 TypeHandlerRegistry

在 `TypeHandlerRegistry.registerBuiltinHandlers()` 中添加：

```swift
handlers.append(MyNewTypeHandler())
```

### 5. 更新 CompilerContext

在 `CompilerContext` 中添加相关的查询方法：
- `getLayoutKey(_ type: Type)` — 添加新类型的 layoutKey 分支
- `getDebugName(_ type: Type)` — 添加新类型的调试名称分支
- `containsGenericParameter(_ type: Type)` — 添加新类型的泛型参数检查

## 添加新的语义分析 Pass

### 1. 定义 Pass 输出

在 `PassInterfaces.swift` 中定义输出结构：

```swift
public struct MyPassOutput: PassOutput {
    public let previousOutput: TypeResolverOutput  // 或其他前置 Pass 输出
    public let myData: MyDataType
}
```

### 2. 实现 Pass

```swift
public class MyPass: CompilerPass {
    typealias Input = TypeResolverInput  // 或其他输入类型
    typealias Output = MyPassOutput
    
    var name: String { "MyPass" }
    
    func run(input: Input) throws -> Output {
        // Pass 逻辑
        return MyPassOutput(
            previousOutput: input.typeResolverOutput,
            myData: processedData
        )
    }
}
```

### 3. 集成到 TypeChecker

在 `TypeCheckerPasses.swift` 的 `check()` 方法中调用新 Pass。

## 添加新诊断

### 使用 DiagnosticCollector

```swift
// 报告错误（带修复建议）
diagnosticCollector.error(
    "错误消息",
    at: sourceSpan,
    fileName: currentFileName,
    fixHint: "修复建议"
)

// 报告警告
diagnosticCollector.warning(
    "警告消息",
    at: sourceSpan,
    fileName: currentFileName
)

// 报告次要错误（由其他错误引起）
diagnosticCollector.secondaryError(
    "次要错误",
    at: sourceSpan,
    fileName: currentFileName,
    causedBy: "主要错误描述"
)
```

### 添加新的 SemanticError 类型

在 `SemanticError.swift` 中添加：

```swift
public enum Kind: Sendable {
    // ... 现有类型
    case myNewError(String)
}

// 在 messageWithoutLocation 中添加
case .myNewError(let detail):
    return "My new error: \(detail)"
```

## 模块系统开发

### 添加新的导入类型

1. 在 `UsingDeclaration.pathKind` 中添加新的路径类型
2. 在 `ModuleResolver` 中添加对应的 `resolveXxx()` 方法
3. 在 `recordImportToGraph()` 中记录导入关系
4. 在 `AccessChecker` 中实现可见性规则

### 模块解析流程

```
resolveModule(entryFile:)
  └── resolveFile(file:module:unit:)
        ├── Lexer + Parser → AST
        ├── 提取 using 声明
        │   └── resolveUsing(using:module:unit:currentFile:)
        │       ├── resolveFileMerge()   → 合并文件到当前模块
        │       ├── resolveSubmodule()   → 创建子模块并递归解析
        │       ├── resolveParent()      → 通过 super 链导航
        │       └── resolveExternal()    → 查找外部模块
        └── 收集非 using 的全局节点
```

### 访问控制规则

| 声明类型 | 默认访问级别 |
|----------|-------------|
| 全局函数/类型/trait | `protected` |
| struct 字段 | `protected` |
| union case | `public` |
| trait 方法 | `public` |
| given 方法 | `protected` |
| using 声明 | `private` |

## 代码生成开发

### 生成 C 代码

```swift
// 使用 CompilerContext 获取 C 标识符
let cName = context.getCIdentifier(defId) ?? "fallback"

// 使用 TypeHandlerRegistry 生成类型代码
let registry = TypeHandlerRegistry.shared
let cTypeName = registry.generateCTypeName(type)
let copyCode = registry.generateCopyCode(type, source: src, dest: dst)
let dropCode = registry.generateDropCode(type, value: val)
```

### C 标识符生成

使用 `CIdentifierUtils.swift` 中的工具函数：

```swift
// 转义 C 关键字
escapeCKeyword("int")  // → "_k_int"

// 清理标识符
sanitizeCIdentifier("my-func")  // → "my_func"

// 生成文件标识符（用于 private 符号隔离）
generateFileIdentifier("myfile.koral")  // → "f1234"

// 生成完整 C 标识符
generateCIdentifier(
    modulePath: ["std", "io"],
    name: "print_line",
    isPrivate: false
)  // → "std_io_print_line"
```

### 处理泛型实例化

```swift
// 使用 CompilerContext 的 layoutKey 生成唯一名称
let key = context.getLayoutKey(.genericStruct(template: "List", args: [.int]))
// 结果: "List_I"

// 使用 debugName 生成可读名称
let debug = context.getDebugName(.genericStruct(template: "List", args: [.int]))
// 结果: "List[Int]"
```

### 逃逸分析集成

```swift
// 在函数代码生成前进行预分析
escapeContext.reset(returnType: funcReturnType, functionName: funcName)
escapeContext.preAnalyze(body: typedBody, params: params)

// 在生成引用表达式时查询
if escapeContext.shouldUseHeapAllocation(innerExpr) {
    // 堆分配
} else {
    // 栈分配
}
```

## 测试开发

### 添加集成测试

1. 在 `compiler/Tests/Cases/` 创建 `.koral` 文件：

```koral
// my_feature.koral
// 测试用例使用 print_line 输出结果
// 编译器会编译并运行，检查退出码

using std.*

let main() = {
    print_line("test passed")
}
```

2. 在 `IntegrationTests.swift` 中添加测试方法：

```swift
func test_my_feature() throws { try runCase(named: "my_feature.koral") }
```

对于期望编译失败的测试（错误检测），测试文件名通常包含 `error`，测试框架会检查编译器是否正确报错。

### 添加多文件/模块测试

创建目录结构：

```
Tests/Cases/my_module_test/
├── my_module_test.koral    # 入口文件（文件名必须与目录名相同）
├── helper.koral            # 合并文件（using "helper"）
└── child/
    └── child.koral         # 子模块（using self.child）
```

## 调试技巧

### 打印 AST

```swift
let printer = ASTPrinter()
print(printer.print(ast))
```

### 打印 TypedAST

```swift
let printer = TypedASTPrinter()
print(printer.print(typedAST))
```

### 查看 DefIdMap 信息

```swift
print(defIdMap.description)
// 输出: DefIdMap(42 definitions):
//   DefId(std.String, kind: type(structure), id: 0)
//   DefId(std.print_line, kind: function, id: 1)
//   ...
```

### 查看诊断信息（带源码片段）

```swift
print(diagnosticCollector.formatWithSource(sourceManager: sourceManager))
```

### 查看逃逸分析报告

使用 `--escape-analysis-report` 命令行选项，或在代码中：

```swift
let escapeContext = EscapeContext(reportingEnabled: true, context: context)
// ... 分析后
print(escapeContext.getFormattedDiagnostics())
```

### 查看生成的 C 代码

```bash
swift run koralc emit-c myfile.koral -o output/
# 查看 output/myfile.c
```

## 常见问题

### Q: 如何处理循环类型引用？

Type 使用 `DefId` 索引而非内联成员信息，天然避免了循环引用。在 Pass 1 注册类型名称（分配 DefId），在 Pass 2 解析完整类型信息（填充 DefIdMap 中的 StructInfo/UnionInfo）。

### Q: 如何处理泛型参数作用域？

使用 `UnifiedScope.defineGenericParameter()` 注册泛型参数，它们在查找时优先于普通名称。泛型参数存储在独立的 `genericParameters` 字典中。

### Q: 如何确保 C 标识符唯一？

使用 `DefIdMap.uniqueCIdentifier(for:)` 或 `CIdentifierUtils.generateCIdentifier()`。它们会自动处理模块路径、private 符号的文件隔离、C 关键字转义和冲突解决。

### Q: 如何添加新的 trait？

1. 在标准库 `std/traits.koral` 中定义 trait
2. TypeChecker 会在 Pass 1 收集 trait 定义
3. 在 Pass 3 中检查 `given` 声明是否满足 trait 要求
4. Monomorphizer 处理泛型 trait 约束的实例化

### Q: 如何添加新的 intrinsic 函数？

1. 在 `AST.swift` 的 intrinsic 相关节点中添加新的 case
2. 在 `TypeCheckerExpressions.swift` 中处理类型检查
3. 在 `CodeGenExpressions.swift` 中生成对应的 C 代码
4. 在标准库中使用 `intrinsic` 关键字声明

### Q: 如何添加新的 foreign 绑定？

1. 在 Koral 代码中使用 `foreign using "library"` 声明外部库
2. 使用 `foreign let` 声明外部函数
3. 使用 `foreign type` 声明外部类型（可选带字段）
4. CodeGen 会生成对应的 C 声明，Driver 会在链接时添加 `-l` 参数
