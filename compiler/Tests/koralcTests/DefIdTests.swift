import Testing

@testable import KoralCompiler

/// DefId 系统单元测试
///
/// 测试 DefId 和 DefIdMap 的核心功能：
/// - DefId 的创建和属性访问
/// - DefIdMap 的 allocate 方法
/// - DefIdMap 的 lookup 方法
/// - DefIdMap 的 lookupById 方法
/// - Property 1: DefId 唯一性
///
/// **Validates: Requirements 1.1, 1.4, 8.1**
@Suite("DefId System Tests")
struct DefIdTests {
    
    // MARK: - DefId Creation and Properties Tests
    
    @Test("DefId creation and basic properties")
    func testDefIdCreation() {
        let defId = DefId(
            modulePath: ["expr_eval", "frontend"],
            name: "Parser",
            kind: .type(.structure),
            sourceFile: "parser.koral",
            id: 42
        )
        
        #expect(defId.modulePath == ["expr_eval", "frontend"])
        #expect(defId.name == "Parser")
        #expect(defId.sourceFile == "parser.koral")
        #expect(defId.id == 42)
        #expect(defId.kind == .type(.structure))
    }
    
    @Test("DefId cIdentifier generation with module path")
    func testDefIdCIdentifierWithModulePath() {
        let defId = DefId(
            modulePath: ["expr_eval", "frontend"],
            name: "Parser",
            kind: .type(.structure),
            sourceFile: "parser.koral",
            id: 1
        )
        
        #expect(defId.cIdentifier == "expr_eval_frontend_Parser")
    }
    
    @Test("DefId cIdentifier generation without module path")
    func testDefIdCIdentifierWithoutModulePath() {
        let defId = DefId(
            modulePath: [],
            name: "main",
            kind: .function,
            sourceFile: "main.koral",
            id: 0
        )
        
        #expect(defId.cIdentifier == "main")
    }
    
    @Test("DefId qualifiedName generation")
    func testDefIdQualifiedName() {
        let defId = DefId(
            modulePath: ["expr_eval", "frontend"],
            name: "Parser",
            kind: .type(.structure),
            sourceFile: "parser.koral",
            id: 1
        )
        
        #expect(defId.qualifiedName == "expr_eval.frontend.Parser")
    }
    
    @Test("DefId qualifiedName for root level definition")
    func testDefIdQualifiedNameRootLevel() {
        let defId = DefId(
            modulePath: [],
            name: "GlobalFunc",
            kind: .function,
            sourceFile: "global.koral",
            id: 0
        )
        
        #expect(defId.qualifiedName == "GlobalFunc")
        #expect(defId.isRootLevel == true)
    }
    
    @Test("DefId isRootLevel property")
    func testDefIdIsRootLevel() {
        let rootDefId = DefId(
            modulePath: [],
            name: "RootType",
            kind: .type(.structure),
            sourceFile: "root.koral",
            id: 0
        )
        
        let nestedDefId = DefId(
            modulePath: ["module"],
            name: "NestedType",
            kind: .type(.structure),
            sourceFile: "nested.koral",
            id: 1
        )
        
        #expect(rootDefId.isRootLevel == true)
        #expect(nestedDefId.isRootLevel == false)
    }
    
    @Test("DefId equality based on id")
    func testDefIdEquality() {
        let defId1 = DefId(
            modulePath: ["module"],
            name: "Type1",
            kind: .type(.structure),
            sourceFile: "type1.koral",
            id: 42
        )
        
        let defId2 = DefId(
            modulePath: ["different"],
            name: "Type2",
            kind: .function,
            sourceFile: "type2.koral",
            id: 42
        )
        
        let defId3 = DefId(
            modulePath: ["module"],
            name: "Type1",
            kind: .type(.structure),
            sourceFile: "type1.koral",
            id: 43
        )
        
        // Same id means equal (even with different properties)
        #expect(defId1 == defId2)
        // Different id means not equal (even with same properties)
        #expect(defId1 != defId3)
    }
    
    @Test("DefId hashable based on id")
    func testDefIdHashable() {
        let defId1 = DefId(
            modulePath: ["module"],
            name: "Type1",
            kind: .type(.structure),
            sourceFile: "type1.koral",
            id: 42
        )
        
        let defId2 = DefId(
            modulePath: ["different"],
            name: "Type2",
            kind: .function,
            sourceFile: "type2.koral",
            id: 42
        )
        
        // Same id should produce same hash
        #expect(defId1.hashValue == defId2.hashValue)
        
        // Can be used in Set
        var set = Set<DefId>()
        set.insert(defId1)
        #expect(set.contains(defId2))
    }
    
