import Testing

@testable import KoralCompiler

// MARK: - Wrapper Function Generation Tests

/// Helper to create a minimal CodeGen instance for testing wrapper function generation.
private func makeCodeGen() -> CodeGen {
  let program = MonomorphizedProgram(globalNodes: [])
  let context = CompilerContext()
  return CodeGen(ast: program, context: context)
}

/// Helper to create a simple trait method signature.
private func method(
  _ name: String,
  parameters: [(name: String, mutable: Bool, type: TypeNode)],
  returnType: TypeNode = .identifier("Void")
) -> TraitMethodSignature {
  TraitMethodSignature(
    name: name,
    parameters: parameters,
    returnType: returnType,
    access: .public
  )
}

// MARK: - isSelfByValue

@Test func isSelfByValue_selfByValue() async throws {
  let cg = makeCodeGen()
  let sig = method("message",
    parameters: [(name: "self", mutable: false, type: .inferredSelf)],
    returnType: .identifier("Int"))
  #expect(cg.isSelfByValue(sig))
}

@Test func isSelfByValue_selfRef() async throws {
  let cg = makeCodeGen()
  let sig = method("count",
    parameters: [(name: "self", mutable: false, type: .reference(.inferredSelf))],
    returnType: .identifier("Int"))
  #expect(!cg.isSelfByValue(sig))
}

@Test func isSelfByValue_noSelfParam() async throws {
  let cg = makeCodeGen()
  let sig = method("static_method",
    parameters: [(name: "x", mutable: false, type: .identifier("Int"))],
    returnType: .identifier("Int"))
  #expect(!cg.isSelfByValue(sig))
}

// MARK: - generateWrapperFunction: self by value (struct type)

@Test func wrapper_selfByValue_structType() async throws {
  let cg = makeCodeGen()
  let defId = DefId(id: 999)
  let concreteType = Type.structure(defId: defId)
  
  // Use Int return type since it's a builtin that resolveTypeNodeForVtable can resolve
  let sig = method("code",
    parameters: [(name: "self", mutable: false, type: .inferredSelf)],
    returnType: .identifier("Int"))
  
  let result = cg.generateWrapperFunction(
    concreteType: concreteType,
    concreteTypeCName: "std_String",
    traitName: "Error",
    methodName: "code",
    signature: sig,
    actualMethodCName: "std_String_Error_code"
  )
  
  #expect(result != nil)
  let code = result!
  
  // Check wrapper function name follows naming convention
  #expect(code.contains("__koral_wrapper_std_String_Error_code"))
  // Check it's static
  #expect(code.hasPrefix("static "))
  // Check it receives struct Ref as first parameter
  #expect(code.contains("struct Ref self_ref"))
  // Check it uses copy function for struct type
  #expect(code.contains("__koral_std_String_copy"))
  // Check it casts self_ref.ptr to the concrete type pointer
  #expect(code.contains("self_ref.ptr"))
  // Check it calls the actual method with the extracted value
  #expect(code.contains("std_String_Error_code(self_val)"))
  // Non-void wrapper stores return value, releases copied self_ref, then returns
  #expect(code.contains("__koral_ret = std_String_Error_code(self_val)"))
  #expect(code.contains("__koral_release(self_ref.control);"))
  #expect(code.contains("return __koral_ret;"))
}

// MARK: - generateWrapperFunction: self ref (no wrapper needed)

@Test func wrapper_selfRef_returnsNil() async throws {
  let cg = makeCodeGen()
  let defId = DefId(id: 999)
  let concreteType = Type.structure(defId: defId)
  
  let sig = method("next",
    parameters: [(name: "self", mutable: false, type: .reference(.inferredSelf))],
    returnType: .identifier("Int"))
  
  let result = cg.generateWrapperFunction(
    concreteType: concreteType,
    concreteTypeCName: "MyIter",
    traitName: "Iterator",
    methodName: "next",
    signature: sig,
    actualMethodCName: "MyIter_Iterator_next"
  )
  
  // self ref methods don't need a wrapper
  #expect(result == nil)
}

