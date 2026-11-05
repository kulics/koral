// ParserBuildCond.swift — `#if` build-conditional declarations
// (cffi-design.md §D). Mirrors compiler/koralc/parser/build_cond.koral.
//
// The construct is parsed into a private tree, checked with the partition
// rule, then SELECTED against the build target and spliced into the
// declaration list. The public AST never sees a conditional node: the
// unselected branch must parse (it is checked for syntax like any other code)
// but never reaches name collection or sema.

/// The build target's condition atoms — what `#if` branches are selected
/// against. Target == host; mirrors std/os `host_os_name()` / `host_arch_name()`.
public enum BuildTarget {
  public static let osAtom: String = {
    #if os(Windows)
    return "windows"
    #elseif os(Linux)
    return "linux"
    #elseif os(macOS)
    return "macos"
    #else
    return ""
    #endif
  }()

  public static let archAtom: String = {
    #if arch(x86_64)
    return "x86_64"
    #elseif arch(arm64)
    return "aarch64"
    #else
    return ""
    #endif
  }()
}

/// A `#if` condition — the mini-grammar of `os("...")` / `arch("...")` atoms
/// combined with `and` / `or` / `not`. Not an expression: nothing here enters
/// name resolution.
indirect enum BuildCond {
  case osEquals(String)
  case archEquals(String)
  case and(BuildCond, BuildCond)
  case or(BuildCond, BuildCond)
  case not(BuildCond)
}

/// One `#if` construct as parsed. `tokenId` is the position of its `#` — the
/// identity of the construct across the file, since the partition rule asks
/// whether two declarations sit on opposite sides of the SAME `#if`.
struct IfBuildNode {
  let tokenId: String
  let cond: BuildCond
  let thenItems: [BuildCondItem]
  let elseItems: [BuildCondItem]
}

/// File / block items as parsed, before selection.
enum BuildCondItem {
  case decl(GlobalNode)
  case ifBuild(IfBuildNode)
}

/// One declaration's position in the `#if` forest: every enclosing construct
/// and which side of it the declaration sits on.
struct BuildCondPlacement {
  let name: String
  let span: SourceSpan
  let chain: [(id: String, isThen: Bool)]
}

/// Whether an item (recursively) contains a `using` declaration. The
/// using-position rule classifies a whole `#if` by this (§D — "受『using 在
/// 文件顶部』的同一约束"; the check stays pure syntax).
func buildItemContainsUsing(_ item: BuildCondItem) -> Bool {
  switch item {
  case .decl(let node):
    if case .usingDeclaration = node {
      return true
    }
    return false
  case .ifBuild(let node):
    return node.thenItems.contains(where: buildItemContainsUsing)
      || node.elseItems.contains(where: buildItemContainsUsing)
  }
}

/// Collect every named declaration's placement, deepest items included.
func collectBuildCondPlacements(
  _ items: [BuildCondItem],
  chain: [(id: String, isThen: Bool)],
  into out: inout [BuildCondPlacement]
) {
  for item in items {
    switch item {
    case .decl(let node):
      if let (name, nameSpan) = buildCondPlacementName(node) {
        out.append(BuildCondPlacement(name: name, span: nameSpan, chain: chain))
      }
    case .ifBuild(let node):
      collectBuildCondPlacements(
        node.thenItems, chain: chain + [(id: node.tokenId, isThen: true)], into: &out)
      collectBuildCondPlacements(
        node.elseItems, chain: chain + [(id: node.tokenId, isThen: false)], into: &out)
    }
  }
}

/// The name a GlobalNode binds and where it is written — mirrors koralc's
/// `decl_name` / `decl_name_span`. `given` blocks and `using` bind nothing
/// under their own name.
func buildCondPlacementName(_ node: GlobalNode) -> (String, SourceSpan)? {
  switch node {
  case .globalVariableDeclaration(let name, _, _, _, _, _, let nameSpan),
    .globalFunctionDeclaration(let name, _, _, _, _, _, _, let nameSpan),
    .intrinsicFunctionDeclaration(let name, _, _, _, _, _, let nameSpan),
    .foreignFunctionDeclaration(let name, _, _, _, _, _, _, let nameSpan),
    .foreignLetDeclaration(let name, _, _, _, _, _, _, let nameSpan),
    .globalStructDeclaration(let name, _, _, _, _, _, let nameSpan),
    .globalEnumDeclaration(let name, _, _, _, _, let nameSpan),
    .intrinsicTypeDeclaration(let name, _, _, _, let nameSpan),
    .foreignTypeDeclaration(let name, _, _, _, let nameSpan),
    .traitDeclaration(let name, _, _, _, _, _, let nameSpan),
    .typeAliasDeclaration(let name, _, _, _, let nameSpan):
    return (name, nameSpan)
  case .usingDeclaration, .givenDeclaration, .givenTraitDeclaration, .intrinsicGivenDeclaration:
    return nil
  }
}

