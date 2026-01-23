import Foundation

// MARK: - C Code Generation Extensions for Qualified Names

/// 生成文件标识符（用于 private 符号的文件隔离）
/// 使用文件路径的哈希值生成短标识符
private func generateFileId(_ sourceFile: String) -> String {
    var hash: UInt32 = 0
    for char in sourceFile.utf8 {
        hash = hash &* 31 &+ UInt32(char)
    }
    return String(hash % 10000)
}

/// 清理标识符，将非法字符替换为下划线
private func sanitizeIdentifier(_ name: String) -> String {
    var result = ""
    for char in name {
        if char.isLetter || char.isNumber || char == "_" {
            result.append(char)
        } else {
            result.append("_")
        }
    }
    return result
}

extension Symbol {
    /// 生成用于 C 代码的限定名
    /// 全局符号（函数、类型、全局变量）需要模块路径前缀
    /// 局部变量和参数不需要前缀
    var qualifiedName: String {
        // Check if this is a global symbol that needs qualification
        // Global symbols have either:
        // 1. A non-empty modulePath (from a submodule)
        // 2. A non-empty sourceFile (private symbol needing file isolation)
        // 3. Are functions or types (always global)
        
        let isGlobalSymbol: Bool
        switch kind {
        case .function, .type, .module:
            isGlobalSymbol = true
        case .variable:
            // Variables are global if they have module path or are private (have sourceFile)
            // Local variables and parameters have empty modulePath and empty sourceFile
            isGlobalSymbol = !modulePath.isEmpty || !sourceFile.isEmpty || access == .private
        }
        
        if isGlobalSymbol {
            var parts: [String] = []
            
            if !modulePath.isEmpty {
                parts.append(modulePath.joined(separator: "_"))
            }
            
            if access == .private && !sourceFile.isEmpty {
                let fileId = generateFileId(sourceFile)
                parts.append("f\(fileId)")
            }
            
            parts.append(sanitizeIdentifier(name))
            
            return parts.joined(separator: "_")
        } else {
            // Local variables and parameters - use original name
            return sanitizeIdentifier(name)
        }
    }
}

extension StructDecl {
    /// 生成用于 C 代码的限定名
    var qualifiedName: String {
        var parts: [String] = []
        
        if !modulePath.isEmpty {
            parts.append(modulePath.joined(separator: "_"))
        }
        
        if access == .private {
            let fileId = generateFileId(sourceFile)
            parts.append("f\(fileId)")
        }
        
        parts.append(sanitizeIdentifier(name))
        
        if let typeArgs = typeArguments, !typeArgs.isEmpty {
            let argsStr = typeArgs.map { $0.layoutKey }.joined(separator: "_")
            parts.append(argsStr)
        }
        
        return parts.joined(separator: "_")
    }
}

extension UnionDecl {
    /// 生成用于 C 代码的限定名
    var qualifiedName: String {
        var parts: [String] = []
        
        if !modulePath.isEmpty {
            parts.append(modulePath.joined(separator: "_"))
        }
        
        if access == .private {
            let fileId = generateFileId(sourceFile)
            parts.append("f\(fileId)")
        }
        
        parts.append(sanitizeIdentifier(name))
        
        if let typeArgs = typeArguments, !typeArgs.isEmpty {
            let argsStr = typeArgs.map { $0.layoutKey }.joined(separator: "_")
            parts.append(argsStr)
        }
        
        return parts.joined(separator: "_")
    }
}

public class CodeGen {
  private let ast: MonomorphizedProgram
  private var indent: String = ""
  private var buffer: String = ""
  private var tempVarCounter = 0
  private var globalInitializations: [(String, TypedExpressionNode)] = []
  private var lifetimeScopeStack: [[(name: String, type: Type)]] = []
  private var userDefinedDrops: [String: String] = [:] // TypeName -> Mangled Drop Function Name
  
  // MARK: - Lambda Code Generation
  /// Counter for generating unique Lambda function names
  private var lambdaCounter = 0
  /// Buffer for Lambda function definitions (generated at the end)
  private var lambdaFunctions: String = ""
  /// Buffer for Lambda environment struct definitions
  private var lambdaEnvStructs: String = ""
  
  // MARK: - Escape Analysis
  /// 逃逸分析上下文，用于追踪变量作用域和逃逸状态
  private var escapeContext: EscapeContext
  
  /// 是否启用逃逸分析报告
  private let escapeAnalysisReportEnabled: Bool

  // Lightweight type declaration wrapper used for dependency ordering before emission
  private enum TypeDeclaration {
    case structure(Symbol, [Symbol])
    case union(Symbol, [UnionCase])

    var name: String {
      switch self {
      case .structure(let identifier, _):
        return identifier.qualifiedName
      case .union(let identifier, _):
        return identifier.qualifiedName
      }
    }
  }

  private struct LoopContext {
    let startLabel: String
    let endLabel: String
    let scopeIndex: Int
  }
  private var loopStack: [LoopContext] = []

  public init(ast: MonomorphizedProgram, escapeAnalysisReportEnabled: Bool = false) {
    self.ast = ast
    self.escapeAnalysisReportEnabled = escapeAnalysisReportEnabled
    self.escapeContext = EscapeContext(reportingEnabled: escapeAnalysisReportEnabled)
  }
  
  // MARK: - Type Validation
  
  /// Validates that a type has been fully resolved (no generic parameters or parameterized types).
  /// This is called during code generation to catch any types that weren't properly resolved
  /// by the Monomorphizer.
  private func assertTypeResolved(_ type: Type, context: String, visited: Set<UUID> = []) {
    switch type {
    case .genericParameter(let name):
      fatalError("CodeGen error: Generic parameter '\(name)' should be resolved before code generation. Context: \(context)")
    case .genericStruct(let template, let args):
      fatalError("CodeGen error: Generic struct '\(template)<\(args.map { $0.description }.joined(separator: ", "))>' should be resolved before code generation. Context: \(context)")
    case .genericUnion(let template, let args):
      fatalError("CodeGen error: Generic union '\(template)<\(args.map { $0.description }.joined(separator: ", "))>' should be resolved before code generation. Context: \(context)")
    case .function(let params, let returns):
      for param in params {
        assertTypeResolved(param.type, context: "\(context) -> function parameter", visited: visited)
      }
      assertTypeResolved(returns, context: "\(context) -> function return type", visited: visited)
    case .reference(let inner):
      assertTypeResolved(inner, context: "\(context) -> reference inner type", visited: visited)
    case .pointer(let element):
      assertTypeResolved(element, context: "\(context) -> pointer element type", visited: visited)
    case .structure(let decl):
      // Prevent infinite recursion for recursive types (using UUID)
      if visited.contains(decl.id) { return }
      var newVisited = visited
      newVisited.insert(decl.id)
      for member in decl.members {
        assertTypeResolved(member.type, context: "\(context) -> struct member '\(member.name)'", visited: newVisited)
      }
    case .union(let decl):
      // Prevent infinite recursion for recursive types (using UUID)
      if visited.contains(decl.id) { return }
      var newVisited = visited
      newVisited.insert(decl.id)
      for unionCase in decl.cases {
        for param in unionCase.parameters {
          assertTypeResolved(param.type, context: "\(context) -> union case '\(unionCase.name)' parameter '\(param.name)'", visited: newVisited)
        }
      }
    default:
      // Primitive types are always resolved
      break
    }
  }
  
  /// Validates that all types in a global node are fully resolved.
  /// This catches any types that weren't properly resolved by the Monomorphizer.
  private func validateGlobalNode(_ node: TypedGlobalNode) {
    switch node {
    case .globalVariable(let identifier, let value, _):
      assertTypeResolved(identifier.type, context: "global variable '\(identifier.name)'")
      validateExpression(value, context: "global variable '\(identifier.name)' initializer")
      
    case .globalFunction(let identifier, let params, let body):
      assertTypeResolved(identifier.type, context: "function '\(identifier.name)'")
      for param in params {
        assertTypeResolved(param.type, context: "function '\(identifier.name)' parameter '\(param.name)'")
      }
      validateExpression(body, context: "function '\(identifier.name)' body")
      
    case .globalStructDeclaration(let identifier, let params):
      assertTypeResolved(identifier.type, context: "struct '\(identifier.name)'")
      for param in params {
        assertTypeResolved(param.type, context: "struct '\(identifier.name)' field '\(param.name)'")
      }
      
    case .globalUnionDeclaration(let identifier, let cases):
      assertTypeResolved(identifier.type, context: "union '\(identifier.name)'")
      for unionCase in cases {
        for param in unionCase.parameters {
          assertTypeResolved(param.type, context: "union '\(identifier.name)' case '\(unionCase.name)' parameter '\(param.name)'")
        }
      }
      
    case .givenDeclaration(let type, let methods):
      assertTypeResolved(type, context: "given declaration")
      for method in methods {
        assertTypeResolved(method.identifier.type, context: "given method '\(method.identifier.name)'")
        for param in method.parameters {
          assertTypeResolved(param.type, context: "given method '\(method.identifier.name)' parameter '\(param.name)'")
        }
        validateExpression(method.body, context: "given method '\(method.identifier.name)' body")
      }
      
    case .genericTypeTemplate, .genericFunctionTemplate:
      // Templates are not emitted, skip validation
      break
    }
  }
  
