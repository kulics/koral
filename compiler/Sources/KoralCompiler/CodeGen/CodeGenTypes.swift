// MARK: - Type Declaration Code Generation Extension

extension CodeGen {

  private func appendManagedNominalCopyFunction(name: String) {
    appendToBuffer("struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n")
    withIndent {
      appendToBuffer("    struct \(name) result = *self;\n")
      appendToBuffer("    if (result.control) { __koral_retain(result.control); }\n")
      appendToBuffer("    return result;\n")
    }
    appendToBuffer("}\n\n")
  }

  private func appendManagedNominalDropFunction(name: String) {
    appendToBuffer("void __koral_\(name)_drop(struct \(name)* self) {\n")
    withIndent {
      appendToBuffer("    if (self->control) { __koral_release(self->control); }\n")
    }
    appendToBuffer("}\n\n")
  }

  private func appendManagedNominalUserDropPrelude(name: String, userDrop: String) {
    appendToBuffer("    struct \(name) __koral_self;\n")
    appendToBuffer("    __koral_self.ptr = raw_payload;\n")
    appendToBuffer("    __koral_self.control = NULL;\n")
    appendToBuffer("    {\n")
    appendToBuffer("        void \(userDrop)(struct \(name)*);\n")
    appendToBuffer("        \(userDrop)(&__koral_self);\n")
    appendToBuffer("    }\n")
  }

  private func appendManagedStructPayloadDropFunction(name: String, payloadName: String, parameters: [Symbol]) {
    appendToBuffer("static void __koral_\(name)_payload_drop(void* raw_payload) {\n")
    withIndent {
      appendToBuffer("    struct \(payloadName)* self = (struct \(payloadName)*)raw_payload;\n")
      if let userDrop = getUserDefinedDrop(for: name) {
        appendManagedNominalUserDropPrelude(name: name, userDrop: userDrop)
      }
      for param in parameters {
        let fieldName = sanitizeCIdentifier(context.getName(param.defId) ?? "<unknown>")
        appendDropStatement(for: param.type, value: "self->\(fieldName)")
      }
    }
    appendToBuffer("}\n\n")
  }

  private func appendManagedEnumPayloadDropFunction(name: String, payloadName: String, cases: [EnumCase]) {
    appendToBuffer("static void __koral_\(name)_payload_drop(void* raw_payload) {\n")
    withIndent {
      appendToBuffer("    struct \(payloadName)* self = (struct \(payloadName)*)raw_payload;\n")
      if let userDrop = getUserDefinedDrop(for: name) {
        appendManagedNominalUserDropPrelude(name: name, userDrop: userDrop)
      }
      appendToBuffer("    switch (self->tag) {\n")
      for (index, c) in cases.enumerated() {
        let caseName = sanitizeCIdentifier(c.name)
        appendToBuffer("    case \(index): // \(c.name)\n")
        let nonVoidParams = c.parameters.filter { param in
          if case .void = param.type { return false }
          return true
        }
        for param in nonVoidParams {
          let fieldName = sanitizeCIdentifier(param.name)
          let fieldPath = "self->data.\(caseName).\(fieldName)"
          appendDropStatement(for: param.type, value: fieldPath)
        }
        appendToBuffer("        break;\n")
      }
      appendToBuffer("    }\n")
    }
    appendToBuffer("}\n\n")
  }

  private func generateManagedStructDeclaration(name: String, type: Type, parameters: [Symbol]) {
    let payloadName = managedPayloadTypeName(for: type)
    appendToBuffer("struct \(payloadName) {\n")
    withIndent {
      for param in parameters {
        addIndent()
        let paramName = context.getName(param.defId) ?? "<unknown>"
        appendToBuffer("\(cTypeName(param.type)) \(sanitizeCIdentifier(paramName));\n")
      }
    }
    appendToBuffer("};\n\n")
    appendManagedNominalCopyFunction(name: name)
    appendManagedStructPayloadDropFunction(name: name, payloadName: payloadName, parameters: parameters)
    appendManagedNominalDropFunction(name: name)
  }

