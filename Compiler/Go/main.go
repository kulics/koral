package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"xs/parser"
	"xs/visitor"

	"github.com/antlr/antlr4/runtime/Go/antlr"
)

func main() {
	err := Compiled("./")
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Println("Completed")
}

// Compiled 编译
func Compiled(dir string) error {
	return filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if info == nil {
			return err
		}

		if info.IsDir() {
		} else if strings.HasSuffix(info.Name(), ".xs") {
			fmt.Println(path)
			InputStream, _ := antlr.NewFileStream(path)
			// Create the Lexer
			Lexer := parser.NewXsLexer(InputStream)
			Tokens := antlr.NewCommonTokenStream(Lexer, antlr.TokenDefaultChannel)
			Parser := parser.NewXsParser(Tokens)
			Parser.BuildParseTrees = true
			Parser.RemoveErrorListeners()
			Parser.AddErrorListener(visitor.NewErrorListener(path))

			AST := Parser.Program()

			Visitor := visitor.XsVisitor{}
			Result := Visitor.Visit(AST)
			gopath := strings.Replace(path, ".xs", ".go", 1)
			if err := ioutil.WriteFile(gopath, []byte(Result.(string)), 0644); err != nil {
				return err
			}
			exec.Command("go", "fmt", gopath).Output()
		}
		return nil
	})
}