// MARK: - generateWrapperFunction: primitive type (bitwise copy)

@Test func wrapper_selfByValue_primitiveType() async throws {
  let cg = makeCodeGen()
  let concreteType = Type.int
  
  let sig = method("to_int",
    parameters: [(name: "self", mutable: false, type: .inferredSelf)],
    returnType: .identifier("Int"))
  
  let result = cg.generateWrapperFunction(
    concreteType: concreteType,
    concreteTypeCName: "Int",
    traitName: "ToInt",
    methodName: "to_int",
    signature: sig,
    actualMethodCName: "Int_ToInt_to_int"
  )
  
  #expect(result != nil)
  let code = result!
  
  // Primitive types use bitwise copy (dereference), not copy function
  #expect(!code.contains("__koral_Int_copy"))
  // Should dereference the pointer
  #expect(code.contains("self_ref.ptr"))
  #expect(code.contains("self_val = *"))
  // Check it calls the actual method
  #expect(code.contains("Int_ToInt_to_int(self_val)"))
}

// MARK: - generateWrapperFunction: with extra parameters

@Test func wrapper_selfByValue_withExtraParams() async throws {
  let cg = makeCodeGen()
  let defId = DefId(id: 999)
  let concreteType = Type.structure(defId: defId)
  
  let sig = method("format",
    parameters: [
      (name: "self", mutable: false, type: .inferredSelf),
      (name: "width", mutable: false, type: .identifier("Int")),
      (name: "fill", mutable: false, type: .identifier("Bool"))
    ],
    returnType: .identifier("Int"))
  
  let result = cg.generateWrapperFunction(
    concreteType: concreteType,
    concreteTypeCName: "MyType",
    traitName: "Formattable",
    methodName: "format",
    signature: sig,
    actualMethodCName: "MyType_Formattable_format"
  )
  
  #expect(result != nil)
  let code = result!
  
  // Check extra parameters are in the wrapper signature
  #expect(code.contains("width"))
  #expect(code.contains("fill"))
  // Check extra parameters are passed through to the actual method call
  #expect(code.contains("MyType_Formattable_format(self_val, width, fill)"))
}

// MARK: - generateWrapperFunction: void return type

@Test func wrapper_selfByValue_voidReturn() async throws {
  let cg = makeCodeGen()
  let defId = DefId(id: 999)
  let concreteType = Type.structure(defId: defId)
  
  let sig = method("do_something",
    parameters: [(name: "self", mutable: false, type: .inferredSelf)],
    returnType: .identifier("Void"))
  
  let result = cg.generateWrapperFunction(
    concreteType: concreteType,
    concreteTypeCName: "MyType",
    traitName: "Action",
    methodName: "do_something",
    signature: sig,
    actualMethodCName: "MyType_Action_do_something"
  )
  
  #expect(result != nil)
  let code = result!
  
  // Void return: function signature should have void return type
  #expect(code.contains("static void __koral_wrapper_MyType_Action_do_something"))
  // Should NOT have "return" before the method call
  #expect(!code.contains("return MyType_Action_do_something"))
  // Should call the method without return
  #expect(code.contains("MyType_Action_do_something(self_val);"))
}

// MARK: - wrapperFunctionName

@Test func wrapperFunctionName_basic() async throws {
  let cg = makeCodeGen()
  let name = cg.wrapperFunctionName(
    concreteTypeCName: "std_String",
    traitName: "Error",
    methodName: "message"
  )
  #expect(name == "__koral_wrapper_std_String_Error_message")
}

// MARK: - Union type uses copy function

