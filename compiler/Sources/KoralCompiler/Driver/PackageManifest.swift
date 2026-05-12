import Foundation

public enum PackageManifestError: Error, CustomStringConvertible {
  case fileNotFound(String)
  case invalidJSON(String)
  case invalidField(path: String, message: String)
  case missingTargetModule(String)
  case duplicateModuleEntry(String)
  case unknownModuleDependency(module: String, dependency: String)
  case cyclicModuleDependency([String])

  public var description: String {
    switch self {
    case .fileNotFound(let path):
      return "Manifest file not found: \(path)"
    case .invalidJSON(let path):
      return "Invalid manifest JSON: \(path)"
    case .invalidField(let path, let message):
      return "Invalid manifest field '\(path)': \(message)"
    case .missingTargetModule(let module):
      return "Target module '\(module)' not found in resolved module graph"
    case .duplicateModuleEntry(let entry):
      return "Duplicate module entry file: \(entry)"
    case .unknownModuleDependency(let module, let dependency):
      return "Module '\(module)' depends on unknown module '\(dependency)'"
    case .cyclicModuleDependency(let cycle):
      return "Cyclic module dependency: \(cycle.joined(separator: " -> "))"
    }
  }
}

public struct PackageDependencyConfig {
  public let key: String
  public let name: String
  public let git: String?
  public let version: String?
  public let moduleAliases: [String: String]
}

public struct PackageModuleConfig {
  public let fullName: String
  public let pathSegments: [String]
  public let entryPath: String
  public let requires: [String]
  public let links: [String]
}

public struct PackageManifest {
  public let manifestPath: String
  public let packageRoot: String
  public let name: String
  public let version: String?
  public let defaultTargetModuleName: String?
  public let links: [String]
  public let modules: [String: PackageModuleConfig]
  public let dependencies: [String: PackageDependencyConfig]
}

public enum ResolvedPackageKind {
  case root
  case std
  case dependency(key: String)
}

public struct ResolvedModuleSpec {
  public let fullName: String
  public let pathSegments: [String]
  public let entryFile: String
  public let requires: [String]
  public let links: [String]
  public let visibleModuleAliases: [ResolvedModuleAliasRule]
  public let packageName: String
  public let packageRoot: String
  public let packageKind: ResolvedPackageKind
}

public struct ResolvedModuleAliasRule {
  public let aliasFullName: String
  public let aliasPathSegments: [String]
  public let targetFullName: String
  public let targetPathSegments: [String]
}

public struct ResolvedPackageGraph {
  public let targetModuleName: String
  public let modulesByName: [String: ResolvedModuleSpec]
  public let reachableModuleNames: [String]
  public let rootManifestPath: String
  public let stdManifestPath: String?
  public let stdRootModuleName: String?
}

private func parseManifestModuleName(_ name: String) -> [String]? {
  guard !name.isEmpty else { return nil }
  let parts = name.split(separator: ":").map(String.init)
  guard !parts.isEmpty else { return nil }
  var normalized: [String] = []
  var index = 0
  while index < parts.count {
    let part = parts[index]
    if part.isEmpty {
      index += 1
      continue
    }
    normalized.append(part)
    index += 1
  }
  guard !normalized.isEmpty else { return nil }

  let rebuilt = normalized.joined(separator: "::")
  guard rebuilt == name else { return nil }

  for segment in normalized {
    guard let first = segment.first, first.isASCII, first.isLowercase else {
      return nil
    }
    for ch in segment {
      guard ch.isASCII else { return nil }
      if ch.isLowercase || ch.isNumber || ch == "_" {
        continue
      }
      return nil
    }
  }
  return normalized
}

private func expectObject(_ value: Any, path: String) throws -> [String: Any] {
  guard let object = value as? [String: Any] else {
    throw PackageManifestError.invalidField(path: path, message: "expected object")
  }
  return object
}

private func expectString(_ value: Any?, path: String) throws -> String {
  guard let value else {
    throw PackageManifestError.invalidField(path: path, message: "missing required string")
  }
  guard let string = value as? String else {
    throw PackageManifestError.invalidField(path: path, message: "expected string")
  }
  return string
}

private func optionalString(_ value: Any?, path: String) throws -> String? {
  guard let value else { return nil }
  guard let string = value as? String else {
    throw PackageManifestError.invalidField(path: path, message: "expected string")
  }
  return string
}