/// Whether two placements sit on opposite sides of the same `#if` somewhere —
/// "两两分道" (§D). Two unconditional declarations are not this check's
/// business (sema's duplicate rules own those).
func buildCondPlacementsPartitioned(_ a: BuildCondPlacement, _ b: BuildCondPlacement) -> Bool {
  for ea in a.chain {
    for eb in b.chain where ea.id == eb.id && ea.isThen != eb.isThen {
      return true
    }
  }
  return false
}

func buildCondEval(_ cond: BuildCond, os: String, arch: String) -> Bool {
  switch cond {
  case .osEquals(let value):
    return value == os
  case .archEquals(let value):
    return value == arch
  case .and(let left, let right):
    return buildCondEval(left, os: os, arch: arch) && buildCondEval(right, os: os, arch: arch)
  case .or(let left, let right):
    return buildCondEval(left, os: os, arch: arch) || buildCondEval(right, os: os, arch: arch)
  case .not(let inner):
    return !buildCondEval(inner, os: os, arch: arch)
  }
}

extension Parser {
  /// Select the target's branch of every `#if`, recursively, and splice the
  /// surviving declarations in source order.
  func selectBuildDecls(_ items: [BuildCondItem]) -> [GlobalNode] {
    var out: [GlobalNode] = []
    collectSelectedBuildDecls(items, into: &out)
    return out
  }

  private func collectSelectedBuildDecls(_ items: [BuildCondItem], into out: inout [GlobalNode]) {
    for item in items {
      switch item {
      case .decl(let node):
        out.append(node)
      case .ifBuild(let node):
        if buildCondEval(node.cond, os: targetOS, arch: targetArch) {
          collectSelectedBuildDecls(node.thenItems, into: &out)
        } else {
          collectSelectedBuildDecls(node.elseItems, into: &out)
        }
      }
    }
  }

  /// The partition rule (§D): same-name declarations must be pairwise
  /// separated by the branches of one `#if … else …`, and an unconditional
  /// declaration may never share a name with a conditional one. Pure syntax —
  /// every branch counts, selected or not, so no build target can turn a
  /// passing check red.
  func checkBuildCondPartitions(_ items: [BuildCondItem]) throws {
    var placements: [BuildCondPlacement] = []
    collectBuildCondPlacements(items, chain: [], into: &placements)
    for i in 0..<placements.count {
      for j in (i + 1)..<placements.count {
        let a = placements[i]
        let b = placements[j]
        if a.name != b.name {
          continue
        }
        if a.chain.isEmpty && b.chain.isEmpty {
          // Two unconditional duplicates: sema reports these with its own
          // wording, on its own terms.
          continue
        }
        if !buildCondPlacementsPartitioned(a, b) {
          throw ParserError.rejectedConstruct(
            span: b.span,
            message:
              "duplicate declaration '\(a.name)': same-name declarations must be partitioned across the branches of one '#if … else …'"
          )
        }
      }
    }
  }

  /// Parse one `#if … then { … } else { … };` item. The current token is `#`.
  func parseIfBuildItem() throws -> IfBuildNode {
    let tokenId = spanTokenId()
    try match(.hash)
    guard currentToken === .ifKeyword else {
      throw ParserError.rejectedConstruct(span: currentSpan, message: "expected 'if' after '#'")
    }
    try match(.ifKeyword)
    let cond = try parseBuildCond()
    guard currentToken === .thenKeyword else {
      throw ParserError.rejectedConstruct(
        span: currentSpan, message: "expected 'then' in '#if' build condition")
    }
    try match(.thenKeyword)
    let thenItems = try parseBuildCondBlock()
    var elseItems: [BuildCondItem] = []
    if currentToken === .elseKeyword {
      try match(.elseKeyword)
      guard currentToken === .leftBrace else {
        throw ParserError.rejectedConstruct(
          span: currentSpan, message: "expected '{' to open '#else' branch block")
      }
      elseItems = try parseBuildCondBlock()
    }
    guard currentToken === .semicolon else {
      throw ParserError.rejectedConstruct(
        span: currentSpan, message: "expected ';' after '#if' declaration")
    }
    try match(.semicolon)
    return IfBuildNode(tokenId: tokenId, cond: cond, thenItems: thenItems, elseItems: elseItems)
  }

  /// A branch block: `{ <global-decl | #if>* }`.
  func parseBuildCondBlock() throws -> [BuildCondItem] {
    guard currentToken === .leftBrace else {
      throw ParserError.rejectedConstruct(
        span: currentSpan, message: "expected '{' to open '#if' branch block")
    }
    try match(.leftBrace)
    return try parseBuildItemList(inBlock: true)
  }

