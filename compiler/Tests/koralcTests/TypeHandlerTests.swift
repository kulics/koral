import Testing

@testable import KoralCompiler

/// TypeHandler 系统单元测试
///
/// 测试 TypeHandler 协议和各种类型处理器的核心功能：
/// - TypeHandlerRegistry 的注册和查找
/// - StructHandler 的类型处理
/// - UnionHandler 的类型处理
/// - GenericHandler 的类型处理
/// - PrimitiveHandler 的类型处理
/// - ReferenceHandler 的类型处理
///
/// **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5**
@Suite("TypeHandler System Tests")
struct TypeHandlerTests {
    private func makeDefId(
        name: String,
        kind: TypeDefKind,
        modulePath: [String],
        sourceFile: String
    ) -> DefId {
        var hasher = Hasher()
        hasher.combine(modulePath)
        hasher.combine(name)
        hasher.combine(sourceFile)
        hasher.combine(kind.description)
        let id = UInt64(bitPattern: Int64(hasher.finalize()))
        return DefId(
            modulePath: modulePath,
            name: name,
            kind: .type(kind),
            sourceFile: sourceFile,
            id: id
        )
    }

    private func makeStructDecl(
        name: String,
        modulePath: [String],
        sourceFile: String,
        access: AccessModifier,
        members: [(name: String, type: Type, mutable: Bool)] = [],
        isGenericInstantiation: Bool = false,
        typeArguments: [Type]? = nil
    ) -> StructDecl {
        return StructDecl(
            name: name,
            defId: makeDefId(name: name, kind: .structure, modulePath: modulePath, sourceFile: sourceFile),
            modulePath: modulePath,
            sourceFile: sourceFile,
            access: access,
            members: members,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments
        )
    }

    private func makeUnionDecl(
        name: String,
        modulePath: [String],
        sourceFile: String,
        access: AccessModifier,
        cases: [UnionCase] = [],
        isGenericInstantiation: Bool = false,
        typeArguments: [Type]? = nil
    ) -> UnionDecl {
        return UnionDecl(
            name: name,
            defId: makeDefId(name: name, kind: .union, modulePath: modulePath, sourceFile: sourceFile),
            modulePath: modulePath,
            sourceFile: sourceFile,
            access: access,
            cases: cases,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments
        )
    }
    
    // MARK: - TypeHandlerRegistry Tests
    
    @Test("TypeHandlerRegistry singleton instance")
    func testRegistrySingleton() {
        let registry1 = TypeHandlerRegistry.shared
        let registry2 = TypeHandlerRegistry.shared
        #expect(registry1 === registry2)
    }
    
    @Test("TypeHandlerRegistry returns correct handler for primitive types")
    func testRegistryPrimitiveHandler() {
        let registry = TypeHandlerRegistry.shared
        
        let intHandler = registry.handler(for: .int)
        let boolHandler = registry.handler(for: .bool)
        let voidHandler = registry.handler(for: .void)
        
        #expect(intHandler is PrimitiveHandler)
        #expect(boolHandler is PrimitiveHandler)
        #expect(voidHandler is PrimitiveHandler)
    }

    @Test("TypeHandlerRegistry returns correct handler for struct types")
    func testRegistryStructHandler() {
        let registry = TypeHandlerRegistry.shared
        
        let structDecl = makeStructDecl(
            name: "TestStruct",
            modulePath: ["test"],
            sourceFile: "test.koral",
            access: .public,
            members: []
        )
        let structType = Type.structure(decl: structDecl)
        
        let handler = registry.handler(for: structType)
        #expect(handler is StructHandler)
    }
    
    @Test("TypeHandlerRegistry returns correct handler for union types")
    func testRegistryUnionHandler() {
        let registry = TypeHandlerRegistry.shared
        
        let unionDecl = makeUnionDecl(
            name: "TestUnion",
            modulePath: ["test"],
            sourceFile: "test.koral",
            access: .public,
            cases: []
        )
        let unionType = Type.union(decl: unionDecl)
        
        let handler = registry.handler(for: unionType)
        #expect(handler is UnionHandler)
    }
    