  private func generateManagedEnumDeclaration(name: String, type: Type, cases: [EnumCase]) {
    let payloadName = managedPayloadTypeName(for: type)
    appendToBuffer("struct \(payloadName) {\n")
    withIndent {
      addIndent()
      appendToBuffer("intptr_t tag;\n")
      addIndent()
      appendToBuffer("union {\n")
      withIndent {
        for c in cases {
          let caseName = sanitizeCIdentifier(c.name)
          let nonVoidParams = c.parameters.filter { param in
            if case .void = param.type { return false }
            return true
          }
          if !nonVoidParams.isEmpty {
            addIndent()
            appendToBuffer("struct {\n")
            withIndent {
              for param in nonVoidParams {
                addIndent()
                appendToBuffer("\(cTypeName(param.type)) \(sanitizeCIdentifier(param.name));\n")
              }
            }
            addIndent()
            appendToBuffer("} \(caseName);\n")
          } else {
            addIndent()
            appendToBuffer("struct {} \(caseName);\n")
          }
        }
      }
      addIndent()
      appendToBuffer("} data;\n")
    }
    appendToBuffer("};\n\n")
    // For enums, pass nil parameters since enum fields are in cases (handled differently)
    appendManagedNominalCopyFunction(name: name)
    appendManagedEnumPayloadDropFunction(name: name, payloadName: payloadName, cases: cases)
    appendManagedNominalDropFunction(name: name)
  }
  
  /// Generate struct type declaration with copy and drop functions
  func generateTypeDeclaration(
    _ identifier: Symbol,
    _ parameters: [Symbol]
  ) {
    let name: String
    if case .structure(let defId) = identifier.type {
      name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
    } else {
      name = cIdentifier(for: identifier)
    }
    if case .structure(let defId) = identifier.type,
       context.isGenericInstantiation(defId) == true || (context.getTypeArguments(defId)?.isEmpty == false) {
      appendToBuffer("// Generic instantiation: \(context.getDebugName(identifier.type))\n")
    }

    if usesManagedNominalRepresentation(identifier.type) {
      generateManagedStructDeclaration(name: name, type: identifier.type, parameters: parameters)
      return
    }
    
    // Generate struct definition
    appendToBuffer("struct \(name) {\n")
    withIndent {
      for param in parameters {
        addIndent()
        let paramName = context.getName(param.defId) ?? "<unknown>"
        appendToBuffer("\(cTypeName(param.type)) \(sanitizeCIdentifier(paramName));\n")
      }
    }
    appendToBuffer("};\n\n")

    // Generate copy function
    appendToBuffer("struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n")
    withIndent {
      appendToBuffer("    struct \(name) result;\n")
      if isStringLikeStorage(name: name, parameters: parameters) {
        let dataField = sanitizeCIdentifier(context.getName(parameters.first(where: { context.getName($0.defId) == "data" })?.defId ?? parameters[0].defId) ?? "data")
        let lenField = sanitizeCIdentifier(context.getName(parameters.first(where: { context.getName($0.defId) == "len" })?.defId ?? parameters[1].defId) ?? "len")
        appendToBuffer("    size_t __koral_copy_len = self->\(lenField);\n")
        appendToBuffer("    result.\(dataField) = malloc(__koral_copy_len + 1);\n")
        appendToBuffer("    memcpy(result.\(dataField), self->\(dataField), __koral_copy_len);\n")
        appendToBuffer("    result.\(dataField)[__koral_copy_len] = 0;\n")
        appendToBuffer("    result.\(lenField) = self->\(lenField);\n")
      } else if isRawArrayLikeStorage(name: name, parameters: parameters) {
        let sourceField = sanitizeCIdentifier(context.getName(parameters.first(where: { context.getName($0.defId) == "source" })?.defId ?? parameters[0].defId) ?? "source")
        let lenField = sanitizeCIdentifier(context.getName(parameters.first(where: { context.getName($0.defId) == "len" })?.defId ?? parameters[1].defId) ?? "len")
        let capField = sanitizeCIdentifier(context.getName(parameters.first(where: { context.getName($0.defId) == "cap" })?.defId ?? parameters[2].defId) ?? "cap")
        let sourceParam = parameters.first(where: { context.getName($0.defId) == "source" })
        let sourceType = sourceParam?.type ?? .void
        let elementType: Type = {
          switch sourceType {
          case .pointer(let inner), .mutablePointer(let inner):
            return inner
          default:
            return sourceType
          }
        }()
        let elementTypeName: String
        switch elementType {
        case .structure(let defId):
          elementTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        case .`enum`(let defId):
          elementTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
        case .genericStruct(let template, let tplDefId, let args):
          elementTypeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
        case .genericEnum(let template, let tplDefId, let args):
          elementTypeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
        default:
          elementTypeName = cTypeName(elementType)
        }
        let mayUseCopyFunc: Bool = {
          switch elementType {
          case .structure, .`enum`, .genericStruct, .genericEnum:
            return true
          default:
            return false
          }
        }()
        if mayUseCopyFunc {
          let elementStorageType: String = {
            switch elementType {
            case .structure, .`enum`, .genericStruct, .genericEnum:
              return "struct \(elementTypeName)"
            default:
              return elementTypeName
            }
          }()
          appendToBuffer("    result.\(sourceField) = malloc(self->\(lenField) * sizeof(\(elementStorageType)));\n")
          appendToBuffer("    for (uintptr_t __koral_i = 0; __koral_i < self->\(lenField); ++__koral_i) {\n")
          withIndent {
            let copyPrefix = "__koral_\(nominalTypeCName(elementType))_copy"
            appendToBuffer("        result.\(sourceField)[__koral_i] = \(copyPrefix)(&(self->\(sourceField)[__koral_i]));\n")
          }
          appendToBuffer("    }\n")
        } else {
          appendToBuffer("    result.\(sourceField) = malloc(self->\(lenField) * sizeof(\(elementTypeName)));\n")
          appendToBuffer("    for (uintptr_t __koral_i = 0; __koral_i < self->\(lenField); ++__koral_i) {\n")
          withIndent {
            appendToBuffer("        result.\(sourceField)[__koral_i] = self->\(sourceField)[__koral_i];\n")
          }
          appendToBuffer("    }\n")
        }
        appendToBuffer("    result.\(lenField) = self->\(lenField);\n")
        appendToBuffer("    result.\(capField) = self->\(capField);\n")
      } else {
        for param in parameters {
          let fieldName = sanitizeCIdentifier(context.getName(param.defId) ?? "<unknown>")
          appendCopyAssignment(
            for: param.type,
            source: "self->\(fieldName)",
            dest: "result.\(fieldName)"
          )
        }
      }
      appendToBuffer("    return result;\n")
    }
    appendToBuffer("}\n\n")

    // Generate drop function
    appendToBuffer("void __koral_\(name)_drop(struct \(name)* self) {\n")
    withIndent {
      // Call user defined drop if exists
      if let userDrop = getUserDefinedDrop(for: name) {
          appendToBuffer("    {\n")
          appendToBuffer("        void \(userDrop)(struct \(name)*);\n")
          appendToBuffer("        \(userDrop)(self);\n")
          appendToBuffer("    }\n")
      }

      for param in parameters {
        let fieldName = sanitizeCIdentifier(context.getName(param.defId) ?? "<unknown>")
        appendDropStatement(for: param.type, value: "self->\(fieldName)")
      }
    }
    appendToBuffer("}\n\n")
  }

