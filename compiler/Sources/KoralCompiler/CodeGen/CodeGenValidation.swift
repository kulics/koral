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
    case .foreignUsing:
      break
    case .foreignFunction(let identifier, let params):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "foreign function '\(name)'")
      for param in params {
        let paramName = context.getName(param.defId) ?? "<unknown>"
        assertTypeResolved(param.type, contextInfo: "foreign function '\(name)' parameter '\(paramName)'")
      }
    case .foreignType(let identifier):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "foreign type '\(name)'")
    case .foreignStruct(let identifier, let fields):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "foreign struct '\(name)'")
      for field in fields {
        assertTypeResolved(field.type, contextInfo: "foreign struct '\(name)' field '\(field.name)'")
      }
    case .foreignGlobalVariable(let identifier, _):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "foreign global '\(name)'")
    case .globalVariable(let identifier, let value, _):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "global variable '\(name)'")
      validateExpression(value, context: "global variable '\(name)' initializer")
      
    case .globalFunction(let identifier, let params, let body):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "function '\(name)'")
      for param in params {
        let paramName = context.getName(param.defId) ?? "<unknown>"
        assertTypeResolved(param.type, contextInfo: "function '\(name)' parameter '\(paramName)'")
      }
      validateExpression(body, context: "function '\(name)' body")
      
    case .globalStructDeclaration(let identifier, let params):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "struct '\(name)'")
      for param in params {
        let paramName = context.getName(param.defId) ?? "<unknown>"
        assertTypeResolved(param.type, contextInfo: "struct '\(name)' field '\(paramName)'")
      }
      
    case .globalUnionDeclaration(let identifier, let cases):
      let name = context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "union '\(name)'")
      for unionCase in cases {
        for param in unionCase.parameters {
          assertTypeResolved(param.type, contextInfo: "union '\(name)' case '\(unionCase.name)' parameter '\(param.name)'")
        }
      }
      
    case .givenDeclaration(let type, let methods):
      assertTypeResolved(type, contextInfo: "given declaration")
      for method in methods {
        let methodName = context.getName(method.identifier.defId) ?? "<unknown>"
        assertTypeResolved(method.identifier.type, contextInfo: "given method '\(methodName)'")
        for param in method.parameters {
          let paramName = context.getName(param.defId) ?? "<unknown>"
          assertTypeResolved(param.type, contextInfo: "given method '\(methodName)' parameter '\(paramName)'")
        }
        validateExpression(method.body, context: "given method '\(methodName)' body")
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
    case .integerLiteral, .floatLiteral, .durationLiteral, .stringLiteral, .booleanLiteral:
      break

    case .interpolatedString(let parts, _):
      for part in parts {
        if case .expression(let expr) = part {
          validateExpression(expr, context: "\(context) -> interpolated part")
        }
      }
      
    case .variable(let identifier):
      let name = self.context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> variable '\(name)'")
      
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
      let name = self.context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> let '\(name)'")
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

    case .ptrExpression(let inner, _):
      validateExpression(inner, context: "\(context) -> ptr inner")

    case .deptrExpression(let inner, _):
      validateExpression(inner, context: "\(context) -> deptr inner")
      
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
      let methodName = self.context.getName(method.defId) ?? "<unknown>"
      assertTypeResolved(method.type, contextInfo: "\(context) -> method reference '\(methodName)'")
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
      let name = self.context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> type construction '\(name)'")
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
        let memberName = self.context.getName(member.defId) ?? "<unknown>"
        assertTypeResolved(member.type, contextInfo: "\(context) -> member path '\(memberName)'")
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
        let paramName = self.context.getName(param.defId) ?? "<unknown>"
        assertTypeResolved(param.type, contextInfo: "\(context) -> lambda parameter '\(paramName)'")
      }
      for capture in captures {
        let captureName = self.context.getName(capture.symbol.defId) ?? "<unknown>"
        assertTypeResolved(capture.symbol.type, contextInfo: "\(context) -> lambda capture '\(captureName)'")
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
      let name = self.context.getName(symbol.defId) ?? "<unknown>"
      assertTypeResolved(symbol.type, contextInfo: "\(context) -> pattern variable '\(name)'")
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
      let name = self.context.getName(identifier.defId) ?? "<unknown>"
      assertTypeResolved(identifier.type, contextInfo: "\(context) -> variable declaration '\(name)'")
      validateExpression(value, context: "\(context) -> variable declaration value")
      
    case .assignment(let target, _, let value):
      validateExpression(target, context: "\(context) -> assignment target")
      validateExpression(value, context: "\(context) -> assignment value")

    case .deptrAssignment(let pointer, _, let value):
      validateExpression(pointer, context: "\(context) -> deptr assignment pointer")
      validateExpression(value, context: "\(context) -> deptr assignment value")
      
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
      
    case .initMemory(let ptr, let val):
      validateExpression(ptr, context: "\(context) -> initMemory ptr")
      validateExpression(val, context: "\(context) -> initMemory val")
      
    case .deinitMemory(let ptr):
      validateExpression(ptr, context: "\(context) -> deinitMemory ptr")
      
    case .takeMemory(let ptr):
      validateExpression(ptr, context: "\(context) -> takeMemory ptr")
      
    case .offsetPtr(let ptr, let offset):
      validateExpression(ptr, context: "\(context) -> offsetPtr ptr")
      validateExpression(offset, context: "\(context) -> offsetPtr offset")
      
    case .nullPtr:
      break  // No expressions to validate
      
    }
  }
}