    @Test("TypeHandlerRegistry returns correct handler for generic types")
    func testRegistryGenericHandler() {
        let registry = TypeHandlerRegistry.shared
        
        let genericStructType = Type.genericStruct(template: "List", args: [.int])
        let genericUnionType = Type.genericUnion(template: "Option", args: [.bool])
        let genericParamType = Type.genericParameter(name: "T")
        
        let structHandler = registry.handler(for: genericStructType)
        let unionHandler = registry.handler(for: genericUnionType)
        let paramHandler = registry.handler(for: genericParamType)
        
        #expect(structHandler is GenericHandler)
        #expect(unionHandler is GenericHandler)
        #expect(paramHandler is GenericHandler)
    }
    
    @Test("TypeHandlerRegistry returns correct handler for reference types")
    func testRegistryReferenceHandler() {
        let registry = TypeHandlerRegistry.shared
        
        let refType = Type.reference(inner: .int)
        let handler = registry.handler(for: refType)
        
        #expect(handler is ReferenceHandler)
    }
    
    @Test("TypeHandlerRegistry returns correct handler for function types")
    func testRegistryFunctionHandler() {
        let registry = TypeHandlerRegistry.shared
        
        let funcType = Type.function(
            parameters: [Parameter(type: .int, kind: .byVal)],
            returns: .bool
        )
        let handler = registry.handler(for: funcType)
        
        #expect(handler is FunctionHandler)
    }
    
    @Test("TypeHandlerRegistry returns correct handler for pointer types")
    func testRegistryPointerHandler() {
        let registry = TypeHandlerRegistry.shared
        
        let ptrType = Type.pointer(element: .int)
        let handler = registry.handler(for: ptrType)
        
        #expect(handler is PointerHandler)
    }

    // MARK: - PrimitiveHandler Tests
    
    @Test("PrimitiveHandler canHandle returns true for primitive types")
    func testPrimitiveHandlerCanHandle() {
        let handler = PrimitiveHandler()
        
        #expect(handler.canHandle(.int) == true)
        #expect(handler.canHandle(.int8) == true)
        #expect(handler.canHandle(.int16) == true)
        #expect(handler.canHandle(.int32) == true)
        #expect(handler.canHandle(.int64) == true)
        #expect(handler.canHandle(.uint) == true)
        #expect(handler.canHandle(.uint8) == true)
        #expect(handler.canHandle(.uint16) == true)
        #expect(handler.canHandle(.uint32) == true)
        #expect(handler.canHandle(.uint64) == true)
        #expect(handler.canHandle(.float32) == true)
        #expect(handler.canHandle(.float64) == true)
        #expect(handler.canHandle(.bool) == true)
        #expect(handler.canHandle(.void) == true)
        #expect(handler.canHandle(.never) == true)
    }
    
    @Test("PrimitiveHandler canHandle returns false for non-primitive types")
    func testPrimitiveHandlerCannotHandle() {
        let handler = PrimitiveHandler()
        
        let structDecl = makeStructDecl(
            name: "S", modulePath: [], sourceFile: "", access: .public, members: []
        )
        #expect(handler.canHandle(.structure(decl: structDecl)) == false)
        #expect(handler.canHandle(.reference(inner: .int)) == false)
        #expect(handler.canHandle(.genericParameter(name: "T")) == false)
    }
    
    @Test("PrimitiveHandler generates correct C type names")
    func testPrimitiveHandlerCTypeName() {
        let handler = PrimitiveHandler()
        
        #expect(handler.generateCTypeName(.int) == "intptr_t")
        #expect(handler.generateCTypeName(.int8) == "int8_t")
        #expect(handler.generateCTypeName(.int16) == "int16_t")
        #expect(handler.generateCTypeName(.int32) == "int32_t")
        #expect(handler.generateCTypeName(.int64) == "int64_t")
        #expect(handler.generateCTypeName(.uint) == "uintptr_t")
        #expect(handler.generateCTypeName(.uint8) == "uint8_t")
        #expect(handler.generateCTypeName(.float32) == "float")
        #expect(handler.generateCTypeName(.float64) == "double")
        #expect(handler.generateCTypeName(.bool) == "int")
        #expect(handler.generateCTypeName(.void) == "void")
    }
    
