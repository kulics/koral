// MARK: - Lambda Expression Code Generation Extension

extension CodeGen {
  
  /// Generates a unique Lambda function name
  func nextLambdaName() -> String {
    let name = "__koral_lambda_\(lambdaCounter)"
    lambdaCounter += 1
    return name
  }
  
  /// Returns the raw C identifier for a symbol, bypassing capture aliases.
  /// Used for env struct field names and env initialization.
  func rawQualifiedName(for symbol: Symbol) -> String {
    // Temporarily clear aliases to get the base name
    let saved = capturedVarAliases[symbol.defId.id]
    capturedVarAliases[symbol.defId.id] = nil
    let name = qualifiedName(for: symbol)
    capturedVarAliases[symbol.defId.id] = saved
    return name
  }
  
  /// Generates code for a Lambda expression
  /// Returns the name of a temporary variable holding the Closure struct
  func generateLambdaExpression(
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
      let result = nextTempWithInit(cType: "struct __koral_Closure", initExpr: "{ .fn = (void*)\(lambdaName), .env = NULL, .drop = NULL }")
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
      let envVar = nextTempWithInit(cType: "struct \(envStructName)*", initExpr: "(struct \(envStructName)*)malloc(sizeof(struct \(envStructName)))")
      addIndent()
      appendToBuffer("\(envVar)->__refcount = 1;\n")
      
      // Initialize captured variables according to semantic capture kind.
      // byValue: copy value; byReference: copy reference value (retain).
      for capture in captures {
        let capturedName = rawQualifiedName(for: capture.symbol)
        let currentExpr = qualifiedName(for: capture.symbol)
        addIndent()
        appendCopyAssignment(for: capture.symbol.type, source: currentExpr, dest: "\(envVar)->\(capturedName)", indent: "")
      }
      
      // Create closure struct
      let result = nextTempWithInit(cType: "struct __koral_Closure", initExpr: "{ .fn = (void*)\(lambdaName), .env = \(envVar), .drop = __koral_\(envStructName)_drop }")
      return result
    }
  }
  
  /// Generates a no-capture Lambda function
  func generateNoCaptureLabmdaFunction(
    name: String,
    parameters: [Symbol],
    funcParams: [Parameter],
    returnType: Type,
    body: TypedExpressionNode
  ) {
    let returnCType = cTypeName(returnType)
    
    // Build parameter list
    var paramList: [String] = []
    for (i, param) in parameters.enumerated() {
      let paramType = funcParams[i].type
      paramList.append("\(cTypeName(paramType)) \(qualifiedName(for: param))")
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
      appendToBuffer("return \(bodyResult);\n")
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
  func generateCaptureLabmdaFunction(
    name: String,
    envStructName: String,
    parameters: [Symbol],
    funcParams: [Parameter],
    returnType: Type,
    captures: [CapturedVariable],
    body: TypedExpressionNode
  ) {
    let returnCType = cTypeName(returnType)
    
    // Build parameter list (env as first parameter)
    var paramList: [String] = ["void* __env"]
    for (i, param) in parameters.enumerated() {
      let paramType = funcParams[i].type
      paramList.append("\(cTypeName(paramType)) \(qualifiedName(for: param))")
    }
    
    let paramsStr = paramList.joined(separator: ", ")
    
    // Generate forward declaration and function
    var funcBuffer = "\n// Lambda function (with capture)\n"
    funcBuffer += "static \(returnCType) \(name)(\(paramsStr));\n"
    funcBuffer += "static \(returnCType) \(name)(\(paramsStr)) {\n"
    funcBuffer += "  struct \(envStructName)* __captured = (struct \(envStructName)*)__env;\n"
    
    // No local aliases — captured variables are accessed via __captured-> pointers
    // through the capturedVarAliases mechanism in qualifiedName().
    
    // Save current state
    let savedBuffer = buffer
    let savedIndent = indent
    let savedLambdaCounter = lambdaCounter
    let savedLambdaFunctions = lambdaFunctions
    let savedCapturedVarAliases = capturedVarAliases
    buffer = ""
    indent = "  "
    lambdaFunctions = ""
    
    // Set up capture aliases so qualifiedName() resolves captured vars
    // through env fields.
    for capture in captures {
      let fieldName = rawQualifiedName(for: capture.symbol)
      capturedVarAliases[capture.symbol.defId.id] = "__captured->\(fieldName)"
    }
    
    // Generate body
    let bodyResult = generateExpressionSSA(body)
    
    if returnType != .void && returnType != .never {
      addIndent()
      appendToBuffer("return \(bodyResult);\n")
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
    capturedVarAliases = savedCapturedVarAliases
    
    // Add to Lambda functions buffer
    lambdaFunctions = savedLambdaFunctions + funcBuffer
  }
  /// Generates the environment struct for a Lambda with captures.
  /// Captures are stored as owned values in the env and dropped in env dtor.
  func generateLambdaEnvStruct(name: String, captures: [CapturedVariable]) {
    func appendIndented(_ code: String, to buffer: inout String, indent: String) {
      let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
      for line in lines {
        buffer += "\(indent)\(line)\n"
      }
    }

    func dropCodeForCapturedField(_ type: Type, fieldExpr: String) -> String {
      switch type {
      case .function:
        return "__koral_closure_release(\(fieldExpr));\n"
      case .structure(let defId):
        if context.isForeignStruct(defId) { return "" }
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        return "__koral_\(typeName)_drop(&\(fieldExpr));\n"
      case .union(let defId):
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
        return "__koral_\(typeName)_drop(&\(fieldExpr));\n"
      default:
        return TypeHandlerRegistry.shared.generateDropCode(type, value: fieldExpr)
      }
    }

    var structBuffer = "\n// Lambda environment struct\n"
    structBuffer += "struct \(name) {\n"
    structBuffer += "  _Atomic intptr_t __refcount;\n"
    
    for capture in captures {
      let capturedName = rawQualifiedName(for: capture.symbol)
      let capturedType = cTypeName(capture.symbol.type)
      structBuffer += "  \(capturedType) \(capturedName);\n"
    }
    
    structBuffer += "};\n"

    // Drop function: release/drop all captured fields, then free env struct.
    structBuffer += "\nstatic void __koral_\(name)_drop(void* raw_env) {\n"
    structBuffer += "  struct \(name)* env = (struct \(name)*)raw_env;\n"
    for capture in captures {
      let capturedName = rawQualifiedName(for: capture.symbol)
      let fieldExpr = "env->\(capturedName)"
      let dropCode = dropCodeForCapturedField(capture.symbol.type, fieldExpr: fieldExpr)
      appendIndented(dropCode, to: &structBuffer, indent: "  ")
    }
    structBuffer += "  free(raw_env);\n"
    structBuffer += "}\n"
    
    // Add to Lambda env structs buffer
    lambdaEnvStructs += structBuffer
  }
}
