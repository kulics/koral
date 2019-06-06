\Compiler <- {
    Antlr4\Runtime
    System
    System\IO
    System\Text
}

_Read Path(): Str
_Path Line(): Str

Main(args: [:]Str) -> () {
    # 检查系统平台，区分路径字符 #
    os := Environment.OSVersion.Platform
    ? os == PlatformID.Unix | os == PlatformID.MacOSX {
        _Read Path = "./"
        _Path Line = "/"
    } _ {
        _Read Path = ".\\"
        _Path Line = "\\"
    }

    Compiled(_Read Path)

    Prt("Completed")
    Rd()
}

Compiled(path: Str) -> () {
        # 获取相对路径下所有文件 #
        Files := Directory.GetFiles(path, "*.xs")
        Files @ file {
            # 文件流读文件 #
            <FileStream>(file, FileMode.Open) ! fs read
            ! {
                FSLength := fs read.Length:Int
                Byte Block := Array<U8>(FSLength)
                r := fs read.Read(Byte Block, 0, Byte Block.Length)
                Input := Encoding.UTF8.GetString(Byte Block)
                # 移除平台差异 #
                Input.Replace("\r", "")

                Stream := <AntlrInputStream>(Input)
                Lexer := <XsLexer>(Stream)
                Tokens := <CommonTokenStream>(Lexer)
                Parser := <XsParser>(Tokens)
                Parser.BuildParseTree = True
                Parser.RemoveErrorListeners()
                Parser.AddErrorListener(ErrorListener{ File Dir = file })

                AST := Parser.program()

                Visitor := XsLangVisitor{}
                Result := Visitor.Visit(AST)

                # 文件流写文件,使用覆盖模式 #
                Byte Result := Encoding.UTF8.GetBytes(Result.to Str())  # 转换为字节 #
                <FileStream>(_Read Path + file.sub Str(0, file.Length - 3) + ".cs", FileMode.Create) ! fs write
                fs write.Write(Byte Result, 0, Byte Result.Length)
            } err: Exception {
                Prt(err)
                <- ()
            }
        }

        Folders := Directory.GetDirectories(path)
        Folders @ folder {
            Compiled(folder)
        }
    }
}