    @Test("PrimitiveHandler does not need copy or drop functions")
    func testPrimitiveHandlerNoCopyDrop() {
        let handler = PrimitiveHandler()
        
        #expect(handler.needsCopyFunction(.int) == false)
        #expect(handler.needsDropFunction(.int) == false)
        #expect(handler.needsCopyFunction(.bool) == false)
        #expect(handler.needsDropFunction(.bool) == false)
    }
    
    @Test("PrimitiveHandler does not contain generic parameters")
    func testPrimitiveHandlerNoGenericParams() {
        let handler = PrimitiveHandler()
        
        #expect(handler.containsGenericParameter(.int) == false)
        #expect(handler.containsGenericParameter(.bool) == false)
        #expect(handler.containsGenericParameter(.void) == false)
    }

    // MARK: - StructHandler Tests
    
    @Test("StructHandler canHandle returns true for struct types")
    func testStructHandlerCanHandle() {
        let handler = StructHandler()
        
        let structDecl = makeStructDecl(
            name: "Point",
            modulePath: ["geometry"],
            sourceFile: "point.koral",
            access: .public,
            members: [
                (name: "x", type: .int, mutable: false),
                (name: "y", type: .int, mutable: false)
            ]
        )
        let structType = Type.structure(decl: structDecl)
        
        #expect(handler.canHandle(structType) == true)
        #expect(handler.canHandle(.int) == false)
    }
    
    @Test("StructHandler getMembers returns struct members")
    func testStructHandlerGetMembers() {
        let handler = StructHandler()
        
        let structDecl = makeStructDecl(
            name: "Point",
            modulePath: ["geometry"],
            sourceFile: "point.koral",
            access: .public,
            members: [
                (name: "x", type: .int, mutable: false),
                (name: "y", type: .int, mutable: true)
            ]
        )
        let structType = Type.structure(decl: structDecl)
        
        let members = handler.getMembers(structType)
        
        #expect(members.count == 2)
        #expect(members[0].name == "x")
        #expect(members[0].type == .int)
        #expect(members[0].mutable == false)
        #expect(members[1].name == "y")
        #expect(members[1].mutable == true)
    }
    
    @Test("StructHandler needs copy and drop functions")
    func testStructHandlerNeedsCopyDrop() {
        let handler = StructHandler()
        
        let structDecl = makeStructDecl(
            name: "S", modulePath: [], sourceFile: "", access: .public, members: []
        )
        let structType = Type.structure(decl: structDecl)
        
        #expect(handler.needsCopyFunction(structType) == true)
        #expect(handler.needsDropFunction(structType) == true)
    }
    
    @Test("StructHandler generates correct C type name")
    func testStructHandlerCTypeName() {
        let handler = StructHandler()
        
        let structDecl = makeStructDecl(
            name: "Point",
            modulePath: ["geometry"],
            sourceFile: "point.koral",
            access: .public,
            members: []
        )
        let structType = Type.structure(decl: structDecl)
        
        let cTypeName = handler.generateCTypeName(structType)
        #expect(cTypeName.contains("struct"))
        #expect(cTypeName.contains("Point"))
    }
    
    @Test("StructHandler generates copy code")
    func testStructHandlerCopyCode() {
        let handler = StructHandler()
        
        let structDecl = makeStructDecl(
            name: "Point",
            modulePath: ["geometry"],
            sourceFile: "point.koral",
            access: .public,
            members: []
        )
        let structType = Type.structure(decl: structDecl)
        
        let copyCode = handler.generateCopyCode(structType, source: "src", dest: "dst")
        #expect(copyCode.contains("__koral_"))
        #expect(copyCode.contains("_copy"))
    }
    
    @Test("StructHandler generates drop code")
    func testStructHandlerDropCode() {
        let handler = StructHandler()
        
        let structDecl = makeStructDecl(
            name: "Point",
            modulePath: ["geometry"],
            sourceFile: "point.koral",
            access: .public,
            members: []
        )
        let structType = Type.structure(decl: structDecl)
        
        let dropCode = handler.generateDropCode(structType, value: "val")
        #expect(dropCode.contains("__koral_"))
        #expect(dropCode.contains("_drop"))
    }
    