    // MARK: - DefKind Tests
    
    @Test("DefKind type variants")
    func testDefKindTypeVariants() {
        let structKind = DefKind.type(.structure)
        let unionKind = DefKind.type(.union)
        let traitKind = DefKind.type(.trait)
        
        #expect(structKind != unionKind)
        #expect(unionKind != traitKind)
        #expect(structKind != traitKind)
    }
    
    @Test("DefKind generic template variants")
    func testDefKindGenericTemplateVariants() {
        let genericStruct = DefKind.genericTemplate(.structure)
        let genericUnion = DefKind.genericTemplate(.union)
        let genericFunc = DefKind.genericTemplate(.function)
        
        #expect(genericStruct != genericUnion)
        #expect(genericUnion != genericFunc)
        #expect(genericStruct != genericFunc)
    }
    
    // MARK: - DefIdMap Allocate Tests
    
    @Test("DefIdMap allocate returns unique IDs")
    func testDefIdMapAllocate() {
        let map = DefIdMap()
        
        let defId1 = map.allocate(
            modulePath: ["module1"],
            name: "Type1",
            kind: .type(.structure),
            sourceFile: "type1.koral"
        )
        
        let defId2 = map.allocate(
            modulePath: ["module1"],
            name: "Type2",
            kind: .type(.structure),
            sourceFile: "type2.koral"
        )
        
        #expect(defId1.id != defId2.id)
        #expect(map.count == 2)
    }
    
    @Test("DefIdMap allocate assigns sequential IDs")
    func testDefIdMapAllocateSequentialIds() {
        let map = DefIdMap()
        
        let defId1 = map.allocate(
            modulePath: ["module"],
            name: "First",
            kind: .function,
            sourceFile: "first.koral"
        )
        
        let defId2 = map.allocate(
            modulePath: ["module"],
            name: "Second",
            kind: .function,
            sourceFile: "second.koral"
        )
        
        let defId3 = map.allocate(
            modulePath: ["module"],
            name: "Third",
            kind: .function,
            sourceFile: "third.koral"
        )
        
        #expect(defId1.id == 0)
        #expect(defId2.id == 1)
        #expect(defId3.id == 2)
    }
    
    @Test("DefIdMap allocate with different kinds")
    func testDefIdMapAllocateDifferentKinds() {
        let map = DefIdMap()
        
        let structDefId = map.allocate(
            modulePath: ["module"],
            name: "MyStruct",
            kind: .type(.structure),
            sourceFile: "types.koral"
        )
        
        let funcDefId = map.allocate(
            modulePath: ["module"],
            name: "myFunc",
            kind: .function,
            sourceFile: "funcs.koral"
        )
        
        let varDefId = map.allocate(
            modulePath: ["module"],
            name: "myVar",
            kind: .variable,
            sourceFile: "vars.koral"
        )
        
        #expect(structDefId.kind == .type(.structure))
        #expect(funcDefId.kind == .function)
        #expect(varDefId.kind == .variable)
    }
    
    // MARK: - DefIdMap Lookup Tests
    
    @Test("DefIdMap lookup finds allocated DefIds")
    func testDefIdMapLookup() {
        let map = DefIdMap()
        
        let allocated = map.allocate(
            modulePath: ["mymodule"],
            name: "MyType",
            kind: .type(.structure),
            sourceFile: "mytype.koral"
        )
        
        let found = map.lookup(modulePath: ["mymodule"], name: "MyType")
        #expect(found != nil)
        #expect(found?.id == allocated.id)
        #expect(found?.name == "MyType")
        #expect(found?.modulePath == ["mymodule"])
    }
    
    @Test("DefIdMap lookup returns nil for non-existent DefId")
    func testDefIdMapLookupNotFound() {
        let map = DefIdMap()
        
        _ = map.allocate(
            modulePath: ["module"],
            name: "ExistingType",
            kind: .type(.structure),
            sourceFile: "existing.koral"
        )
        
        let notFound = map.lookup(modulePath: ["module"], name: "NonExistentType")
        #expect(notFound == nil)
    }
    