private func optionalStringArray(_ value: Any?, path: String) throws -> [String] {
  guard let value else { return [] }
  guard let array = value as? [Any] else {
    throw PackageManifestError.invalidField(path: path, message: "expected string array")
  }
  var result: [String] = []
  for (index, element) in array.enumerated() {
    guard let string = element as? String else {
      throw PackageManifestError.invalidField(
        path: "\(path)[\(index)]",
        message: "expected string"
      )
    }
    result.append(string)
  }
  return result
}

private func optionalStringMap(_ value: Any?, path: String) throws -> [String: String] {
  guard let value else { return [:] }
  guard let object = value as? [String: Any] else {
    throw PackageManifestError.invalidField(path: path, message: "expected object")
  }
  var result: [String: String] = [:]
  for (key, element) in object {
    guard let string = element as? String else {
      throw PackageManifestError.invalidField(
        path: "\(path).\(key)",
        message: "expected string"
      )
    }
    result[key] = string
  }
  return result
}

public func loadPackageManifest(at manifestPath: String) throws -> PackageManifest {
  let manifestURL = URL(fileURLWithPath: manifestPath).standardized
  guard FileManager.default.fileExists(atPath: manifestURL.path) else {
    throw PackageManifestError.fileNotFound(manifestURL.path)
  }

  let data = try Data(contentsOf: manifestURL)
  let raw: Any
  do {
    raw = try JSONSerialization.jsonObject(with: data)
  } catch {
    throw PackageManifestError.invalidJSON(manifestURL.path)
  }

  let object = try expectObject(raw, path: "<root>")
  let packageRoot = manifestURL.deletingLastPathComponent().path
  let name = try expectString(object["name"], path: "name")
  let version = try optionalString(object["version"], path: "version")
  let defaultTargetModuleName = try optionalString(object["entry"], path: "entry")
  let packageLinks = try optionalStringArray(object["links"], path: "links")

  var dependencies: [String: PackageDependencyConfig] = [:]
  if let rawDependencies = object["dependencies"] {
    let dependencyObject = try expectObject(rawDependencies, path: "dependencies")
    for (depKey, rawDependency) in dependencyObject {
      let depObject = try expectObject(rawDependency, path: "dependencies.\(depKey)")
      let depName = try expectString(depObject["name"], path: "dependencies.\(depKey).name")
      let depGit = try optionalString(depObject["git"], path: "dependencies.\(depKey).git")
      let depVersion = try optionalString(depObject["version"], path: "dependencies.\(depKey).version")
      let depAliases = try optionalStringMap(
        depObject["module_aliases"],
        path: "dependencies.\(depKey).module_aliases"
      )
      dependencies[depKey] = PackageDependencyConfig(
        key: depKey,
        name: depName,
        git: depGit,
        version: depVersion,
        moduleAliases: depAliases
      )
    }
  }

  var modules: [String: PackageModuleConfig] = [:]
  if let rawModules = object["modules"] {
    let moduleObject = try expectObject(rawModules, path: "modules")
    var seenEntries = Set<String>()
    for (moduleName, rawModule) in moduleObject {
      guard let pathSegments = parseManifestModuleName(moduleName) else {
        throw PackageManifestError.invalidField(
          path: "modules.\(moduleName)",
          message: "module name must be lower_snake segments joined by '::'"
        )
      }
      let moduleConfigObject = try expectObject(rawModule, path: "modules.\(moduleName)")
      let entryPath = try expectString(moduleConfigObject["entry"], path: "modules.\(moduleName).entry")
      let absoluteEntry = URL(fileURLWithPath: packageRoot)
        .appendingPathComponent(entryPath)
        .standardized
        .path
      if !seenEntries.insert(absoluteEntry).inserted {
        throw PackageManifestError.duplicateModuleEntry(entryPath)
      }

      let requires = try optionalStringArray(moduleConfigObject["requires"], path: "modules.\(moduleName).requires")
      let links = try optionalStringArray(moduleConfigObject["links"], path: "modules.\(moduleName).links")
      modules[moduleName] = PackageModuleConfig(
        fullName: moduleName,
        pathSegments: pathSegments.map(moduleFileNameToIdentifier),
        entryPath: absoluteEntry,
        requires: requires,
        links: links
      )
    }
  }

  if let defaultTargetModuleName {
    guard parseManifestModuleName(defaultTargetModuleName) != nil else {
      throw PackageManifestError.invalidField(
        path: "entry",
        message: "expected module full name such as 'app' or 'app::main'"
      )
    }
    if modules[defaultTargetModuleName] == nil {
      throw PackageManifestError.invalidField(
        path: "entry",
        message: "default target module '\(defaultTargetModuleName)' is not declared in 'modules'"
      )
    }
  } else if modules.count > 1 {
    throw PackageManifestError.invalidField(
      path: "entry",
      message: "required when manifest declares multiple modules"
    )
  }

  return PackageManifest(
    manifestPath: manifestURL.path,
    packageRoot: packageRoot,
    name: name,
    version: version,
    defaultTargetModuleName: defaultTargetModuleName,
    links: packageLinks,
    modules: modules,
    dependencies: dependencies
  )
}