    @Test("StructHandler getQualifiedName returns correct name")
    func testStructHandlerQualifiedName() {
        let handler = StructHandler()
        
        let structDecl = makeStructDecl(
            name: "Point",
            modulePath: ["geometry"],
            sourceFile: "point.koral",
            access: .public,
            members: []
        )
        let structType = Type.structure(decl: structDecl)
        
        let qualifiedName = handler.getQualifiedName(structType)
        #expect(qualifiedName.contains("Point"))
    }
    
    @Test("StructHandler containsGenericParameter detects generic members")
    func testStructHandlerContainsGenericParam() {
        let handler = StructHandler()
        
        // Struct without generic parameters
        let simpleDecl = makeStructDecl(
            name: "Simple",
            modulePath: [],
            sourceFile: "",
            access: .public,
            members: [(name: "x", type: .int, mutable: false)]
        )
        let simpleType = Type.structure(decl: simpleDecl)
        #expect(handler.containsGenericParameter(simpleType) == false)
        
        // Struct with generic parameter in member
        let genericDecl = makeStructDecl(
            name: "Container",
            modulePath: [],
            sourceFile: "",
            access: .public,
            members: [(name: "value", type: .genericParameter(name: "T"), mutable: false)]
        )
        let genericType = Type.structure(decl: genericDecl)
        #expect(handler.containsGenericParameter(genericType) == true)
    }

    // MARK: - UnionHandler Tests
    
    @Test("UnionHandler canHandle returns true for union types")
    func testUnionHandlerCanHandle() {
        let handler = UnionHandler()
        
        let unionDecl = makeUnionDecl(
            name: "Option",
            modulePath: ["std"],
            sourceFile: "option.koral",
            access: .public,
            cases: [
                UnionCase(name: "Some", parameters: [(name: "value", type: .int)]),
                UnionCase(name: "None", parameters: [])
            ]
        )
        let unionType = Type.union(decl: unionDecl)
        
        #expect(handler.canHandle(unionType) == true)
        #expect(handler.canHandle(.int) == false)
    }
    
    @Test("UnionHandler getCases returns union cases")
    func testUnionHandlerGetCases() {
        let handler = UnionHandler()
        
        let unionDecl = makeUnionDecl(
            name: "Result",
            modulePath: ["std"],
            sourceFile: "result.koral",
            access: .public,
            cases: [
                UnionCase(name: "Ok", parameters: [(name: "value", type: .int)]),
                UnionCase(name: "Err", parameters: [(name: "error", type: .bool)])
            ]
        )
        let unionType = Type.union(decl: unionDecl)
        
        let cases = handler.getCases(unionType)
        
        #expect(cases != nil)
        #expect(cases?.count == 2)
        #expect(cases?[0].name == "Ok")
        #expect(cases?[1].name == "Err")
    }
    
    @Test("UnionHandler getCase returns specific case")
    func testUnionHandlerGetCase() {
        let handler = UnionHandler()
        
        let unionDecl = makeUnionDecl(
            name: "Option",
            modulePath: [],
            sourceFile: "",
            access: .public,
            cases: [
                UnionCase(name: "Some", parameters: [(name: "value", type: .int)]),
                UnionCase(name: "None", parameters: [])
            ]
        )
        let unionType = Type.union(decl: unionDecl)
        
        let someCase = handler.getCase(unionType, name: "Some")
        let noneCase = handler.getCase(unionType, name: "None")
        let invalidCase = handler.getCase(unionType, name: "Invalid")
        
        #expect(someCase != nil)
        #expect(someCase?.name == "Some")
        #expect(someCase?.parameters.count == 1)
        #expect(noneCase != nil)
        #expect(noneCase?.parameters.count == 0)
        #expect(invalidCase == nil)
    }
    
    @Test("UnionHandler getCaseIndex returns correct index")
    func testUnionHandlerGetCaseIndex() {
        let handler = UnionHandler()
        
        let unionDecl = makeUnionDecl(
            name: "Color",
            modulePath: [],
            sourceFile: "",
            access: .public,
            cases: [
                UnionCase(name: "Red", parameters: []),
                UnionCase(name: "Green", parameters: []),
                UnionCase(name: "Blue", parameters: [])
            ]
        )
        let unionType = Type.union(decl: unionDecl)
        
        #expect(handler.getCaseIndex(unionType, name: "Red") == 0)
        #expect(handler.getCaseIndex(unionType, name: "Green") == 1)
        #expect(handler.getCaseIndex(unionType, name: "Blue") == 2)
        #expect(handler.getCaseIndex(unionType, name: "Yellow") == nil)
    }
    
