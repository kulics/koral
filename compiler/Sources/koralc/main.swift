import Foundation

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath

// use test file for now
let testPath = currentPath
                        
let fileURL = URL(fileURLWithPath: testPath)
                .appendingPathComponent("LanguageTest")
                .appendingPathComponent("test.koral")

do {
    let input = try String(contentsOf: fileURL, encoding: .utf8)
    let lexer = Lexer(input: input)
    let parser = Parser(lexer: lexer)
    let ast = try parser.parse()
    // printAST(ast)
    let typeChecker = TypeChecker(ast: ast)
    let typedAST = try typeChecker.check()
    print("type check pass!")
    // printTypedAST(typedAST)
    let codeGen = CodeGen(ast: typedAST)
    let code = codeGen.generate()
    print("\nGenerated C code:")
    
    // Get the directory and base filename
    let directory = fileURL.deletingLastPathComponent()
    let baseFilename = fileURL.deletingPathExtension().lastPathComponent
    
    // Create the output file URL with .c extension
    let outputFileURL = directory.appendingPathComponent("\(baseFilename).c")
    
    // Write the code to the output file
    try code.write(to: outputFileURL, atomically: true, encoding: .utf8)
    print("\nC code written to: \(outputFileURL.path)")
} catch let error as ParserError {
    print("parser error: \(error)")
} catch let error as LexerError {
    print("lexer error: \(error)")
} catch let error as SemanticError {
    print("semantic error: \(error)")
} catch let error as NSError {
    print("read file error: \(error)")
}