private func addManifestModules(
  from manifest: PackageManifest,
  packageKind: ResolvedPackageKind,
  into modulesByName: inout [String: ResolvedModuleSpec]
) {
  for (name, module) in manifest.modules {
    modulesByName[name] = ResolvedModuleSpec(
      fullName: name,
      pathSegments: module.pathSegments,
      entryFile: module.entryPath,
      requires: module.requires,
      links: manifest.links + module.links,
      visibleModuleAliases: [],
      packageName: manifest.name,
      packageRoot: manifest.packageRoot,
      packageKind: packageKind
    )
  }
}

private func buildDependencyAliasRules(
  rootManifest: PackageManifest,
  dependencyManifestsByKey: [String: PackageManifest],
  existingModuleNames: Set<String>
) throws -> [ResolvedModuleAliasRule] {
  var rules: [ResolvedModuleAliasRule] = []
  var claimedAliasNames = existingModuleNames

  for (depKey, dependency) in rootManifest.dependencies.sorted(by: { $0.key < $1.key }) {
    guard let dependencyManifest = dependencyManifestsByKey[depKey] else {
      continue
    }

    let publishedModuleNames = Set(dependencyManifest.modules.keys)
    for (publishedName, aliasName) in dependency.moduleAliases.sorted(by: { $0.key < $1.key }) {
      guard let publishedSegments = parseManifestModuleName(publishedName) else {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey).module_aliases.\(publishedName)",
          message: "published module name must be lower_snake segments joined by '::'"
        )
      }
      guard let aliasSegments = parseManifestModuleName(aliasName) else {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey).module_aliases.\(publishedName)",
          message: "alias must be lower_snake segments joined by '::'"
        )
      }

      let publishesTargetModule = publishedModuleNames.contains(publishedName)
      if !publishesTargetModule {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey).module_aliases.\(publishedName)",
          message: "dependency '\(depKey)' does not publish module '\(publishedName)'"
        )
      }

      if claimedAliasNames.contains(aliasName) {
        throw PackageManifestError.invalidField(
          path: "dependencies.\(depKey).module_aliases.\(publishedName)",
          message: "alias '\(aliasName)' conflicts with an existing module name"
        )
      }
      claimedAliasNames.insert(aliasName)

      rules.append(
        ResolvedModuleAliasRule(
          aliasFullName: aliasName,
          aliasPathSegments: aliasSegments.map(moduleFileNameToIdentifier),
          targetFullName: publishedName,
          targetPathSegments: publishedSegments.map(moduleFileNameToIdentifier)
        )
      )
    }
  }

  return rules
}

private func rewriteModuleRequirementNames(
  _ requirements: [String],
  using aliasRules: [ResolvedModuleAliasRule]
) -> [String] {
  guard !aliasRules.isEmpty else {
    return requirements
  }

  let sortedRules = aliasRules.sorted {
    if $0.aliasFullName.count == $1.aliasFullName.count {
      return $0.aliasFullName < $1.aliasFullName
    }
    return $0.aliasFullName.count > $1.aliasFullName.count
  }

  var rewritten: [String] = []
  for requirement in requirements {
    var rewrittenRequirement = requirement
    for aliasRule in sortedRules {
      if requirement == aliasRule.aliasFullName {
        rewrittenRequirement = aliasRule.targetFullName
        break
      }
      let aliasPrefix = aliasRule.aliasFullName + "::"
      if requirement.hasPrefix(aliasPrefix) {
        rewrittenRequirement = aliasRule.targetFullName + "::" + requirement.dropFirst(aliasPrefix.count)
        break
      }
    }
    rewritten.append(rewrittenRequirement)
  }
  return rewritten
}

