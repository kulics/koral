import Testing

@testable import KoralCompiler

/// 泛型参数作用域测试
///
/// 测试泛型参数的作用域隔离和优先查找：
/// - 泛型参数的定义和查找
/// - 泛型参数优先于同名外部类型
/// - 嵌套泛型的处理
/// - 方法级类型参数冲突检测
///
/// **Property 4: 泛型参数作用域隔离**
/// **Validates: Requirements 4.1, 4.3, 4.4, 4.5**
@Suite("Generic Scope Tests")
struct GenericScopeTests {
    
    // MARK: - 泛型参数定义和查找测试
    
    @Test("defineGenericParameter stores generic parameter")
    func testDefineGenericParameter() {
        let scope = Scope()
        let genericType = Type.genericParameter(name: "T")
        
        scope.defineGenericParameter("T", type: genericType)
        
        #expect(scope.isGenericParameter("T") == true)
    }
    
    @Test("isGenericParameter returns false for non-generic parameter")
    func testIsGenericParameterFalse() {
        let scope = Scope()
        
        #expect(scope.isGenericParameter("T") == false)
    }
    
    @Test("isGenericParameter searches parent scope")
    func testIsGenericParameterParentScope() {
        let parentScope = Scope()
        let childScope = Scope(parent: parentScope)
        
        let genericType = Type.genericParameter(name: "T")
        parentScope.defineGenericParameter("T", type: genericType)
        
        #expect(childScope.isGenericParameter("T") == true)
    }
    
    @Test("lookupType finds generic parameter first")
    func testLookupTypeGenericParameterPriority() throws {
        let scope = Scope()
        
        // 定义一个普通类型 V
        let structDecl = StructDecl(
            name: "V",
            defId: DefId(
                modulePath: ["types"],
                name: "V",
                kind: .type(.structure),
                sourceFile: "types.koral",
                id: 1
            ),
            modulePath: ["types"],
            sourceFile: "types.koral",
            access: .default,
            members: [],
            isGenericInstantiation: false
        )
        let structType = Type.structure(decl: structDecl)
        try scope.defineType("V", type: structType)
        
        // 定义一个同名的泛型参数 V
        let genericType = Type.genericParameter(name: "V")
        scope.defineGenericParameter("V", type: genericType)
        
        // 查找时应该返回泛型参数，而不是普通类型
        let foundType = scope.lookupType("V")
        #expect(foundType != nil)
        
        if case .genericParameter(let name) = foundType {
            #expect(name == "V")
        } else {
            Issue.record("Expected generic parameter type, got \(String(describing: foundType))")
        }
    }
    
    // MARK: - 嵌套作用域测试
    
    @Test("nested scope inherits generic parameters")
    func testNestedScopeInheritsGenericParameters() {
        let outerScope = Scope()
        let innerScope = Scope(parent: outerScope)
        
        let genericType = Type.genericParameter(name: "T")
        outerScope.defineGenericParameter("T", type: genericType)
        
        // 内部作用域应该能看到外部作用域的泛型参数
        #expect(innerScope.isGenericParameter("T") == true)
        
        let foundType = innerScope.lookupType("T")
        #expect(foundType != nil)
        if case .genericParameter(let name) = foundType {
            #expect(name == "T")
        } else {
            Issue.record("Expected generic parameter type")
        }
    }
    
    @Test("inner scope generic parameter shadows outer")
    func testInnerScopeGenericParameterShadows() {
        let outerScope = Scope()
        let innerScope = Scope(parent: outerScope)
        
        // 外部作用域定义泛型参数 T
        let outerGenericType = Type.genericParameter(name: "T")
        outerScope.defineGenericParameter("T", type: outerGenericType)
        
        // 内部作用域也定义泛型参数 T（方法级泛型）
        let innerGenericType = Type.genericParameter(name: "T")
        innerScope.defineGenericParameter("T", type: innerGenericType)
        
        // 内部作用域应该看到自己的泛型参数
        #expect(innerScope.isGenericParameter("T") == true)
    }
    
    // MARK: - 泛型参数清理测试
    
    @Test("generic parameters are scoped correctly")
    func testGenericParameterScoping() {
        let globalScope = Scope()
        
        // 模拟进入泛型定义
        let genericScope = Scope(parent: globalScope)
        let genericType = Type.genericParameter(name: "T")
        genericScope.defineGenericParameter("T", type: genericType)
        
        // 在泛型作用域内可以看到 T
        #expect(genericScope.isGenericParameter("T") == true)
        
        // 全局作用域看不到 T
        #expect(globalScope.isGenericParameter("T") == false)
    }
    
    // MARK: - 多泛型参数测试
    
    @Test("multiple generic parameters")
    func testMultipleGenericParameters() {
        let scope = Scope()
        
        scope.defineGenericParameter("K", type: .genericParameter(name: "K"))
        scope.defineGenericParameter("V", type: .genericParameter(name: "V"))
        
        #expect(scope.isGenericParameter("K") == true)
        #expect(scope.isGenericParameter("V") == true)
        #expect(scope.isGenericParameter("T") == false)
    }
    
    // MARK: - 与普通类型的交互测试
    
    @Test("generic parameter does not affect normal type lookup")
    func testGenericParameterDoesNotAffectNormalType() throws {
        let scope = Scope()
        
        // 定义普通类型
        let structDecl = StructDecl(
            name: "MyStruct",
            defId: DefId(
                modulePath: [],
                name: "MyStruct",
                kind: .type(.structure),
                sourceFile: "test.koral",
                id: 2
            ),
            modulePath: [],
            sourceFile: "test.koral",
            access: .default,
            members: [],
            isGenericInstantiation: false
        )
        try scope.defineType("MyStruct", type: .structure(decl: structDecl))
        
        // 定义泛型参数
        scope.defineGenericParameter("T", type: .genericParameter(name: "T"))
        
        // 普通类型查找应该正常工作
        let myStructType = scope.lookupType("MyStruct")
        #expect(myStructType != nil)
        if case .structure(let decl) = myStructType {
            #expect(decl.name == "MyStruct")
        } else {
            Issue.record("Expected structure type")
        }
        
        // 泛型参数查找也应该正常工作
        let tType = scope.lookupType("T")
        #expect(tType != nil)
        if case .genericParameter(let name) = tType {
            #expect(name == "T")
        } else {
            Issue.record("Expected generic parameter type")
        }
    }
}