@Test func wrapper_selfByValue_unionType() async throws {
  let cg = makeCodeGen()
  let defId = DefId(id: 999)
  let concreteType = Type.union(defId: defId)
  
  let sig = method("describe",
    parameters: [(name: "self", mutable: false, type: .inferredSelf)],
    returnType: .identifier("Int"))
  
  let result = cg.generateWrapperFunction(
    concreteType: concreteType,
    concreteTypeCName: "MyUnion",
    traitName: "Describable",
    methodName: "describe",
    signature: sig,
    actualMethodCName: "MyUnion_Describable_describe"
  )
  
  #expect(result != nil)
  let code = result!
  
  // Union types also have copy functions
  #expect(code.contains("__koral_MyUnion_copy"))
  // Should cast self_ref.ptr to the concrete type pointer
  #expect(code.contains("self_ref.ptr"))
}


// MARK: - vtableInstanceName

@Test func vtableInstanceName_basic() async throws {
  let cg = makeCodeGen()
  let name = cg.vtableInstanceName(
    concreteTypeCName: "std_String",
    traitName: "Error"
  )
  #expect(name == "__koral_vtable_Error_for_std_String")
}

@Test func vtableInstanceName_sanitizesNames() async throws {
  let cg = makeCodeGen()
  let name = cg.vtableInstanceName(
    concreteTypeCName: "my.module.MyType",
    traitName: "my.module.MyTrait"
  )
  #expect(name == "__koral_vtable_my_module_MyTrait_for_my_module_MyType")
}

// MARK: - generateVtableInstance: basic self by value

@Test func vtableInstance_selfByValue() async throws {
  let context = CompilerContext()
  // Register a trait with a self by value method
  let traitInfo = TraitDeclInfo(
    name: "Error",
    superTraits: [],
    methods: [
      TraitMethodSignature(
        name: "message",
        parameters: [(name: "self", mutable: false, type: .inferredSelf)],
        returnType: .identifier("Int"),
        access: .public
      )
    ],
    access: .public
  )
  let program = MonomorphizedProgram(globalNodes: [], traits: ["Error": traitInfo])
  let cg = CodeGen(ast: program, context: context)

  let result = cg.generateVtableInstance(
    concreteTypeCName: "std_String",
    traitName: "Error",
    actualMethodCNames: ["message": "std_String_Error_message"]
  )

  #expect(result != nil)
  let code = result!
  // Should be static const
  #expect(code.hasPrefix("static const struct"))
  // Should reference the vtable struct type
  #expect(code.contains("__koral_vtable_Error"))
  // Should use the correct instance name
  #expect(code.contains("__koral_vtable_Error_for_std_String"))
  // self by value: should use wrapper function name, not actual method
  #expect(code.contains("__koral_wrapper_std_String_Error_message"))
  // Should NOT contain the actual method name directly as a vtable entry
  #expect(!code.contains(".message = std_String_Error_message"))
}

// MARK: - generateVtableInstance: self ref (direct method)

@Test func vtableInstance_selfRef() async throws {
  let context = CompilerContext()
  let traitInfo = TraitDeclInfo(
    name: "IntIterator",
    superTraits: [],
    methods: [
      TraitMethodSignature(
        name: "next",
        parameters: [(name: "self", mutable: false, type: .reference(.inferredSelf))],
        returnType: .identifier("Int"),
        access: .public
      )
    ],
    access: .public
  )
  let program = MonomorphizedProgram(globalNodes: [], traits: ["IntIterator": traitInfo])
  let cg = CodeGen(ast: program, context: context)

  let result = cg.generateVtableInstance(
    concreteTypeCName: "MyIter",
    traitName: "IntIterator",
    actualMethodCNames: ["next": "MyIter_next"]
  )

  #expect(result != nil)
  let code = result!
  // self ref: should use actual method name directly
  #expect(code.contains(".next = MyIter_next"))
  // Should NOT use a wrapper
  #expect(!code.contains("__koral_wrapper"))
  // Correct instance name
  #expect(code.contains("__koral_vtable_IntIterator_for_MyIter"))
}

// MARK: - generateVtableInstance: deduplication

