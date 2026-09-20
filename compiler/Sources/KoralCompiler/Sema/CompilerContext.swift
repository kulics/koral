import Foundation

/// CompilerContext - Unified query/update context for DefId and type info.
///
/// Provides immutable query APIs and explicit update APIs to avoid reliance
/// on global mutable state and to support parallel compilation.
public final class CompilerContext: @unchecked Sendable {
    public private(set) var defIdMap: DefIdMap

    public init(defIdMap: DefIdMap = DefIdMap()) {
        self.defIdMap = defIdMap
    }

    // MARK: - DefIdMap Queries

    public func getName(_ defId: DefId) -> String? {
        defIdMap.getName(defId)
    }

    public func getModulePath(_ defId: DefId) -> [String]? {
        defIdMap.getModulePath(defId)
    }

    public func getSourceFile(_ defId: DefId) -> String? {
        defIdMap.getSourceFile(defId)
    }

    public func getKind(_ defId: DefId) -> DefKind? {
        defIdMap.getKind(defId)
    }

    public func getAccess(_ defId: DefId) -> AccessModifier? {
        defIdMap.getAccess(defId)
    }

    public func getPackageID(_ defId: DefId) -> String? {
        defIdMap.getPackageID(defId)
    }

    public func getSpan(_ defId: DefId) -> SourceSpan? {
        defIdMap.getSpan(defId)
    }

    public func getQualifiedName(_ defId: DefId) -> String? {
        defIdMap.getQualifiedName(defId)
    }

    public func getCIdentifier(_ defId: DefId) -> String? {
        defIdMap.getCIdentifier(defId)
    }

    public func getSymbolType(_ defId: DefId) -> Type? {
        defIdMap.getSymbolType(defId)
    }

    public func getSymbolKind(_ defId: DefId) -> SymbolKind? {
        defIdMap.getSymbolKind(defId)
    }

    public func isSymbolMutable(_ defId: DefId) -> Bool {
        defIdMap.isSymbolMutable(defId) ?? false
    }

    public func lookupDefId(
        modulePath: [String],
        name: String,
        sourceFile: String?
    ) -> DefId? {
        defIdMap.lookup(modulePath: modulePath, name: name, sourceFile: sourceFile)
    }

    public func lookupSymbol(
        name: String,
        sourceFile: String?,
        scope: UnifiedScope
    ) -> DefId? {
        scope.lookup(name, sourceFile: sourceFile)
    }

    public func allocateDefId(
        modulePath: [String],
        name: String,
        kind: DefKind,
        sourceFile: String,
        access: AccessModifier = .module_private,
        packageID: String = "",
        span: SourceSpan = .unknown
    ) -> DefId {
        defIdMap.allocate(
            modulePath: modulePath,
            name: name,
            kind: kind,
            sourceFile: sourceFile,
            access: access,
            packageID: packageID,
            span: span
        )
    }

    public func createSymbol(
        name: String,
        modulePath: [String],
        sourceFile: String,
        type: Type,
        kind: SymbolKind,
        access: AccessModifier = .module_private,
        span: SourceSpan = .unknown,
        packageID: String = "",
        isMutable: Bool = false
    ) -> Symbol {
        let defKind: DefKind
        switch kind {
        case .function:
            defKind = .function
        case .variable:
            defKind = .variable
        case .type:
            if case .opaque = type {
                defKind = .type(.opaque)
            } else {
                defKind = .type(.structure)
            }
        case .module:
            defKind = .module
        }

        let defId: DefId
        if access == .file_private {
            defId = defIdMap.lookupExact(
                modulePath: modulePath,
                name: name,
                sourceFile: sourceFile
            ) ?? defIdMap.allocate(
                modulePath: modulePath,
                name: name,
                kind: defKind,
                sourceFile: sourceFile,
                access: access,
                packageID: packageID,
                span: span
            )
        } else {
            defId = defIdMap.lookup(
                modulePath: modulePath,
                name: name,
                sourceFile: nil
            ) ?? defIdMap.allocate(
                modulePath: modulePath,
                name: name,
                kind: defKind,
                sourceFile: sourceFile,
                access: access,
                packageID: packageID,
                span: span
            )
        }

        defIdMap.addSymbolInfo(
            defId: defId,
            type: type,
            kind: kind,
            isMutable: isMutable
        )

        return Symbol(defId: defId, type: type, kind: kind)
    }