  /// The item loop shared by the file and branch blocks: declarations and
  /// `#if` items in source order, with the using-position rule applied the
  /// same way at every level (§D). `inBlock` ends at `}`; the file ends at
  /// end of input.
  func parseBuildItemList(inBlock: Bool) throws -> [BuildCondItem] {
    var items: [BuildCondItem] = []
    var hasNonUsingItem = false
    while true {
      if currentToken === .semicolon {
        try match(.semicolon)
        continue
      }
      if inBlock {
        if currentToken === .rightBrace {
          try match(.rightBrace)
          return items
        }
        if currentToken === .eof {
          throw ParserError.rejectedConstruct(
            span: currentSpan, message: "expected '}' to close '#if' branch block")
        }
      } else if currentToken === .eof {
        return items
      }
      let itemStart = currentSpan
      if currentToken === .hash {
        let node = try parseIfBuildItem()
        if buildItemContainsUsing(.ifBuild(node)) {
          if hasNonUsingItem {
            throw ParserError.usingAfterDeclaration(span: itemStart)
          }
        } else {
          hasNonUsingItem = true
        }
        items.append(.ifBuild(node))
      } else if isUsingDeclaration() {
        if hasNonUsingItem {
          throw ParserError.usingAfterDeclaration(span: itemStart)
        }
        let usingDecl = try parseUsingDeclaration()
        items.append(.decl(.usingDeclaration(usingDecl)))
        try requireSemicolon()
      } else {
        hasNonUsingItem = true
        let statement = try parseGlobalDeclaration()
        items.append(.decl(statement))
        try requireSemicolon()
      }
    }
  }

  /// The condition mini-grammar (§D) — an operator layer over atoms:
  /// `<cond-or> ::= <cond-and> ("or" <cond-and>)*` and friends down to
  /// `<pred-head> "(" <pred-value> ")"` and parenthesized groups.
  func parseBuildCond() throws -> BuildCond {
    var left = try parseBuildCondAnd()
    while currentToken === .orKeyword {
      try match(.orKeyword)
      let right = try parseBuildCondAnd()
      left = .or(left, right)
    }
    return left
  }

  func parseBuildCondAnd() throws -> BuildCond {
    var left = try parseBuildCondNot()
    while currentToken === .andKeyword {
      try match(.andKeyword)
      let right = try parseBuildCondNot()
      left = .and(left, right)
    }
    return left
  }

  func parseBuildCondNot() throws -> BuildCond {
    if currentToken === .notKeyword {
      try match(.notKeyword)
      return .not(try parseBuildCondNot())
    }
    return try parseBuildCondAtom()
  }

  func parseBuildCondAtom() throws -> BuildCond {
    if currentToken === .leftParen {
      try match(.leftParen)
      let inner = try parseBuildCond()
      guard currentToken === .rightParen else {
        throw ParserError.rejectedConstruct(
          span: currentSpan, message: "expected ')' after build condition")
      }
      try match(.rightParen)
      return inner
    }
    let headSpan = currentSpan
    let head: String
    if case .identifier(let name) = currentToken {
      head = name
    } else {
      head = ""
    }
    guard head == "os" || head == "arch" else {
      throw ParserError.rejectedConstruct(
        span: headSpan,
        message: "unknown build condition predicate '\(head)'; expected 'os' or 'arch'")
    }
    try match(.identifier(head))
    guard currentToken === .leftParen else {
      throw ParserError.rejectedConstruct(span: currentSpan, message: "expected '(' after '\(head)'")
    }
    try match(.leftParen)
    let valueSpan = currentSpan
    let value: String
    if case .string(let text) = currentToken {
      value = text
    } else {
      throw ParserError.rejectedConstruct(
        span: valueSpan, message: "expected string condition value")
    }
    try match(.string(value))
    guard currentToken === .rightParen else {
      throw ParserError.rejectedConstruct(
        span: currentSpan, message: "expected ')' after condition value")
    }
    try match(.rightParen)
    if head == "os" {
      guard isOSConditionAtom(value) else {
        throw ParserError.rejectedConstruct(
          span: valueSpan,
          message: "unknown os condition value '\(value)'; expected one of windows, linux, macos")
      }
      return .osEquals(value)
    }
    guard isArchConditionAtom(value) else {
      throw ParserError.rejectedConstruct(
        span: valueSpan,
        message: "unknown arch condition value '\(value)'; expected one of x86_64, aarch64")
    }
    return .archEquals(value)
  }

  /// A stable identity for a `#if` construct: where its `#` sits. Mirrors
  /// koralc's `token_position_text`.
  private func spanTokenId() -> String {
    let span = currentSpan
    return "\(span.start.line):\(span.start.column)"
  }
}