    @Test("UnionHandler needs copy and drop functions")
    func testUnionHandlerNeedsCopyDrop() {
        let handler = UnionHandler()
        
        let unionDecl = makeUnionDecl(
            name: "U", modulePath: [], sourceFile: "", access: .public, cases: []
        )
        let unionType = Type.union(decl: unionDecl)
        
        #expect(handler.needsCopyFunction(unionType) == true)
        #expect(handler.needsDropFunction(unionType) == true)
    }
    
    @Test("UnionHandler generates correct C type name")
    func testUnionHandlerCTypeName() {
        let handler = UnionHandler()
        
        let unionDecl = makeUnionDecl(
            name: "Option",
            modulePath: ["std"],
            sourceFile: "option.koral",
            access: .public,
            cases: []
        )
        let unionType = Type.union(decl: unionDecl)
        
        let cTypeName = handler.generateCTypeName(unionType)
        #expect(cTypeName.contains("struct"))
        #expect(cTypeName.contains("Option"))
    }
    
    @Test("UnionHandler containsGenericParameter detects generic cases")
    func testUnionHandlerContainsGenericParam() {
        let handler = UnionHandler()
        
        // Union without generic parameters
        let simpleDecl = makeUnionDecl(
            name: "Simple",
            modulePath: [],
            sourceFile: "",
            access: .public,
            cases: [UnionCase(name: "A", parameters: [(name: "x", type: .int)])]
        )
        let simpleType = Type.union(decl: simpleDecl)
        #expect(handler.containsGenericParameter(simpleType) == false)
        
        // Union with generic parameter in case
        let genericDecl = makeUnionDecl(
            name: "Option",
            modulePath: [],
            sourceFile: "",
            access: .public,
            cases: [
                UnionCase(name: "Some", parameters: [(name: "value", type: .genericParameter(name: "T"))]),
                UnionCase(name: "None", parameters: [])
            ]
        )
        let genericType = Type.union(decl: genericDecl)
        #expect(handler.containsGenericParameter(genericType) == true)
    }

    // MARK: - GenericHandler Tests
    
    @Test("GenericHandler canHandle returns true for generic types")
    func testGenericHandlerCanHandle() {
        let handler = GenericHandler()
        
        #expect(handler.canHandle(.genericStruct(template: "List", args: [.int])) == true)
        #expect(handler.canHandle(.genericUnion(template: "Option", args: [.bool])) == true)
        #expect(handler.canHandle(.genericParameter(name: "T")) == true)
        #expect(handler.canHandle(.int) == false)
    }
    
    @Test("GenericHandler getTemplateName returns template name")
    func testGenericHandlerGetTemplateName() {
        let handler = GenericHandler()
        
        #expect(handler.getTemplateName(.genericStruct(template: "List", args: [.int])) == "List")
        #expect(handler.getTemplateName(.genericUnion(template: "Option", args: [.bool])) == "Option")
        #expect(handler.getTemplateName(.genericParameter(name: "T")) == "T")
        #expect(handler.getTemplateName(.int) == nil)
    }
    
    @Test("GenericHandler getTypeArguments returns type arguments")
    func testGenericHandlerGetTypeArguments() {
        let handler = GenericHandler()
        
        let structArgs = handler.getTypeArguments(.genericStruct(template: "Map", args: [.int, .bool]))
        #expect(structArgs != nil)
        #expect(structArgs?.count == 2)
        #expect(structArgs?[0] == .int)
        #expect(structArgs?[1] == .bool)
        
        let unionArgs = handler.getTypeArguments(.genericUnion(template: "Result", args: [.int]))
        #expect(unionArgs != nil)
        #expect(unionArgs?.count == 1)
        
        #expect(handler.getTypeArguments(.genericParameter(name: "T")) == nil)
    }
    
