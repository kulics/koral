import Testing

@testable import KoralCompiler

@Test func example() async throws {
  // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}

private func parseNodes(_ source: String) throws -> [GlobalNode] {
  let lexer = Lexer(input: source)
  let parser = Parser(lexer: lexer)
  let ast = try parser.parse()
  guard case .program(let nodes) = ast else {
    return []
  }
  return nodes
}

@Test func parserGlobalDefaultsToProtected() throws {
  let nodes = try parseNodes("let x Int = 1")
  guard let first = nodes.first,
        case .globalVariableDeclaration(_, _, _, _, let access, _) = first else {
    Issue.record("expected global variable declaration")
    return
  }
  #expect(access == .protected)
}

@Test func parserForeignFunctionDefaultsToProtected() throws {
  let nodes = try parseNodes("foreign let f() Int")
  guard let first = nodes.first,
        case .foreignFunctionDeclaration(_, _, _, let access, _) = first else {
    Issue.record("expected foreign function declaration")
    return
  }
  #expect(access == .protected)
}

@Test func parserStructFieldDefaultsToPublic() throws {
  let nodes = try parseNodes("type S(x Int)")
  guard let first = nodes.first,
        case .globalStructDeclaration(_, _, let fields, _, _) = first else {
    Issue.record("expected struct declaration")
    return
  }
  #expect(fields.count == 1)
  #expect(fields[0].access == .public)
}

@Test func parserTraitMethodDefaultsToPublic() throws {
  let source = """
  trait T {
    m(self) Void
  }
  """
  let nodes = try parseNodes(source)
  guard let first = nodes.first,
        case .traitDeclaration(_, _, _, let methods, _, _) = first else {
    Issue.record("expected trait declaration")
    return
  }
  #expect(methods.count == 1)
  #expect(methods[0].access == .public)
}

@Test func parserGivenMethodDefaultsToProtected() throws {
  let source = """
  given Int {
    m(self) Void = {}
  }
  """
  let nodes = try parseNodes(source)
  guard let first = nodes.first,
        case .givenDeclaration(_, _, let methods, _) = first else {
    Issue.record("expected given declaration")
    return
  }
  #expect(methods.count == 1)
  #expect(methods[0].access == .protected)
}

@Test func parserUsingDefaultsToPrivate() throws {
  let nodes = try parseNodes("using std")
  guard let first = nodes.first,
        case .usingDeclaration(let usingDecl) = first else {
    Issue.record("expected using declaration")
    return
  }
  #expect(usingDecl.access == .private)
}