  /// Validates that all types in an expression are fully resolved.
  private func validateExpression(_ expr: TypedExpressionNode, context: String) {
    assertTypeResolved(expr.type, context: context)
    
    switch expr {
    case .integerLiteral, .floatLiteral, .stringLiteral, .booleanLiteral:
      break
      
    case .variable(let identifier):
      assertTypeResolved(identifier.type, context: "\(context) -> variable '\(identifier.name)'")
      
    case .castExpression(let inner, let type):
      assertTypeResolved(type, context: "\(context) -> cast target type")
      validateExpression(inner, context: "\(context) -> cast inner")
      
    case .arithmeticExpression(let left, _, let right, _):
      validateExpression(left, context: "\(context) -> arithmetic left")
      validateExpression(right, context: "\(context) -> arithmetic right")
      
    case .comparisonExpression(let left, _, let right, _):
      validateExpression(left, context: "\(context) -> comparison left")
      validateExpression(right, context: "\(context) -> comparison right")
      
    case .letExpression(let identifier, let value, let body, _):
      assertTypeResolved(identifier.type, context: "\(context) -> let '\(identifier.name)'")
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
      
    case .methodReference(let base, let method, let typeArgs, _):
      validateExpression(base, context: "\(context) -> method reference base")
      assertTypeResolved(method.type, context: "\(context) -> method reference '\(method.name)'")
      if let typeArgs = typeArgs {
        for typeArg in typeArgs {
          assertTypeResolved(typeArg, context: "\(context) -> method reference type arg")
        }
      }
      
    case .whileExpression(let condition, let body, _):
      validateExpression(condition, context: "\(context) -> while condition")
      validateExpression(body, context: "\(context) -> while body")
      
    case .typeConstruction(let identifier, let typeArgs, let arguments, _):
      assertTypeResolved(identifier.type, context: "\(context) -> type construction '\(identifier.name)'")
      if let typeArgs = typeArgs {
        for typeArg in typeArgs {
          assertTypeResolved(typeArg, context: "\(context) -> type construction type arg")
        }
      }
      for arg in arguments {
        validateExpression(arg, context: "\(context) -> type construction argument")
      }
      
    case .memberPath(let source, let path):
      validateExpression(source, context: "\(context) -> member path source")
      for member in path {
        assertTypeResolved(member.type, context: "\(context) -> member path '\(member.name)'")
      }
      
    case .subscriptExpression(let base, let arguments, let method, _):
      validateExpression(base, context: "\(context) -> subscript base")
      for arg in arguments {
        validateExpression(arg, context: "\(context) -> subscript argument")
      }
      assertTypeResolved(method.type, context: "\(context) -> subscript method")
      
    case .unionConstruction(let type, let caseName, let arguments):
      assertTypeResolved(type, context: "\(context) -> union construction '\(caseName)'")
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
        assertTypeResolved(type, context: "\(context) -> if pattern binding '\(name)'")
      }
      validateExpression(thenBranch, context: "\(context) -> if pattern then")
      if let elseBranch = elseBranch {
        validateExpression(elseBranch, context: "\(context) -> if pattern else")
      }
      
    case .whilePatternExpression(let subject, let pattern, let bindings, let body, _):
      validateExpression(subject, context: "\(context) -> while pattern subject")
      validatePattern(pattern, context: "\(context) -> while pattern")
      for (name, _, type) in bindings {
        assertTypeResolved(type, context: "\(context) -> while pattern binding '\(name)'")
      }
      validateExpression(body, context: "\(context) -> while pattern body")
      
    case .lambdaExpression(let parameters, let captures, let body, let type):
      assertTypeResolved(type, context: "\(context) -> lambda type")
      for param in parameters {
        assertTypeResolved(param.type, context: "\(context) -> lambda parameter '\(param.name)'")
      }
      for capture in captures {
        assertTypeResolved(capture.symbol.type, context: "\(context) -> lambda capture '\(capture.symbol.name)'")
      }
      validateExpression(body, context: "\(context) -> lambda body")
    }
  }
  
  /// Validates that all types in a pattern are fully resolved.
  private func validatePattern(_ pattern: TypedPattern, context: String) {
    switch pattern {
    case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
      break
    case .variable(let symbol):
      assertTypeResolved(symbol.type, context: "\(context) -> pattern variable '\(symbol.name)'")
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
  private func validateStatement(_ stmt: TypedStatementNode, context: String) {
    switch stmt {
    case .variableDeclaration(let identifier, let value, _):
      assertTypeResolved(identifier.type, context: "\(context) -> variable declaration '\(identifier.name)'")
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
  private func validateIntrinsic(_ intrinsic: TypedIntrinsic, context: String) {
    switch intrinsic {
    case .allocMemory(let count, let resultType):
      validateExpression(count, context: "\(context) -> allocMemory count")
      assertTypeResolved(resultType, context: "\(context) -> allocMemory result type")
      
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

  private func pushScope() {
    lifetimeScopeStack.append([])
    escapeContext.enterScope()
  }

  private func popScopeWithoutCleanup() {
    _ = lifetimeScopeStack.popLast()
    escapeContext.leaveScope()
  }

  private func popScope() {
    let vars = lifetimeScopeStack.removeLast()
    for (name, type) in vars.reversed() {
      if case .structure(let decl) = type {
        let qualifiedTypeName = decl.qualifiedName
        addIndent()
        buffer += "__koral_\(qualifiedTypeName)_drop(&\(name));\n"
      } else if case .union(let decl) = type {
        let qualifiedTypeName = decl.qualifiedName
        addIndent()
        buffer += "__koral_\(qualifiedTypeName)_drop(&\(name));\n"
      } else if case .reference(_) = type {
        addIndent()
        buffer += "__koral_release(\(name).control);\n"
      }
    }
    escapeContext.leaveScope()
  }

  private func emitCleanup(fromScopeIndex startIndex: Int) {
    guard !lifetimeScopeStack.isEmpty else { return }
    let clampedStart = max(0, min(startIndex, lifetimeScopeStack.count - 1))

    for scopeIndex in stride(from: lifetimeScopeStack.count - 1, through: clampedStart, by: -1) {
      let vars = lifetimeScopeStack[scopeIndex]
      for (name, type) in vars.reversed() {
        if case .structure(let decl) = type {
          let qualifiedTypeName = decl.qualifiedName
          addIndent()
          buffer += "__koral_\(qualifiedTypeName)_drop(&\(name));\n"
        } else if case .union(let decl) = type {
          let qualifiedTypeName = decl.qualifiedName
          addIndent()
          buffer += "__koral_\(qualifiedTypeName)_drop(&\(name));\n"
        } else if case .reference(_) = type {
          addIndent()
          buffer += "__koral_release(\(name).control);\n"
        }
      }
    }
  }

  private func emitCleanupForScope(at scopeIndex: Int) {
    guard scopeIndex >= 0 && scopeIndex < lifetimeScopeStack.count else { return }
    let vars = lifetimeScopeStack[scopeIndex]
    for (name, type) in vars.reversed() {
      if case .structure(let decl) = type {
        let qualifiedTypeName = decl.qualifiedName
        addIndent()
        buffer += "__koral_\(qualifiedTypeName)_drop(&\(name));\n"
      } else if case .union(let decl) = type {
        let qualifiedTypeName = decl.qualifiedName
        addIndent()
        buffer += "__koral_\(qualifiedTypeName)_drop(&\(name));\n"
      } else if case .reference(_) = type {
        addIndent()
        buffer += "__koral_release(\(name).control);\n"
      }
    }
  }

  private func registerVariable(_ name: String, _ type: Type) {
    lifetimeScopeStack[lifetimeScopeStack.count - 1].append((name: name, type: type))
    escapeContext.registerVariable(name)
  }


  public func generate() -> String {
    buffer = """
      #include <stdio.h>
      #include <stdlib.h>
      #include <stdatomic.h>
      #include <string.h>
      #include <stdint.h>
      #include <math.h>

      // Integer power function using fast exponentiation
      static inline intptr_t __koral_ipow(intptr_t base, intptr_t exp) {
          intptr_t result = 1;
          while (exp > 0) {
              if (exp & 1) result *= base;
              base *= base;
              exp >>= 1;
          }
          return result;
      }

      // Generic Ref type
      struct Ref { void* ptr; void* control; };

      // Unified Closure type for all function types (16 bytes)
      // fn: function pointer (with env as first param if env != NULL)
      // env: environment pointer (NULL for no-capture lambdas)
      struct __koral_Closure { void* fn; void* env; };

      typedef void (*Koral_Dtor)(void*);

      struct Koral_Control {
          _Atomic int count;
          Koral_Dtor dtor;
          void* ptr;
      };

      void __koral_retain(void* raw_control) {
          if (!raw_control) return;
          struct Koral_Control* control = (struct Koral_Control*)raw_control;
          atomic_fetch_add(&control->count, 1);
      }

      void __koral_release(void* raw_control) {
          if (!raw_control) return;
          struct Koral_Control* control = (struct Koral_Control*)raw_control;
          int prev = atomic_fetch_sub(&control->count, 1);
          if (prev == 1) {
              if (control->dtor) {
                  control->dtor(control->ptr);
              }
              free(control->ptr);
              free(control);
          }
      }

      """

    // 生成程序体
    generateProgram(ast)
    
    // Insert Lambda env structs after the runtime definitions
    if !lambdaEnvStructs.isEmpty {
      // Find the position after the runtime definitions (after __koral_release)
      if let insertPos = buffer.range(of: "void __koral_release(void* raw_control)") {
        // Find the end of __koral_release function
        if let funcEnd = buffer.range(of: "}\n\n", range: insertPos.upperBound..<buffer.endIndex) {
          let insertIndex = funcEnd.upperBound
          buffer.insert(contentsOf: lambdaEnvStructs, at: insertIndex)
        }
      }
    }
    
    return buffer
  }
  
  /// 获取逃逸分析诊断报告
  /// 
  /// 返回所有在代码生成过程中收集的逃逸分析诊断信息。
  /// 只有在启用逃逸分析报告时才会有内容。
  public func getEscapeAnalysisDiagnostics() -> String {
    return escapeContext.getFormattedDiagnostics()
  }
  
  /// 获取逃逸分析诊断列表
  public func getEscapeDiagnostics() -> [EscapeDiagnostic] {
    return escapeContext.diagnostics
  }

  private func collectTypeDeclarations(_ nodes: [TypedGlobalNode]) -> [TypeDeclaration] {
    var result: [TypeDeclaration] = []
    for node in nodes {
      switch node {
      case .globalStructDeclaration(let identifier, let parameters):
        result.append(.structure(identifier, parameters))
      case .globalUnionDeclaration(let identifier, let cases):
        result.append(.union(identifier, cases))
      default:
        continue
      }
    }
    return result
  }

  private func dependencies(for declaration: TypeDeclaration, available: Set<String>) -> Set<String> {
    var deps: Set<String> = []

    func recordDependency(from type: Type, selfName: String) {
      switch type {
      case .structure(let decl):
        let qualifiedName = decl.qualifiedName
        if qualifiedName != selfName && available.contains(qualifiedName) {
          deps.insert(qualifiedName)
        }
      case .union(let decl):
        let qualifiedName = decl.qualifiedName
        if qualifiedName != selfName && available.contains(qualifiedName) {
          deps.insert(qualifiedName)
        }
      default:
        break
      }
    }

    switch declaration {
    case .structure(let identifier, let parameters):
      for param in parameters {
        recordDependency(from: param.type, selfName: identifier.qualifiedName)
      }
    case .union(let identifier, let cases):
      for c in cases {
        for param in c.parameters {
          recordDependency(from: param.type, selfName: identifier.qualifiedName)
        }
      }
    }

    return deps
  }

  private func sortTypeDeclarations(_ declarations: [TypeDeclaration]) -> [TypeDeclaration] {
    let available = Set(declarations.map { $0.name })
    var dependencyMap: [String: Set<String>] = [:]
    var dependents: [String: Set<String>] = [:]
    var indegree: [String: Int] = [:]
    var originalIndex: [String: Int] = [:]

    for (index, decl) in declarations.enumerated() {
      originalIndex[decl.name] = index
      let deps = dependencies(for: decl, available: available)
      dependencyMap[decl.name] = deps
      indegree[decl.name] = deps.count
      for dep in deps {
        dependents[dep, default: []].insert(decl.name)
      }
    }

    func enqueueZeroIndegree(_ queue: inout [String], _ name: String) {
      queue.append(name)
      queue.sort { (originalIndex[$0] ?? 0) < (originalIndex[$1] ?? 0) }
    }

    var queue: [String] = []
    for decl in declarations where (indegree[decl.name] ?? 0) == 0 {
      enqueueZeroIndegree(&queue, decl.name)
    }

    var ordered: [TypeDeclaration] = []
    var emitted: Set<String> = []

    while !queue.isEmpty {
      let name = queue.removeFirst()
      guard let decl = declarations.first(where: { $0.name == name }) else { continue }
      ordered.append(decl)
      emitted.insert(name)

      for follower in dependents[name] ?? [] {
        let newDegree = (indegree[follower] ?? 0) - 1
        indegree[follower] = newDegree
        if newDegree == 0 {
          enqueueZeroIndegree(&queue, follower)
        }
      }
    }

    if ordered.count < declarations.count {
      for decl in declarations where !emitted.contains(decl.name) {
        ordered.append(decl)
      }
    }

    return ordered
  }

  private func generateProgram(_ program: MonomorphizedProgram) {
    let nodes = program.globalNodes
    
      // Pass -1: Validate all types are resolved (no generic parameters or parameterized types)
      #if DEBUG
      for node in nodes {
        validateGlobalNode(node)
      }
      #endif
    
      // Pass 0: Scan for user-defined drops
      for node in nodes {
        if case .givenDeclaration(let type, let methods) = node {
             var typeName: String?
             if case .structure(let decl) = type { typeName = decl.qualifiedName }
             if case .union(let decl) = type { typeName = decl.qualifiedName }

             if let name = typeName {
                 for method in methods {
                     if method.identifier.methodKind == .drop {
                         userDefinedDrops[name] = method.identifier.name
                     }
                 }
             }
        }
        if case .globalFunction(let identifier, _, _) = node {
          if identifier.methodKind == .drop {
            // Mangled name is TypeName___drop, so we can extract TypeName
            // Note: This relies on the mangling scheme in TypeChecker
            let typeName = String(identifier.name.dropLast(7))
            userDefinedDrops[typeName] = identifier.name
          }
        }
      }

      // 先生成所有类型声明，按依赖顺序排序以确保字段类型已定义
      let typeDeclarations = collectTypeDeclarations(nodes)
      
      for decl in sortTypeDeclarations(typeDeclarations) {
        switch decl {
        case .structure(let identifier, let parameters):
          generateTypeDeclaration(identifier, parameters)
        case .union(let identifier, let cases):
          generateUnionDeclaration(identifier, cases)
        }
      }

      // 然后生成所有函数声明
      for node in nodes {
        if case .globalFunction(let identifier, let params, _) = node {
          generateFunctionDeclaration(identifier, params)
        }
        if case .givenDeclaration(let type, let methods) = node {
          if type.containsGenericParameter { continue }
          for method in methods {
            generateFunctionDeclaration(method.identifier, method.parameters)
          }
        }
      }
      buffer += "\n"

      // 生成全局变量声明
      for node in nodes {
        if case .globalVariable(let identifier, let value, _) = node {
          let cType = getCType(identifier.type)
          let cName = identifier.qualifiedName
          switch value {
          case .integerLiteral(_, _), .floatLiteral(_, _),
            .stringLiteral(_, _), .booleanLiteral(_, _):
            buffer += "\(cType) \(cName) = "
            buffer += generateExpressionSSA(value)
            buffer += ";\n"
          default:
            // 复杂表达式延迟到 main 函数中初始化
            buffer += "\(cType) \(cName);\n"
            globalInitializations.append((cName, value))
          }
        }
      }
      buffer += "\n"

      // 生成函数实现
      for node in nodes {
        if case .globalFunction(let identifier, let params, let body) = node {
          generateGlobalFunction(identifier, params, body)
        }
        if case .givenDeclaration(let type, let methods) = node {
          if type.containsGenericParameter { continue }
          for method in methods {
            generateGlobalFunction(method.identifier, method.parameters, method.body)
          }
        }
      }

      // 生成 main 函数用于初始化全局变量
      if !globalInitializations.isEmpty {
        generateMainFunction()
      }
  }

  private func generateMainFunction() {
    buffer += "\nint main() {\n"
    withIndent {
      // 生成全局变量初始化
      pushScope()
      for (name, value) in globalInitializations {
        let resultVar = generateExpressionSSA(value)
        addIndent()
        buffer += "\(name) = \(resultVar);\n"
      }
      popScope()
      // 如果需要的话，这里可以调用用户定义的 main 函数
      addIndent()
      buffer += "return 0;\n"
    }
    buffer += "}\n"
  }

  private func generateFunctionDeclaration(_ identifier: Symbol, _ params: [Symbol]) {
    let cName = identifier.qualifiedName
    let returnType = cName == "main" ? "int" : getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
    buffer += "\(returnType) \(cName)(\(paramList));\n"
  }

  private func generateGlobalFunction(
    _ identifier: Symbol,
    _ params: [Symbol],
    _ body: TypedExpressionNode
  ) {
    let cName = identifier.qualifiedName
    
    // 重置逃逸分析上下文，设置当前函数的返回类型和函数名
    let funcReturnType = getFunctionReturnTypeAsType(identifier.type)
    escapeContext.reset(returnType: funcReturnType, functionName: cName)
    
    // 预分析函数体，识别所有可能逃逸的变量
    escapeContext.preAnalyze(body: body, params: params)
    
    // 重置作用域状态（预分析会修改作用域状态）
    escapeContext.variableScopes = [:]
    escapeContext.currentScopeLevel = 0
    // 注意：escapedVariables 保留，因为这是预分析的结果
    
    // Save Lambda state before generating function body
    let savedLambdaFunctions = lambdaFunctions
    lambdaFunctions = ""
    
    let returnType = cName == "main" ? "int" : getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
    
    // Generate function body to a temporary buffer to collect Lambda functions
    let savedBuffer = buffer
    buffer = ""
    buffer += "\(returnType) \(cName)(\(paramList)) {\n"

    withIndent {
      generateFunctionBody(body, params)
    }
    buffer += "}\n"
    
    let functionCode = buffer
    buffer = savedBuffer
    
    // Insert Lambda functions before this function, then the function itself
    if !lambdaFunctions.isEmpty {
      buffer += lambdaFunctions
    }
    buffer += functionCode
    
    // Restore Lambda state
    lambdaFunctions = savedLambdaFunctions
  }

  // 生成参数的 C 声明：类型若为 reference(T) 则 getCType 返回 T*
  private func getParamCDecl(_ param: Symbol) -> String {
    return "\(getCType(param.type)) \(param.name)"
  }

  private func generateFunctionBody(_ body: TypedExpressionNode, _ params: [Symbol]) {
    pushScope()
    for param in params {
      registerVariable(param.name, param.type)
    }
    let resultVar = generateExpressionSSA(body)

    // `Never` 表达式不返回；不要生成返回临时变量或 return 语句。
    if body.type == .never {
      popScope()
      return
    }

    let result = nextTemp()
    if case .structure(let decl) = body.type {
      addIndent()
      if body.valueCategory == .lvalue {
        buffer += "\(getCType(body.type)) \(result) = __koral_\(decl.qualifiedName)_copy(&\(resultVar));\n"
      } else {
        buffer += "\(getCType(body.type)) \(result) = \(resultVar);\n"
      }
    } else if case .reference(_) = body.type {
      addIndent()
      buffer += "\(getCType(body.type)) \(result) = \(resultVar);\n"
      if body.valueCategory == .lvalue {
        addIndent()
        buffer += "__koral_retain(\(result).control);\n"
      }
    } else if body.type != .void {
      addIndent()
      buffer += "\(getCType(body.type)) \(result) = \(resultVar);\n"
    }
    popScope()

    if body.type != .void {
      addIndent()
      buffer += "return \(result);\n"
    }
  }

  private func generateExpressionSSA(_ expr: TypedExpressionNode) -> String {
    switch expr {
    case .integerLiteral(let value, _):
      return String(value)

    case .floatLiteral(let value, _):
      return String(value)

    case .stringLiteral(let value, let type):
      let bytesVar = nextTemp() + "_bytes"
      let utf8Bytes = Array(value.utf8)
      let byteLiterals = utf8Bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
      addIndent()
      buffer += "static const uint8_t \(bytesVar)[] = { \(byteLiterals) };\n"

      let result = nextTemp()
      addIndent()
      buffer += "\(getCType(type)) \(result) = String_from_utf8_bytes_unchecked((uint8_t*)\(bytesVar), \(utf8Bytes.count));\n"
      return result

    case .booleanLiteral(let value, _):
      return value ? "1" : "0"

    case .variable(let identifier):
      return identifier.qualifiedName

    case .castExpression(let inner, let type):
      // Cast is only used for scalar and pointer conversions (Sema enforces legality).
      let innerResult = generateExpressionSSA(inner)
      let targetCType = getCType(type)

      if inner.type == type {
        return innerResult
      }

      func isFloat(_ t: Type) -> Bool {
        switch t {
        case .float32, .float64: return true
        default: return false
        }
      }

      func isSignedInt(_ t: Type) -> Bool {
        switch t {
        case .int, .int8, .int16, .int32, .int64: return true
        default: return false
        }
      }

      func isUnsignedInt(_ t: Type) -> Bool {
        switch t {
        case .uint, .uint8, .uint16, .uint32, .uint64: return true
        default: return false
        }
      }

      func minMaxMacros(for t: Type) -> (min: String, max: String)? {
        switch t {
        case .int8: return ("INT8_MIN", "INT8_MAX")
        case .int16: return ("INT16_MIN", "INT16_MAX")
        case .int32: return ("INT32_MIN", "INT32_MAX")
        case .int64: return ("INT64_MIN", "INT64_MAX")
        case .int: return ("INTPTR_MIN", "INTPTR_MAX")
        case .uint8: return ("0", "UINT8_MAX")
        case .uint16: return ("0", "UINT16_MAX")
        case .uint32: return ("0", "UINT32_MAX")
        case .uint64: return ("0", "UINT64_MAX")
        case .uint: return ("0", "UINTPTR_MAX")
        default: return nil
        }
      }

      // float -> int/uint: runtime range check, overflow panics.
      if isFloat(inner.type) && (isSignedInt(type) || isUnsignedInt(type)) {
        guard let (minMacro, maxMacro) = minMaxMacros(for: type) else {
          fatalError("Unsupported float->int cast target: \(type)")
        }

        let fVar = nextTemp()
        addIndent()
        buffer += "double \(fVar) = (double)\(innerResult);\n"

        addIndent()
        buffer += "if (!(\(fVar) >= (double)\(minMacro) && \(fVar) <= (double)\(maxMacro))) {\n"
        withIndent {
          addIndent()
          buffer += "fprintf(stderr, \"Panic: float-to-int cast overflow\\n\");\n"
          addIndent()
          buffer += "exit(1);\n"
        }
        addIndent()
        buffer += "}\n"

        let result = nextTemp()
        addIndent()
        buffer += "\(targetCType) \(result) = (\(targetCType))\(fVar);\n"
        return result
      }

      // Pointer <-> Int/UInt casts: prefer uintptr_t/intptr_t intermediates.
      if case .pointer = type {
        let result = nextTemp()
        addIndent()
        if inner.type == .uint {
          buffer += "\(targetCType) \(result) = (\(targetCType))(uintptr_t)\(innerResult);\n"
        } else if inner.type == .int {
          buffer += "\(targetCType) \(result) = (\(targetCType))(intptr_t)\(innerResult);\n"
        } else {
          buffer += "\(targetCType) \(result) = (\(targetCType))\(innerResult);\n"
        }
        return result
      }

      if case .pointer = inner.type {
        let result = nextTemp()
        addIndent()
        buffer += "\(targetCType) \(result) = (\(targetCType))\(innerResult);\n"
        return result
      }

      // Default scalar cast.
      let result = nextTemp()
      addIndent()
      buffer += "\(targetCType) \(result) = (\(targetCType))\(innerResult);\n"
      return result

    case .blockExpression(let statements, let finalExpr, _):
      return generateBlockScope(statements, finalExpr: finalExpr)

    case .arithmeticExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let result = nextTemp()
      addIndent()
      if op == .power {
        // Special handling for power operator
        if isFloatType(type) {
          buffer += "\(getCType(type)) \(result) = pow(\(leftResult), \(rightResult));\n"
        } else {
          buffer += "\(getCType(type)) \(result) = __koral_ipow(\(leftResult), \(rightResult));\n"
        }
      } else {
        buffer +=
          "\(getCType(type)) \(result) = \(leftResult) \(arithmeticOpToC(op)) \(rightResult);\n"
      }
      return result

    case .comparisonExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let result = nextTemp()
      addIndent()
      buffer +=
        "\(getCType(type)) \(result) = \(leftResult) \(comparisonOpToC(op)) \(rightResult);\n"
      return result

    case .letExpression(let identifier, let value, let body, let type):
      let valueVar = generateExpressionSSA(value)

      let resultVar = nextTemp()
      if type != .void {
        addIndent()
        buffer += "\(getCType(type)) \(resultVar);\n"
      }

      addIndent()
      buffer += "{\n"
      withIndent {
        addIndent()
        let cType = getCType(identifier.type)
        buffer += "\(cType) \(identifier.name) = \(valueVar);\n"

        pushScope()
        registerVariable(identifier.name, identifier.type)

        let bodyResultVar = generateExpressionSSA(body)

        if type != .void {
          if case .structure(let decl) = type {
            addIndent()
            if body.valueCategory == .lvalue {
              buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(bodyResultVar));\n"
            } else {
              buffer += "\(resultVar) = \(bodyResultVar);\n"
            }
          } else if case .reference(_) = type {
            addIndent()
            buffer += "\(resultVar) = \(bodyResultVar);\n"
            if body.valueCategory == .lvalue {
              addIndent()
              buffer += "__koral_retain(\(resultVar).control);\n"
            }
          } else {
            addIndent()
            buffer += "\(resultVar) = \(bodyResultVar);\n"
          }
        }

        popScope()
      }
      addIndent()
      buffer += "}\n"

      return type == .void ? "" : resultVar

    case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
      let conditionVar = generateExpressionSSA(condition)

      if type == .void || type == .never {
        addIndent()
        buffer += "if (\(conditionVar)) {\n"
        withIndent {
          pushScope()
          _ = generateExpressionSSA(thenBranch)
          popScope()
        }
        if let elseBranch = elseBranch {
          addIndent()
          buffer += "} else {\n"
          withIndent {
            pushScope()
            _ = generateExpressionSSA(elseBranch)
            popScope()
          }
        }
        addIndent()
        buffer += "}\n"
        return ""
      } else {
        guard let elseBranch = elseBranch else {
          fatalError("Non-void if expression must have else branch (Sema should catch this)")
        }
        let resultVar = nextTemp() // Declare resultVar before using it
        if type != .never {
            addIndent()
            buffer += "\(getCType(type)) \(resultVar);\n"
        }
        
        addIndent()
        buffer += "if (\(conditionVar)) {\n"
        withIndent {
          pushScope()
          let thenResult = generateExpressionSSA(thenBranch)
          if type != .never && thenBranch.type != .never {
              addIndent()
              if case .structure(let decl) = type {
                if thenBranch.valueCategory == .lvalue {
                  switch thenBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(thenResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(thenResult);\n"
                }
              } else if case .union(let decl) = type {
                if thenBranch.valueCategory == .lvalue {
                  switch thenBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(thenResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(thenResult);\n"
                }
              } else if case .reference(_) = type {
                buffer += "\(resultVar) = \(thenResult);\n"
                if thenBranch.valueCategory == .lvalue {
                  addIndent()
                  buffer += "__koral_retain(\(resultVar).control);\n"
                }
              } else {
                buffer += "\(resultVar) = \(thenResult);\n"
              }
          }
          popScope()
        }
        addIndent()
        buffer += "} else {\n"
        withIndent {
          pushScope()
          let elseResult = generateExpressionSSA(elseBranch)
          if type != .never && elseBranch.type != .never {
              addIndent()
              if case .structure(let decl) = type {
                if elseBranch.valueCategory == .lvalue {
                  switch elseBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(elseResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(elseResult);\n"
                }
              } else if case .union(let decl) = type {
                if elseBranch.valueCategory == .lvalue {
                  switch elseBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(elseResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(elseResult);\n"
                }
              } else if case .reference(_) = type {
                buffer += "\(resultVar) = \(elseResult);\n"
                if elseBranch.valueCategory == .lvalue {
                  addIndent()
                  buffer += "__koral_retain(\(resultVar).control);\n"
                }
              } else {
                buffer += "\(resultVar) = \(elseResult);\n"
              }
          }
          popScope()
        }
        addIndent()
        buffer += "}\n"
        return resultVar
      }

    case .call(let callee, let arguments, let type):
      return generateCall(callee, arguments, type)
    case .genericCall:
      fatalError("Generic call should have been resolved by monomorphizer before code generation")
    case .methodReference:
      fatalError("Method reference not in call position is not supported yet")
    case .staticMethodCall:
      fatalError("Static method call should have been resolved by monomorphizer before code generation")
      
    case .unionConstruction(let type, let caseName, let args):
      return generateUnionConstructor(type: type, caseName: caseName, args: args)

    case .derefExpression(let inner, let type):
      let innerResult = generateExpressionSSA(inner)
      let result = nextTemp()
      
      addIndent()
      buffer += "\(getCType(type)) \(result);\n"
      
      if case .structure(let decl) = type {
        // Struct: call copy constructor
        addIndent()
        buffer += "\(result) = __koral_\(decl.qualifiedName)_copy((struct \(decl.qualifiedName)*)\(innerResult).ptr);\n"
      } else if case .reference(_) = type {
        // Reference: copy struct Ref and retain
        addIndent()
        buffer += "\(result) = *(struct Ref*)\(innerResult).ptr;\n"
        addIndent()
        buffer += "__koral_retain(\(result).control);\n"
      } else {
        // Primitive: direct dereference
        let cType = getCType(type)
        addIndent()
        buffer += "\(result) = *(\(cType)*)\(innerResult).ptr;\n"
      }
      return result

    case .referenceExpression(let inner, let type):
      // 使用逃逸分析决定分配策略
      let shouldHeapAllocate = escapeContext.shouldUseHeapAllocation(inner)
      
      if inner.valueCategory == .lvalue && !shouldHeapAllocate {
        // 不逃逸的 lvalue：栈分配（取地址）
        let (lvaluePath, controlPath) = buildRefComponents(inner)
        let result = nextTemp()
        addIndent()
        buffer += "\(getCType(type)) \(result);\n"
        addIndent()
        buffer += "\(result).ptr = &\(lvaluePath);\n"
        addIndent()
        buffer += "\(result).control = \(controlPath);\n"
        addIndent()
        buffer += "__koral_retain(\(result).control);\n"
        return result
      } else {
        // 逃逸的 lvalue 或 rvalue：堆分配
        let innerResult = generateExpressionSSA(inner)
        let result = nextTemp()
        let innerType = inner.type
        let innerCType = getCType(innerType)

        addIndent()
        buffer += "\(getCType(type)) \(result);\n"

        // 1. 分配数据内存
        addIndent()
        buffer += "\(result).ptr = malloc(sizeof(\(innerCType)));\n"

        // 2. 初始化数据
        if case .structure(let decl) = innerType {
          addIndent()
          if inner.valueCategory == .lvalue {
            // 对于逃逸的 lvalue，需要复制数据
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(decl.qualifiedName)_copy(&\(innerResult));\n"
          } else {
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(decl.qualifiedName)_copy(&\(innerResult));\n"
          }
        } else if case .union(let decl) = innerType {
          addIndent()
          if inner.valueCategory == .lvalue {
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(decl.qualifiedName)_copy(&\(innerResult));\n"
          } else {
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(decl.qualifiedName)_copy(&\(innerResult));\n"
          }
        } else {
          addIndent()
          buffer += "*(\(innerCType)*)\(result).ptr = \(innerResult);\n"
        }

        // 3. 分配控制块
        addIndent()
        buffer += "\(result).control = malloc(sizeof(struct Koral_Control));\n"
        addIndent()
        buffer += "((struct Koral_Control*)\(result).control)->count = 1;\n"
        addIndent()
        buffer += "((struct Koral_Control*)\(result).control)->ptr = \(result).ptr;\n"

        // 4. 设置析构函数
        if case .structure(let decl) = innerType {
          addIndent()
          buffer += "((struct Koral_Control*)\(result).control)->dtor = (Koral_Dtor)__koral_\(decl.qualifiedName)_drop;\n"
        } else if case .union(let decl) = innerType {
          addIndent()
          buffer += "((struct Koral_Control*)\(result).control)->dtor = (Koral_Dtor)__koral_\(decl.qualifiedName)_drop;\n"
        } else {
          addIndent()
          buffer += "((struct Koral_Control*)\(result).control)->dtor = NULL;\n"
        }

        return result
      }

    case .matchExpression(let subject, let cases, let type):
      return generateMatchExpression(subject, cases, type)

    case .whileExpression(let condition, let body, _):
      let labelPrefix = nextTemp()
      let startLabel = "\(labelPrefix)_start"
      let endLabel = "\(labelPrefix)_end"
      addIndent()
      buffer += "\(startLabel): {\n"
      withIndent {
        let conditionVar = generateExpressionSSA(condition)
        addIndent()
        buffer += "if (!\(conditionVar)) { goto \(endLabel); }\n"
        pushScope()
        loopStack.append(LoopContext(startLabel: startLabel, endLabel: endLabel, scopeIndex: lifetimeScopeStack.count - 1))
        _ = generateExpressionSSA(body)
        loopStack.removeLast()
        popScope()
        addIndent()
        buffer += "goto \(startLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return ""
      
    case .ifPatternExpression(let subject, let pattern, let bindings, let thenBranch, let elseBranch, let type):
      // Generate subject expression
      let subjectVar = generateExpressionSSA(subject)
      let subjectTemp = nextTemp() + "_subject"
      addIndent()
      buffer += "\(getCType(subject.type)) \(subjectTemp) = \(subjectVar);\n"
      
      // Generate pattern matching condition and bindings
      let (prelude, _, condition, bindingCode, _) = 
          generatePatternConditionAndBindings(pattern, subjectTemp, subject.type, isMove: false)
      
      // Output prelude
      for p in prelude {
        addIndent()
        buffer += p
      }
      
      if type == .void || type == .never {
        addIndent()
        buffer += "if (\(condition)) {\n"
        withIndent {
          pushScope()
          // Generate bindings
          for b in bindingCode {
            addIndent()
            buffer += b
          }
          // Register bound variables in scope
          for (name, _, varType) in bindings {
            registerVariable(name, varType)
          }
          _ = generateExpressionSSA(thenBranch)
          popScope()
        }
        if let elseBranch = elseBranch {
          addIndent()
          buffer += "} else {\n"
          withIndent {
            pushScope()
            _ = generateExpressionSSA(elseBranch)
            popScope()
          }
        }
        addIndent()
        buffer += "}\n"
        return ""
      } else {
        guard let elseBranch = elseBranch else {
          fatalError("Non-void if pattern expression must have else branch")
        }
        let resultVar = nextTemp()
        if type != .never {
          addIndent()
          buffer += "\(getCType(type)) \(resultVar);\n"
        }
        
        addIndent()
        buffer += "if (\(condition)) {\n"
        withIndent {
          pushScope()
          // Generate bindings
          for b in bindingCode {
            addIndent()
            buffer += b
          }
          // Register bound variables in scope
          for (name, _, varType) in bindings {
            registerVariable(name, varType)
          }
          let thenResult = generateExpressionSSA(thenBranch)
          if type != .never && thenBranch.type != .never {
            addIndent()
            if case .structure(let decl) = type {
              if thenBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(thenResult));\n"
              } else {
                buffer += "\(resultVar) = \(thenResult);\n"
              }
            } else if case .union(let decl) = type {
              if thenBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(thenResult));\n"
              } else {
                buffer += "\(resultVar) = \(thenResult);\n"
              }
            } else if case .reference(_) = type {
              buffer += "\(resultVar) = \(thenResult);\n"
              if thenBranch.valueCategory == .lvalue {
                addIndent()
                buffer += "__koral_retain(\(resultVar).control);\n"
              }
            } else {
              buffer += "\(resultVar) = \(thenResult);\n"
            }
          }
          popScope()
        }
        addIndent()
        buffer += "} else {\n"
        withIndent {
          pushScope()
          let elseResult = generateExpressionSSA(elseBranch)
          if type != .never && elseBranch.type != .never {
            addIndent()
            if case .structure(let decl) = type {
              if elseBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(elseResult));\n"
              } else {
                buffer += "\(resultVar) = \(elseResult);\n"
              }
            } else if case .union(let decl) = type {
              if elseBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(elseResult));\n"
              } else {
                buffer += "\(resultVar) = \(elseResult);\n"
              }
            } else if case .reference(_) = type {
              buffer += "\(resultVar) = \(elseResult);\n"
              if elseBranch.valueCategory == .lvalue {
                addIndent()
                buffer += "__koral_retain(\(resultVar).control);\n"
              }
            } else {
              buffer += "\(resultVar) = \(elseResult);\n"
            }
          }
          popScope()
        }
        addIndent()
        buffer += "}\n"
        return resultVar
      }
      
    case .whilePatternExpression(let subject, let pattern, let bindings, let body, _):
      let labelPrefix = nextTemp()
      let startLabel = "\(labelPrefix)_start"
      let endLabel = "\(labelPrefix)_end"
      
      addIndent()
      buffer += "\(startLabel): {\n"
      withIndent {
        // Generate subject expression (evaluated each iteration)
        let subjectVar = generateExpressionSSA(subject)
        let subjectTemp = nextTemp() + "_subject"
        addIndent()
        buffer += "\(getCType(subject.type)) \(subjectTemp) = \(subjectVar);\n"
        
        // Generate pattern matching condition and bindings
        let (prelude, _, condition, bindingCode, _) = 
            generatePatternConditionAndBindings(pattern, subjectTemp, subject.type, isMove: false)
        
        // Output prelude
        for p in prelude {
          addIndent()
          buffer += p
        }
        
        addIndent()
        buffer += "if (!(\(condition))) { goto \(endLabel); }\n"
        
        pushScope()
        // Generate bindings
        for b in bindingCode {
          addIndent()
          buffer += b
        }
        // Register bound variables in scope
        for (name, _, varType) in bindings {
          registerVariable(name, varType)
        }
        
        loopStack.append(LoopContext(startLabel: startLabel, endLabel: endLabel, scopeIndex: lifetimeScopeStack.count - 1))
        _ = generateExpressionSSA(body)
        loopStack.removeLast()
        popScope()
        addIndent()
        buffer += "goto \(startLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return ""

    case .andExpression(let left, let right, _):
      let result = nextTemp()
      let leftResult = generateExpressionSSA(left)
      let endLabel = nextTemp()

      addIndent()
      buffer += "_Bool \(result);\n"
      addIndent()
      buffer += "if (!\(leftResult)) {\n"
      withIndent {
        addIndent()
        buffer += "\(result) = 0;\n"
        addIndent()
        buffer += "goto \(endLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      // 单独处理短路时的临时对象
      pushScope()
      let rightResult = generateExpressionSSA(right)
      addIndent()
      buffer += "\(result) = \(rightResult);\n"
      popScope()
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return result

    case .orExpression(let left, let right, _):
      let result = nextTemp()
      let leftResult = generateExpressionSSA(left)
      let endLabel = nextTemp()

      addIndent()
      buffer += "_Bool \(result);\n"
      addIndent()
      buffer += "if (\(leftResult)) {\n"
      withIndent {
        addIndent()
        buffer += "\(result) = 1;\n"
        addIndent()
        buffer += "goto \(endLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      // 单独处理短路时的临时对象
      pushScope()
      let rightResult = generateExpressionSSA(right)
      addIndent()
      buffer += "\(result) = \(rightResult);\n"
      popScope()
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return result

    case .notExpression(let expr, _):
      let exprResult = generateExpressionSSA(expr)
      let result = nextTemp()
      addIndent()
      buffer += "_Bool \(result) = !\(exprResult);\n"
      return result

    case .bitwiseExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let result = nextTemp()
      addIndent()
      buffer += "\(getCType(type)) \(result) = \(leftResult) \(bitwiseOpToC(op)) \(rightResult);\n"
      return result

    case .bitwiseNotExpression(let expr, let type):
      let exprResult = generateExpressionSSA(expr)
      let result = nextTemp()
      addIndent()
      buffer += "\(getCType(type)) \(result) = ~\(exprResult);\n"
      return result

    case .typeConstruction(let identifier, _, let arguments, _):
      let result = nextTemp()
      var argResults: [String] = []
      
      // Get canonical members to check for casts
      let canonicalMembers: [(name: String, type: Type, mutable: Bool)]
      if case .structure(let decl) = identifier.type.canonical {
          canonicalMembers = decl.members
      } else {
          canonicalMembers = []
      }
      
      for (index, arg) in arguments.enumerated() {
        let argResult = generateExpressionSSA(arg)
        var finalArg = argResult

        if case .structure(let decl) = arg.type {
          addIndent()
          let argCopy = nextTemp()
          if arg.valueCategory == .lvalue {
            switch arg {
            default:
              buffer += "\(getCType(arg.type)) \(argCopy) = __koral_\(decl.qualifiedName)_copy(&\(argResult));\n"
            }
          } else {
            buffer += "\(getCType(arg.type)) \(argCopy) = \(argResult);\n"
          }
          finalArg = argCopy
        } else if case .reference(_) = arg.type {
          addIndent()
          buffer += "__koral_retain(\(argResult).control);\n"
          finalArg = argResult
        }
        
        // Check for cast
        if index < canonicalMembers.count {
            let canonicalType = canonicalMembers[index].type
            if canonicalType != arg.type {
                let targetCType = getCType(canonicalType)
                // Cast the value to the canonical type
                // For structs (like Ref_Int -> Ref_Void), we need to cast the value.
                // Since we are initializing a struct member, we can cast the expression.
                // `(struct Ref_Void) { ... }`? No, C doesn't support casting structs easily unless they are pointers.
                // But here we are initializing `struct Box_R { struct Ref_Void val; }`.
                // We are providing `{ arg }`.
                // If `arg` is `struct Ref_Int`, we can't just cast it to `struct Ref_Void`.
                // We need to reinterpret cast? `*(struct Ref_Void*)&arg`.
                
                finalArg = "*(\(targetCType)*)&(\(finalArg))"
            }
        }
        
        argResults.append(finalArg)
      }

      addIndent()
      buffer += "\(getCType(identifier.type)) \(result) = {"
      buffer += argResults.joined(separator: ", ")
      buffer += "};\n"
      return result
    case .memberPath(let source, let path):
      return generateMemberPath(source, path)
    case .subscriptExpression(let base, let args, let method, _):
        guard case .function(_, let returns) = method.type else { fatalError() }
        let callNode = TypedExpressionNode.call(
          callee: .methodReference(base: base, method: method, typeArgs: nil, type: method.type),
          arguments: args,
          type: returns)
        return generateExpressionSSA(callNode)

    case .intrinsicCall(let node):
      return generateIntrinsicSSA(node)
      
    case .lambdaExpression(let parameters, let captures, let body, let type):
      return generateLambdaExpression(parameters: parameters, captures: captures, body: body, type: type)
    }
  }
  
  // MARK: - Lambda Expression Code Generation
  
  /// Generates a unique Lambda function name
  private func nextLambdaName() -> String {
    let name = "__koral_lambda_\(lambdaCounter)"
    lambdaCounter += 1
    return name
  }
  
  /// Generates code for a Lambda expression
  /// Returns the name of a temporary variable holding the Closure struct
  private func generateLambdaExpression(
    parameters: [Symbol],
    captures: [CapturedVariable],
    body: TypedExpressionNode,
    type: Type
  ) -> String {
    guard case .function(let funcParams, let returnType) = type else {
      fatalError("Lambda expression must have function type")
    }
    
    let lambdaName = nextLambdaName()
    
    if captures.isEmpty {
      // No-capture Lambda: generate a simple function, env = NULL
      generateNoCaptureLabmdaFunction(
        name: lambdaName,
        parameters: parameters,
        funcParams: funcParams,
        returnType: returnType,
        body: body
      )
      
      // Create closure struct with env = NULL
      let result = nextTemp()
      addIndent()
      buffer += "struct __koral_Closure \(result) = { .fn = (void*)\(lambdaName), .env = NULL };\n"
      return result
    } else {
      // With-capture Lambda: generate env struct and wrapper function
      let envStructName = "\(lambdaName)_env"
      
      // Generate environment struct definition
      generateLambdaEnvStruct(name: envStructName, captures: captures)
      
      // Generate Lambda function with env parameter
      generateCaptureLabmdaFunction(
        name: lambdaName,
        envStructName: envStructName,
        parameters: parameters,
        funcParams: funcParams,
        returnType: returnType,
        captures: captures,
        body: body
      )
      
      // Allocate and initialize environment
      let envVar = nextTemp()
      addIndent()
      buffer += "struct \(envStructName)* \(envVar) = (struct \(envStructName)*)malloc(sizeof(struct \(envStructName)));\n"
      addIndent()
      buffer += "\(envVar)->__refcount = 1;\n"
      
      // Initialize captured variables
      for capture in captures {
        addIndent()
        let capturedName = capture.symbol.qualifiedName
        if case .reference(_) = capture.symbol.type {
          // Reference type: copy the Ref struct and retain
          buffer += "\(envVar)->\(capturedName) = \(capturedName);\n"
          addIndent()
          buffer += "__koral_retain(\(envVar)->\(capturedName).control);\n"
        } else {
          // Value type: copy the value
          buffer += "\(envVar)->\(capturedName) = \(capturedName);\n"
        }
      }
      
      // Create closure struct
      let result = nextTemp()
      addIndent()
      buffer += "struct __koral_Closure \(result) = { .fn = (void*)\(lambdaName), .env = \(envVar) };\n"
      return result
    }
  }
  
  /// Generates a no-capture Lambda function
  private func generateNoCaptureLabmdaFunction(
    name: String,
    parameters: [Symbol],
    funcParams: [Parameter],
    returnType: Type,
    body: TypedExpressionNode
  ) {
    let returnCType = getCType(returnType)
    
    // Build parameter list
    var paramList: [String] = []
    for (i, param) in parameters.enumerated() {
      let paramType = funcParams[i].type
      paramList.append("\(getCType(paramType)) \(param.qualifiedName)")
    }
    
    let paramsStr = paramList.isEmpty ? "void" : paramList.joined(separator: ", ")
    
    // Generate forward declaration
    var funcBuffer = "\n// Lambda function (no capture)\n"
    funcBuffer += "static \(returnCType) \(name)(\(paramsStr));\n"
    funcBuffer += "static \(returnCType) \(name)(\(paramsStr)) {\n"
    
    // Save current state
    let savedBuffer = buffer
    let savedIndent = indent
    let savedLambdaCounter = lambdaCounter
    let savedLambdaFunctions = lambdaFunctions
    buffer = ""
    indent = "  "
    lambdaFunctions = ""
    
    // Generate body
    let bodyResult = generateExpressionSSA(body)
    
    if returnType != .void && returnType != .never {
      addIndent()
      buffer += "return \(bodyResult);\n"
    }
    
    funcBuffer += buffer
    funcBuffer += "}\n"
    
    // Handle nested lambdas
    if !lambdaFunctions.isEmpty {
      funcBuffer = lambdaFunctions + funcBuffer
    }
    
    // Restore state
    buffer = savedBuffer
    indent = savedIndent
    lambdaCounter = savedLambdaCounter + (lambdaCounter - savedLambdaCounter)
    
    // Add to Lambda functions buffer
    lambdaFunctions = savedLambdaFunctions + funcBuffer
  }
  
  /// Generates a Lambda function with captures
  private func generateCaptureLabmdaFunction(
    name: String,
    envStructName: String,
    parameters: [Symbol],
    funcParams: [Parameter],
    returnType: Type,
    captures: [CapturedVariable],
    body: TypedExpressionNode
  ) {
    let returnCType = getCType(returnType)
    
    // Build parameter list (env as first parameter)
    var paramList: [String] = ["void* __env"]
    for (i, param) in parameters.enumerated() {
      let paramType = funcParams[i].type
      paramList.append("\(getCType(paramType)) \(param.qualifiedName)")
    }
    
    let paramsStr = paramList.joined(separator: ", ")
    
    // Generate forward declaration and function
    var funcBuffer = "\n// Lambda function (with capture)\n"
    funcBuffer += "static \(returnCType) \(name)(\(paramsStr));\n"
    funcBuffer += "static \(returnCType) \(name)(\(paramsStr)) {\n"
    funcBuffer += "  struct \(envStructName)* __captured = (struct \(envStructName)*)__env;\n"
    
    // Generate local aliases for captured variables
    for capture in captures {
      let capturedName = capture.symbol.qualifiedName
      let capturedType = getCType(capture.symbol.type)
      funcBuffer += "  \(capturedType) \(capturedName) = __captured->\(capturedName);\n"
    }
    
    // Save current state
    let savedBuffer = buffer
    let savedIndent = indent
    let savedLambdaCounter = lambdaCounter
    let savedLambdaFunctions = lambdaFunctions
    buffer = ""
    indent = "  "
    lambdaFunctions = ""
    
    // Generate body
    let bodyResult = generateExpressionSSA(body)
    
    if returnType != .void && returnType != .never {
      addIndent()
      buffer += "return \(bodyResult);\n"
    }
    
    funcBuffer += buffer
    funcBuffer += "}\n"
    
    // Handle nested lambdas
    if !lambdaFunctions.isEmpty {
      funcBuffer = lambdaFunctions + funcBuffer
    }
    
    // Restore state
    buffer = savedBuffer
    indent = savedIndent
    lambdaCounter = savedLambdaCounter + (lambdaCounter - savedLambdaCounter)
    
    // Add to Lambda functions buffer
    lambdaFunctions = savedLambdaFunctions + funcBuffer
  }
  
  /// Generates the environment struct for a Lambda with captures
  private func generateLambdaEnvStruct(name: String, captures: [CapturedVariable]) {
    var structBuffer = "\n// Lambda environment struct\n"
    structBuffer += "struct \(name) {\n"
    structBuffer += "  intptr_t __refcount;\n"
    
    for capture in captures {
      let capturedName = capture.symbol.qualifiedName
      let capturedType = getCType(capture.symbol.type)
      structBuffer += "  \(capturedType) \(capturedName);\n"
    }
    
    structBuffer += "};\n"
    
    // Add to Lambda env structs buffer
    lambdaEnvStructs += structBuffer
  }


  private func generateIntrinsicSSA(_ node: TypedIntrinsic) -> String {
    switch node {
    case .allocMemory(let count, let type):
      // malloc
      guard case .pointer(let element) = type else { fatalError("alloc_memory expects Pointer result") }
      let countVal = generateExpressionSSA(count)
      let elemSize = "sizeof(\(getCType(element)))"
      let result = nextTemp()
      addIndent()
      buffer += "\(getCType(type)) \(result);\n"
      addIndent()
      buffer += "\(result) = malloc(\(countVal) * \(elemSize));\n"
      return result

    case .deallocMemory(let ptr):
      let ptrVal = generateExpressionSSA(ptr)
      addIndent()
      buffer += "free(\(ptrVal));\n"
      return ""

    case .copyMemory(let dest, let src, let count):
      // memcpy
      guard case .pointer(let element) = dest.type else { fatalError() }
      let d = generateExpressionSSA(dest)
      let s = generateExpressionSSA(src)
      let c = generateExpressionSSA(count)
      let elemSize = "sizeof(\(getCType(element)))"
      addIndent()
      buffer += "memcpy(\(d), \(s), \(c) * \(elemSize));\n"
      return ""

    case .moveMemory(let dest, let src, let count):
      // memmove
      guard case .pointer(let element) = dest.type else { fatalError() }
      let d = generateExpressionSSA(dest)
      let s = generateExpressionSSA(src)
      let c = generateExpressionSSA(count)
      let elemSize = "sizeof(\(getCType(element)))"
      addIndent()
      buffer += "memmove(\(d), \(s), \(c) * \(elemSize));\n"
      return ""

    case .refCount(let val):
      let valRes = generateExpressionSSA(val)
      let result = nextTemp()
      addIndent()
      buffer += "int \(result) = 0;\n"
      addIndent()
      buffer += "if (\(valRes).control) {\n"
      withIndent {
        addIndent()
        buffer += "\(result) = atomic_load(&((struct Koral_Control*)\(valRes).control)->count);\n"
      }
      addIndent()
      buffer += "}\n"
      return result

    case .ptrInit(let ptr, let val):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let v = generateExpressionSSA(val)
      let cType = getCType(element)
      addIndent()
      if case .reference(_) = element {
        buffer += "*(struct Ref*)\(p) = \(v);\n"
        addIndent()
        buffer += "__koral_retain(((struct Ref*)\(p))->control);\n"
      } else if case .structure(let decl) = element {
        if decl.name == "String" {
          buffer += "*(\(cType)*)\(p) = __koral_String_copy(&\(v));\n"
        } else {
          buffer += "*(\(cType)*)\(p) = __koral_\(decl.qualifiedName)_copy(&\(v));\n"
        }
      } else if case .union(let decl) = element {
        buffer += "*(\(cType)*)\(p) = __koral_\(decl.qualifiedName)_copy(&\(v));\n"
      } else {
        buffer += "*(\(cType)*)\(p) = \(v);\n"
      }
      return ""

    case .ptrDeinit(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      if case .reference(_) = element {
        addIndent()
        buffer += "__koral_release(((struct Ref*)\(p))->control);\n"
      } else if case .structure(let decl) = element {
        if decl.name == "String" {  // String is primitive struct
          addIndent()
          buffer += "__koral_String_drop(\(p));\n"
        } else {
          addIndent()
          buffer += "__koral_\(decl.qualifiedName)_drop(\(p));\n"
        }
      }
      // int/float/bool/void -> noop
      return ""

    case .ptrPeek(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let cType = getCType(element)
      let result = nextTemp()
      addIndent()
      // For types that need deep copy (structs, unions), use copy function
      if case .structure(let decl) = element {
        buffer += "\(cType) \(result) = __koral_\(decl.qualifiedName)_copy((\(cType)*)\(p));\n"
      } else if case .union(let decl) = element {
        buffer += "\(cType) \(result) = __koral_\(decl.qualifiedName)_copy((\(cType)*)\(p));\n"
      } else if case .reference(_) = element {
        // Reference: copy struct Ref and retain
        buffer += "\(cType) \(result) = *(\(cType)*)\(p);\n"
        addIndent()
        buffer += "__koral_retain(\(result).control);\n"
      } else {
        // Primitive types: simple copy
        buffer += "\(cType) \(result) = *(\(cType)*)\(p);\n"
      }
      return result

    case .ptrTake(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let cType = getCType(element)
      let result = nextTemp()
      addIndent()
      buffer += "\(cType) \(result) = *(\(cType)*)\(p);\n"
      return result

    case .ptrReplace(let ptr, let val):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let v = generateExpressionSSA(val)
      let cType = getCType(element)
      let result = nextTemp()
      addIndent()
      buffer += "\(cType) \(result) = *(\(cType)*)\(p);\n"
      addIndent()
      if case .reference(_) = element {
        buffer += "*(struct Ref*)\(p) = \(v);\n"
        addIndent()
        buffer += "__koral_retain(((struct Ref*)\(p))->control);\n"
      } else if case .structure(let decl) = element {
        if decl.name == "String" {
          buffer += "*(\(cType)*)\(p) = __koral_String_copy(&\(v));\n"
        } else {
          buffer += "*(\(cType)*)\(p) = __koral_\(decl.qualifiedName)_copy(&\(v));\n"
        }
      } else {
        buffer += "*(\(cType)*)\(p) = \(v);\n"
      }
      return result

    case .ptrBits:
      // Return pointer bit width (32 or 64)
      let result = nextTemp()
      addIndent()
      buffer += "int64_t \(result) = sizeof(void*) * 8;\n"
      return result

    case .ptrOffset(let ptr, let offset):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let o = generateExpressionSSA(offset)
      let cType = getCType(element)
      let result = nextTemp()
      addIndent()
      buffer += "\(getCType(ptr.type)) \(result);\n"
      addIndent()
      buffer += "\(result) = ((\(cType)*)\(p)) + \(o);\n"
      return result

    case .exit(let code):
      let c = generateExpressionSSA(code)
      addIndent()
      buffer += "exit(\(c));\n"
      return ""

    case .abort:
      addIndent()
      buffer += "abort();\n"
      return ""

    case .float32Bits(let value):
      let v = generateExpressionSSA(value)
      let result = nextTemp()
      addIndent()
      buffer += "uint32_t \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(v), sizeof(uint32_t));\n"
      return result

    case .float64Bits(let value):
      let v = generateExpressionSSA(value)
      let result = nextTemp()
      addIndent()
      buffer += "uint64_t \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(v), sizeof(uint64_t));\n"
      return result

    case .float32FromBits(let bits):
      let b = generateExpressionSSA(bits)
      let bitsTemp = nextTemp()
      let result = nextTemp()
      addIndent()
      buffer += "uint32_t \(bitsTemp) = \(b);\n"
      addIndent()
      buffer += "float \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(bitsTemp), sizeof(float));\n"
      return result

    case .float64FromBits(let bits):
      let b = generateExpressionSSA(bits)
      let bitsTemp = nextTemp()
      let result = nextTemp()
      addIndent()
      buffer += "uint64_t \(bitsTemp) = \(b);\n"
      addIndent()
      buffer += "double \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(bitsTemp), sizeof(double));\n"
      return result

    // Low-level IO intrinsics (minimal set using file descriptors)
    case .fwrite(let ptr, let len, let fd):
      let p = generateExpressionSSA(ptr)
      let l = generateExpressionSSA(len)
      let f = generateExpressionSSA(fd)
      let result = nextTemp()
      addIndent()
      buffer += "FILE* _fwrite_stream_\(result) = (\(f) == 1) ? stdout : ((\(f) == 2) ? stderr : stdin);\n"
      addIndent()
      buffer += "int64_t \(result) = fwrite((const char*)\(p), 1, \(l), _fwrite_stream_\(result));\n"
      return result

    case .fgetc(let fd):
      let f = generateExpressionSSA(fd)
      let result = nextTemp()
      addIndent()
      buffer += "FILE* _fgetc_stream_\(result) = (\(f) == 0) ? stdin : ((\(f) == 1) ? stdout : stderr);\n"
      addIndent()
      buffer += "int64_t \(result) = fgetc(_fgetc_stream_\(result));\n"
      return result

    case .fflush(let fd):
      let f = generateExpressionSSA(fd)
      addIndent()
      buffer += "FILE* _fflush_stream = (\(f) == 1) ? stdout : ((\(f) == 2) ? stderr : stdin);\n"
      addIndent()
      buffer += "fflush(_fflush_stream);\n"
      return ""
    }
  }

  // 构建引用组件：返回 (访问路径, 控制块指针)
  private func buildRefComponents(_ expr: TypedExpressionNode) -> (path: String, control: String) {
    switch expr {
    case .variable(let identifier):
      let path = identifier.qualifiedName
      if case .reference(_) = identifier.type {
        return (path, "\(path).control")
      } else {
        return (path, "NULL")
      }
    case .memberPath(let source, let path):
      var (basePath, baseControl) = buildRefComponents(source)
      var curType = source.type

      for member in path {
        if case .reference(let inner) = curType {
          // Dereferencing a ref type updates the control block
          baseControl = "\(basePath).control"
          let innerCType = getCType(inner)
          basePath = "((\(innerCType)*)\(basePath).ptr)->\(member.name)"
        } else {
          // Accessing member of value type keeps the same control block
          basePath += ".\(member.name)"
        }
        curType = member.type
      }
      return (basePath, baseControl)
    case .subscriptExpression(let base, let args, let method, let type):
         guard case .function(_, let returns) = method.type else { fatalError() }
         let callNode = TypedExpressionNode.call(
             callee: .methodReference(base: base, method: method, typeArgs: nil, type: method.type),
             arguments: args,
             type: returns)
         let refResult = generateExpressionSSA(callNode)
         
         if case .reference(_) = type {
             return (refResult, "\(refResult).control")
         } else {
             return (refResult, "NULL")
         }

    case .derefExpression(let inner, let type):
         // Dereferencing a reference type gives us an LValue
         let refResult = generateExpressionSSA(inner)
         let cType = getCType(type)
         let path = "(*(\(cType)*)\(refResult).ptr)"
         let control = "\(refResult).control"
         return (path, control)
         
    default:
      fatalError("ref requires lvalue (variable or memberAccess)")
    }
  }

  private func nextTemp() -> String {
    tempVarCounter += 1
    return "_t\(tempVarCounter)"
  }

  private func generateStatement(_ stmt: TypedStatementNode) {
    switch stmt {
    case .variableDeclaration(let identifier, let value, _):
      let valueResult = generateExpressionSSA(value)
      // void/never 类型的值不能赋给变量
      if value.type != .void && value.type != .never {
        // 如果是可变类型，增加引用计数
        if case .structure(let decl) = identifier.type {
          addIndent()
          buffer += "\(getCType(identifier.type)) \(identifier.name) = "
          if value.valueCategory == .lvalue {
            buffer += "__koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(valueResult);\n"
          }
          registerVariable(identifier.name, identifier.type)
        } else if case .union(let decl) = identifier.type {
          addIndent()
          buffer += "\(getCType(identifier.type)) \(identifier.name) = "
          if value.valueCategory == .lvalue {
            buffer += "__koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(valueResult);\n"
          }
          registerVariable(identifier.name, identifier.type)
        } else if case .reference(_) = identifier.type {
          addIndent()
          buffer += "\(getCType(identifier.type)) \(identifier.name) = \(valueResult);\n"
          if value.valueCategory == .lvalue {
            addIndent()
            buffer += "__koral_retain(\(identifier.name).control);\n"
          }
          registerVariable(identifier.name, identifier.type)
        } else {
          addIndent()
          buffer += "\(getCType(identifier.type)) \(identifier.name) = \(valueResult);\n"
        }
      }
    case .assignment(let target, let value):
      // 检测是否是结构体字段赋值（用于逃逸分析）
      let isFieldAssignment = isStructFieldAssignment(target)
      if isFieldAssignment && isReferenceType(value.type) {
        escapeContext.inFieldAssignmentContext = true
      }
      
      // Use buildRefComponents to get the C LValue path
      let (lhsPath, _) = buildRefComponents(target)
      let valueResult = generateExpressionSSA(value)
      
      escapeContext.inFieldAssignmentContext = false
      
      if value.type == .void || value.type == .never { return }

      if case .structure(let decl) = target.type {
        addIndent()
        if value.valueCategory == .lvalue {
           buffer += "\(lhsPath) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
        } else {
           buffer += "\(lhsPath) = \(valueResult);\n"
        }
      } else if case .reference(_) = target.type {
         addIndent()
         buffer += "\(lhsPath) = \(valueResult);\n"
         if value.valueCategory == .lvalue {
             addIndent()
             buffer += "__koral_retain(\(lhsPath).control);\n"
         }
      } else {
         addIndent()
         buffer += "\(lhsPath) = \(valueResult);\n"
      }

    case .compoundAssignment(let target, let op, let value):
      let (lhsPath, _) = buildRefComponents(target)
      let valueResult = generateExpressionSSA(value)
      let opStr = compoundOpToC(op)
      
      addIndent()
      buffer += "\(lhsPath) \(opStr) \(valueResult);\n"
      
    case .expression(let expr):
      _ = generateExpressionSSA(expr)

    case .return(let value):
      if let value = value {
        if value.type == .never {
          _ = generateExpressionSSA(value)
          return
        }
        
        // 设置返回上下文标志，用于逃逸分析
        escapeContext.inReturnContext = true
        let valueResult = generateExpressionSSA(value)
        escapeContext.inReturnContext = false
        
        let retVar = nextTemp()

        if case .structure(let decl) = value.type {
          addIndent()
          if value.valueCategory == .lvalue {
            buffer += "\(getCType(value.type)) \(retVar) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(getCType(value.type)) \(retVar) = \(valueResult);\n"
          }
        } else if case .union(let decl) = value.type {
          addIndent()
          if value.valueCategory == .lvalue {
            buffer += "\(getCType(value.type)) \(retVar) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(getCType(value.type)) \(retVar) = \(valueResult);\n"
          }
        } else if case .reference(_) = value.type {
          addIndent()
          buffer += "\(getCType(value.type)) \(retVar) = \(valueResult);\n"
          if value.valueCategory == .lvalue {
            addIndent()
            buffer += "__koral_retain(\(retVar).control);\n"
          }
        } else {
          addIndent()
          buffer += "\(getCType(value.type)) \(retVar) = \(valueResult);\n"
        }

        emitCleanup(fromScopeIndex: 0)
        addIndent()
        buffer += "return \(retVar);\n"
      } else {
        emitCleanup(fromScopeIndex: 0)
        addIndent()
        buffer += "return;\n"
      }

    case .break:
      guard let ctx = loopStack.last else {
        fatalError("break used outside of loop codegen")
      }
      emitCleanup(fromScopeIndex: ctx.scopeIndex)
      addIndent()
      buffer += "goto \(ctx.endLabel);\n"

    case .continue:
      guard let ctx = loopStack.last else {
        fatalError("continue used outside of loop codegen")
      }
      emitCleanup(fromScopeIndex: ctx.scopeIndex)
      addIndent()
      buffer += "goto \(ctx.startLabel);\n"
    }
  }

  private func compoundOpToC(_ op: CompoundAssignmentOperator) -> String {
    switch op {
    case .plus: return "+="
    case .minus: return "-="
    case .multiply: return "*="
    case .divide: return "/="
    case .modulo: return "%="
    case .power: return "**="  // Special handling needed
    case .bitwiseAnd: return "&="
    case .bitwiseOr: return "|="
    case .bitwiseXor: return "^="
    case .shiftLeft: return "<<="
    case .shiftRight: return ">>="
    }
  }

  private func arithmeticOpToC(_ op: ArithmeticOperator) -> String {
    switch op {
    case .plus: return "+"
    case .minus: return "-"
    case .multiply: return "*"
    case .divide: return "/"
    case .modulo: return "%"
    case .power: return "**"  // Special handling needed
    }
  }

  private func comparisonOpToC(_ op: ComparisonOperator) -> String {
    switch op {
    case .equal: return "=="
    case .notEqual: return "!="
    case .greater: return ">"
    case .less: return "<"
    case .greaterEqual: return ">="
    case .lessEqual: return "<="
    }
  }

  private func bitwiseOpToC(_ op: BitwiseOperator) -> String {
    switch op {
    case .and: return "&"
    case .or: return "|"
    case .xor: return "^"
    case .shiftLeft: return "<<"
    case .shiftRight: return ">>"
    }
  }

  private func getCType(_ type: Type) -> String {
    switch type {
    case .int: return "intptr_t"
    case .int8: return "int8_t"
    case .int16: return "int16_t"
    case .int32: return "int32_t"
    case .int64: return "int64_t"
    case .uint: return "uintptr_t"
    case .uint8: return "uint8_t"
    case .uint16: return "uint16_t"
    case .uint32: return "uint32_t"
    case .uint64: return "uint64_t"
    case .float32: return "float"
    case .float64: return "double"
    case .bool: return "_Bool"
    case .void: return "void"
    case .never: return "void"
    case .function(_, _):
      // All function types use the unified Closure struct (16 bytes: fn + env)
      return "struct __koral_Closure"
    case .structure(let decl):
      return "struct \(decl.qualifiedName)"
    case .union(let decl):
      return "struct \(decl.qualifiedName)"
    case .genericParameter(let name):
      fatalError("Generic parameter \(name) should be resolved before CodeGen")
    case .reference(_):
      return "struct Ref"
    case .pointer(_):
        return "void*"
    case .genericStruct(let template, _):
      fatalError("Generic struct \(template) should be resolved before CodeGen")
    case .genericUnion(let template, _):
      fatalError("Generic union \(template) should be resolved before CodeGen")
    case .module:
      fatalError("Module type should not appear in CodeGen")
    }
  }

  private func isFloatType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64: return true
    default: return false
    }
  }

  private func getFunctionReturnType(_ type: Type) -> String {
    switch type {
    case .function(_, let returns):
      return getCType(returns)
    default:
      fatalError("Expected function type")
    }
  }
  
  /// 获取函数类型的返回类型（作为 Type）
  private func getFunctionReturnTypeAsType(_ type: Type) -> Type? {
    switch type {
    case .function(_, let returns):
      return returns
    default:
      return nil
    }
  }
  
  // MARK: - 逃逸分析辅助函数
  
  /// 检查表达式是否是结构体字段赋值
  private func isStructFieldAssignment(_ target: TypedExpressionNode) -> Bool {
    switch target {
    case .memberPath(let source, let path):
      // 如果路径长度 > 0，说明是字段访问
      if !path.isEmpty {
        // 检查源是否是结构体类型
        if case .structure(_) = source.type {
          return true
        }
        if case .union(_) = source.type {
          return true
        }
      }
      return false
    default:
      return false
    }
  }
  
  /// 检查类型是否是引用类型
  private func isReferenceType(_ type: Type) -> Bool {
    if case .reference(_) = type {
      return true
    }
    return false
  }

  private func addIndent() {
    buffer += indent
  }

  private func withIndent(_ body: () -> Void) {
    let oldIndent = indent
    indent += "    "
    body()
    indent = oldIndent
  }

  private func generateTypeDeclaration(
    _ identifier: Symbol,
    _ parameters: [Symbol]
  ) {
    let name = identifier.qualifiedName
    
    // 所有类型都生成 struct，字段为值类型
    buffer += "struct \(name) {\n"
    withIndent {
      for param in parameters {
        addIndent()
        buffer += "\(getCType(param.type)) \(param.name);\n"
      }
    }
    buffer += "};\n\n"

    // 自动生成 copy/drop，需要递归处理
    buffer += "struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n"
    withIndent {
      buffer += "    struct \(name) result;\n"
      for param in parameters {
        if case .structure(let decl) = param.type {
          let qualifiedFieldTypeName = decl.qualifiedName
          buffer += "    result.\(param.name) = __koral_\(qualifiedFieldTypeName)_copy(&self->\(param.name));\n"
        } else if case .reference(_) = param.type {
          buffer += "    result.\(param.name) = self->\(param.name);\n"
          buffer += "    __koral_retain(result.\(param.name).control);\n"
        } else {
          buffer += "    result.\(param.name) = self->\(param.name);\n"
        }
      }
      buffer += "    return result;\n"
    }
    buffer += "}\n\n"

    buffer += "void __koral_\(name)_drop(void* raw_self) {\n"
    withIndent {
      buffer += "    struct \(name)* self = (struct \(name)*)raw_self;\n"

      // Call user defined drop if exists
      if let userDrop = userDefinedDrops[name] {
          buffer += "    {\n"
          buffer += "        void \(userDrop)(struct Ref);\n"
          buffer += "        struct Ref r;\n"
          buffer += "        r.ptr = self;\n"
          buffer += "        r.control = NULL;\n" // Control is NULL as we are inside the destructor managed by control/scope
          buffer += "        \(userDrop)(r);\n" 
          buffer += "    }\n"
      }

      for param in parameters {
        if case .structure(let decl) = param.type {
          let qualifiedFieldTypeName = decl.qualifiedName
          buffer += "    __koral_\(qualifiedFieldTypeName)_drop(&self->\(param.name));\n"
        } else if case .reference(_) = param.type {
          buffer += "    __koral_release(self->\(param.name).control);\n"
        }
      }
    }
    buffer += "}\n\n"
  }

  private func generateUnionDeclaration(_ identifier: Symbol, _ cases: [UnionCase]) {
    let name = identifier.qualifiedName
    buffer += "struct \(name) {\n"
    withIndent {
      addIndent()
      buffer += "intptr_t tag;\n"
      addIndent()
      buffer += "union {\n"
      withIndent {
        for c in cases {
            if !c.parameters.isEmpty {
                addIndent()
                buffer += "struct {\n"
                withIndent {
                    for param in c.parameters {
                        addIndent()
                        buffer += "\(getCType(param.type)) \(param.name);\n"
                    }
                }
                addIndent()
                buffer += "} \(c.name);\n"
            } else {
                 addIndent()
                 buffer += "struct {} \(c.name);\n"
            }
        }
      }
      addIndent()
      buffer += "} data;\n"
    }
    buffer += "};\n\n"

    // Generate Copy
    buffer += "struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n"
    withIndent {
        buffer += "    struct \(name) result;\n"
        buffer += "    result.tag = self->tag;\n"
        buffer += "    switch (self->tag) {\n"
        for (index, c) in cases.enumerated() {
             buffer += "    case \(index): // \(c.name)\n"
             if !c.parameters.isEmpty {
                 for param in c.parameters {
                     let fieldPath = "self->data.\(c.name).\(param.name)"
                     let resultPath = "result.data.\(c.name).\(param.name)"
                     if case .structure(let decl) = param.type {
                         let qualifiedFieldTypeName = decl.qualifiedName
                         buffer += "        \(resultPath) = __koral_\(qualifiedFieldTypeName)_copy(&\(fieldPath));\n"
                     } else if case .union(let decl) = param.type {
                        let qualifiedFieldTypeName = decl.qualifiedName
                        buffer += "        \(resultPath) = __koral_\(qualifiedFieldTypeName)_copy(&\(fieldPath));\n"
                     } else if case .reference(_) = param.type {
                         buffer += "        \(resultPath) = \(fieldPath);\n"
                         buffer += "        __koral_retain(\(resultPath).control);\n"
                     } else {
                         buffer += "        \(resultPath) = \(fieldPath);\n"
                     }
                 }
             }
             buffer += "        break;\n"
        }
        buffer += "    }\n"
        buffer += "    return result;\n"
    }
    buffer += "}\n\n"

    // Generate Drop
    buffer += "void __koral_\(name)_drop(void* raw_self) {\n"
    withIndent {
        buffer += "    struct \(name)* self = (struct \(name)*)raw_self;\n"

        // Call user defined drop if exists
        if let userDrop = userDefinedDrops[name] {
            buffer += "    {\n"
            buffer += "        void \(userDrop)(struct Ref);\n"
            buffer += "        struct Ref r;\n"
            buffer += "        r.ptr = self;\n"
            buffer += "        r.control = NULL;\n" // Control is NULL as we are inside the destructor managed by control/scope
            buffer += "        \(userDrop)(r);\n" 
            buffer += "    }\n"
        }

        buffer += "    switch (self->tag) {\n"
        for (index, c) in cases.enumerated() {
             buffer += "    case \(index): // \(c.name)\n"
             for param in c.parameters {
                 let fieldPath = "self->data.\(c.name).\(param.name)"
                 if case .structure(let decl) = param.type {
                     let qualifiedFieldTypeName = decl.qualifiedName
                     buffer += "        __koral_\(qualifiedFieldTypeName)_drop(&\(fieldPath));\n"
                 } else if case .union(let decl) = param.type {
                     let qualifiedFieldTypeName = decl.qualifiedName
                     buffer += "        __koral_\(qualifiedFieldTypeName)_drop(&\(fieldPath));\n"
                 } else if case .reference(_) = param.type {
                     buffer += "        __koral_release(\(fieldPath).control);\n"
                 }
             }
             buffer += "        break;\n"
        }
        buffer += "    }\n"
    }
    buffer += "}\n\n"
  }

  private func generateUnionConstructor(type: Type, caseName: String, args: [TypedExpressionNode]) -> String {
      guard case .union(let decl) = type else { fatalError() }
      let typeName = decl.qualifiedName
      let cases = decl.cases
      
      // Calculate tag index
      let tagIndex = cases.firstIndex(where: { $0.name == caseName })!
      
      let result = nextTemp()
      addIndent()
      buffer += "struct \(typeName) \(result);\n"
      addIndent()
      buffer += "\(result).tag = \(tagIndex);\n"
      
      // Assign members
      // The union member name is same as case name
      let caseInfo = cases[tagIndex]
      
      if !args.isEmpty {
          let unionMemberPath = "\(result).data.\(caseName)"
          for (argExpr, param) in zip(args, caseInfo.parameters) {
              let argResult = generateExpressionSSA(argExpr)
              
              addIndent()
              if case .structure(let structDecl) = param.type {
                   if argExpr.valueCategory == .lvalue {
                       buffer += "\(unionMemberPath).\(param.name) = __koral_\(structDecl.qualifiedName)_copy(&\(argResult));\n"
                   } else {
                       buffer += "\(unionMemberPath).\(param.name) = \(argResult);\n"
                   }
              } else if case .reference(_) = param.type {
                   buffer += "\(unionMemberPath).\(param.name) = \(argResult);\n"
                   if argExpr.valueCategory == .lvalue {
                       addIndent()
                       buffer += "__koral_retain(\(unionMemberPath).\(param.name).control);\n"
                   }
              } else {
                   buffer += "\(unionMemberPath).\(param.name) = \(argResult);\n"
              }
          }
      }
      
      return result
  }

  private func generateMatchExpression(_ subject: TypedExpressionNode, _ cases: [TypedMatchCase], _ type: Type) -> String {
    let subjectVarSSA = generateExpressionSSA(subject)
    let resultVar = nextTemp()
    
    if type != .void && type != .never {
        addIndent()
        buffer += "\(getCType(type)) \(resultVar);\n"
    }
    
    // Dereference subject if it acts as a reference but pattern matches against value
    var subjectVar = subjectVarSSA
    var subjectType = subject.type
    if case .reference(let inner) = subject.type {
        let innerCType = getCType(inner)
        let derefVar = nextTemp()
        addIndent()
        buffer += "\(innerCType) \(derefVar) = *(\(innerCType)*)\(subjectVarSSA).ptr;\n"
        subjectVar = derefVar
        subjectType = inner
    }
    

    let endLabel = "match_end_\(nextTemp())"
    
    for c in cases {
         addIndent()
         buffer += "{\n"
         withIndent {
         let caseScopeIndex = lifetimeScopeStack.count
         pushScope()

         let isMove = false
         let (prelude, preludeVars, condition, bindings, vars) = generatePatternConditionAndBindings(c.pattern, subjectVar, subjectType, isMove: isMove)

         // Prelude runs regardless of match success (temps used in the condition)
         for p in prelude {
           addIndent()
           buffer += p
         }
         for (name, varType) in preludeVars {
           registerVariable(name, varType)
         }

         addIndent()
         buffer += "if (\(condition)) {\n"
         withIndent {
           // Bindings should only exist on the matched path
           pushScope()

           for b in bindings {
             addIndent()
             buffer += b
           }
           for (name, varType) in vars {
             registerVariable(name, varType)
           }
                 
           let bodyResult = generateExpressionSSA(c.body)
           if type != .void && type != .never && c.body.type != .never {
             addIndent()
             if case .structure(let decl) = type {
              if c.body.valueCategory == .lvalue {
                 buffer += "\(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(bodyResult));\n"
              } else {
                 buffer += "\(resultVar) = \(bodyResult);\n"
              }
             } else if case .reference(_) = type {
              buffer += "\(resultVar) = \(bodyResult);\n"
              if c.body.valueCategory == .lvalue {
                 addIndent()
                 buffer += "__koral_retain(\(resultVar).control);\n"
              }
             } else {
              buffer += "\(resultVar) = \(bodyResult);\n"
             }
           }

           // Cleanup bindings, then cleanup prelude temps (outer case scope), then jump out.
           popScope()
           emitCleanupForScope(at: caseScopeIndex)
           addIndent()
           buffer += "goto \(endLabel);\n"
         }
         addIndent()
         buffer += "}\n"

         // Mismatch path: cleanup prelude temps, then discard the prelude scope.
         emitCleanupForScope(at: caseScopeIndex)
         popScopeWithoutCleanup()
         }
         addIndent()
         buffer += "}\n"
    }
    
    addIndent()
    buffer += "\(endLabel):;\n"
    return (type == .void || type == .never) ? "" : resultVar
  }

    private func generatePatternConditionAndBindings(
    _ pattern: TypedPattern,
    _ path: String,
    _ type: Type,
    isMove: Bool = false
    ) -> (prelude: [String], preludeVars: [(String, Type)], condition: String, bindings: [String], vars: [(String, Type)]) {
      switch pattern {
      case .integerLiteral(let val):
        return ([], [], "\(path) == \(val)", [], [])
      case .booleanLiteral(let val):
        return ([], [], "\(path) == \(val ? 1 : 0)", [], [])
      case .stringLiteral(let value):
        let bytesVar = nextTemp() + "_pat_bytes"
        let utf8Bytes = Array(value.utf8)
        let byteLiterals = utf8Bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
        let literalVar = nextTemp() + "_pat_str"
        var prelude = ""
        prelude += "static const uint8_t \(bytesVar)[] = { \(byteLiterals) };\n"
        prelude += "\(getCType(type)) \(literalVar) = String_from_utf8_bytes_unchecked((uint8_t*)\(bytesVar), \(utf8Bytes.count));\n"
        // Compare via compiler-protocol `String.__equals(self, other String) Bool`.
        // Value-passing semantics: String___equals consumes its arguments, so we must copy
        // the subject before comparison to allow multiple pattern matches on the same variable.
        return ([prelude], [(literalVar, type)], "String___equals(__koral_String_copy(&\(path)), \(literalVar))", [], [])
      case .wildcard:
        return ([], [], "1", [], [])
      case .variable(let symbol):
        let name = symbol.name
        let varType = symbol.type
        var bindCode = ""
        let cType = getCType(varType)
        bindCode += "\(cType) \(name);\n"
          
        if isMove {
          // Move Semantics: Shallow Copy. Source cleanup is suppressed via consumeVariable.
          bindCode += "\(name) = \(path);\n"
        } else {
          // Copy Semantics
          if case .structure(let decl) = varType {
             bindCode += "\(name) = __koral_\(decl.qualifiedName)_copy(&\(path));\n"
          } else if case .reference(_) = varType {
             bindCode += "\(name) = \(path);\n"
             bindCode += "__koral_retain(\(name).control);\n"
          } else {
             bindCode += "\(name) = \(path);\n"
          }
        }
        return ([], [], "1", [bindCode], [(name, varType)])
          
      case .unionCase(let caseName, let expectedTagIndex, let args):
        guard case .union(let decl) = type else { fatalError("Union pattern on non-union type") }
        let cases = decl.cases
          
        var prelude: [String] = []
        var preludeVars: [(String, Type)] = []
        var condition = "(\(path).tag == \(expectedTagIndex))"
        var bindings: [String] = []
        var vars: [(String, Type)] = []
          
        let caseDef = cases[expectedTagIndex]
          
        for (i, subInd) in args.enumerated() {
           let paramName = caseDef.parameters[i].name
           let paramType = caseDef.parameters[i].type
           let subPath = "\(path).data.\(caseName).\(paramName)"
               
           let (subPre, subPreVars, subCond, subBind, subVars) = generatePatternConditionAndBindings(subInd, subPath, paramType, isMove: isMove)
               
           if subCond != "1" {
             condition += " && (\(subCond))"
           }
           prelude.append(contentsOf: subPre)
           preludeVars.append(contentsOf: subPreVars)
           bindings.append(contentsOf: subBind)
           vars.append(contentsOf: subVars)
        }
        return (prelude, preludeVars, condition, bindings, vars)
        
      case .comparisonPattern(let op, let value):
        // Comparison pattern generates a simple comparison
        let opStr: String
        switch op {
        case .greater: opStr = ">"
        case .less: opStr = "<"
        case .greaterEqual: opStr = ">="
        case .lessEqual: opStr = "<="
        }
        
        let condition = "(\(path) \(opStr) \(value))"
        return ([], [], condition, [], [])
        
      case .andPattern(let left, let right):
        // And pattern: both sub-patterns must match
        let (leftPre, leftPreVars, leftCond, leftBind, leftVars) = 
            generatePatternConditionAndBindings(left, path, type, isMove: isMove)
        let (rightPre, rightPreVars, rightCond, rightBind, rightVars) = 
            generatePatternConditionAndBindings(right, path, type, isMove: isMove)
        
        let condition = "(\(leftCond)) && (\(rightCond))"
        return (
            leftPre + rightPre,
            leftPreVars + rightPreVars,
            condition,
            leftBind + rightBind,
            leftVars + rightVars
        )
        
      case .orPattern(let left, let right):
        // Or pattern: either sub-pattern must match
        // For bindings, we need to handle them specially since both branches bind the same variables
        let (leftPre, leftPreVars, leftCond, leftBind, leftVars) = 
            generatePatternConditionAndBindings(left, path, type, isMove: isMove)
        let (rightPre, rightPreVars, rightCond, rightBind, rightVars) = 
            generatePatternConditionAndBindings(right, path, type, isMove: isMove)
        
        let condition = "(\(leftCond)) || (\(rightCond))"
        
        // For or patterns with bindings, we need to generate conditional bindings
        // The bindings should be the same in both branches (enforced by type checker)
        // We use the left branch bindings but they will be set by whichever branch matches
        // Since both branches bind the same variables, we can use either set
        // The actual binding code will be generated based on which branch matched
        
        // If there are bindings, we need to generate conditional binding code
        var combinedBind: [String] = []
        if !leftVars.isEmpty {
            // Generate conditional bindings using ternary operator
            // First, we need to evaluate which branch matched
            let matchLeftVar = nextTemp() + "_match_left"
            combinedBind.append("int \(matchLeftVar) = \(leftCond);\n")
            
            // For each variable, generate conditional assignment
            for (i, (name, varType)) in leftVars.enumerated() {
                let cType = getCType(varType)
                combinedBind.append("\(cType) \(name);\n")
                
                // Get the binding expressions from left and right
                // This is simplified - in practice we'd need to extract the actual binding expressions
                // For now, we assume the binding is just the path (for simple variable patterns)
                if i < rightVars.count {
                    // Both branches have this variable - use conditional
                    combinedBind.append("if (\(matchLeftVar)) {\n")
                    combinedBind.append(contentsOf: leftBind.filter { $0.contains(name) })
                    combinedBind.append("} else {\n")
                    combinedBind.append(contentsOf: rightBind.filter { $0.contains(name) })
                    combinedBind.append("}\n")
                }
            }
        }
        
        // If no bindings, just use empty bindings
        let finalBind = leftVars.isEmpty ? [] : combinedBind
        
        return (
            leftPre + rightPre,
            leftPreVars + rightPreVars,
            condition,
            finalBind,
            leftVars
        )
        
      case .notPattern(let pattern):
        // Not pattern: negate the sub-pattern condition
        let (pre, preVars, cond, _, _) = 
            generatePatternConditionAndBindings(pattern, path, type, isMove: isMove)
        
        let condition = "!(\(cond))"
        // Not patterns cannot have bindings (enforced by type checker)
        return (pre, preVars, condition, [], [])
      }
    }


  private func generateBlockScope(
    _ statements: [TypedStatementNode], finalExpr: TypedExpressionNode?
  ) -> String {
    pushScope()
    // 先处理所有语句
    for stmt in statements {
      generateStatement(stmt)
    }

    // 生成最终表达式
    var result = ""
    if let finalExpr = finalExpr {
      let temp = generateExpressionSSA(finalExpr)
      if finalExpr.type != .void && finalExpr.type != .never {
        let resultVar = nextTemp()
        if case .structure(let decl) = finalExpr.type {
          if finalExpr.valueCategory == .lvalue {
            // Returning an lvalue struct from a block:
            // - Copy types must be copied, because scope cleanup will drop the original.
            switch finalExpr {
            default:
              addIndent()
              buffer += "\(getCType(finalExpr.type)) \(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(temp));\n"
            }
          } else {
            addIndent()
            buffer += "\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n"
          }
        } else if case .union(let decl) = finalExpr.type {
          if finalExpr.valueCategory == .lvalue {
            switch finalExpr {
            default:
              addIndent()
              buffer += "\(getCType(finalExpr.type)) \(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(temp));\n"
            }
          } else {
            addIndent()
            buffer += "\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n"
          }
        } else {
          addIndent()
          buffer += "\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n"
          if case .reference(_) = finalExpr.type, finalExpr.valueCategory == .lvalue {
            addIndent()
            buffer += "__koral_retain(\(resultVar).control);\n"
          }
        }
        result = resultVar
      }
    }
    popScope()
    return result
  }

  private func generateAssignment(_ identifier: Symbol, _ value: TypedExpressionNode) {
    if value.type == .void || value.type == .never {
      _ = generateExpressionSSA(value)
      return
    }
    let valueResult = generateExpressionSSA(value)
    if case .structure(let decl) = identifier.type {
      if value.valueCategory == .lvalue {
        let copyResult = nextTemp()
        addIndent()
        buffer += "\(getCType(value.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
        addIndent()
        buffer += "__koral_\(decl.qualifiedName)_drop(&\(identifier.name));\n"
        addIndent()
        buffer += "\(identifier.name) = \(copyResult);\n"
      } else {
        addIndent()
        buffer += "__koral_\(decl.qualifiedName)_drop(&\(identifier.name));\n"
        addIndent()
        buffer += "\(identifier.name) = \(valueResult);\n"
      }
    } else if case .union(let decl) = identifier.type {
      if value.valueCategory == .lvalue {
        let copyResult = nextTemp()
        addIndent()
        buffer += "\(getCType(value.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
        addIndent()
        buffer += "__koral_\(decl.qualifiedName)_drop(&\(identifier.name));\n"
        addIndent()
        buffer += "\(identifier.name) = \(copyResult);\n"
      } else {
        addIndent()
        buffer += "__koral_\(decl.qualifiedName)_drop(&\(identifier.name));\n"
        addIndent()
        buffer += "\(identifier.name) = \(valueResult);\n"
      }
    } else if case .reference(_) = identifier.type {
      addIndent()
      buffer += "__koral_release(\(identifier.name).control);\n"
      addIndent()
      buffer += "\(identifier.name) = \(valueResult);\n"
      if value.valueCategory == .lvalue {
        addIndent()
        buffer += "__koral_retain(\(identifier.name).control);\n"
      }
    } else {
      addIndent()
      buffer += "\(identifier.name) = \(valueResult);\n"
    }
  }

  private func generateMemberAccessAssignment(
    _ base: Symbol,
    _ memberPath: [Symbol], _ value: TypedExpressionNode
  ) {
    if value.type == .void || value.type == .never {
      _ = generateExpressionSSA(value)
      return
    }
    let baseResult = base.name
    let valueResult = generateExpressionSSA(value)
    var accessPath = baseResult
    var curType = base.type
    for (index, item) in memberPath.enumerated() {
      let isLast = index == memberPath.count - 1
      let memberName = item.name
      let memberType = item.type
      
      var memberAccess: String
      if case .reference(let inner) = curType {
          let innerCType = getCType(inner)
          memberAccess = "((\(innerCType)*)\(accessPath).ptr)->\(memberName)"
      } else {
          memberAccess = "\(accessPath).\(memberName)"
      }
      
      // Only apply type cast for non-reference struct members when the C types differ
      // This handles cases where generic type parameters are replaced with concrete types
      // but the C representation needs explicit casting
      if case .structure(let decl) = curType.canonical {
        if let canonicalMember = decl.members.first(where: { $0.name == memberName }) {
          // Compare C type representations instead of Type equality
          // This avoids issues with UUID-based type identity for generic instantiations
          let canonicalCType = getCType(canonicalMember.type)
          let memberCTypeStr = getCType(memberType)
          if canonicalCType != memberCTypeStr {
            // Skip cast for reference types - they all use struct Ref
            if case .reference(_) = memberType {
              // No cast needed for reference types
            } else {
              let targetCType = getCType(memberType)
              memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
            }
          }
        }
      }
      
      accessPath = memberAccess
      curType = memberType
      
      if isLast, case .structure(let decl) = memberType {
        if value.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          buffer += "\(getCType(value.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n"
          addIndent()
          buffer += "__koral_\(decl.qualifiedName)_drop(&\(accessPath));\n"
          addIndent()
          buffer += "\(accessPath) = \(copyResult);\n"
        } else {
          addIndent()
          buffer += "__koral_\(decl.qualifiedName)_drop(&\(accessPath));\n"
          addIndent()
          buffer += "\(accessPath) = \(valueResult);\n"
        }
        return
      }
    }
    addIndent()
    buffer += "\(accessPath) = \(valueResult);\n"
  }

  private func generateCall(
    _ callee: TypedExpressionNode, _ arguments: [TypedExpressionNode], _ type: Type
  ) -> String {
    if case .methodReference(let base, let method, _, _) = callee {
      var allArgs = [base]
      allArgs.append(contentsOf: arguments)
      return generateFunctionCall(method, allArgs, type)
    }

    if case .variable(let identifier) = callee {
      // Check if this is a function type variable (closure call)
      // Regular functions have kind = .function, while closure variables have kind = .variable
      if case .variable(_) = identifier.kind,
         case .function(let funcParams, let returnType) = identifier.type {
        return generateClosureCall(
          closureVar: identifier.qualifiedName,
          funcParams: funcParams,
          returnType: returnType,
          arguments: arguments
        )
      }
      return generateFunctionCall(identifier, arguments, type)
    }

    // Handle indirect call through expression (e.g., lambda expression result)
    if case .function(let funcParams, let returnType) = callee.type {
      let closureResult = generateExpressionSSA(callee)
      return generateClosureCall(
        closureVar: closureResult,
        funcParams: funcParams,
        returnType: returnType,
        arguments: arguments
      )
    }

    fatalError("Indirect call not supported: callee type = \(callee.type)")
  }
  
  /// Generates code for calling a closure (function type variable)
  /// Handles both no-capture (env == NULL) and with-capture (env != NULL) cases
  private func generateClosureCall(
    closureVar: String,
    funcParams: [Parameter],
    returnType: Type,
    arguments: [TypedExpressionNode]
  ) -> String {
    // Generate argument values
    var argResults: [String] = []
    for arg in arguments {
      let result = generateExpressionSSA(arg)
      if case .structure(let decl) = arg.type {
        if arg.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          buffer += "\(getCType(arg.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(result));\n"
          argResults.append(copyResult)
        } else {
          argResults.append(result)
        }
      } else if case .reference(_) = arg.type {
        if arg.valueCategory == .lvalue {
          addIndent()
          buffer += "__koral_retain(\(result).control);\n"
        }
        argResults.append(result)
      } else {
        argResults.append(result)
      }
    }
    
    let returnCType = getCType(returnType)
    
    // Build function pointer type for no-capture case: ReturnType (*)(Args...)
    var noCaptureParamTypes: [String] = []
    for param in funcParams {
      noCaptureParamTypes.append(getCType(param.type))
    }
    let noCaptureParamsStr = noCaptureParamTypes.isEmpty ? "void" : noCaptureParamTypes.joined(separator: ", ")
    let noCaptureFnPtrType = "\(returnCType) (*)(\(noCaptureParamsStr))"
    
    // Build function pointer type for with-capture case: ReturnType (*)(void*, Args...)
    var withCaptureParamTypes: [String] = ["void*"]
    for param in funcParams {
      withCaptureParamTypes.append(getCType(param.type))
    }
    let withCaptureParamsStr = withCaptureParamTypes.joined(separator: ", ")
    let withCaptureFnPtrType = "\(returnCType) (*)(\(withCaptureParamsStr))"
    
    // Build argument list strings
    let argsStr = argResults.joined(separator: ", ")
    let argsWithEnvStr = argResults.isEmpty ? "\(closureVar).env" : "\(closureVar).env, \(argsStr)"
    
    // Generate conditional call based on env == NULL
    if returnType == .void || returnType == .never {
      addIndent()
      buffer += "if (\(closureVar).env == NULL) {\n"
      indent += "  "
      addIndent()
      buffer += "((\(noCaptureFnPtrType))(\(closureVar).fn))(\(argsStr));\n"
      indent = String(indent.dropLast(2))
      addIndent()
      buffer += "} else {\n"
      indent += "  "
      addIndent()
      buffer += "((\(withCaptureFnPtrType))(\(closureVar).fn))(\(argsWithEnvStr));\n"
      indent = String(indent.dropLast(2))
      addIndent()
      buffer += "}\n"
      return ""
    } else {
      let result = nextTemp()
      addIndent()
      buffer += "\(returnCType) \(result);\n"
      addIndent()
      buffer += "if (\(closureVar).env == NULL) {\n"
      indent += "  "
      addIndent()
      buffer += "\(result) = ((\(noCaptureFnPtrType))(\(closureVar).fn))(\(argsStr));\n"
      indent = String(indent.dropLast(2))
      addIndent()
      buffer += "} else {\n"
      indent += "  "
      addIndent()
      buffer += "\(result) = ((\(withCaptureFnPtrType))(\(closureVar).fn))(\(argsWithEnvStr));\n"
      indent = String(indent.dropLast(2))
      addIndent()
      buffer += "}\n"
      return result
    }
  }

  private func generateFunctionCall(
    _ identifier: Symbol, _ arguments: [TypedExpressionNode], _ type: Type
  ) -> String {
    var paramResults: [String] = []
    // struct类型参数传递用值，isValue==false 的 struct 参数自动递归 copy
    for arg in arguments {
      let result = generateExpressionSSA(arg)
      if case .structure(let decl) = arg.type {
        if arg.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          buffer += "\(getCType(arg.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(result));\n"
          paramResults.append(copyResult)
        } else {
          paramResults.append(result)
        }
      } else if case .reference(_) = arg.type {
        if arg.valueCategory == .lvalue {
          addIndent()
          buffer += "__koral_retain(\(result).control);\n"
        }
        paramResults.append(result)
      } else {
        paramResults.append(result)
      }
    }
    
    // Intrinsic Implementation is now handled in .intrinsic AST node.
    // However, keeping this for backward compatibility if any old logic slipped through
    // or if we switch back.
    // But since we are cleaning up, we can remove the pointer checks from here as they should be intercepted
    // by AST generation.
    // If we missed something in AST transform, this might be dead code.
    
    addIndent()
    if type == .void || type == .never {
      buffer += "\(identifier.qualifiedName)("
      buffer += paramResults.joined(separator: ", ")
      buffer += ");\n"
      return ""
    } else {
      let result = nextTemp()
      buffer += "\(getCType(type)) \(result) = \(identifier.qualifiedName)("
      buffer += paramResults.joined(separator: ", ")
      buffer += ");\n"
      return result
    }
  }

  private func generateMemberPath(_ source: TypedExpressionNode, _ path: [Symbol]) -> String {
    let sourceResult = generateExpressionSSA(source)
    var access = sourceResult
    var curType = source.type
    for member in path {
      var memberAccess: String
      if case .reference(let inner) = curType {
          let innerCType = getCType(inner)
          memberAccess = "((\(innerCType)*)\(access).ptr)->\(member.name)"
      } else {
          memberAccess = "\(access).\(member.name)"
      }
      
      // Only apply type cast for non-reference struct members when the C types differ
      // This handles cases where generic type parameters are replaced with concrete types
      // but the C representation needs explicit casting
      if case .structure(let decl) = curType.canonical {
        if let canonicalMember = decl.members.first(where: { $0.name == member.name }) {
          // Compare C type representations instead of Type equality
          // This avoids issues with UUID-based type identity for generic instantiations
          let canonicalCType = getCType(canonicalMember.type)
          let memberCType = getCType(member.type)
          if canonicalCType != memberCType {
            // Skip cast for reference types - they all use struct Ref
            if case .reference(_) = member.type {
              // No cast needed for reference types
            } else {
              let targetCType = getCType(member.type)
              memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
            }
          }
        }
      }
      
      access = memberAccess
      curType = member.type
    }
    let result = nextTemp()
    addIndent()
    buffer += "\(getCType(path.last?.type ?? .void)) \(result) = \(access);\n"
    return result
  }
}