  private func isStringLikeStorage(name: String, parameters: [Symbol]) -> Bool {
    let names = parameters.map { context.getName($0.defId) ?? "" }
    return names.contains("data") && names.contains("len") && (name.contains("String") || name.contains("_String"))
  }

  private func isRawArrayLikeStorage(name: String, parameters: [Symbol]) -> Bool {
    let names = parameters.map { context.getName($0.defId) ?? "" }
    let hasSource = names.contains("source")
    let hasLen = names.contains("len")
    let hasCap = names.contains("cap")
    return hasSource && hasLen && hasCap && (name.contains("List_") || name.contains("Deque_") || name.contains("StringBuilder") || name.contains("Set_") || name.contains("Dict_"))
  }

  /// Generate enum type declaration with copy and drop functions
  func generateEnumDeclaration(_ identifier: Symbol, _ cases: [EnumCase]) {
    let name: String
    if case .`enum`(let defId) = identifier.type {
      name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
    } else {
      name = cIdentifier(for: identifier)
    }
    if case .`enum`(let defId) = identifier.type,
       context.isGenericInstantiation(defId) == true || (context.getTypeArguments(defId)?.isEmpty == false) {
      appendToBuffer("// Generic instantiation: \(context.getDebugName(identifier.type))\n")
    }

    if usesManagedNominalRepresentation(identifier.type) {
      generateManagedEnumDeclaration(name: name, type: identifier.type, cases: cases)
      return
    }

    appendToBuffer("struct \(name) {\n")
    withIndent {
      addIndent()
      appendToBuffer("intptr_t tag;\n")
      addIndent()
      appendToBuffer("union {\n")
      withIndent {
        for c in cases {
            let caseName = sanitizeCIdentifier(c.name)
            // Filter out Void type parameters - they don't need storage
            let nonVoidParams = c.parameters.filter { param in
                if case .void = param.type { return false }
                return true
            }
            if !nonVoidParams.isEmpty {
                addIndent()
                appendToBuffer("struct {\n")
                withIndent {
                    for param in nonVoidParams {
                        addIndent()
                        appendToBuffer("\(cTypeName(param.type)) \(sanitizeCIdentifier(param.name));\n")
                    }
                }
                addIndent()
                appendToBuffer("} \(caseName);\n")
            } else {
                 addIndent()
                 appendToBuffer("struct {} \(caseName);\n")
            }
        }
      }
      addIndent()
      appendToBuffer("} data;\n")
    }
    appendToBuffer("};\n\n")

    // Generate Copy
    appendToBuffer("struct \(name) __koral_\(name)_copy(const struct \(name) *self) {\n")
    withIndent {
        appendToBuffer("    struct \(name) result;\n")
        appendToBuffer("    result.tag = self->tag;\n")
        appendToBuffer("    switch (self->tag) {\n")
        for (index, c) in cases.enumerated() {
             let caseName = sanitizeCIdentifier(c.name)
             appendToBuffer("    case \(index): // \(c.name)\n")
             // Filter out Void type parameters
             let nonVoidParams = c.parameters.filter { param in
                 if case .void = param.type { return false }
                 return true
             }
             if !nonVoidParams.isEmpty {
                 for param in nonVoidParams {
                     let fieldName = sanitizeCIdentifier(param.name)
                     let fieldPath = "self->data.\(caseName).\(fieldName)"
                     let resultPath = "result.data.\(caseName).\(fieldName)"
                     appendCopyAssignment(
                       for: param.type,
                       source: fieldPath,
                       dest: resultPath
                     )
                 }
             }
             appendToBuffer("        break;\n")
        }
        appendToBuffer("    }\n")
        appendToBuffer("    return result;\n")
    }
    appendToBuffer("}\n\n")

    // Generate Drop
    appendToBuffer("void __koral_\(name)_drop(struct \(name)* self) {\n")
    withIndent {
        // Call user defined drop if exists
        if let userDrop = getUserDefinedDrop(for: name) {
            appendToBuffer("    {\n")
          appendToBuffer("        void \(userDrop)(struct \(name)*);\n")
            appendToBuffer("        \(userDrop)(self);\n")
            appendToBuffer("    }\n")
        }

        appendToBuffer("    switch (self->tag) {\n")
        for (index, c) in cases.enumerated() {
             let caseName = sanitizeCIdentifier(c.name)
             appendToBuffer("    case \(index): // \(c.name)\n")
             // Filter out Void type parameters
             let nonVoidParams = c.parameters.filter { param in
                 if case .void = param.type { return false }
                 return true
             }
             for param in nonVoidParams {
               let fieldName = sanitizeCIdentifier(param.name)
               let fieldPath = "self->data.\(caseName).\(fieldName)"
               appendDropStatement(for: param.type, value: fieldPath)
             }
             appendToBuffer("        break;\n")
        }
        appendToBuffer("    }\n")
    }
    appendToBuffer("}\n\n")
  }

  /// Generate foreign struct declaration without copy/drop
  func generateForeignStructDeclaration(
    _ identifier: Symbol,
    _ fields: [(name: String, type: Type)]
  ) {
    let name: String
    if case .structure(let defId) = identifier.type {
      name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
    } else {
      name = cIdentifier(for: identifier)
    }

    appendToBuffer("struct \(name) {\n")
    withIndent {
      for field in fields {
        addIndent()
        appendToBuffer("\(cTypeName(field.type)) \(sanitizeCIdentifier(field.name));\n")
      }
    }
    appendToBuffer("};\n\n")
  }

}