    @Test("DefIdMap lookup with sourceFile for private symbols")
    func testDefIdMapLookupWithSourceFile() {
        let map = DefIdMap()
        
        let allocated = map.allocate(
            modulePath: ["module"],
            name: "PrivateType",
            kind: .type(.structure),
            sourceFile: "private.koral"
        )
        
        // Lookup with matching sourceFile
        let foundWithFile = map.lookup(
            modulePath: ["module"],
            name: "PrivateType",
            sourceFile: "private.koral"
        )
        #expect(foundWithFile != nil)
        #expect(foundWithFile?.id == allocated.id)
    }
    
    @Test("DefIdMap lookup with nested module path")
    func testDefIdMapLookupNestedModulePath() {
        let map = DefIdMap()
        
        let allocated = map.allocate(
            modulePath: ["root", "sub", "nested"],
            name: "DeepType",
            kind: .type(.structure),
            sourceFile: "deep.koral"
        )
        
        let found = map.lookup(modulePath: ["root", "sub", "nested"], name: "DeepType")
        #expect(found != nil)
        #expect(found?.id == allocated.id)
        #expect(found?.qualifiedName == "root.sub.nested.DeepType")
    }
    
    // MARK: - DefIdMap LookupById Tests
    
    @Test("DefIdMap lookupById finds allocated DefIds")
    func testDefIdMapLookupById() {
        let map = DefIdMap()
        
        let allocated = map.allocate(
            modulePath: ["module"],
            name: "MyType",
            kind: .type(.structure),
            sourceFile: "mytype.koral"
        )
        
        let found = map.lookupById(allocated.id)
        #expect(found != nil)
        #expect(found?.name == "MyType")
        #expect(found?.modulePath == ["module"])
    }
    
    @Test("DefIdMap lookupById returns nil for non-existent ID")
    func testDefIdMapLookupByIdNotFound() {
        let map = DefIdMap()
        
        _ = map.allocate(
            modulePath: ["module"],
            name: "Type",
            kind: .type(.structure),
            sourceFile: "type.koral"
        )
        
        let notFound = map.lookupById(999)
        #expect(notFound == nil)
    }
    
    // MARK: - DefIdMap Contains Tests
    
    @Test("DefIdMap contains check")
    func testDefIdMapContains() {
        let map = DefIdMap()
        
        _ = map.allocate(
            modulePath: ["module"],
            name: "ExistingType",
            kind: .type(.structure),
            sourceFile: "existing.koral"
        )
        
        #expect(map.contains(modulePath: ["module"], name: "ExistingType") == true)
        #expect(map.contains(modulePath: ["module"], name: "NonExistent") == false)
        #expect(map.contains(modulePath: ["other"], name: "ExistingType") == false)
    }
    
    // MARK: - DefIdMap AllDefIds Tests
    
    @Test("DefIdMap allDefIds returns all allocated DefIds sorted by ID")
    func testDefIdMapAllDefIds() {
        let map = DefIdMap()
        
        _ = map.allocate(modulePath: ["a"], name: "TypeA", kind: .type(.structure), sourceFile: "a.koral")
        _ = map.allocate(modulePath: ["b"], name: "TypeB", kind: .type(.union), sourceFile: "b.koral")
        _ = map.allocate(modulePath: ["c"], name: "TypeC", kind: .function, sourceFile: "c.koral")
        
        let allDefIds = map.allDefIds
        
        #expect(allDefIds.count == 3)
        #expect(allDefIds[0].name == "TypeA")
        #expect(allDefIds[1].name == "TypeB")
        #expect(allDefIds[2].name == "TypeC")
        #expect(allDefIds[0].id < allDefIds[1].id)
        #expect(allDefIds[1].id < allDefIds[2].id)
    }
    
    // MARK: - Property 1: DefId Uniqueness Tests
    
    @Test("Property 1: DefId uniqueness across many allocations")
    func testDefIdUniqueness() {
        let map = DefIdMap()
        var ids = Set<UInt64>()
        
        // 分配 100 个 DefId
        for i in 0..<100 {
            let defId = map.allocate(
                modulePath: ["module\(i % 10)"],
                name: "Type\(i)",
                kind: .type(.structure),
                sourceFile: "file\(i).koral"
            )
            
            // 验证 ID 唯一性
            #expect(!ids.contains(defId.id), "DefId \(defId.id) should be unique")
            ids.insert(defId.id)
        }
        
        #expect(ids.count == 100)
        #expect(map.count == 100)
    }
    
