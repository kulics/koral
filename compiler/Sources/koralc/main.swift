import Foundation

print("Hello, world!")

// let fileManaget = FileManager.default
// let currentPath = fileManaget.currentDirectoryPath
// print("Current path: \(currentPath)")

// let filePath = currentPath + "\\Tests\\koralcTests\\koralcTests.swift"
// let fileURL = URL(fileURLWithPath: filePath)

// do {
//     // 尝试读取文件内容
//     let content = try String(contentsOf: fileURL, encoding: .utf8)
//     print("文件内容为：")
//     print(content)
// } catch {
//     // 若读取过程中出现错误，打印错误信息
//     print("读取文件时出错：\(error)")
// }
// 使用示例
let input = """
// variable
let x Int = 5;
let y Float = 3.2;
let z String = "Hello";
let b Bool = true;
// function
let add(x Int, y Int) Int = x + y;
let subtract(x Int, y Int) Int = x - y;
let multiply(x Int, y Int) Int = x * y;
let divide(x Int, y Int) Int = x / y;
let modulo(x Int, y Int) Int = x % y;
let compare(x Int, y Int) Bool = x == y;
let greater(x Int, y Int) Bool = x > y;
let less(x Int, y Int) Bool = x < y;
let blockExample(a Int, b Int) Int = {
    let result Int = a * b;
    result
};
let mut x_mut Int = 5;
let change_x() Int = {
    x_mut = 10;
    x_mut
};
"""
let lexer = Lexer(input: input)
let parser = Parser(lexer: lexer)

do {
    let ast = try parser.parse()
    let typeChecker = TypeChecker(ast: ast)
    try typeChecker.check()
    print("type check pass!")
} catch let error as ParserError {
    print("parser error: \(error)")
} catch let error as LexerError {
    print("lexer error: \(error)")
} catch let error as SemanticError {
    print("semantic error: \(error)")
}

// let codeGen = CodeGen(ast: ast)
// let code = codeGen.generate()