@Test func vtableInstance_deduplication() async throws {
  let context = CompilerContext()
  let traitInfo = TraitDeclInfo(
    name: "Error",
    superTraits: [],
    methods: [
      TraitMethodSignature(
        name: "message",
        parameters: [(name: "self", mutable: false, type: .inferredSelf)],
        returnType: .identifier("Int"),
        access: .public
      )
    ],
    access: .public
  )
  let program = MonomorphizedProgram(globalNodes: [], traits: ["Error": traitInfo])
  let cg = CodeGen(ast: program, context: context)

  let first = cg.generateVtableInstance(
    concreteTypeCName: "std_String",
    traitName: "Error",
    actualMethodCNames: ["message": "std_String_Error_message"]
  )
  #expect(first != nil)

  // Second call with same combination should return nil (already generated)
  let second = cg.generateVtableInstance(
    concreteTypeCName: "std_String",
    traitName: "Error",
    actualMethodCNames: ["message": "std_String_Error_message"]
  )
  #expect(second == nil)
}

// MARK: - generateVtableInstance: mixed self/self ref methods

@Test func vtableInstance_mixedMethods() async throws {
  let context = CompilerContext()
  let traitInfo = TraitDeclInfo(
    name: "MixedTrait",
    superTraits: [],
    methods: [
      TraitMethodSignature(
        name: "by_value",
        parameters: [(name: "self", mutable: false, type: .inferredSelf)],
        returnType: .identifier("Int"),
        access: .public
      ),
      TraitMethodSignature(
        name: "by_ref",
        parameters: [(name: "self", mutable: false, type: .reference(.inferredSelf))],
        returnType: .identifier("Int"),
        access: .public
      )
    ],
    access: .public
  )
  let program = MonomorphizedProgram(globalNodes: [], traits: ["MixedTrait": traitInfo])
  let cg = CodeGen(ast: program, context: context)

  let result = cg.generateVtableInstance(
    concreteTypeCName: "MyType",
    traitName: "MixedTrait",
    actualMethodCNames: [
      "by_value": "MyType_MixedTrait_by_value",
      "by_ref": "MyType_by_ref"
    ]
  )

  #expect(result != nil)
  let code = result!
  // self by value: uses wrapper
  #expect(code.contains(".by_value = __koral_wrapper_MyType_MixedTrait_by_value"))
  // self ref: uses actual method directly
  #expect(code.contains(".by_ref = MyType_by_ref"))
}

// MARK: - generateVtableInstance: unknown trait returns nil

@Test func vtableInstance_unknownTrait() async throws {
  let cg = makeCodeGen()
  let result = cg.generateVtableInstance(
    concreteTypeCName: "MyType",
    traitName: "NonExistentTrait",
    actualMethodCNames: [:]
  )
  #expect(result == nil)
}

// MARK: - generateVtableInstance: different concrete types are independent

@Test func vtableInstance_differentConcreteTypes() async throws {
  let context = CompilerContext()
  let traitInfo = TraitDeclInfo(
    name: "Error",
    superTraits: [],
    methods: [
      TraitMethodSignature(
        name: "message",
        parameters: [(name: "self", mutable: false, type: .inferredSelf)],
        returnType: .identifier("Int"),
        access: .public
      )
    ],
    access: .public
  )
  let program = MonomorphizedProgram(globalNodes: [], traits: ["Error": traitInfo])
  let cg = CodeGen(ast: program, context: context)

  let first = cg.generateVtableInstance(
    concreteTypeCName: "std_String",
    traitName: "Error",
    actualMethodCNames: ["message": "std_String_Error_message"]
  )
  #expect(first != nil)
  #expect(first!.contains("__koral_vtable_Error_for_std_String"))

  // Different concrete type should generate a separate vtable
  let second = cg.generateVtableInstance(
    concreteTypeCName: "MyError",
    traitName: "Error",
    actualMethodCNames: ["message": "MyError_Error_message"]
  )
  #expect(second != nil)
  #expect(second!.contains("__koral_vtable_Error_for_MyError"))
}
