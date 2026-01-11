public class CodeGen {
  private let ast: TypedProgram
  private var indent: String = ""
  private var buffer: String = ""
  private var tempVarCounter = 0
  private var globalInitializations: [(String, TypedExpressionNode)] = []
  private var lifetimeScopeStack: [[(name: String, type: Type, consumed: Bool)]] = []
  private var userDefinedDrops: [String: String] = [:] // TypeName -> Mangled Drop Function Name

  private struct LoopContext {
    let startLabel: String
    let endLabel: String
    let scopeIndex: Int
  }
  private var loopStack: [LoopContext] = []

  public init(ast: TypedProgram) {
    self.ast = ast
  }

  private func pushScope() {
    lifetimeScopeStack.append([])
  }

  private func popScopeWithoutCleanup() {
    _ = lifetimeScopeStack.popLast()
  }

  private func popScope() {
    let vars = lifetimeScopeStack.removeLast()
    // 反向遍历变量列表,对可变类型变量调用 destroy
    for (name, type, consumed) in vars.reversed() {
      if consumed { continue }
      if case .structure(let typeName, _, _, _) = type {
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(name));\n"
      } else if case .union(let typeName, _, _, _) = type {
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(name));\n"
      } else if case .reference(_) = type {
        addIndent()
        buffer += "__koral_release(\(name).control);\n"
      }
    }
  }

  private func emitCleanup(fromScopeIndex startIndex: Int) {
    guard !lifetimeScopeStack.isEmpty else { return }
    let clampedStart = max(0, min(startIndex, lifetimeScopeStack.count - 1))

    for scopeIndex in stride(from: lifetimeScopeStack.count - 1, through: clampedStart, by: -1) {
      let vars = lifetimeScopeStack[scopeIndex]
      for (name, type, consumed) in vars.reversed() {
        if consumed { continue }
        if case .structure(let typeName, _, _, _) = type {
          addIndent()
          buffer += "__koral_\(typeName)_drop(&\(name));\n"
        } else if case .union(let typeName, _, _, _) = type {
          addIndent()
          buffer += "__koral_\(typeName)_drop(&\(name));\n"
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
    for (name, type, consumed) in vars.reversed() {
      if consumed { continue }
      if case .structure(let typeName, _, _, _) = type {
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(name));\n"
      } else if case .union(let typeName, _, _, _) = type {
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(name));\n"
      } else if case .reference(_) = type {
        addIndent()
        buffer += "__koral_release(\(name).control);\n"
      }
    }
  }

  private func registerVariable(_ name: String, _ type: Type) {
    lifetimeScopeStack[lifetimeScopeStack.count - 1].append((name: name, type: type, consumed: false))
  }

  // Consume a variable from the scope (mark as moved so it won't be dropped)
  private func consumeVariable(_ name: String) {
    for scopeIndex in (0..<lifetimeScopeStack.count).reversed() {
       if let index = lifetimeScopeStack[scopeIndex].lastIndex(where: { $0.name == name }) {
           var entry = lifetimeScopeStack[scopeIndex][index]
           entry.consumed = true
           lifetimeScopeStack[scopeIndex][index] = entry
           return
       }
    }
  }


  public func generate() -> String {
    buffer = """
      #include <stdio.h>
      #include <stdlib.h>
      #include <stdatomic.h>
      #include <string.h>
      #include <stdint.h>

      // Generic Ref type
      struct Ref { void* ptr; void* control; };

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
    return buffer
  }

  private func generateProgram(_ program: TypedProgram) {
    switch program {
    case .program(let nodes):
      // Pass 0: Scan for user-defined drops
      for node in nodes {
        if case .givenDeclaration(let type, let methods) = node {
             var typeName: String?
             if case .structure(let name, _, _, _) = type { typeName = name }
             if case .union(let name, _, _, _) = type { typeName = name }

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

      // 先生成所有类型声明
      for node in nodes {
        if case .globalStructDeclaration(let identifier, let parameters) = node {
          generateTypeDeclaration(identifier, parameters)
        }
        if case .globalUnionDeclaration(let identifier, let cases) = node {
          generateUnionDeclaration(identifier, cases)
        }
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
          switch value {
          case .integerLiteral(_, _), .floatLiteral(_, _),
            .stringLiteral(_, _), .booleanLiteral(_, _):
            buffer += "\(cType) \(identifier.name) = "
            buffer += generateExpressionSSA(value)
            buffer += ";\n"
          default:
            // 复杂表达式延迟到 main 函数中初始化
            buffer += "\(cType) \(identifier.name);\n"
            globalInitializations.append((identifier.name, value))
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
    let returnType = identifier.name == "main" ? "int" : getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
    buffer += "\(returnType) \(identifier.name)(\(paramList));\n"
  }

  private func generateGlobalFunction(
    _ identifier: Symbol,
    _ params: [Symbol],
    _ body: TypedExpressionNode
  ) {
    let returnType = identifier.name == "main" ? "int" : getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
    buffer += "\(returnType) \(identifier.name)(\(paramList)) {\n"

    withIndent {
      generateFunctionBody(body, params)
    }
    buffer += "}\n"
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
    let result = nextTemp()
    if case .structure(let typeName, _, _, _) = body.type {
      addIndent()
      if body.valueCategory == .lvalue {
        buffer += "\(getCType(body.type)) \(result) = __koral_\(typeName)_copy(&\(resultVar));\n"
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
      return identifier.name

    case .blockExpression(let statements, let finalExpr, _):
      return generateBlockScope(statements, finalExpr: finalExpr)

    case .arithmeticExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let result = nextTemp()
      addIndent()
      buffer +=
        "\(getCType(type)) \(result) = \(leftResult) \(arithmeticOpToC(op)) \(rightResult);\n"
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
          if case .structure(let typeName, _, _, _) = type {
            addIndent()
            if body.valueCategory == .lvalue {
              buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(bodyResultVar));\n"
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

      if type == .void {
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
              buffer += "\(resultVar) = \(thenResult);\n"
              if case .reference(_) = type, thenBranch.valueCategory == .lvalue {
                addIndent()
                buffer += "__koral_retain(\(resultVar).control);\n"
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
              buffer += "\(resultVar) = \(elseResult);\n"
              if case .reference(_) = type, elseBranch.valueCategory == .lvalue {
                addIndent()
                buffer += "__koral_retain(\(resultVar).control);\n"
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
    case .methodReference:
      fatalError("Method reference not in call position is not supported yet")
      
    case .unionConstruction(let type, let caseName, let args):
      return generateUnionConstructor(type: type, caseName: caseName, args: args)

    case .derefExpression(let inner, let type):
      let innerResult = generateExpressionSSA(inner)
      let result = nextTemp()
      
      addIndent()
      buffer += "\(getCType(type)) \(result);\n"
      
      if case .structure(let typeName, _, _, _) = type {
        // Struct: call copy constructor
        addIndent()
        buffer += "\(result) = __koral_\(typeName)_copy((struct \(typeName)*)\(innerResult).ptr);\n"
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
      if inner.valueCategory == .lvalue {
        // 取引用：构造 Ref 结构体
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
        // 堆分配：构造 Ref 结构体
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
        if case .structure(let typeName, _, _, _) = innerType {
          addIndent()
          buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(typeName)_copy(&\(innerResult));\n"
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
        if case .structure(let typeName, _, _, _) = innerType {
          addIndent()
          buffer += "((struct Koral_Control*)\(result).control)->dtor = __koral_\(typeName)_drop;\n"
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

    case .typeConstruction(let identifier, let arguments, _):
      let result = nextTemp()
      var argResults: [String] = []
      
      // Get canonical members to check for casts
      let canonicalMembers: [(name: String, type: Type, mutable: Bool)]
      if case .structure(_, let members, _, _) = identifier.type.canonical {
          canonicalMembers = members
      } else {
          canonicalMembers = []
      }
      
      for (index, arg) in arguments.enumerated() {
        let argResult = generateExpressionSSA(arg)
        var finalArg = argResult

        if case .structure(let typeName, _, _, _) = arg.type {
          addIndent()
          let argCopy = nextTemp()
          if arg.valueCategory == .lvalue {
            buffer += "\(getCType(arg.type)) \(argCopy) = __koral_\(typeName)_copy(&\(argResult));\n"
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
          callee: .methodReference(base: base, method: method, type: method.type),
          arguments: args,
          type: returns)
        return generateExpressionSSA(callNode)

    case .intrinsicCall(let node):
      return generateIntrinsicSSA(node)
    }
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
      buffer += "*(\(cType)*)\(p) = \(v);\n"
      return ""

    case .ptrDeinit(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      if case .reference(_) = element {
        addIndent()
        buffer += "__koral_release(((struct Ref*)\(p))->control);\n"
      } else if case .structure(let name, _, _, _) = element {
        if name == "String" {  // String is primitive struct
          addIndent()
          buffer += "__koral_String_drop(\(p));\n"
        } else {
          addIndent()
          buffer += "__koral_\(name)_drop(\(p));\n"
        }
      }
      // int/float/bool/void -> noop
      return ""

    case .ptrPeek(let ptr):
      guard case .pointer(_) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let result = nextTemp()
      addIndent()
      buffer += "struct Ref \(result);\n"
      addIndent()
      buffer += "\(result).ptr = \(p);\n"
      addIndent()
      buffer += "\(result).control = NULL;\n"  // Unowned
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
      buffer += "*(\(cType)*)\(p) = \(v);\n"
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

    case .printString(let msg):
      let m = generateExpressionSSA(msg)
      // Access StringStorage through the ref inside String
      let storageVar = nextTemp()
      addIndent()
      buffer += "struct StringStorage* \(storageVar) = (struct StringStorage*)\(m).storage.ptr;\n"
      addIndent()
      buffer += "printf(\"%.*s\\n\", (int)\(storageVar)->len, (const char*)\(storageVar)->data);\n"
      return ""
    case .printInt(let val):
      let v = generateExpressionSSA(val)
      addIndent()
      buffer += "printf(\"%lld\\n\", \(v));\n"
      return ""
    case .printBool(let val):
      let v = generateExpressionSSA(val)
      addIndent()
      buffer += "printf(\"%s\\n\", \(v) ? \"true\" : \"false\");\n"
      return ""
    case .panic(let msg):
      let m = generateExpressionSSA(msg)
      let storageVar = nextTemp()
      addIndent()
      buffer += "struct StringStorage* \(storageVar) = (struct StringStorage*)\(m).storage.ptr;\n"
      addIndent()
      buffer += "fprintf(stderr, \"Panic: %.*s\\n\", (int)\(storageVar)->len, (const char*)\(storageVar)->data);\n"
      addIndent()
      buffer += "exit(1);\n"
      return ""

    case .exit(let code):
      let c = generateExpressionSSA(code)
      addIndent()
      buffer += "exit(\(c));\n"
      return ""

    case .abort:
      addIndent()
      buffer += "abort();\n"
      return ""
    }
  }

  // 构建引用组件：返回 (访问路径, 控制块指针)
  private func buildRefComponents(_ expr: TypedExpressionNode) -> (path: String, control: String) {
    switch expr {
    case .variable(let identifier):
      let path = identifier.name
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
    case .subscriptExpression(let base, let args, let method, _):
         guard case .function(_, let returns) = method.type else { fatalError() }
         let callNode = TypedExpressionNode.call(
             callee: .methodReference(base: base, method: method, type: method.type),
             arguments: args,
             type: returns)
         let refResult = generateExpressionSSA(callNode)
         
         // Return the Ref structure itself. 
         // Caller (e.g. memberPath) will handle unwrapping .ptr if the type is Reference.
         return (refResult, "\(refResult).control")

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
      // void 类型的值不能赋给变量
      if value.type != .void {
        // 如果是可变类型，增加引用计数
        if case .structure(let typeName, _, _, _) = identifier.type {
          addIndent()
          buffer += "\(getCType(identifier.type)) \(identifier.name) = "
          if value.valueCategory == .lvalue {
            buffer += "__koral_\(typeName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(valueResult);\n"
          }
          registerVariable(identifier.name, identifier.type)
        } else if case .union(let typeName, _, _, _) = identifier.type {
          addIndent()
          buffer += "\(getCType(identifier.type)) \(identifier.name) = "
          if value.valueCategory == .lvalue {
            buffer += "__koral_\(typeName)_copy(&\(valueResult));\n"
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
      // Use buildRefComponents to get the C LValue path
      let (lhsPath, _) = buildRefComponents(target)
      let valueResult = generateExpressionSSA(value)
      
      if value.type == .void { return }

      if case .structure(let typeName, _, _, _) = target.type {
        addIndent()
        if value.valueCategory == .lvalue {
           buffer += "\(lhsPath) = __koral_\(typeName)_copy(&\(valueResult));\n"
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
        let valueResult = generateExpressionSSA(value)
        let retVar = nextTemp()

        if case .structure(let typeName, _, _, _) = value.type {
          addIndent()
          if value.valueCategory == .lvalue {
            buffer += "\(getCType(value.type)) \(retVar) = __koral_\(typeName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(getCType(value.type)) \(retVar) = \(valueResult);\n"
          }
        } else if case .union(let typeName, _, _, _) = value.type {
          addIndent()
          if value.valueCategory == .lvalue {
            buffer += "\(getCType(value.type)) \(retVar) = __koral_\(typeName)_copy(&\(valueResult));\n"
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
    }
  }

  private func arithmeticOpToC(_ op: ArithmeticOperator) -> String {
    switch op {
    case .plus: return "+"
    case .minus: return "-"
    case .multiply: return "*"
    case .divide: return "/"
    case .modulo: return "%"
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
      fatalError("Function type not supported in getCType")
    case .structure(let name, _, _, _):
      return "struct \(name)"
    case .union(let name, _, _, _):
      return "struct \(name)"
    case .genericParameter(let name):
      fatalError("Generic parameter \(name) should be resolved before CodeGen")
    case .reference(_):
      return "struct Ref"
    case .pointer(_):
        return "void*"
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
    let name = identifier.name
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
        if case .structure(let fieldTypeName, _, _, _) = param.type {
          buffer += "    result.\(param.name) = __koral_\(fieldTypeName)_copy(&self->\(param.name));\n"
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
        if case .structure(let fieldTypeName, _, _, _) = param.type {
          buffer += "    __koral_\(fieldTypeName)_drop(&self->\(param.name));\n"
        } else if case .reference(_) = param.type {
          buffer += "    __koral_release(self->\(param.name).control);\n"
        }
      }
    }
    buffer += "}\n\n"
  }

  private func generateUnionDeclaration(_ identifier: Symbol, _ cases: [UnionCase]) {
    let name = identifier.name
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
                     if case .structure(let fieldTypeName, _, _, _) = param.type {
                         buffer += "        \(resultPath) = __koral_\(fieldTypeName)_copy(&\(fieldPath));\n"
                     } else if case .union(let fieldTypeName, _, _, _) = param.type {
                        buffer += "        \(resultPath) = __koral_\(fieldTypeName)_copy(&\(fieldPath));\n"
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
                 if case .structure(let fieldTypeName, _, _, _) = param.type {
                     buffer += "        __koral_\(fieldTypeName)_drop(&\(fieldPath));\n"
                 } else if case .union(let fieldTypeName, _, _, _) = param.type {
                     buffer += "        __koral_\(fieldTypeName)_drop(&\(fieldPath));\n"
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
      guard case .union(let typeName, let cases, _, _) = type else { fatalError() }
      
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
              if case .structure(let structName, _, _, _) = param.type {
                   if argExpr.valueCategory == .lvalue {
                       buffer += "\(unionMemberPath).\(param.name) = __koral_\(structName)_copy(&\(argResult));\n"
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
    
    // Check for move semantics and consume variable from scope if necessary
    if !subject.type.isCopy {
        if case .variable(let identifier) = subject {
            consumeVariable(identifier.name)
        }
    }

    let endLabel = "match_end_\(nextTemp())"
    
    for c in cases {
         addIndent()
         buffer += "{\n"
         withIndent {
         let caseScopeIndex = lifetimeScopeStack.count
         pushScope()

         let isMove = !subject.type.isCopy
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
             if case .structure(let typeName, _, _, _) = type {
              if c.body.valueCategory == .lvalue {
                 buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(bodyResult));\n"
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
    return type != .void ? resultVar : ""
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
        // `String_equals` consumes (drops) both arguments. In match conditions we must pass
        // copies so we don't consume the subject value or double-drop the prelude literal.
        return ([prelude], [(literalVar, type)], "String_equals(__koral_String_copy(&\(path)), __koral_String_copy(&\(literalVar)))", [], [])
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
          if case .structure(let typeName, _, _, _) = varType {
             bindCode += "\(name) = __koral_\(typeName)_copy(&\(path));\n"
          } else if case .reference(_) = varType {
             bindCode += "\(name) = \(path);\n"
             bindCode += "__koral_retain(\(name).control);\n"
          } else {
             bindCode += "\(name) = \(path);\n"
          }
        }
        return ([], [], "1", [bindCode], [(name, varType)])
          
      case .unionCase(let caseName, let expectedTagIndex, let args):
        guard case .union(_, let cases, _, _) = type else { fatalError("Union pattern on non-union type") }
          
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
        if case .structure(let typeName, _, _, _) = finalExpr.type {
          if finalExpr.valueCategory == .lvalue {
            // Returning an lvalue struct from a block:
            // - Copy types must be copied, because scope cleanup will drop the original.
            // - Move types can be moved, but we must mark the source variable as consumed.
            switch finalExpr {
            case .variable(let symbol) where !symbol.type.isCopy:
              addIndent()
              buffer += "\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n"
              consumeVariable(symbol.name)
            default:
              addIndent()
              buffer += "\(getCType(finalExpr.type)) \(resultVar) = __koral_\(typeName)_copy(&\(temp));\n"
            }
          } else {
            addIndent()
            buffer += "\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n"
          }
        } else if case .union(let typeName, _, _, _) = finalExpr.type {
          if finalExpr.valueCategory == .lvalue {
            switch finalExpr {
            case .variable(let symbol) where !symbol.type.isCopy:
              addIndent()
              buffer += "\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n"
              consumeVariable(symbol.name)
            default:
              addIndent()
              buffer += "\(getCType(finalExpr.type)) \(resultVar) = __koral_\(typeName)_copy(&\(temp));\n"
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
    if value.type == .void {
      _ = generateExpressionSSA(value)
      return
    }
    let valueResult = generateExpressionSSA(value)
    if case .structure(let typeName, _, _, _) = identifier.type {
      if value.valueCategory == .lvalue {
        let copyResult = nextTemp()
        addIndent()
        buffer += "\(getCType(value.type)) \(copyResult) = __koral_\(typeName)_copy(&\(valueResult));\n"
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(identifier.name));\n"
        addIndent()
        buffer += "\(identifier.name) = \(copyResult);\n"
      } else {
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(identifier.name));\n"
        addIndent()
        buffer += "\(identifier.name) = \(valueResult);\n"
      }
    } else if case .union(let typeName, _, _, _) = identifier.type {
      if value.valueCategory == .lvalue {
        let copyResult = nextTemp()
        addIndent()
        buffer += "\(getCType(value.type)) \(copyResult) = __koral_\(typeName)_copy(&\(valueResult));\n"
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(identifier.name));\n"
        addIndent()
        buffer += "\(identifier.name) = \(copyResult);\n"
      } else {
        addIndent()
        buffer += "__koral_\(typeName)_drop(&\(identifier.name));\n"
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
    if value.type == .void {
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
      
      if case .structure(_, let members, _, _) = curType.canonical {
        if let canonicalMember = members.first(where: { $0.name == memberName }) {
          if canonicalMember.type != memberType {
            let targetCType = getCType(memberType)
            memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
          }
        }
      }
      
      accessPath = memberAccess
      curType = memberType
      
      if isLast, case .structure(let typeName, _, _, _) = memberType {
        if value.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          buffer += "\(getCType(value.type)) \(copyResult) = __koral_\(typeName)_copy(&\(valueResult));\n"
          addIndent()
          buffer += "__koral_\(typeName)_drop(&\(accessPath));\n"
          addIndent()
          buffer += "\(accessPath) = \(copyResult);\n"
        } else {
          addIndent()
          buffer += "__koral_\(typeName)_drop(&\(accessPath));\n"
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
    if case .methodReference(let base, let method, _) = callee {
      var allArgs = [base]
      allArgs.append(contentsOf: arguments)
      return generateFunctionCall(method, allArgs, type)
    }

    if case .variable(let identifier) = callee {
      return generateFunctionCall(identifier, arguments, type)
    }

    fatalError("Indirect call not supported yet")
  }

  private func generateFunctionCall(
    _ identifier: Symbol, _ arguments: [TypedExpressionNode], _ type: Type
  ) -> String {
    var paramResults: [String] = []
    // struct类型参数传递用值，isValue==false 的 struct 参数自动递归 copy
    for arg in arguments {
      let result = generateExpressionSSA(arg)
      if case .structure(let typeName, _, _, _) = arg.type {
        if arg.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          buffer += "\(getCType(arg.type)) \(copyResult) = __koral_\(typeName)_copy(&\(result));\n"
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
    if type == .void {
      buffer += "\(identifier.name)("
      buffer += paramResults.joined(separator: ", ")
      buffer += ");\n"
      return ""
    } else {
      let result = nextTemp()
      buffer += "\(getCType(type)) \(result) = \(identifier.name)("
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
      
      if case .structure(_, let members, _, _) = curType.canonical {
        if let canonicalMember = members.first(where: { $0.name == member.name }) {
          if canonicalMember.type != member.type {
            let targetCType = getCType(member.type)
            memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
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
