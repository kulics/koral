import Testing
@testable import KoralCompiler

@Suite("CodeGen Improvement Tests")
struct CodeGenTests {
    
    // MARK: - DefId C Identifier Tests
    
    @Test("DefId generates correct C identifier for simple name")
    func testDefIdSimpleCIdentifier() {
        let defId = DefId(
            modulePath: [],
            name: "main",
            kind: .function,
            sourceFile: "main.koral",
            id: 1
        )
        
        #expect(defId.cIdentifier == "main")
    }
    
    @Test("DefId generates correct C identifier with module path")
    func testDefIdModulePathCIdentifier() {
        let defId = DefId(
            modulePath: ["expr_eval", "frontend"],
            name: "Parser",
            kind: .type(.structure),
            sourceFile: "parser.koral",
            id: 2
        )
        
        #expect(defId.cIdentifier == "expr_eval_frontend_Parser")
    }
    
    @Test("DefId generates C identifier with file isolation for private symbols")
    func testDefIdPrivateCIdentifier() {
        let defId = DefId(
            modulePath: ["mymodule"],
            name: "PrivateType",
            kind: .type(.structure),
            sourceFile: "private.koral",
            id: 3
        )
        
        let cIdWithFile = defId.cIdentifierWithFileIsolation
        #expect(cIdWithFile.contains("mymodule"))
        #expect(cIdWithFile.contains("PrivateType"))
        #expect(cIdWithFile.contains("f"))  // File hash prefix
    }
    
    @Test("DefId escapes C keywords")
    func testDefIdEscapesCKeywords() {
        let defId = DefId(
            modulePath: [],
            name: "int",
            kind: .variable,
            sourceFile: "test.koral",
            id: 4
        )
        
        #expect(defId.cIdentifier == "_k_int")
    }
    
    @Test("DefId escapes reserved identifiers starting with underscore")
    func testDefIdEscapesReservedIdentifiers() {
        let defId = DefId(
            modulePath: [],
            name: "_Reserved",
            kind: .variable,
            sourceFile: "test.koral",
            id: 5
        )
        
        #expect(defId.cIdentifier == "_k__Reserved")
    }
    
    // MARK: - DefIdMap Conflict Detection Tests
    
    @Test("DefIdMap detects no conflicts for unique identifiers")
    func testNoConflicts() {
        let defIdMap = DefIdMap()
        
        _ = defIdMap.allocate(modulePath: ["a"], name: "Foo", kind: .type(.structure), sourceFile: "a.koral")
        _ = defIdMap.allocate(modulePath: ["b"], name: "Bar", kind: .type(.structure), sourceFile: "b.koral")
        _ = defIdMap.allocate(modulePath: ["c"], name: "Baz", kind: .function, sourceFile: "c.koral")
        
        let conflicts = defIdMap.detectCIdentifierConflicts()
        #expect(conflicts.isEmpty)
    }
    
    @Test("DefIdMap generates unique C identifiers with suffix for conflicts")
    func testUniqueIdentifierGeneration() {
        let defIdMap = DefIdMap()
        
        // These would have the same C identifier without conflict resolution
        let defId1 = defIdMap.allocate(modulePath: [], name: "test", kind: .function, sourceFile: "a.koral")
        let defId2 = defIdMap.allocate(modulePath: [], name: "test", kind: .function, sourceFile: "b.koral")
        
        let cId1 = defIdMap.uniqueCIdentifier(for: defId1)
        let cId2 = defIdMap.uniqueCIdentifier(for: defId2)
        
        // First one should be without suffix, second with suffix
        #expect(cId1 == "test")
        #expect(cId2 == "test_1")
    }
    
    // MARK: - Type Debug Name Tests
    
    @Test("Type debugName for primitive types")
    func testPrimitiveDebugNames() {
        #expect(Type.int.debugName == "Int")
        #expect(Type.int8.debugName == "Int8")
        #expect(Type.uint.debugName == "UInt")
        #expect(Type.float32.debugName == "Float32")
        #expect(Type.bool.debugName == "Bool")
        #expect(Type.void.debugName == "Void")
        #expect(Type.never.debugName == "Never")
    }
    
    @Test("Type debugName for reference types")
    func testReferenceDebugName() {
        let refType = Type.reference(inner: .int)
        #expect(refType.debugName == "ref Int")
    }
    
