// ParserTypes.swift
// Type parsing methods for the Koral compiler Parser

/// Extension containing all type parsing methods
extension Parser {
  
  // MARK: - Type Parsing

  /// Parse type identifier
  /// Supports:
  /// - Simple types: Int, String, Bool
  /// - Generic types: [T]List, [K, V]Map
  /// - Function types: [ParamType1, ParamType2, ReturnType]Func
  /// - Reference types: Int ref, [T]List ref
  /// - Self type: Self, Self ref
  /// - Module-qualified types: module.TypeName, module.[T]List
  func parseType() throws -> TypeNode {
    // Handle Self type
    if currentToken === .selfTypeKeyword {
      try match(.selfTypeKeyword)
      var type: TypeNode = .inferredSelf
      while true {
        if currentToken === .refKeyword {
          try match(.refKeyword)
          type = .reference(type)
          continue
        }
        if currentToken === .ptrKeyword {
          try match(.ptrKeyword)
          type = .pointer(type)
          continue
        }
        if currentToken === .weakrefKeyword {
          try match(.weakrefKeyword)
          type = .weakReference(type)
          continue
        }
        break
      }
      return type
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
        var type: TypeNode = .functionType(paramTypes: paramTypes, returnType: returnType)
        while true {
          if currentToken === .refKeyword {
            try match(.refKeyword)
            type = .reference(type)
            continue
          }
          if currentToken === .ptrKeyword {
            try match(.ptrKeyword)
            type = .pointer(type)
            continue
          }
          if currentToken === .weakrefKeyword {
            try match(.weakrefKeyword)
            type = .weakReference(type)
            continue
          }
          break
        }
        return type
      }


      // Regular generic type
      var type = TypeNode.generic(base: name, args: args)
      while true {
        if currentToken === .refKeyword {
          try match(.refKeyword)
          type = .reference(type)
          continue
        }
        if currentToken === .ptrKeyword {
          try match(.ptrKeyword)
          type = .pointer(type)
          continue
        }
        if currentToken === .weakrefKeyword {
          try match(.weakrefKeyword)
          type = .weakReference(type)
          continue
        }
        break
      }
      return type
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
        
        var type = TypeNode.moduleQualifiedGeneric(module: name, base: typeName, args: args)
        while true {
          if currentToken === .refKeyword {
            try match(.refKeyword)
            type = .reference(type)
            continue
          }
          if currentToken === .ptrKeyword {
            try match(.ptrKeyword)
            type = .pointer(type)
            continue
          }
          if currentToken === .weakrefKeyword {
            try match(.weakrefKeyword)
            type = .weakReference(type)
            continue
          }
          break
        }
        return type
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
      
      var type: TypeNode = .moduleQualified(module: name, name: typeName)
      while true {
        if currentToken === .refKeyword {
          try match(.refKeyword)
          type = .reference(type)
          continue
        }
        if currentToken === .ptrKeyword {
          try match(.ptrKeyword)
          type = .pointer(type)
          continue
        }
        if currentToken === .weakrefKeyword {
          try match(.weakrefKeyword)
          type = .weakReference(type)
          continue
        }
        break
      }
      return type
    }

    // Simple type - must start with uppercase
    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }

    var type: TypeNode = .identifier(name)

    // Handle reference/pointer/weakref type suffix
    while true {
      if currentToken === .refKeyword {
        try match(.refKeyword)
        type = .reference(type)
        continue
      }
      if currentToken === .ptrKeyword {
        try match(.ptrKeyword)
        type = .pointer(type)
        continue
      }
      if currentToken === .weakrefKeyword {
        try match(.weakrefKeyword)
        type = .weakReference(type)
        continue
      }
      break
    }

    return type
  }
}