    @Test("GenericHandler isGenericStruct/Union/Parameter")
    func testGenericHandlerTypeChecks() {
        let handler = GenericHandler()
        
        let genericStruct = Type.genericStruct(template: "List", args: [.int])
        let genericUnion = Type.genericUnion(template: "Option", args: [.int])
        let genericParam = Type.genericParameter(name: "T")
        
        #expect(handler.isGenericStruct(genericStruct) == true)
        #expect(handler.isGenericStruct(genericUnion) == false)
        #expect(handler.isGenericStruct(genericParam) == false)
        
        #expect(handler.isGenericUnion(genericUnion) == true)
        #expect(handler.isGenericUnion(genericStruct) == false)
        
        #expect(handler.isGenericParameter(genericParam) == true)
        #expect(handler.isGenericParameter(genericStruct) == false)
    }
    
    @Test("GenericHandler getGenericParameterName")
    func testGenericHandlerGetGenericParameterName() {
        let handler = GenericHandler()
        
        #expect(handler.getGenericParameterName(.genericParameter(name: "T")) == "T")
        #expect(handler.getGenericParameterName(.genericParameter(name: "Element")) == "Element")
        #expect(handler.getGenericParameterName(.int) == nil)
    }
    
    @Test("GenericHandler containsGenericParameter")
    func testGenericHandlerContainsGenericParam() {
        let handler = GenericHandler()
        
        // Generic parameter always contains generic parameter
        #expect(handler.containsGenericParameter(.genericParameter(name: "T")) == true)
        
        // Generic struct/union with concrete args
        #expect(handler.containsGenericParameter(.genericStruct(template: "List", args: [.int])) == false)
        
        // Generic struct/union with generic args
        #expect(handler.containsGenericParameter(.genericStruct(template: "List", args: [.genericParameter(name: "T")])) == true)
    }
    
    @Test("GenericHandler generates qualified name")
    func testGenericHandlerQualifiedName() {
        let handler = GenericHandler()
        
        let qualifiedStruct = handler.getQualifiedName(.genericStruct(template: "List", args: [.int]))
        #expect(qualifiedStruct.contains("List"))
        
        let qualifiedUnion = handler.getQualifiedName(.genericUnion(template: "Option", args: [.bool]))
        #expect(qualifiedUnion.contains("Option"))
        
        let qualifiedParam = handler.getQualifiedName(.genericParameter(name: "T"))
        #expect(qualifiedParam == "T")
    }

    // MARK: - ReferenceHandler Tests
    
    @Test("ReferenceHandler canHandle returns true for reference types")
    func testReferenceHandlerCanHandle() {
        let handler = ReferenceHandler()
        
        #expect(handler.canHandle(.reference(inner: .int)) == true)
        #expect(handler.canHandle(.reference(inner: .bool)) == true)
        #expect(handler.canHandle(.int) == false)
    }
    
    @Test("ReferenceHandler getInnerType returns inner type")
    func testReferenceHandlerGetInnerType() {
        let handler = ReferenceHandler()
        
        #expect(handler.getInnerType(.reference(inner: .int)) == .int)
        #expect(handler.getInnerType(.reference(inner: .bool)) == .bool)
        #expect(handler.getInnerType(.int) == nil)
    }
    
    @Test("ReferenceHandler needs copy and drop functions")
    func testReferenceHandlerNeedsCopyDrop() {
        let handler = ReferenceHandler()
        
        let refType = Type.reference(inner: .int)
        #expect(handler.needsCopyFunction(refType) == true)
        #expect(handler.needsDropFunction(refType) == true)
    }
    
    @Test("ReferenceHandler generates correct C type name")
    func testReferenceHandlerCTypeName() {
        let handler = ReferenceHandler()
        
        let cTypeName = handler.generateCTypeName(.reference(inner: .int))
        #expect(cTypeName == "struct Ref")
    }
    
    @Test("ReferenceHandler generates copy code with retain")
    func testReferenceHandlerCopyCode() {
        let handler = ReferenceHandler()
        
        let copyCode = handler.generateCopyCode(.reference(inner: .int), source: "src", dest: "dst")
        #expect(copyCode.contains("__koral_retain"))
    }
    