    // MARK: - Typed Definition Queries

    public func getStructMembers(_ defId: DefId) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool)]? {
        defIdMap.getStructMembers(defId)
    }

    public func getEnumCases(_ defId: DefId) -> [EnumCase]? {
        defIdMap.getEnumCases(defId)
    }

    public func getForeignStructFields(_ defId: DefId) -> [(name: String, type: Type)]? {
        defIdMap.getForeignStructFields(defId)
    }

    public func isForeignStruct(_ defId: DefId) -> Bool {
        defIdMap.isForeignStruct(defId)
    }

    public func setNotDeref(_ defId: DefId) {
        defIdMap.setNotDeref(defId)
    }

    public func isNotDeref(_ defId: DefId) -> Bool {
        defIdMap.isNotDeref(defId)
    }

    public func setCname(_ defId: DefId, _ cname: String) {
        defIdMap.setCname(defId, cname)
    }

    public func getCname(_ defId: DefId) -> String? {
        defIdMap.getCname(defId)
    }

    public func isGenericInstantiation(_ defId: DefId) -> Bool? {
        defIdMap.isGenericInstantiation(defId)
    }

    public func isTypeMutable(_ defId: DefId) -> Bool {
        defIdMap.isStructMutable(defId)
    }

    public func isGenericStructTemplateMutable(_ defId: DefId) -> Bool {
        defIdMap.getGenericStructTemplateInfo(defId)?.isMutable ?? false
    }

    public func setExplicitDrop(_ defId: DefId) {
        defIdMap.setExplicitDrop(defId)
    }

    public func hasExplicitDrop(_ defId: DefId) -> Bool {
        if defIdMap.hasExplicitDrop(defId) {
            return true
        }
        if let templateName = defIdMap.getTemplateName(defId) {
            if let templateDefId = defIdMap.lookupGenericStructTemplateDefId(templateName),
               defIdMap.hasExplicitDrop(templateDefId) {
                return true
            }
            if let templateDefId = defIdMap.lookupGenericEnumTemplateDefId(templateName),
               defIdMap.hasExplicitDrop(templateDefId) {
                return true
            }
        }
        return false
    }

    public enum NominalLayoutKind {
        case value
        case managed
    }

    public func nominalLayoutKind(for type: Type) -> NominalLayoutKind {
        return requiresManagedNominalLayout(for: type) ? .managed : .value
    }

    private func requiresManagedNominalLayout(for type: Type) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never,
             .function, .reference, .mutableReference, .borrowedReference,
             .mutableBorrowedReference, .pointer, .mutablePointer,
             .weakReference, .mutableWeakReference, .genericParameter,
             .module, .typeVariable, .traitObject:
            return false

        case .structure(let defId), .`enum`(let defId), .opaque(let defId):
            return requiresManagedNominalLayout(for: defId)

        case .genericStruct(let template, let args):
            if let templateDefId = defIdMap.lookupGenericStructTemplateDefId(template),
               (isGenericStructTemplateMutable(templateDefId) || defIdMap.hasExplicitDrop(templateDefId)) {
                return true
            }
            let layoutName = SemaUtils.makeLayoutName(baseName: template, args: args, context: self)
            if let defId = defIdMap.lookup(modulePath: [], name: layoutName) {
                return requiresManagedNominalLayout(for: defId)
            }
            return false

        case .genericEnum(let template, let args):
            if let templateDefId = defIdMap.lookupGenericEnumTemplateDefId(template),
               defIdMap.hasExplicitDrop(templateDefId) {
                return true
            }
            let layoutName = SemaUtils.makeLayoutName(baseName: template, args: args, context: self)
            if let defId = defIdMap.lookup(modulePath: [], name: layoutName) {
                return requiresManagedNominalLayout(for: defId)
            }
            return false
        }
    }

    private func requiresManagedNominalLayout(for defId: DefId) -> Bool {
        if isTypeMutable(defId) || hasExplicitDrop(defId) {
            return true
        }

        var path: Set<DefId> = [defId]
        return containsNominalValueCycle(current: defId, target: defId, path: &path)
    }

    private func containsNominalValueCycle(current: DefId, target: DefId, path: inout Set<DefId>) -> Bool {
        for dependency in directNominalValueDependencies(of: current) {
            if dependency == target {
                return true
            }
            if path.contains(dependency) {
                continue
            }
            path.insert(dependency)
            if containsNominalValueCycle(current: dependency, target: target, path: &path) {
                return true
            }
            path.remove(dependency)
        }
        return false
    }

    private func directNominalValueDependencies(of defId: DefId) -> [DefId] {
        if isTypeMutable(defId) || hasExplicitDrop(defId) {
            return []
        }

        if let members = getStructMembers(defId) {
            var result: [DefId] = []
            for member in members {
                result.append(contentsOf: directNominalValueDependencies(in: member.type))
            }
            return result
        }

        if let cases = getEnumCases(defId) {
            var result: [DefId] = []
            for enumCase in cases {
                for param in enumCase.parameters {
                    result.append(contentsOf: directNominalValueDependencies(in: param.type))
                }
            }
            return result
        }

        return []
    }

    private func directNominalValueDependencies(in type: Type) -> [DefId] {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never,
             .function, .reference, .mutableReference, .borrowedReference,
             .mutableBorrowedReference, .pointer, .mutablePointer,
             .weakReference, .mutableWeakReference, .genericParameter,
             .module, .typeVariable, .traitObject:
            return []
        case .structure(let defId), .`enum`(let defId), .opaque(let defId):
            return (isTypeMutable(defId) || hasExplicitDrop(defId)) ? [] : [defId]
        case .genericStruct(let template, let args):
            if let templateDefId = defIdMap.lookupGenericStructTemplateDefId(template),
               (isGenericStructTemplateMutable(templateDefId) || defIdMap.hasExplicitDrop(templateDefId)) {
                return []
            }
            let layoutName = SemaUtils.makeLayoutName(baseName: template, args: args, context: self)
            if let defId = defIdMap.lookup(modulePath: [], name: layoutName) {
                return (isTypeMutable(defId) || hasExplicitDrop(defId)) ? [] : [defId]
            }
            return []
        case .genericEnum(let template, let args):
            if let templateDefId = defIdMap.lookupGenericEnumTemplateDefId(template),
               defIdMap.hasExplicitDrop(templateDefId) {
                return []
            }
            let layoutName = SemaUtils.makeLayoutName(baseName: template, args: args, context: self)
            if let defId = defIdMap.lookup(modulePath: [], name: layoutName) {
                return (isTypeMutable(defId) || hasExplicitDrop(defId)) ? [] : [defId]
            }
            return []
        }
    }

    public func getTypeArguments(_ defId: DefId) -> [Type]? {
        defIdMap.getTypeArguments(defId)
    }

    public func getTemplateName(_ defId: DefId) -> String? {
        return defIdMap.getTemplateName(defId)
    }

    // MARK: - Unified Updates

    public func setDefIdMap(_ map: DefIdMap) {
        defIdMap = map
    }

    public func updateStructInfo(
        defId: DefId,
        members: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool)],
        isGenericInstantiation: Bool,
        typeArguments: [Type]?,
        templateName: String? = nil,
        isMutable: Bool = false
    ) {
        let resolvedTemplateName = templateName ?? defIdMap.getTemplateName(defId)
        let inheritedTemplateMutability: Bool
        if let resolvedTemplateName,
           let templateDefId = defIdMap.lookupGenericStructTemplateDefId(resolvedTemplateName) {
            inheritedTemplateMutability = isGenericStructTemplateMutable(templateDefId)
        } else {
            inheritedTemplateMutability = false
        }
        let resolvedIsMutable = isMutable || defIdMap.isStructMutable(defId) || inheritedTemplateMutability
        defIdMap.addStructInfo(
            defId: defId,
            members: members,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments,
            templateName: resolvedTemplateName,
            isMutable: resolvedIsMutable
        )
    }

    public func updateEnumInfo(
        defId: DefId,
        cases: [EnumCase],
        isGenericInstantiation: Bool,
        typeArguments: [Type]?,
        templateName: String? = nil
    ) {
        let resolvedTemplateName = templateName ?? defIdMap.getTemplateName(defId)
        defIdMap.addEnumInfo(
            defId: defId,
            cases: cases,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments,
            templateName: resolvedTemplateName
        )
    }

    public func updateForeignStructFields(defId: DefId, fields: [(name: String, type: Type)]) {
        defIdMap.setForeignStructFields(defId, fields)
    }

    // MARK: - Type Queries

    public func getTypeName(_ type: Type) -> String {
        switch type {
        case .structure(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        case .`enum`(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        case .opaque(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        default:
            return type.description
        }
    }

    public func getDebugName(_ type: Type) -> String {
        switch type {
        case .int: return "Int"
        case .int8: return "Int8"
        case .int16: return "Int16"
        case .int32: return "Int32"
        case .int64: return "Int64"
        case .uint: return "UInt"
        case .uint8: return "UInt8"
        case .uint16: return "UInt16"
        case .uint32: return "UInt32"
        case .uint64: return "UInt64"
        case .float32: return "Float32"
        case .float64: return "Float64"
        case .bool: return "Bool"
        case .void: return "Void"
        case .never: return "Never"
        case .function(let params, let returns):
            let paramStr = params.map { getDebugName($0.type) }.joined(separator: ", ")
            return "Func(\(paramStr)) \(getDebugName(returns))"
        case .reference(let inner): return "*\(getDebugName(inner))"
        case .mutableReference(let inner): return "*mutable \(getDebugName(inner))"
        case .borrowedReference(let inner): return "ref *\(getDebugName(inner))"
        case .mutableBorrowedReference(let inner): return "ref mutable *\(getDebugName(inner))"
        case .pointer(let element): return "*unsafe \(getDebugName(element))"
        case .mutablePointer(let element): return "*unsafe mutable \(getDebugName(element))"
        case .weakReference(let inner): return "?*\(getDebugName(inner))"
        case .mutableWeakReference(let inner): return "?*mutable \(getDebugName(inner))"
        case .structure(let defId):
            var name = defIdMap.getName(defId) ?? "<unknown>"
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                let argsStr = typeArgs.map { getDebugName($0) }.joined(separator: ", ")
                name += "[\(argsStr)]"
            }
            return name
        case .`enum`(let defId):
            var name = defIdMap.getName(defId) ?? "<unknown>"
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                let argsStr = typeArgs.map { getDebugName($0) }.joined(separator: ", ")
                name += "[\(argsStr)]"
            }
            return name
        case .opaque(let defId):
            return defIdMap.getName(defId) ?? "<unknown>"
        case .genericParameter(let name):
            return name
        case .genericStruct(let template, let args):
            let argsStr = args.map { getDebugName($0) }.joined(separator: ", ")
            return "\(template)[\(argsStr)]"
        case .genericEnum(let template, let args):
            let argsStr = args.map { getDebugName($0) }.joined(separator: ", ")
            return "\(template)[\(argsStr)]"
        case .module(let info):
            return "module \(info.modulePath.joined(separator: "."))"
        case .typeVariable(let tv):
            return "?\(tv.id)"
        case .traitObject(let traitName, let typeArgs):
            if typeArgs.isEmpty { return traitName }
            let argsStr = typeArgs.map { getDebugName($0) }.joined(separator: ", ")
            return "[\(argsStr)]\(traitName)"
        }
    }

    // MARK: - Type Variable Queries

    public func freeTypeVariables(in type: Type) -> [TypeVariable] {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return []
        case .typeVariable(let tv):
            return [tv]
        case .function(let params, let returns):
            var result: [TypeVariable] = []
            for param in params {
                result.append(contentsOf: freeTypeVariables(in: param.type))
            }
            result.append(contentsOf: freeTypeVariables(in: returns))
            return result
        case .structure(let defId):
            var result: [TypeVariable] = []
            for member in defIdMap.getStructMembers(defId) ?? [] {
                result.append(contentsOf: freeTypeVariables(in: member.type))
            }
            return result
        case .`enum`(let defId):
            var result: [TypeVariable] = []
            for c in defIdMap.getEnumCases(defId) ?? [] {
                for param in c.parameters {
                    result.append(contentsOf: freeTypeVariables(in: param.type))
                }
            }
            return result
        case .reference(let inner):
            return freeTypeVariables(in: inner)
        case .mutableReference(let inner):
            return freeTypeVariables(in: inner)
        case .borrowedReference(let inner):
            return freeTypeVariables(in: inner)
        case .mutableBorrowedReference(let inner):
            return freeTypeVariables(in: inner)
        case .pointer(let element):
            return freeTypeVariables(in: element)
        case .mutablePointer(let element):
            return freeTypeVariables(in: element)
        case .weakReference(let inner):
            return freeTypeVariables(in: inner)
        case .mutableWeakReference(let inner):
            return freeTypeVariables(in: inner)
        case .genericParameter:
            return []
        case .genericStruct(_, let args):
            return args.flatMap { freeTypeVariables(in: $0) }
        case .genericEnum(_, let args):
            return args.flatMap { freeTypeVariables(in: $0) }
        case .module:
            return []
        case .opaque:
            return []
        case .traitObject(_, let typeArgs):
            return typeArgs.flatMap { freeTypeVariables(in: $0) }
        }
    }

    public func containsTypeVariable(_ type: Type) -> Bool {
        return !freeTypeVariables(in: type).isEmpty
    }

    public func getLayoutKey(_ type: Type) -> String {
        switch type {
        case .int: return "I"
        case .int8: return "I8"
        case .int16: return "I16"
        case .int32: return "I32"
        case .int64: return "I64"
        case .uint: return "U"
        case .uint8: return "U8"
        case .uint16: return "U16"
        case .uint32: return "U32"
        case .uint64: return "U64"
        case .float32: return "F32"
        case .float64: return "F64"
        case .bool: return "B"
        case .void: return "V"
        case .never: return "N"
        case .function: return "Fn"
        case .reference(let inner): return "R_\(getLayoutKey(inner))"
        case .mutableReference(let inner): return "MR_\(getLayoutKey(inner))"
        case .borrowedReference(let inner): return "R_BR_\(getLayoutKey(inner))"
        case .mutableBorrowedReference(let inner): return "MR_BR_\(getLayoutKey(inner))"
        case .pointer(let element): return "P_\(getLayoutKey(element))"
        case .mutablePointer(let element): return "MP_\(getLayoutKey(element))"
        case .weakReference(let inner): return "W_\(getLayoutKey(inner))"
        case .mutableWeakReference(let inner): return "MW_\(getLayoutKey(inner))"
        case .structure(let defId):
            return layoutKey(for: defId)
        case .`enum`(let defId):
            return layoutKey(for: defId)
        case .opaque(let defId):
            return layoutKey(for: defId)
        case .genericParameter(let name):
            return "Param_\(name)"
        case .genericStruct(let template, let args):
            let argsKeys = args.map { getLayoutKey($0) }.joined(separator: "_")
            return "\(template)_\(argsKeys)"
        case .genericEnum(let template, let args):
            let argsKeys = args.map { getLayoutKey($0) }.joined(separator: "_")
            return "\(template)_\(argsKeys)"
        case .module(let info):
            return "M_\(info.modulePath.joined(separator: "_"))"
        case .typeVariable(let tv):
            return "TV_\(tv.id)"
        case .traitObject(let traitName, let typeArgs):
            if typeArgs.isEmpty { return "TO_\(traitName)" }
            let argsKeys = typeArgs.map { getLayoutKey($0) }.joined(separator: "_")
            return "TO_\(traitName)_\(argsKeys)"
        }
    }

    private func layoutKey(for defId: DefId) -> String {
        guard let metadata = defIdMap.metadata(for: defId) else {
            return "T_\(defId.id)"
        }
        var parts: [String] = []
        if !metadata.modulePath.isEmpty {
            parts.append(metadata.modulePath.joined(separator: "_"))
        }
        if metadata.access == .file_private {
            var hash: UInt32 = 0
            for char in metadata.sourceFile.utf8 {
                hash = hash &* 31 &+ UInt32(char)
            }
            parts.append("f\(hash % 10000)")
        }
        parts.append(metadata.name)
        if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
            // For generic instantiations, the layout name already includes type args.
            if (defIdMap.isGenericInstantiation(defId) ?? false) == false {
                let argsStr = typeArgs.map { getLayoutKey($0) }.joined(separator: "_")
                parts.append(argsStr)
            }
        }
        return parts.joined(separator: "_")
    }

    public func containsGenericParameter(_ type: Type) -> Bool {
        var visited: Set<DefId> = []
        return containsGenericParameterInternal(type, visited: &visited)
    }

    private func containsGenericParameterInternal(_ type: Type, visited: inout Set<DefId>) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return false
        case .function(let params, let returns):
            return containsGenericParameterInternal(returns, visited: &visited)
                || params.contains { containsGenericParameterInternal($0.type, visited: &visited) }
        case .structure(let defId):
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                return typeArgs.contains { containsGenericParameterInternal($0, visited: &visited) }
            }
            if visited.contains(defId) { return false }
            visited.insert(defId)
            return (defIdMap.getStructMembers(defId) ?? []).contains {
                containsGenericParameterInternal($0.type, visited: &visited)
            }
        case .`enum`(let defId):
            if let typeArgs = defIdMap.getTypeArguments(defId), !typeArgs.isEmpty {
                return typeArgs.contains { containsGenericParameterInternal($0, visited: &visited) }
            }
            if visited.contains(defId) { return false }
            visited.insert(defId)
            return (defIdMap.getEnumCases(defId) ?? []).contains { c in
                c.parameters.contains { containsGenericParameterInternal($0.type, visited: &visited) }
            }
        case .opaque:
            return false
        case .reference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .mutableReference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .borrowedReference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .mutableBorrowedReference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .pointer(let element):
            return containsGenericParameterInternal(element, visited: &visited)
        case .mutablePointer(let element):
            return containsGenericParameterInternal(element, visited: &visited)
        case .weakReference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .mutableWeakReference(let inner):
            return containsGenericParameterInternal(inner, visited: &visited)
        case .genericParameter:
            return true
        case .genericStruct(_, let args):
            return args.contains { containsGenericParameterInternal($0, visited: &visited) }
        case .genericEnum(_, let args):
            return args.contains { containsGenericParameterInternal($0, visited: &visited) }
        case .module:
            return false
        case .typeVariable:
            return true
        case .traitObject(_, let typeArgs):
            return typeArgs.contains { containsGenericParameterInternal($0, visited: &visited) }
        }
    }
}
