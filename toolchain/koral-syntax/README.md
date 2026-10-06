# koral-syntax

The syntactic front end of Koral: tokens, the concrete syntax tree, the parser
that builds it, the printer that spells it back out, and the contract that says
what a rewrite may change.

Two tools depend on it, and they are why it exists as a package rather than as
part of either:

- **`toolchain/koralfmt`** — the formatter. Lays source out; must not change it.
- **`toolchain/doc`** — the standard library API doc generator. Reads
  declarations; must not guess at where they are.

Both used to carry their own idea of Koral's shape. The doc generator counted
braces and scanned lines to find declarations, which could not tell a `//`
inside a string from a comment. Pulling the parser out means there is one
answer to "what is a declaration", and one answer to "how is it spelled".

## The layers

| File | What it holds |
| --- | --- |
| `tokenizer.koral` | source text to tokens. Comments are tokens; they are content, not trivia. |
| `cst.koral` | the CST node types. Every token that carries spelling is kept on its node. |
| `parser.koral` | tokens to CST. Full structure, so the printer never infers spacing from token text. |
| `printer.koral` | CST to text. `print_file` lays a whole file out; `print_signature` renders a declaration without its body. |
| `contract.koral` | what a rewrite may change, and `format_source_checked` — the entry point that proves it. |

```koral
using "koral_syntax";                                    // everything
using "koral_syntax" { CstParser, Printer, format_source_checked };
```

## The formatting contract

`format_source_checked(source)` formats, then proves two things about the
result before returning it:

1. **Nothing but `;` and `,` moved.** Strip those two from both sides and the
   token sequences are identical, in order and spelling. Names, literals,
   comments, operators and delimiters are untouched.
2. **It settles.** Formatting the output again produces it back.

`;` and `,` may be added or removed because the surface syntax makes both
optional in ways that carry no meaning:

- `;` — a terminator automatic semicolon insertion would have supplied.
  Making it explicit is the point of formatting.
- `,` — a list separator. A list exploded across lines ends with one so the next
  edit is a one-line diff; a list kept on one line does not.

Neither can hide a real change: a dropped separator makes the output
unparseable, and the check re-parses what it produced.

Byte-order marks and line endings are file-level markers rather than language
content. `koralfmt` folds `\r\n` to `\n` and puts a BOM back where it found
one; see `toolchain/koralfmt/koralfmt.koral`.

## The declaration-only view

`Printer.print_signature(d)` renders a declaration the way generated API docs
show it — bodies left out, only what a consumer of the module can see:

- a top-level declaration is shown only if it is `public`
- a `given` block is always shown (it carries no access modifier), with its
  `public` members — the rest belong to the implementor
- a trait shows every member; a trait's whole body is its interface
- a struct type shows fields that are not explicitly non-public, and an enum
  type shows all of its cases

It is spelled by the same printer the formatter uses, so a signature on a docs
page is the syntax `koralfmt` would write for it.

## Checking it

```bash
# formatter: language assertions + every real .koral file in the repo
bin/compiler/koralc build --package-config toolchain/koralfmt/koral.json --target-module koralfmt/test -o bin/koralfmt-test
bin/koralfmt-test/koralfmt__test

# doc generator: extraction self-test, then "are the checked-in pages current?"
bin/compiler/koralc build --package-config toolchain/doc/koral.json --target-module koral_doc -o bin/toolchain-doc-gen
bin/toolchain-doc-gen/koral_doc --self-test
bin/toolchain-doc-gen/koral_doc --check
```
