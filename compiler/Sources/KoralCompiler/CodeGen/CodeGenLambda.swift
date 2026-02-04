// MARK: - Lambda Expression Code Generation Extension

extension CodeGen {
  
  /// Generates a unique Lambda function name
  func nextLambdaName() -> String {
    let name = "__koral_lambda_\(lambdaCounter)"
    lambdaCounter += 1
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
      let result = nextTemp()
      addIndent()
      appendToBuffer("struct __koral_Closure \(result) = { .fn = (void*)\(lambdaName), .env = NULL, .drop = NULL };\n")
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
      appendToBuffer("struct \(envStructName)* \(envVar) = (struct \(envStructName)*)malloc(sizeof(struct \(envStructName)));\n")
      addIndent()
      appendToBuffer("\(envVar)->__refcount = 1;\n")
      
      // Initialize captured variables
      for capture in captures {
        let capturedName = qualifiedName(for: capture.symbol)
        appendCopyAssignment(
          for: capture.symbol.type,
          source: capturedName,
          dest: "\(envVar)->\(capturedName)",
          indent: indent
        )
      }
      
      // Create closure struct
      let result = nextTemp()
      addIndent()
      appendToBuffer("struct __koral_Closure \(result) = { .fn = (void*)\(lambdaName), .env = \(envVar), .drop = __koral_\(envStructName)_drop };\n")
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
    
    // Generate local aliases for captured variables
    for capture in captures {
      let capturedName = qualifiedName(for: capture.symbol)
      let capturedType = cTypeName(capture.symbol.type)
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
  
  /// Generates the environment struct for a Lambda with captures
  func generateLambdaEnvStruct(name: String, captures: [CapturedVariable]) {
    var structBuffer = "\n// Lambda environment struct\n"
    structBuffer += "struct \(name) {\n"
    structBuffer += "  intptr_t __refcount;\n"
    
    for capture in captures {
      let capturedName = qualifiedName(for: capture.symbol)
      let capturedType = cTypeName(capture.symbol.type)
      structBuffer += "  \(capturedType) \(capturedName);\n"
    }
    
    structBuffer += "};\n"

    structBuffer += "\nstatic void __koral_\(name)_drop(void* raw_env) {\n"
    structBuffer += "  struct \(name)* env = (struct \(name)*)raw_env;\n"
    for capture in captures {
      let capturedName = qualifiedName(for: capture.symbol)
      let valuePath = "env->\(capturedName)"
      switch capture.symbol.type {
      case .function:
        structBuffer += "  __koral_closure_release(\(valuePath));\n"
      case .structure(let defId):
        if !context.isForeignStruct(defId) {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          structBuffer += "  __koral_\(typeName)_drop(&\(valuePath));\n"
        }
      case .union(let defId):
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
        structBuffer += "  __koral_\(typeName)_drop(&\(valuePath));\n"
      default:
        let dropCode = TypeHandlerRegistry.shared.generateDropCode(capture.symbol.type, value: valuePath)
        if !dropCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          structBuffer += "  \(dropCode)\n"
        }
      }
    }
    structBuffer += "  free(env);\n"
    structBuffer += "}\n"
    
    // Add to Lambda env structs buffer
    lambdaEnvStructs += structBuffer
  }
}