    @Test("ReferenceHandler generates drop code with release")
    func testReferenceHandlerDropCode() {
        let handler = ReferenceHandler()
        
        let dropCode = handler.generateDropCode(.reference(inner: .int), value: "val")
        #expect(dropCode.contains("__koral_release"))
    }
    
    @Test("ReferenceHandler containsGenericParameter checks inner type")
    func testReferenceHandlerContainsGenericParam() {
        let handler = ReferenceHandler()
        
        #expect(handler.containsGenericParameter(.reference(inner: .int)) == false)
        #expect(handler.containsGenericParameter(.reference(inner: .genericParameter(name: "T"))) == true)
    }
    
    // MARK: - FunctionHandler Tests
    
    @Test("FunctionHandler canHandle returns true for function types")
    func testFunctionHandlerCanHandle() {
        let handler = FunctionHandler()
        
        let funcType = Type.function(
            parameters: [Parameter(type: .int, kind: .byVal)],
            returns: .bool
        )
        #expect(handler.canHandle(funcType) == true)
        #expect(handler.canHandle(.int) == false)
    }
    
    @Test("FunctionHandler getParameters returns function parameters")
    func testFunctionHandlerGetParameters() {
        let handler = FunctionHandler()
        
        let funcType = Type.function(
            parameters: [
                Parameter(type: .int, kind: .byVal),
                Parameter(type: .bool, kind: .byRef)
            ],
            returns: .void
        )
        
        let params = handler.getParameters(funcType)
        #expect(params != nil)
        #expect(params?.count == 2)
        #expect(params?[0].type == .int)
        #expect(params?[0].kind == .byVal)
        #expect(params?[1].type == .bool)
        #expect(params?[1].kind == .byRef)
    }
    
    @Test("FunctionHandler getReturnType returns return type")
    func testFunctionHandlerGetReturnType() {
        let handler = FunctionHandler()
        
        let funcType = Type.function(parameters: [], returns: .int)
        #expect(handler.getReturnType(funcType) == .int)
        
        let voidFunc = Type.function(parameters: [], returns: .void)
        #expect(handler.getReturnType(voidFunc) == .void)
    }
    
    @Test("FunctionHandler generates correct C type name")
    func testFunctionHandlerCTypeName() {
        let handler = FunctionHandler()
        
        let funcType = Type.function(parameters: [], returns: .void)
        let cTypeName = handler.generateCTypeName(funcType)
        #expect(cTypeName == "struct __koral_Closure")
    }
    
    @Test("FunctionHandler containsGenericParameter checks params and return")
    func testFunctionHandlerContainsGenericParam() {
        let handler = FunctionHandler()
        
        // No generic parameters
        let simpleFunc = Type.function(parameters: [Parameter(type: .int, kind: .byVal)], returns: .bool)
        #expect(handler.containsGenericParameter(simpleFunc) == false)
        
        // Generic in parameter
        let genericParamFunc = Type.function(
            parameters: [Parameter(type: .genericParameter(name: "T"), kind: .byVal)],
            returns: .bool
        )
        #expect(handler.containsGenericParameter(genericParamFunc) == true)
        
        // Generic in return type
        let genericReturnFunc = Type.function(parameters: [], returns: .genericParameter(name: "T"))
        #expect(handler.containsGenericParameter(genericReturnFunc) == true)
    }

    // MARK: - PointerHandler Tests
    
    @Test("PointerHandler canHandle returns true for pointer types")
    func testPointerHandlerCanHandle() {
        let handler = PointerHandler()
        
        #expect(handler.canHandle(.pointer(element: .int)) == true)
        #expect(handler.canHandle(.pointer(element: .bool)) == true)
        #expect(handler.canHandle(.int) == false)
    }
    
    @Test("PointerHandler getElementType returns element type")
    func testPointerHandlerGetElementType() {
        let handler = PointerHandler()
        
        #expect(handler.getElementType(.pointer(element: .int)) == .int)
        #expect(handler.getElementType(.pointer(element: .bool)) == .bool)
        #expect(handler.getElementType(.int) == nil)
    }
    
