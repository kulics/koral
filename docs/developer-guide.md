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

# 运行特定测试
swift test --filter IntegrationTests
swift test --filter TypeHandlerTests

# 并行运行测试（加速测试执行）
swift test --parallel

# 并行运行特定测试
swift test --filter IntegrationTests --parallel
```

> **注意**: 使用 `--parallel` 选项可以显著加速测试执行，特别是对于集成测试。但如果测试之间有共享状态或资源冲突，可能需要禁用并行模式。

### 编译 Koral 程序

```bash
swift run koralc input.koral -o output
```

## 添加新类型

### 1. 定义类型

在 `Type.swift` 中添加新的类型 case：

```swift
public indirect enum Type: Hashable, Equatable {
    // ... 现有类型
    case myNewType(/* 参数 */)
}
```

### 2. 实现 TypeHandler

创建新的 TypeHandler 实现：

```swift
public class MyNewTypeHandler: TypeHandler {
    public func canHandle(_ type: Type) -> Bool {
        if case .myNewType = type { return true }
        return false
    }
    
    public func getMembers(_ type: Type) -> [(name: String, type: Type)]? {
        // 返回类型成员
        return nil
    }
    
    public func getMethods(_ type: Type) -> [String]? {
        // 返回可用方法
        return nil
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        // 是否需要拷贝函数
        return false
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        // 是否需要析构函数
        return false
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        // 生成 C 类型名
        return "my_new_type"
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        return "\(dest) = \(source);"
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        return ""
    }
    
    public func getQualifiedName(_ type: Type) -> String? {
        return "MyNewType"
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        return false
    }
}
```

### 3. 注册 TypeHandler

在 `TypeHandlerRegistry` 中注册：

```swift
extension TypeHandlerRegistry {
    public static let shared: TypeHandlerRegistry = {
        let registry = TypeHandlerRegistry()
        // ... 现有处理器
        registry.register(MyNewTypeHandler())
        return registry
    }()
}
```

### 4. 更新 layoutKey

在 `Type.swift` 中添加 layoutKey：

```swift
public var layoutKey: String {
    switch self {
    // ... 现有类型
    case .myNewType:
        return "MNT"  // 唯一的短标识符
    }
}
```

### 5. 更新 debugName

```swift
public var debugName: String {
    switch self {
    // ... 现有类型
    case .myNewType:
        return "MyNewType"
    }
}
```

## 添加新 Pass

### 1. 定义 Pass 输出

在 `PassInterfaces.swift` 中定义输出结构：

```swift
public struct MyPassOutput: PassOutput {
    public let previousOutput: PreviousPassOutput
    public let myData: MyDataType
}
```

### 2. 实现 Pass

```swift
public class MyPass {
    public func run(input: PreviousPassOutput) throws -> MyPassOutput {
        // Pass 逻辑
        return MyPassOutput(
            previousOutput: input,
            myData: processedData
        )
    }
}
```

### 3. 集成到 TypeChecker

在 `TypeCheckerPasses.swift` 中调用新 Pass：

```swift
// 在 check() 方法中
let myPassOutput = try runMyPass(previousOutput: previousOutput)
self.myPassOutput = myPassOutput
```

## 添加新诊断

### 1. 使用 DiagnosticCollector

```swift
// 报告错误
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

// 报告次要错误
diagnosticCollector.secondaryError(
    "次要错误",
    at: sourceSpan,
    fileName: currentFileName,
    causedBy: "主要错误描述"
)
```

### 2. 添加新的 SemanticError 类型

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

1. 在 `ImportKind` 枚举中添加新类型
2. 在 `ModuleResolver` 中处理新的 using 语法
3. 在 `VisibilityChecker` 中实现可见性规则

### 处理模块符号

```swift
// 创建模块符号
let moduleInfo = ModuleSymbolInfo(
    modulePath: ["my", "module"],
    publicSymbols: symbols,
    publicTypes: types
)

// 注册到 TypeChecker
moduleSymbols[moduleKey] = moduleInfo
```

## 代码生成开发

### 生成 C 代码

```swift
// 使用 qualifiedName 生成唯一标识符
let cName = symbol.qualifiedName

// 使用 TypeHandler 生成类型代码
let handler = TypeHandlerRegistry.shared.handler(for: type)
let cTypeName = handler.generateCTypeName(type)
let copyCode = handler.generateCopyCode(type, source: src, dest: dst)
let dropCode = handler.generateDropCode(type, value: val)
```

### 处理泛型实例化

```swift
// 使用 layoutKey 生成唯一名称
let layoutName = SemaUtils.generateLayoutName(baseName: "List", args: [.int])
// 结果: "List_I"

// 使用 debugName 生成可读名称
let debugName = type.debugName
// 结果: "List[Int]"
```

## 测试开发

### 添加单元测试

```swift
import Testing
@testable import KoralCompiler

@Suite("My Feature Tests")
struct MyFeatureTests {
    @Test("Test description")
    func testMyFeature() {
        // 测试代码
        #expect(result == expected)
    }
}
```

### 添加集成测试

1. 在 `compiler/Tests/Cases/` 创建 `.koral` 文件
2. 在 `IntegrationTests.swift` 中添加测试方法：

```swift
func test_my_feature() throws {
    try runTest("my_feature")
}
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

### 查看 DefId 信息

```swift
print(defIdMap.description)
```

### 查看诊断信息

```swift
print(diagnosticCollector.formatWithSource(sourceManager: sourceManager))
```

## 常见问题

### Q: 如何处理循环类型引用？

使用占位符类型，在 Pass 1 注册类型名称，在 Pass 2 解析完整类型。

### Q: 如何处理泛型参数作用域？

使用 `Scope.defineGenericParameter()` 注册泛型参数，它们会被优先查找。

### Q: 如何确保 C 标识符唯一？

使用 `DefIdMap.uniqueCIdentifier()` 或 `Symbol.qualifiedName`，它们会自动处理模块路径和冲突。

### Q: 如何添加新的 trait？

1. 在标准库中定义 trait
2. 在 `TypeChecker` 中注册 trait 信息
3. 在 `Monomorphizer` 中处理 trait 约束
