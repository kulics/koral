import Foundation

// MARK: - Type Validation Extension

extension CodeGen {
  
  /// Validates that a type has been fully resolved (no generic parameters or parameterized types).
  /// This is called during code generation to catch any types that weren't properly resolved
  /// by the Monomorphizer.
  func assertTypeResolved(_ type: Type, contextInfo: String, visited: Set<UInt64> = []) {
    switch type {
    case .genericParameter(let name):
      fatalError("CodeGen error: Generic parameter '\(name)' should be resolved before code generation. Context: \(contextInfo)")
    case .genericStruct(let template, let args):
      fatalError("CodeGen error: Generic struct '\(template)<\(args.map { $0.description }.joined(separator: ", "))>' should be resolved before code generation. Context: \(contextInfo)")
    case .genericUnion(let template, let args):
      fatalError("CodeGen error: Generic union '\(template)<\(args.map { $0.description }.joined(separator: ", "))>' should be resolved before code generation. Context: \(contextInfo)")
    case .function(let params, let returns):
      for param in params {
        assertTypeResolved(param.type, contextInfo: "\(contextInfo) -> function parameter", visited: visited)
      }
      assertTypeResolved(returns, contextInfo: "\(contextInfo) -> function return type", visited: visited)
    case .reference(let inner):
      assertTypeResolved(inner, contextInfo: "\(contextInfo) -> reference inner type", visited: visited)
    case .pointer(let element):
      assertTypeResolved(element, contextInfo: "\(contextInfo) -> pointer element type", visited: visited)
    case .structure(let defId):
      // Prevent infinite recursion for recursive types (using DefId)
      if visited.contains(defId.id) { return }
      var newVisited = visited
      newVisited.insert(defId.id)
      for member in context.getStructMembers(defId) ?? [] {
        assertTypeResolved(member.type, contextInfo: "\(contextInfo) -> struct member '\(member.name)'", visited: newVisited)
      }
    case .union(let defId):
      // Prevent infinite recursion for recursive types (using DefId)
      if visited.contains(defId.id) { return }
      var newVisited = visited
      newVisited.insert(defId.id)
      for unionCase in context.getUnionCases(defId) ?? [] {
        for param in unionCase.parameters {
          assertTypeResolved(param.type, contextInfo: "\(contextInfo) -> union case '\(unionCase.name)' parameter '\(param.name)'", visited: newVisited)
        }
      }
    default:
      // Primitive types are always resolved
      break
    }
  }
  
  /// Validates that all types in a global node are fully resolved.
  /// This catches any types that weren't properly resolved by the Monomorphizer.
  func validateGlobalNode(_ node: TypedGlobalNode) {
    switch node {
    case .globalVariable(let identifier, let value, _):
      assertTypeResolved(identifier.type, contextInfo: "global variable '\(identifier.name)'")
      validateExpression(value, context: "global variable '\(identifier.name)' initializer")
      
    case .globalFunction(let identifier, let params, let body):
      assertTypeResolved(identifier.type, contextInfo: "function '\(identifier.name)'")
      for param in params {
        assertTypeResolved(param.type, contextInfo: "function '\(identifier.name)' parameter '\(param.name)'")
      }
      validateExpression(body, context: "function '\(identifier.name)' body")
      
    case .globalStructDeclaration(let identifier, let params):
      assertTypeResolved(identifier.type, contextInfo: "struct '\(identifier.name)'")
      for param in params {
        assertTypeResolved(param.type, contextInfo: "struct '\(identifier.name)' field '\(param.name)'")
      }
      
    case .globalUnionDeclaration(let identifier, let cases):
      assertTypeResolved(identifier.type, contextInfo: "union '\(identifier.name)'")
      for unionCase in cases {
        for param in unionCase.parameters {
          assertTypeResolved(param.type, contextInfo: "union '\(identifier.name)' case '\(unionCase.name)' parameter '\(param.name)'")
        }
      }
      
    case .givenDeclaration(let type, let methods):
      assertTypeResolved(type, contextInfo: "given declaration")
      for method in methods {
        assertTypeResolved(method.identifier.type, contextInfo: "given method '\(method.identifier.name)'")
        for param in method.parameters {
          assertTypeResolved(param.type, contextInfo: "given method '\(method.identifier.name)' parameter '\(param.name)'")
        }
        validateExpression(method.body, context: "given method '\(method.identifier.name)' body")
      }
      
    case .genericTypeTemplate, .genericFunctionTemplate:
      // Templates are not emitted, skip validation
      break
    }
  }
  