    @Test("PointerHandler does not need copy or drop functions")
    func testPointerHandlerNoCopyDrop() {
        let handler = PointerHandler()
        
        let ptrType = Type.pointer(element: .int)
        #expect(handler.needsCopyFunction(ptrType) == false)
        #expect(handler.needsDropFunction(ptrType) == false)
    }
    
    @Test("PointerHandler containsGenericParameter checks element type")
    func testPointerHandlerContainsGenericParam() {
        let handler = PointerHandler()
        
        #expect(handler.containsGenericParameter(.pointer(element: .int)) == false)
        #expect(handler.containsGenericParameter(.pointer(element: .genericParameter(name: "T"))) == true)
    }
    
    // MARK: - TypeHandlerKind Tests
    
    @Test("TypeHandlerKind.from returns correct kind for all types")
    func testTypeHandlerKindFrom() {
        // Primitives
        #expect(TypeHandlerKind.from(.int) == .primitive)
        #expect(TypeHandlerKind.from(.bool) == .primitive)
        #expect(TypeHandlerKind.from(.void) == .primitive)
        #expect(TypeHandlerKind.from(.never) == .primitive)
        
        // Structure
        let structDecl = makeStructDecl(name: "S", modulePath: [], sourceFile: "", access: .public, members: [])
        #expect(TypeHandlerKind.from(.structure(decl: structDecl)) == .structure)
        
        // Union
        let unionDecl = makeUnionDecl(name: "U", modulePath: [], sourceFile: "", access: .public, cases: [])
        #expect(TypeHandlerKind.from(.union(decl: unionDecl)) == .union)
        
        // Function
        #expect(TypeHandlerKind.from(.function(parameters: [], returns: .void)) == .function)
        
        // Reference
        #expect(TypeHandlerKind.from(.reference(inner: .int)) == .reference)
        
        // Pointer
        #expect(TypeHandlerKind.from(.pointer(element: .int)) == .pointer)
        
        // Generic types
        #expect(TypeHandlerKind.from(.genericParameter(name: "T")) == .genericParameter)
        #expect(TypeHandlerKind.from(.genericStruct(template: "List", args: [])) == .genericStruct)
        #expect(TypeHandlerKind.from(.genericUnion(template: "Option", args: [])) == .genericUnion)
    }
    
    // MARK: - Type Extension Tests
    
    @Test("Type.handler extension returns correct handler")
    func testTypeHandlerExtension() {
        #expect(Type.int.handler is PrimitiveHandler)
        
        let structDecl = makeStructDecl(name: "S", modulePath: [], sourceFile: "", access: .public, members: [])
        #expect(Type.structure(decl: structDecl).handler is StructHandler)
        
        let unionDecl = makeUnionDecl(name: "U", modulePath: [], sourceFile: "", access: .public, cases: [])
        #expect(Type.union(decl: unionDecl).handler is UnionHandler)
        
        #expect(Type.genericParameter(name: "T").handler is GenericHandler)
        #expect(Type.reference(inner: .int).handler is ReferenceHandler)
    }
    
    @Test("Type.cTypeName extension returns correct C type name")
    func testTypeCTypeNameExtension() {
        #expect(Type.int.cTypeName == "intptr_t")
        #expect(Type.bool.cTypeName == "int")
        #expect(Type.void.cTypeName == "void")
        #expect(Type.reference(inner: .int).cTypeName == "struct Ref")
    }
    
    @Test("Type.needsCopy extension returns correct value")
    func testTypeNeedsCopyExtension() {
        #expect(Type.int.needsCopy == false)
        #expect(Type.bool.needsCopy == false)
        #expect(Type.reference(inner: .int).needsCopy == true)
        
        let structDecl = makeStructDecl(name: "S", modulePath: [], sourceFile: "", access: .public, members: [])
        #expect(Type.structure(decl: structDecl).needsCopy == true)
    }
    
    @Test("Type.needsDrop extension returns correct value")
    func testTypeNeedsDropExtension() {
        #expect(Type.int.needsDrop == false)
        #expect(Type.bool.needsDrop == false)
        #expect(Type.reference(inner: .int).needsDrop == true)
        
        let unionDecl = makeUnionDecl(name: "U", modulePath: [], sourceFile: "", access: .public, cases: [])
        #expect(Type.union(decl: unionDecl).needsDrop == true)
    }
}
