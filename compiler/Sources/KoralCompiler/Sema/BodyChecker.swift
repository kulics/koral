/// BodyChecker.swift - Pass 3: 检查函数体和表达式
///
/// BodyChecker 是编译器的第三个 Pass，负责：
/// - 检查函数体和表达式
/// - 进行类型推导
/// - 生成类型化的 AST
/// - 收集泛型实例化请求
///
/// ## 设计参考
/// - Rust 编译器 (rustc): 类型检查阶段
/// - 原 TypeCheckerPasses.swift 中的 checkGlobalDeclaration 方法
///
/// ## 依赖关系
/// - 输入：TypeResolverOutput（包含 SymbolTable 和 NameCollectorOutput）
/// - 输出：BodyCheckerOutput（包含 TypedAST、InstantiationRequests 和 TypeResolverOutput）
///
/// **Validates: Requirements 2.1, 2.2**

import Foundation

// MARK: - BodyChecker

/// BodyChecker - Pass 3: 检查函数体和表达式
///
/// 负责：
/// - 检查函数体和表达式
/// - 进行类型推导
/// - 生成类型化的 AST
/// - 收集泛型实例化请求
///
/// ## 注意
/// 当前实现作为 TypeChecker 的包装器，委托实际的类型检查工作给 TypeChecker。
/// 这是为了保持向后兼容性，同时建立新的 Pass 架构。
/// 未来可以逐步将 checkGlobalDeclaration 的逻辑迁移到这里。
public class BodyChecker: CompilerPass {
    public typealias Input = BodyCheckerInput
    public typealias Output = BodyCheckerOutput
    
    public var name: String { "BodyChecker" }
    
    // MARK: - 私有属性
    
    /// 标准库全局节点数量
    private var coreGlobalCount: Int = 0

    /// 关联的 TypeChecker（用于复用现有语义检查逻辑）
    private let checker: TypeChecker
    
    /// 收集到的类型化声明
    private var typedDeclarations: [TypedGlobalNode] = []
    
    /// 泛型实例化请求
    private var instantiationRequests: Set<InstantiationRequest> = []
    
    // MARK: - 初始化
    
    /// 创建一个新的 BodyChecker
    ///
    /// - Parameter coreGlobalCount: 标准库全局节点数量（用于判断是否是标准库定义）
    public init(checker: TypeChecker, coreGlobalCount: Int = 0) {
        self.checker = checker
        self.coreGlobalCount = coreGlobalCount
    }
    
    // MARK: - CompilerPass 实现
    
    /// 执行 Pass 3
    ///
    /// 当前实现委托给 TypeChecker 的 checkGlobalDeclaration 方法。
    /// 这是为了保持向后兼容性，同时建立新的 Pass 架构。
    ///
    /// - Parameter input: BodyChecker 的输入
    /// - Returns: BodyChecker 的输出
    /// - Throws: 如果遇到语义错误
    public func run(input: Input) throws -> Output {
        let typeResolverOutput = input.typeResolverOutput
        let nameCollectorOutput = typeResolverOutput.nameCollectorOutput
        let moduleResolverOutput = nameCollectorOutput.moduleResolverOutput
        let astNodes = moduleResolverOutput.astNodes

        checker.defIdMap = nameCollectorOutput.defIdMap
        
        // 重置状态
        typedDeclarations = []
        instantiationRequests = []
        
        // 过滤出非 using 声明的节点
        let declarations = astNodes.filter { node in
            if case .usingDeclaration = node { return false }
            return true
        }
        
        // Pass 3: 检查函数体并生成 Typed AST
        for (index, decl) in declarations.enumerated() {
            let isStdLib = index < coreGlobalCount
            checker.isCurrentDeclStdLib = isStdLib
            let sourceInfo = checker.nodeSourceInfoMap[index]
            checker.currentFileName = sourceInfo?.sourceFile ?? (isStdLib ? checker.coreFileName : checker.userFileName)
            checker.currentSourceFile = sourceInfo?.sourceFile ?? checker.currentFileName
            checker.currentModulePath = sourceInfo?.modulePath ?? []
            checker.currentSpan = decl.span
            
            do {
                let result = try checker.checkGlobalDeclaration(decl)
                
                if let typedDecl = result {
                    typedDeclarations.append(typedDecl)
                }
            } catch let error as SemanticError {
                try? checker.handleError(error)
                continue
            } catch {
                throw error
            }
        }
        
        let typedProgram = TypedProgram.program(globalNodes: typedDeclarations)
        instantiationRequests = checker.instantiationRequests
        
        return BodyCheckerOutput(
            typedAST: typedProgram,
            instantiationRequests: instantiationRequests,
            typeResolverOutput: typeResolverOutput
        )
    }
    
    // MARK: - 公共访问器
    
    /// 获取收集到的类型化声明
    public var declarations: [TypedGlobalNode] {
        return typedDeclarations
    }
    
    /// 获取泛型实例化请求
    public var requests: Set<InstantiationRequest> {
        return instantiationRequests
    }
}

