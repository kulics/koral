import Testing

@testable import KoralCompiler

// MARK: - Object Safety Check Tests

/// Helper to create a minimal TypeChecker with pre-populated traits for testing.
private func makeTypeChecker(traits: [String: TraitDeclInfo]) -> TypeChecker {
  let tc = TypeChecker(ast: .program(globalNodes: []))
  tc.traits = traits
  return tc
}

/// Helper to create a simple trait method signature.
private func method(
  _ name: String,
  typeParameters: [TypeParameterDecl] = [],
  parameters: [(name: String, mutable: Bool, type: TypeNode)],
  returnType: TypeNode = .identifier("Void")
) -> TraitMethodSignature {
  TraitMethodSignature(
    name: name,
    typeParameters: typeParameters,
    parameters: parameters,
    returnType: returnType,
    access: .public
  )
}

// MARK: - Object-safe traits

@Test func objectSafe_simpleMethod_selfByValue() async throws {
  // trait ToString { to_string(self) String }
  let tc = makeTypeChecker(traits: [
    "ToString": TraitDeclInfo(
      name: "ToString",
      superTraits: [],
      methods: [
        method("to_string",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .identifier("String"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("ToString")
  #expect(safe)
  #expect(reasons.isEmpty)
}

@Test func objectSafe_selfRefMethod() async throws {
  // trait Countable { count(self ref) Int }
  let tc = makeTypeChecker(traits: [
    "Countable": TraitDeclInfo(
      name: "Countable",
      superTraits: [],
      methods: [
        method("count",
               parameters: [(name: "self", mutable: false, type: .reference(.inferredSelf))],
               returnType: .identifier("Int"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Countable")
  #expect(safe)
  #expect(reasons.isEmpty)
}

@Test func objectSafe_multipleMethods() async throws {
  // trait Error { message(self) String }
  // + a second method with non-Self params
  let tc = makeTypeChecker(traits: [
    "Error": TraitDeclInfo(
      name: "Error",
      superTraits: [],
      methods: [
        method("message",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .identifier("String")),
        method("code",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .identifier("Int"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Error")
  #expect(safe)
  #expect(reasons.isEmpty)
}

@Test func objectSafe_noMethods() async throws {
  // trait Marker {}  — no methods, trivially object-safe
  let tc = makeTypeChecker(traits: [
    "Marker": TraitDeclInfo(
      name: "Marker",
      superTraits: [],
      methods: [],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Marker")
  #expect(safe)
  #expect(reasons.isEmpty)
}

// MARK: - Non-object-safe traits

@Test func notObjectSafe_genericMethod() async throws {
  // trait Serializable { serialize[T Any](self, format T) String }
  let tc = makeTypeChecker(traits: [
    "Serializable": TraitDeclInfo(
      name: "Serializable",
      superTraits: [],
      methods: [
        method("serialize",
               typeParameters: [(name: "T", constraints: [.identifier("Any")])],
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "format", mutable: false, type: .identifier("T"))
               ],
               returnType: .identifier("String"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Serializable")
  #expect(!safe)
  #expect(reasons.count == 1)
  #expect(reasons[0].contains("generic type parameters"))
}

@Test func notObjectSafe_selfInParameter() async throws {
  // trait Eq { equals(self, other Self) Bool }
  let tc = makeTypeChecker(traits: [
    "Eq": TraitDeclInfo(
      name: "Eq",
      superTraits: [],
      methods: [
        method("equals",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "other", mutable: false, type: .inferredSelf)
               ],
               returnType: .identifier("Bool"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Eq")
  #expect(!safe)
  #expect(reasons.count == 1)
  #expect(reasons[0].contains("Self"))
  #expect(reasons[0].contains("other"))
}

@Test func notObjectSafe_selfInReturnType() async throws {
  // trait Clonable { clone(self) Self }
  let tc = makeTypeChecker(traits: [
    "Clonable": TraitDeclInfo(
      name: "Clonable",
      superTraits: [],
      methods: [
        method("clone",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .inferredSelf)
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Clonable")
  #expect(!safe)
  #expect(reasons.count == 1)
  #expect(reasons[0].contains("return type"))
}

@Test func notObjectSafe_selfInNestedType() async throws {
  // trait Foo { bar(self, x Self ref) Void }
  let tc = makeTypeChecker(traits: [
    "Foo": TraitDeclInfo(
      name: "Foo",
      superTraits: [],
      methods: [
        method("bar",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "x", mutable: false, type: .reference(.inferredSelf))
               ])
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Foo")
  #expect(!safe)
  #expect(reasons.count == 1)
  #expect(reasons[0].contains("Self"))
}

@Test func notObjectSafe_multipleViolations() async throws {
  // trait Bad { 
  //   foo[T](self) Void           — generic type param
  //   bar(self, x Self) Self      — Self in param AND return
  // }
  let tc = makeTypeChecker(traits: [
    "Bad": TraitDeclInfo(
      name: "Bad",
      superTraits: [],
      methods: [
        method("foo",
               typeParameters: [(name: "T", constraints: [])],
               parameters: [(name: "self", mutable: false, type: .inferredSelf)]),
        method("bar",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "x", mutable: false, type: .inferredSelf)
               ],
               returnType: .inferredSelf)
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Bad")
  #expect(!safe)
  #expect(reasons.count == 3) // generic param + Self in param + Self in return
}

// MARK: - Trait inheritance

@Test func objectSafe_safeParent() async throws {
  // trait Parent { msg(self) String }
  // trait Child: Parent { code(self) Int }
  let tc = makeTypeChecker(traits: [
    "Parent": TraitDeclInfo(
      name: "Parent",
      superTraits: [],
      methods: [
        method("msg",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .identifier("String"))
      ],
      access: .public
    ),
    "Child": TraitDeclInfo(
      name: "Child",
      superTraits: [.simple(name: "Parent")],
      methods: [
        method("code",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .identifier("Int"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Child")
  #expect(safe)
  #expect(reasons.isEmpty)
}

@Test func notObjectSafe_unsafeParent() async throws {
  // trait UnsafeParent { compare(self, other Self) Bool }
  // trait Child: UnsafeParent { name(self) String }
  let tc = makeTypeChecker(traits: [
    "UnsafeParent": TraitDeclInfo(
      name: "UnsafeParent",
      superTraits: [],
      methods: [
        method("compare",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "other", mutable: false, type: .inferredSelf)
               ],
               returnType: .identifier("Bool"))
      ],
      access: .public
    ),
    "Child": TraitDeclInfo(
      name: "Child",
      superTraits: [.simple(name: "UnsafeParent")],
      methods: [
        method("name",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .identifier("String"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Child")
  #expect(!safe)
  #expect(reasons.contains { $0.contains("inherited from UnsafeParent") })
}

@Test func notObjectSafe_transitiveUnsafeGrandparent() async throws {
  // trait Grandparent { eq(self, other Self) Bool }  — unsafe
  // trait Parent: Grandparent { }                    — unsafe by inheritance
  // trait Child: Parent { name(self) String }        — unsafe by inheritance
  let tc = makeTypeChecker(traits: [
    "Grandparent": TraitDeclInfo(
      name: "Grandparent",
      superTraits: [],
      methods: [
        method("eq",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "other", mutable: false, type: .inferredSelf)
               ],
               returnType: .identifier("Bool"))
      ],
      access: .public
    ),
    "Parent": TraitDeclInfo(
      name: "Parent",
      superTraits: [.simple(name: "Grandparent")],
      methods: [],
      access: .public
    ),
    "Child": TraitDeclInfo(
      name: "Child",
      superTraits: [.simple(name: "Parent")],
      methods: [
        method("name",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .identifier("String"))
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Child")
  #expect(!safe)
  #expect(reasons.contains { $0.contains("inherited from Parent") })
}

// MARK: - containsSelfType edge cases

@Test func notObjectSafe_selfInGenericArg() async throws {
  // trait Foo { bar(self, x [Self]List) Void }
  let tc = makeTypeChecker(traits: [
    "Foo": TraitDeclInfo(
      name: "Foo",
      superTraits: [],
      methods: [
        method("bar",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "x", mutable: false, type: .generic(base: "List", args: [.inferredSelf]))
               ])
      ],
      access: .public
    )
  ])
  let (safe, _) = try tc.checkObjectSafety("Foo")
  #expect(!safe)
}

@Test func notObjectSafe_selfInFunctionType() async throws {
  // trait Foo { bar(self, f [Self, Bool]Func) Void }
  let tc = makeTypeChecker(traits: [
    "Foo": TraitDeclInfo(
      name: "Foo",
      superTraits: [],
      methods: [
        method("bar",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "f", mutable: false, type: .functionType(paramTypes: [.inferredSelf], returnType: .identifier("Bool")))
               ])
      ],
      access: .public
    )
  ])
  let (safe, _) = try tc.checkObjectSafety("Foo")
  #expect(!safe)
}

@Test func notObjectSafe_selfInReturnFunctionType() async throws {
  // trait Foo { bar(self) [Int, Self]Func }
  let tc = makeTypeChecker(traits: [
    "Foo": TraitDeclInfo(
      name: "Foo",
      superTraits: [],
      methods: [
        method("bar",
               parameters: [(name: "self", mutable: false, type: .inferredSelf)],
               returnType: .functionType(paramTypes: [.identifier("Int")], returnType: .inferredSelf))
      ],
      access: .public
    )
  ])
  let (safe, _) = try tc.checkObjectSafety("Foo")
  #expect(!safe)
}

@Test func objectSafe_selfOnlyInReceiver() async throws {
  // Self in receiver position is allowed (both self and self ref)
  // trait Foo { bar(self, x Int) String; baz(self ref, y Bool) Void }
  let tc = makeTypeChecker(traits: [
    "Foo": TraitDeclInfo(
      name: "Foo",
      superTraits: [],
      methods: [
        method("bar",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "x", mutable: false, type: .identifier("Int"))
               ],
               returnType: .identifier("String")),
        method("baz",
               parameters: [
                 (name: "self", mutable: false, type: .reference(.inferredSelf)),
                 (name: "y", mutable: false, type: .identifier("Bool"))
               ])
      ],
      access: .public
    )
  ])
  let (safe, reasons) = try tc.checkObjectSafety("Foo")
  #expect(safe)
  #expect(reasons.isEmpty)
}

@Test func notObjectSafe_selfIdentifierInParam() async throws {
  // TypeNode.identifier("Self") should also be detected
  let tc = makeTypeChecker(traits: [
    "Foo": TraitDeclInfo(
      name: "Foo",
      superTraits: [],
      methods: [
        method("bar",
               parameters: [
                 (name: "self", mutable: false, type: .inferredSelf),
                 (name: "other", mutable: false, type: .identifier("Self"))
               ],
               returnType: .identifier("Void"))
      ],
      access: .public
    )
  ])
  let (safe, _) = try tc.checkObjectSafety("Foo")
  #expect(!safe)
}
