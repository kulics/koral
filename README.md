# The Koral Programming Language

Koral is a compiled language built for the way code is written now: much of it is produced by AI agents, and all of it is read by people. Its rules are shaped to give a generator few ways to go wrong and a reviewer few places to look — statement boundaries are explicit, mutability is declared once, a module-level name has one owner, and error flow is spelled inside the expression. The compiler audits the rest.

There is no garbage collector and no manual `free`. Nominal types come in exactly two forms, chosen at the declaration site — shallowly immutable `type` and shared `type mutable` — and memory management follows from that one decision. Koral compiles to C for broad platform compatibility.

> Status: Koral is experimental and not yet production-ready.

## Why Koral is shaped this way

- **Explicit statement boundaries.** Every statement ends with `;`, newlines are insignificant, and there is no automatic semicolon insertion. A generator emits one statement at a time; a reviewer sees exactly where each one ends.
- **The declaration fixes the call shape.** A positional parameter (`name: Type`) is passed by position, a named parameter (`name: Type =`) by label, and there is no optional-label form — a generated call site cannot drift into a half-labeled variant. Destructuring follows the same rules.
- **One import form.** `using` has a single spelling; the specifier's shape decides the meaning (`"./helpers.koral"` merges a file, `"std/io"` imports a module). There are no globs; `as` renames one symbol.
- **A module-level name has one owner.** A second, different declaration under the same spelling — from a top-level declaration, another import, or the prelude — is an error, not silent shadowing. Renaming is always explicit.
- **Errors flow through the expression.** `or else`, `and then` and `or return` handle absence and failure inline; the language has no `throw` / `try` / `catch`. A reviewer never has to scan a call graph to see where an error can travel.
- **One shape for control flow.** `if`, `when`, `while` and `for` are all expressions, and their branches read the same `... then ...` shape — `if` and `when` produce branch values, loops produce `Void`.
- **The compiler audits generated code.** `when` must be exhaustive, a `for` pattern may not fail, the rest pattern `...` never binds, and evaluation order is fully specified. Partial output fails to compile instead of compiling and misbehaving.
- **Mutability is declared once, at the type.** `type` values are shallowly immutable and have no identity; `type mutable` values are shared objects whose `mutable` fields change in place. Layout is the compiler's business — there is no managed-reference syntax to invent.

## A taste of Koral

```koral
type Point(x: Int, y: Int);
type mutable Counter(mutable hits: Int);

type Shape {
    Circle(r: Float64),
    Rectangle(w: Float64, h: Float64),
};

trait Describe {
    describe(self): String;
};

given Point: Describe {
    describe(self): String = "Point(\(self.x), \(self.y))";
};

let area(s: Shape): Float64 = when s in {
    .Circle(r) then 3.14159 * r * r,
    .Rectangle(w, h) then w * h,
};

let lookup(key: String): Option[Int] =
    if key == "port" then Option[Int].Some(8080) else Option[Int].None();

let double_port(config: Option[Int]): Option[Int] = {
    let port = config or return;
    return Option[Int].Some(port * 2);
};

let main(): Void = {
    let c = Counter(0);
    c.hits = c.hits + 1;

    let shapes: List[Shape] = [.Circle(1.0), .Rectangle(2.0, 3.0)];
    let mutable total = 0.0;
    for s in shapes then {
        total = total + area(s);
    };

    if lookup("port") is .Some(v) and v > 0 then {
        println("port = \(v)");
    };
    let port = lookup("port") or else 8080;

    when double_port(lookup("port")) in {
        .Some(n) then println("doubled: \(n)"),
        .None() then println("no port"),
    };
    println(Point(1, 2).describe());
};
```

## Language highlights

- Automatic memory management without a GC or manual `free`, driven by `type` / `type mutable`
- Expression-oriented control flow with exhaustive pattern matching
- Algebraic data types, generics with trait constraints, monomorphized zero-cost abstraction
- Trait objects for runtime polymorphism; `given` blocks for implementations
- C FFI (`let foreign`, `type foreign`, raw pointers `*T` / `*mutable T`) and a C backend
- `defer` for deterministic cleanup

## Getting started

Prerequisites: a Swift toolchain (to build the bootstrap compiler), `clang`, and Git.

```bash
git clone https://github.com/kulics/koral.git
cd koral

# 1) Build the frozen Swift reference compiler.
swift build -c release --package-path compiler-reference

# 2) Build the self-hosting compiler with it (this is what you develop against).
compiler-reference/.build/release/koralc build \
  --package-config compiler/koral.json --target-module koralc -o bin/compiler

# 3) Compile and run a single file.
bin/compiler/koralc run hello.koral
```

`koralc` also offers `build`, `check` and `emit-c`. A project tool (`koral init`, `build`, `check`, `run`, `get`, `format`, `clean`, …) lives in `toolchain/koral/`, and `bash scripts/verify.sh` runs the full verification chain.

## Repository layout

- **`compiler/`** — the self-hosting compiler, written in Koral. **This is what you develop.**
- **`compiler-reference/`** — the frozen Swift compiler: reference oracle, build seed, and backup. See [Compiler roles](docs/implementation/developer-guide.md#compiler-roles) for when it may be touched.
- `std/` · `tests/` · `toolchain/` · `samples/` — standard library, shared test runner, tools, sample programs
- `docs/` — documentation by audience; start at the [documentation map](docs/README.md)

## Documentation

This README is an overview. The normative grammar is [`docs/guide/grammar.bnf`](docs/guide/grammar.bnf); when documentation and implementation disagree, update one or both so they converge.

- [Language Guide (English)](docs/guide/document.md) · [语言文档（中文）](docs/guide/document-zh.md)
- [Grammar (BNF)](docs/guide/grammar.bnf) — normative
- [Standard Library API](docs/api/std/) — generated
- [Design Documents](docs/design/) · [Compiler Developer Guide](docs/implementation/developer-guide.md)