    @Test("Type debugName for pointer types")
    func testPointerDebugName() {
        let ptrType = Type.pointer(element: .int)
        #expect(ptrType.debugName == "Pointer[Int]")
    }
    
    @Test("Type debugName for function types")
    func testFunctionDebugName() {
        let funcType = Type.function(
            parameters: [
                Parameter(type: .int, kind: .byVal),
                Parameter(type: .bool, kind: .byVal)
            ],
            returns: .void
        )
        #expect(funcType.debugName == "(Int, Bool) -> Void")
    }
    
    @Test("Type debugName for generic struct")
    func testGenericStructDebugName() {
        let genericType = Type.genericStruct(template: "List", args: [.int])
        #expect(genericType.debugName == "List[Int]")
    }
    
    @Test("Type debugName for generic union")
    func testGenericUnionDebugName() {
        let genericType = Type.genericUnion(template: "Option", args: [.int])
        #expect(genericType.debugName == "Option[Int]")
    }
    
    @Test("Type debugName for nested generic types")
    func testNestedGenericDebugName() {
        let innerType = Type.genericStruct(template: "List", args: [.int])
        let outerType = Type.genericStruct(template: "Option", args: [innerType])
        #expect(outerType.debugName == "Option[List[Int]]")
    }
    
    @Test("Type debugName for generic parameter")
    func testGenericParameterDebugName() {
        let paramType = Type.genericParameter(name: "T")
        #expect(paramType.debugName == "T")
    }
    
    // MARK: - Type Layout Key Tests
    
    @Test("Type layoutKey for primitive types")
    func testPrimitiveLayoutKeys() {
        #expect(Type.int.layoutKey == "I")
        #expect(Type.int8.layoutKey == "I8")
        #expect(Type.uint.layoutKey == "U")
        #expect(Type.float32.layoutKey == "F32")
        #expect(Type.bool.layoutKey == "B")
        #expect(Type.void.layoutKey == "V")
    }
    
    @Test("Type layoutKey for reference types")
    func testReferenceLayoutKey() {
        let refType = Type.reference(inner: .int)
        #expect(refType.layoutKey == "R_I")
    }
    
    @Test("Type layoutKey for pointer types")
    func testPointerLayoutKey() {
        let ptrType = Type.pointer(element: .int)
        #expect(ptrType.layoutKey == "P_I")
    }
    
    @Test("Type layoutKey for generic struct")
    func testGenericStructLayoutKey() {
        let genericType = Type.genericStruct(template: "List", args: [.int])
        #expect(genericType.layoutKey == "List_I")
    }
    
    @Test("Type layoutKey for nested generic types")
    func testNestedGenericLayoutKey() {
        let innerType = Type.genericStruct(template: "List", args: [.int])
        let outerType = Type.genericStruct(template: "Option", args: [innerType])
        #expect(outerType.layoutKey == "Option_List_I")
    }
    
    // MARK: - Property Tests
    
    @Test("Property: C identifiers are unique across different module paths")
    func testCIdentifierUniqueness() {
        let defIdMap = DefIdMap()
        
        // Create multiple DefIds with different module paths
        let defIds = [
            defIdMap.allocate(modulePath: ["a"], name: "Type", kind: .type(.structure), sourceFile: "a.koral"),
            defIdMap.allocate(modulePath: ["b"], name: "Type", kind: .type(.structure), sourceFile: "b.koral"),
            defIdMap.allocate(modulePath: ["a", "b"], name: "Type", kind: .type(.structure), sourceFile: "ab.koral"),
            defIdMap.allocate(modulePath: [], name: "Type", kind: .type(.structure), sourceFile: "root.koral")
        ]
        
        // All C identifiers should be unique
        var cIdentifiers: Set<String> = []
        for defId in defIds {
            let cId = defIdMap.uniqueCIdentifier(for: defId)
            #expect(!cIdentifiers.contains(cId), "Duplicate C identifier: \(cId)")
            cIdentifiers.insert(cId)
        }
    }
    
    @Test("Property: Layout keys are deterministic")
    func testLayoutKeyDeterminism() {
        // Same type should always produce the same layout key
        let type1 = Type.genericStruct(template: "List", args: [.int])
        let type2 = Type.genericStruct(template: "List", args: [.int])
        
        #expect(type1.layoutKey == type2.layoutKey)
        
        // Different types should produce different layout keys
        let type3 = Type.genericStruct(template: "List", args: [.bool])
        #expect(type1.layoutKey != type3.layoutKey)
    }
}