private func validateResolvedModuleGraph(_ modulesByName: [String: ResolvedModuleSpec]) throws {
  for (name, module) in modulesByName {
    for requirement in module.requires {
      guard modulesByName[requirement] != nil else {
        throw PackageManifestError.unknownModuleDependency(module: name, dependency: requirement)
      }
    }
  }

  var visiting = Set<String>()
  var visited = Set<String>()
  var stack: [String] = []

  func visit(_ moduleName: String) throws {
    if visited.contains(moduleName) {
      return
    }
    if visiting.contains(moduleName) {
      if let cycleStart = stack.firstIndex(of: moduleName) {
        throw PackageManifestError.cyclicModuleDependency(Array(stack[cycleStart...]) + [moduleName])
      }
      throw PackageManifestError.cyclicModuleDependency([moduleName])
    }

    visiting.insert(moduleName)
    stack.append(moduleName)
    defer {
      _ = stack.popLast()
      visiting.remove(moduleName)
      visited.insert(moduleName)
    }

    for requirement in modulesByName[moduleName]?.requires ?? [] {
      try visit(requirement)
    }
  }

  for moduleName in modulesByName.keys.sorted() {
    try visit(moduleName)
  }
}

public func loadResolvedPackageGraph(
  rootManifestPath: String,
  targetModuleName: String,
  stdManifestPath: String?,
  depsRoot: String?
) throws -> ResolvedPackageGraph {
  let rootManifest = try loadPackageManifest(at: rootManifestPath)
  var modulesByName: [String: ResolvedModuleSpec] = [:]
  addManifestModules(from: rootManifest, packageKind: .root, into: &modulesByName)
  var dependencyManifestsByKey: [String: PackageManifest] = [:]

  var stdRootModuleName: String?
  if let stdManifestPath {
    let stdManifest = try loadPackageManifest(at: stdManifestPath)
    addManifestModules(from: stdManifest, packageKind: .std, into: &modulesByName)
    stdRootModuleName = stdManifest.modules.keys.sorted().first(where: { !$0.contains("::") })
      ?? stdManifest.modules.keys.sorted().first
  }

  if let depsRoot {
    for (depKey, _) in rootManifest.dependencies.sorted(by: { $0.key < $1.key }) {
      let depManifestPath = URL(fileURLWithPath: depsRoot)
        .appendingPathComponent(depKey)
        .appendingPathComponent("koral.json")
        .standardized
        .path
      if FileManager.default.fileExists(atPath: depManifestPath) {
        let dependencyManifest = try loadPackageManifest(at: depManifestPath)
        dependencyManifestsByKey[depKey] = dependencyManifest
        addManifestModules(
          from: dependencyManifest,
          packageKind: .dependency(key: depKey),
          into: &modulesByName
        )
      }
    }
  }

  let aliasRules = try buildDependencyAliasRules(
    rootManifest: rootManifest,
    dependencyManifestsByKey: dependencyManifestsByKey,
    existingModuleNames: Set(modulesByName.keys)
  )

  if !aliasRules.isEmpty {
    for moduleName in modulesByName.keys.sorted() {
      guard let spec = modulesByName[moduleName] else {
        continue
      }
      guard case .root = spec.packageKind else {
        continue
      }
      modulesByName[moduleName] = ResolvedModuleSpec(
        fullName: spec.fullName,
        pathSegments: spec.pathSegments,
        entryFile: spec.entryFile,
        requires: rewriteModuleRequirementNames(spec.requires, using: aliasRules),
        links: spec.links,
        visibleModuleAliases: aliasRules,
        packageName: spec.packageName,
        packageRoot: spec.packageRoot,
        packageKind: spec.packageKind
      )
    }
  }

  try validateResolvedModuleGraph(modulesByName)

  guard modulesByName[targetModuleName] != nil else {
    throw PackageManifestError.missingTargetModule(targetModuleName)
  }

  var reachable = Set<String>()
  func markReachable(_ moduleName: String) {
    guard reachable.insert(moduleName).inserted else { return }
    for requirement in modulesByName[moduleName]?.requires ?? [] {
      markReachable(requirement)
    }
  }
  markReachable(targetModuleName)

  return ResolvedPackageGraph(
    targetModuleName: targetModuleName,
    modulesByName: modulesByName,
    reachableModuleNames: reachable.sorted(),
    rootManifestPath: URL(fileURLWithPath: rootManifestPath).standardized.path,
    stdManifestPath: stdManifestPath.map { URL(fileURLWithPath: $0).standardized.path },
    stdRootModuleName: stdRootModuleName
  )
}