    @Test("Property 1: DefId uniqueness with same name in different modules")
    func testDefIdUniquenessAcrossModules() {
        let map = DefIdMap()
        
        // Same name in different modules should get different IDs
        let defId1 = map.allocate(
            modulePath: ["module1"],
            name: "SameName",
            kind: .type(.structure),
            sourceFile: "file1.koral"
        )
        
        let defId2 = map.allocate(
            modulePath: ["module2"],
            name: "SameName",
            kind: .type(.structure),
            sourceFile: "file2.koral"
        )
        
        let defId3 = map.allocate(
            modulePath: ["module1", "sub"],
            name: "SameName",
            kind: .type(.structure),
            sourceFile: "file3.koral"
        )
        
        #expect(defId1.id != defId2.id)
        #expect(defId2.id != defId3.id)
        #expect(defId1.id != defId3.id)
        
        // But they should have different cIdentifiers
        #expect(defId1.cIdentifier == "module1_SameName")
        #expect(defId2.cIdentifier == "module2_SameName")
        #expect(defId3.cIdentifier == "module1_sub_SameName")
    }
    
    @Test("Property 1: DefId uniqueness with same name and different kinds")
    func testDefIdUniquenessWithDifferentKinds() {
        let map = DefIdMap()
        
        // Same name with different kinds should get different IDs
        let structDefId = map.allocate(
            modulePath: ["module"],
            name: "Item",
            kind: .type(.structure),
            sourceFile: "item.koral"
        )
        
        let funcDefId = map.allocate(
            modulePath: ["module"],
            name: "Item",
            kind: .function,
            sourceFile: "item.koral"
        )
        
        #expect(structDefId.id != funcDefId.id)
    }
    
    @Test("Property 1: C identifier uniqueness for different DefIds")
    func testCIdentifierUniqueness() {
        let map = DefIdMap()
        var cIdentifiers = Set<String>()
        
        // Create DefIds with various module paths
        let testCases: [([String], String)] = [
            ([], "GlobalType"),
            (["module"], "Type"),
            (["module", "sub"], "Type"),
            (["other"], "Type"),
            (["a", "b", "c"], "DeepType"),
        ]
        
        for (modulePath, name) in testCases {
            let defId = map.allocate(
                modulePath: modulePath,
                name: name,
                kind: .type(.structure),
                sourceFile: "test.koral"
            )
            
            // Each cIdentifier should be unique
            #expect(!cIdentifiers.contains(defId.cIdentifier), 
                   "cIdentifier '\(defId.cIdentifier)' should be unique")
            cIdentifiers.insert(defId.cIdentifier)
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("DefIdMap with empty module path")
    func testDefIdMapEmptyModulePath() {
        let map = DefIdMap()
        
        let defId = map.allocate(
            modulePath: [],
            name: "RootFunction",
            kind: .function,
            sourceFile: "root.koral"
        )
        
        #expect(defId.modulePath.isEmpty)
        #expect(defId.cIdentifier == "RootFunction")
        #expect(defId.qualifiedName == "RootFunction")
        
        let found = map.lookup(modulePath: [], name: "RootFunction")
        #expect(found != nil)
        #expect(found?.id == defId.id)
    }
    
    @Test("DefIdMap with special characters in names")
    func testDefIdMapSpecialNames() {
        let map = DefIdMap()
        
        // Names with underscores (valid in Koral)
        let defId = map.allocate(
            modulePath: ["my_module"],
            name: "my_type",
            kind: .type(.structure),
            sourceFile: "my_file.koral"
        )
        
        #expect(defId.cIdentifier == "my_module_my_type")
        
        let found = map.lookup(modulePath: ["my_module"], name: "my_type")
        #expect(found != nil)
    }
    
    @Test("DefIdMap count property")
    func testDefIdMapCount() {
        let map = DefIdMap()
        
        #expect(map.count == 0)
        
        _ = map.allocate(modulePath: [], name: "A", kind: .function, sourceFile: "a.koral")
        #expect(map.count == 1)
        
        _ = map.allocate(modulePath: [], name: "B", kind: .function, sourceFile: "b.koral")
        #expect(map.count == 2)
        
        _ = map.allocate(modulePath: ["m"], name: "C", kind: .type(.structure), sourceFile: "c.koral")
        #expect(map.count == 3)
    }
}