  /// Validates that all types in an expression are fully resolved.
  func validateExpression(_ expr: TypedExpressionNode, context: String) {
    assertTypeResolved(expr.type, contextInfo: context)
    
    switch expr {
    case .integerLiteral, .floatLiteral, .stringLiteral, .booleanLiteral:
      break
      
    case .variable(let identifier):
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> variable '\(identifier.name)'")
      
    case .castExpression(let inner, let type):
      assertTypeResolved(type, contextInfo: "\(context) -> cast target type")
      validateExpression(inner, context: "\(context) -> cast inner")
      
    case .arithmeticExpression(let left, _, let right, _):
      validateExpression(left, context: "\(context) -> arithmetic left")
      validateExpression(right, context: "\(context) -> arithmetic right")
      
    case .comparisonExpression(let left, _, let right, _):
      validateExpression(left, context: "\(context) -> comparison left")
      validateExpression(right, context: "\(context) -> comparison right")
      
    case .letExpression(let identifier, let value, let body, _):
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> let '\(identifier.name)'")
      validateExpression(value, context: "\(context) -> let value")
      validateExpression(body, context: "\(context) -> let body")
      
    case .andExpression(let left, let right, _):
      validateExpression(left, context: "\(context) -> and left")
      validateExpression(right, context: "\(context) -> and right")
      
    case .orExpression(let left, let right, _):
      validateExpression(left, context: "\(context) -> or left")
      validateExpression(right, context: "\(context) -> or right")
      
    case .notExpression(let inner, _):
      validateExpression(inner, context: "\(context) -> not inner")
      
    case .bitwiseExpression(let left, _, let right, _):
      validateExpression(left, context: "\(context) -> bitwise left")
      validateExpression(right, context: "\(context) -> bitwise right")
      
    case .bitwiseNotExpression(let inner, _):
      validateExpression(inner, context: "\(context) -> bitwise not inner")
      
    case .derefExpression(let inner, _):
      validateExpression(inner, context: "\(context) -> deref inner")
      
    case .referenceExpression(let inner, _):
      validateExpression(inner, context: "\(context) -> reference inner")
      
    case .blockExpression(let statements, let finalExpr, _):
      for stmt in statements {
        validateStatement(stmt, context: "\(context) -> block statement")
      }
      if let finalExpr = finalExpr {
        validateExpression(finalExpr, context: "\(context) -> block final expression")
      }
      
    case .ifExpression(let condition, let thenBranch, let elseBranch, _):
      validateExpression(condition, context: "\(context) -> if condition")
      validateExpression(thenBranch, context: "\(context) -> if then")
      if let elseBranch = elseBranch {
        validateExpression(elseBranch, context: "\(context) -> if else")
      }
      
    case .call(let callee, let arguments, _):
      validateExpression(callee, context: "\(context) -> call callee")
      for arg in arguments {
        validateExpression(arg, context: "\(context) -> call argument")
      }
      
    case .genericCall(let functionName, let typeArgs, _, _):
      fatalError("CodeGen error: genericCall '\(functionName)' with type args \(typeArgs.map { $0.description }.joined(separator: ", ")) should be resolved before code generation. Context: \(context)")
      
    case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, _):
      validateExpression(base, context: "\(context) -> method reference base")
      assertTypeResolved(method.type, contextInfo: "\(context) -> method reference '\(method.name)'")
      if let typeArgs = typeArgs {
        for typeArg in typeArgs {
          assertTypeResolved(typeArg, contextInfo: "\(context) -> method reference type arg")
        }
      }
      if let methodTypeArgs = methodTypeArgs {
        for typeArg in methodTypeArgs {
          assertTypeResolved(typeArg, contextInfo: "\(context) -> method reference method type arg")
        }
      }
      
    case .traitMethodPlaceholder(let traitName, let methodName, let base, _, _):
      // Trait method placeholders should be resolved by Monomorphizer before reaching CodeGen
      fatalError("CodeGen error: Unresolved trait method placeholder '\(traitName).\(methodName)' on base type \(base.type). Context: \(context)")
      
    case .whileExpression(let condition, let body, _):
      validateExpression(condition, context: "\(context) -> while condition")
      validateExpression(body, context: "\(context) -> while body")
      
    case .typeConstruction(let identifier, let typeArgs, let arguments, _):
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> type construction '\(identifier.name)'")
      if let typeArgs = typeArgs {
        for typeArg in typeArgs {
          assertTypeResolved(typeArg, contextInfo: "\(context) -> type construction type arg")
        }
      }
      for arg in arguments {
        validateExpression(arg, context: "\(context) -> type construction argument")
      }
      
    case .memberPath(let source, let path):
      validateExpression(source, context: "\(context) -> member path source")
      for member in path {
        assertTypeResolved(member.type, contextInfo: "\(context) -> member path '\(member.name)'")
      }
      
    case .subscriptExpression(let base, let arguments, let method, _):
      validateExpression(base, context: "\(context) -> subscript base")
      for arg in arguments {
        validateExpression(arg, context: "\(context) -> subscript argument")
      }
      assertTypeResolved(method.type, contextInfo: "\(context) -> subscript method")
      
    case .unionConstruction(let type, let caseName, let arguments):
      assertTypeResolved(type, contextInfo: "\(context) -> union construction '\(caseName)'")
      for arg in arguments {
        validateExpression(arg, context: "\(context) -> union construction argument")
      }
      
    case .intrinsicCall(let intrinsic):
      validateIntrinsic(intrinsic, context: "\(context) -> intrinsic call")
      
    case .matchExpression(let subject, let cases, _):
      validateExpression(subject, context: "\(context) -> match subject")
      for matchCase in cases {
        validatePattern(matchCase.pattern, context: "\(context) -> match case pattern")
        validateExpression(matchCase.body, context: "\(context) -> match case body")
      }
      
    case .staticMethodCall(let baseType, let methodName, let typeArgs, _, _):
      fatalError("CodeGen error: staticMethodCall '\(methodName)' on type '\(baseType)' with type args \(typeArgs.map { $0.description }.joined(separator: ", ")) should be resolved before code generation. Context: \(context)")
      
    case .ifPatternExpression(let subject, let pattern, let bindings, let thenBranch, let elseBranch, _):
      validateExpression(subject, context: "\(context) -> if pattern subject")
      validatePattern(pattern, context: "\(context) -> if pattern")
      for (name, _, type) in bindings {
        assertTypeResolved(type, contextInfo: "\(context) -> if pattern binding '\(name)'")
      }
      validateExpression(thenBranch, context: "\(context) -> if pattern then")
      if let elseBranch = elseBranch {
        validateExpression(elseBranch, context: "\(context) -> if pattern else")
      }
      
    case .whilePatternExpression(let subject, let pattern, let bindings, let body, _):
      validateExpression(subject, context: "\(context) -> while pattern subject")
      validatePattern(pattern, context: "\(context) -> while pattern")
      for (name, _, type) in bindings {
        assertTypeResolved(type, contextInfo: "\(context) -> while pattern binding '\(name)'")
      }
      validateExpression(body, context: "\(context) -> while pattern body")
      
    case .lambdaExpression(let parameters, let captures, let body, let type):
      assertTypeResolved(type, contextInfo: "\(context) -> lambda type")
      for param in parameters {
        assertTypeResolved(param.type, contextInfo: "\(context) -> lambda parameter '\(param.name)'")
      }
      for capture in captures {
        assertTypeResolved(capture.symbol.type, contextInfo: "\(context) -> lambda capture '\(capture.symbol.name)'")
      }
      validateExpression(body, context: "\(context) -> lambda body")
    }
  }
  
  /// Validates that all types in a pattern are fully resolved.
  func validatePattern(_ pattern: TypedPattern, context: String) {
    switch pattern {
    case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
      break
    case .variable(let symbol):
      assertTypeResolved(symbol.type, contextInfo: "\(context) -> pattern variable '\(symbol.name)'")
    case .unionCase(_, _, let elements):
      for element in elements {
        validatePattern(element, context: "\(context) -> union case element")
      }
    case .comparisonPattern:
      // Comparison patterns don't have types to validate
      break
    case .andPattern(let left, let right):
      validatePattern(left, context: "\(context) -> and pattern left")
      validatePattern(right, context: "\(context) -> and pattern right")
    case .orPattern(let left, let right):
      validatePattern(left, context: "\(context) -> or pattern left")
      validatePattern(right, context: "\(context) -> or pattern right")
    case .notPattern(let inner):
      validatePattern(inner, context: "\(context) -> not pattern inner")
    }
  }
  
  /// Validates that all types in a statement are fully resolved.
  func validateStatement(_ stmt: TypedStatementNode, context: String) {
    switch stmt {
    case .variableDeclaration(let identifier, let value, _):
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> variable declaration '\(identifier.name)'")
      validateExpression(value, context: "\(context) -> variable declaration value")
      
    case .assignment(let target, let value):
      validateExpression(target, context: "\(context) -> assignment target")
      validateExpression(value, context: "\(context) -> assignment value")
      
    case .compoundAssignment(let target, _, let value):
      validateExpression(target, context: "\(context) -> compound assignment target")
      validateExpression(value, context: "\(context) -> compound assignment value")
      
    case .expression(let expr):
      validateExpression(expr, context: "\(context) -> expression statement")
      
    case .return(let value):
      if let value = value {
        validateExpression(value, context: "\(context) -> return value")
      }
      
    case .break, .continue:
      break
    }
  }
  
  /// Validates that all types in an intrinsic call are fully resolved.
  func validateIntrinsic(_ intrinsic: TypedIntrinsic, context: String) {
    switch intrinsic {
    case .allocMemory(let count, let resultType):
      validateExpression(count, context: "\(context) -> allocMemory count")
      assertTypeResolved(resultType, contextInfo: "\(context) -> allocMemory result type")
      
    case .deallocMemory(let ptr):
      validateExpression(ptr, context: "\(context) -> deallocMemory ptr")
      
    case .copyMemory(let dest, let src, let count):
      validateExpression(dest, context: "\(context) -> copyMemory dest")
      validateExpression(src, context: "\(context) -> copyMemory src")
      validateExpression(count, context: "\(context) -> copyMemory count")
      
    case .moveMemory(let dest, let src, let count):
      validateExpression(dest, context: "\(context) -> moveMemory dest")
      validateExpression(src, context: "\(context) -> moveMemory src")
      validateExpression(count, context: "\(context) -> moveMemory count")
      
    case .refCount(let val):
      validateExpression(val, context: "\(context) -> refCount val")
      
    case .ptrInit(let ptr, let val):
      validateExpression(ptr, context: "\(context) -> ptrInit ptr")
      validateExpression(val, context: "\(context) -> ptrInit val")
      
    case .ptrDeinit(let ptr):
      validateExpression(ptr, context: "\(context) -> ptrDeinit ptr")
      
    case .ptrPeek(let ptr):
      validateExpression(ptr, context: "\(context) -> ptrPeek ptr")
      
    case .ptrTake(let ptr):
      validateExpression(ptr, context: "\(context) -> ptrTake ptr")
      
    case .ptrReplace(let ptr, let val):
      validateExpression(ptr, context: "\(context) -> ptrReplace ptr")
      validateExpression(val, context: "\(context) -> ptrReplace val")
      
    case .ptrBits:
      break  // No expressions to validate
      
    case .ptrOffset(let ptr, let offset):
      validateExpression(ptr, context: "\(context) -> ptrOffset ptr")
      validateExpression(offset, context: "\(context) -> ptrOffset offset")
      
    case .exit(let code):
      validateExpression(code, context: "\(context) -> exit code")
      
    case .abort:
      break
      
    case .float32Bits(let value):
      validateExpression(value, context: "\(context) -> float32Bits value")
      
    case .float64Bits(let value):
      validateExpression(value, context: "\(context) -> float64Bits value")

    case .float32FromBits(let bits):
      validateExpression(bits, context: "\(context) -> float32FromBits bits")
      
    case .float64FromBits(let bits):
      validateExpression(bits, context: "\(context) -> float64FromBits bits")

    // Low-level IO intrinsics (minimal set using file descriptors)
    case .fwrite(let ptr, let len, let fd):
      validateExpression(ptr, context: "\(context) -> fwrite ptr")
      validateExpression(len, context: "\(context) -> fwrite len")
      validateExpression(fd, context: "\(context) -> fwrite fd")
      
    case .fgetc(let fd):
      validateExpression(fd, context: "\(context) -> fgetc fd")
      
    case .fflush(let fd):
      validateExpression(fd, context: "\(context) -> fflush fd")
    }
  }
}
