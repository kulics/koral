import Foundation

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath

// use test file for now
let testPath = currentPath
                        .appendingPathComponent("Tests")
                        .appendingPathComponent("koralcTests")
                        .appendingPathComponent("test.koral")
let fileURL = URL(fileURLWithPath: testPath)

do {
    let input = try String(contentsOf: fileURL, encoding: .utf8)
    let lexer = Lexer(input: input)
    let parser = Parser(lexer: lexer)
    let ast = try parser.parse()
    let typeChecker = TypeChecker(ast: ast)
    try typeChecker.check()
    print("type check pass!")
    // let codeGen = CodeGen(ast: ast)
    // let code = codeGen.generate()
} catch let error as ParserError {
    print("parser error: \(error)")
} catch let error as LexerError {
    print("lexer error: \(error)")
} catch let error as SemanticError {
    print("semantic error: \(error)")
} catch let error as NSError {
    print("read file error: \(error)")
}
