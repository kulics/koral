// ParserTypes.swift
// Type parsing methods for the Koral compiler Parser

/// Extension containing all type parsing methods
extension Parser {

  private func parseTypeSuffixes(for base: TypeNode) throws -> TypeNode {
    var type = base
    while true {
      if currentToken === .mutKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .refKeyword {
          try match(.mutKeyword)
          try match(.refKeyword)
          type = .reference(type, mutable: true)
          continue
        }
        if nextToken === .ptrKeyword {
          try match(.mutKeyword)
          try match(.ptrKeyword)
          type = .pointer(type, mutable: true)
          continue
        }
        if nextToken === .weakrefKeyword {
          try match(.mutKeyword)
          try match(.weakrefKeyword)
          type = .weakReference(type, mutable: true)
          continue
        }
      }
      if currentToken === .refKeyword {
        try match(.refKeyword)
        type = .reference(type, mutable: false)
        continue
      }
      if currentToken === .ptrKeyword {
        try match(.ptrKeyword)
        type = .pointer(type, mutable: false)
        continue
      }
      if currentToken === .weakrefKeyword {
        try match(.weakrefKeyword)
        type = .weakReference(type, mutable: false)
        continue
      }
      break
    }
    return type
  }
  
  // MARK: - Type Parsing

  /// Parse type identifier
  /// Supports:
  /// - Simple types: Int, String, Bool
  /// - Generic types: [T]List, [K, V]Dict
  /// - Function types: [ParamType1, ParamType2, ReturnType]Func
  /// - Reference types: Int ref, [T]List ref
  /// - Self type: Self, Self ref
  /// - Module-qualified types: module.TypeName, module.[T]List
  func parseType() throws -> TypeNode {
    // Handle Self type
    if currentToken === .selfTypeKeyword {
      try match(.selfTypeKeyword)
      return try parseTypeSuffixes(for: .inferredSelf)
    }
    
    // Handle generic types and function types: [...]TypeName
    if currentToken === .leftBracket {
      try match(.leftBracket)
      var args: [TypeNode] = []
      while currentToken !== .rightBracket {
        args.append(try parseType())
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightBracket)

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedTypeIdentifier(
          span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))

      // Check if this is a function type: [...]Func
      if name == "Func" {
        // Function type: [ParamType1, ParamType2, ..., ReturnType]Func
        // The last type is the return type, all others are parameter types
        guard !args.isEmpty else {
          throw ParserError.invalidFunctionType(
            span: currentSpan, message: "Function type must have at least a return type")
        }
        let returnType = args.last!
        let paramTypes = Array(args.dropLast())
        return try parseTypeSuffixes(for: .functionType(paramTypes: paramTypes, returnType: returnType))
      }


      // Regular generic type
      return try parseTypeSuffixes(for: .generic(base: name, args: args))
    }

    // Handle simple type identifier or module-qualified type
    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(
        span: currentSpan, got: currentToken.description)
    }
    try match(.identifier(name))
    
    // Check for module-qualified type: module.TypeName or module.[T]List
    if currentToken === .dot {
      // This is a module-qualified type
      try match(.dot)
      
      // Check for generic type after module prefix: module.[T]List
      if currentToken === .leftBracket {
        try match(.leftBracket)
        var args: [TypeNode] = []
        while currentToken !== .rightBracket {
          args.append(try parseType())
          if currentToken === .comma {
            try match(.comma)
          }
        }
        try match(.rightBracket)
        
        guard case .identifier(let typeName) = currentToken else {
          throw ParserError.expectedTypeIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        
        if !isValidTypeName(typeName) {
          throw ParserError.invalidTypeName(span: currentSpan, name: typeName)
        }
        try match(.identifier(typeName))
        
        return try parseTypeSuffixes(for: .moduleQualifiedGeneric(module: name, base: typeName, args: args))
      }
      
      // Simple module-qualified type: module.TypeName
      guard case .identifier(let typeName) = currentToken else {
        throw ParserError.expectedTypeIdentifier(
          span: currentSpan, got: currentToken.description)
      }
      
      if !isValidTypeName(typeName) {
        throw ParserError.invalidTypeName(span: currentSpan, name: typeName)
      }
      try match(.identifier(typeName))
      
      return try parseTypeSuffixes(for: .moduleQualified(module: name, name: typeName))
    }

    // Simple type - must start with uppercase
    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }

    return try parseTypeSuffixes(for: .identifier(name))
  }
}
