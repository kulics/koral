\Xs\Example <- {
    System
    System\IO
    System\Linq
    System\ComponentModel\DataAnnotations\Schema
    System\ComponentModel\DataAnnotations

    Xs\Example.ExampleStatic
}

## 
    main function 
##
Main() ~> () {
    Prt("main function")
    # run test
    test type()
    test operator()
    test string()
    test optional()
    test switch()
    test if()
    test array()
    test dictionary()
    test loop()
    x := test func("testcall")
    _ = test func params(1, 2, 
    (a: I32, b: I32, c: I32, d: I8) -> (z: Str, a: I32, b: I32, c: I32) {
        <- ("",a,b,c)
    })
    test check()
    test type convert()
    test default()
    test lambda()
    test linq()
    _ = <~ test async()

    y := test tuple(1).to str()

    p := App{}

    _ = p.C(1)
    test interface(p)

    p.test func template<I32, Str>(1, "2").test package()
    
    @ True {
        <- @
    }
    
    ? 1 == 1 {
        Prt("test exception expression")
    }

    Rd()
}

static x() := 0 {
    get { 
        <- (_static x)
    }
}

static y() := "hello" {
    get { 
        <- (_static y) 
    }
    set { 
        _static y = value 
    }
}

Readonly: ReadOnly<I32> = RO(5)
static g: I64

test tuple(i: I32) -> (v: Str) {
    <- ("tuple")
}

test type() -> () {
    i1: I8 = 1               # sbyte
    i2: I16 = 1              # short
    i3: I32 = 1              # int
    i4: I64 = 1              # long
    u1: U8 = 1               # byte
    u2: U16 = 1              # ushort
    u3: U32 = 1              # uint
    u4: U64 = 1              # ulong
    f1: F32 = 1              # float
    f2: F64 = 1              # double
    char1: Chr = 'a'         # char
    string1: Str = "123"     # string
}

test operator() -> () {
    i :Str = "128.687"
    i += ".890"
    b :I32
    b = 0
    b += const data
    b = + - b
    b -= 1
    b *= 2
    b /= 2
    b %= 5
    Prt("2 pow 2 = ", 2 ** 2) 
    Prt("4 extract root for 2 = ", 4 // 2) 
    Prt("4 log with base 2 = ", 4 %% 2) 
    Prt(" mark string I32 " b " ")
    c := False
    c = ~c
    c = 1 >< 2
    c = 3 == 3
    c = 3 >= 1
    c = 1 <= 3
    c = True | False
    c = True & False
    d := 11
    d = d.And(1).Or(2).Xor(3).Not().Lft(1).Rht(2)
    Prt(b.to str())
}

test string() -> () {
    "love xs" @ ea {
        ? ea == 'e' {
            Prt("love xs")
        }
    }
}

test optional() -> () {
    a: ^I32 = 1
    a^.to str()
    b: ^Str = ""
    b^.to str()
    c: ^{} = ()
    d: ^App = ()
    e: ^[]^I32 = []^I32{0}
    e^[0]^.to str()^.to str()
    f := d.Def(App{})
}

test type convert() -> () {
    x := App{}
    y := x:Program:
    z1 := (12.34).ToF32()
    z2 := z1.ToI64()
    Prt( z2.To<{}>().To<I64>() )
    Prt( y == :Program )
    Prt( y >< :Program )
    Prt( x:Program:.Running )
    Prt( ?(:Program) )
    Prt( ?(x) )
}

test default() -> () {
    x := Def<Program>()
    y := Def<Protocol>()
    z := Def<(I32)->(I32)>()
}

test switch() -> () {
    x :{} = 3
    x ? 1 {
        Prt(1)
    } :Str {
        Prt("string")
    } :I32 {
        Prt("int")
    } () {
        Prt("null")
    } _ {
        Prt("default")
    }
}

test if() -> () {
    x := 5
    ? x == 2 {
        Prt(2)
    } x == 3 {
        Prt(3)
    } _ {
        Prt("else")
    }
    ? x == 5 {
        Prt("yes")
    }
}

test array() -> () {
    lst single := {1}
    lst number := {1,2,5,6,8,4}
    lst number = lst number + 0
    lst number += 3 + 7
    lst number -= 6
    take := lst number[0]
    take = in package array{}.Arr[2]
    lst obj := {"123", 432, App{}}
    lst arr := {{1,1,1}, {1,1,1}}
    lst empty := []I32{}
    array: [I32] = ArrOf(1,2,3)
    lst number @ item {
        Prt(item)
    }
    lst number @ [i]v {
        Prt(i, ":", v)
    }
    slice := lst number[0<=]
    slice2 := lst number[<3]
}

test dictionary() -> () {
    empty := [Str]I32{}
    dic temp := {["k1"]1,["k2"]2}
    dic temp += {["k3"]3}
    dic temp @ [k]v {
        Prt(k)
        Prt(v)
    }
    dic temp -= "k1"
    Prt(dic temp["k2"])
}

test loop() -> () {
    Prt(" 0 to 10")
    [0 <= 10] @ i {
        Prt(i, ", ", "")
    }
    Prt(" ")
    Prt(" 0 to 8 step 2")
    [0 < 8, 2] @ ea {
        Prt(ea, ", ", "")
    }
    Prt(" ")
    Prt(" 8 to 2 step 2")
    [8 > 0, 2] @ ea {
        Prt(ea, ", ", "")
        ? ea == 6 {
            -> @
        }
    }
    Prt(" ")
    @ {
        <- @
    }
    a := 0
    b := 8
    @ a < b {
        a += 1
    }
}

test check() -> () {
    z1: ^Defer = ()
    ! z2 := Defer{}
    ! {
        z1 = Defer{}
        ! z3 := Defer{}
        x := 1 * 1
        y := 1 + 1
    } ex: IOException {
        !(ex)
    } e {
        !(e)
    } _ {
        ? z1 >< () {
            z1.Dispose()
        }
    }
}

test func(s: Str = "test") -> (out1: Str, out2: I32) {
    s = s + "test"
    i := 1+1*3*9/8
    out2 := i + 5 + (i + 8)
    # func in func
    in func() -> () {
        <- ()
    }
    in func()

    <- (s, i)
}

test func params(a: I32, b: I32, fn: (I32, I32, I32, I8) ->
    (Str, I32, I32, I32)) -> (a: I32, b: Str, c: Str) {
    <- (0, "", "")
}

test lambda() -> () {
    test1(fn: (I32, I32) -> (I32, I32)) -> () {
        (o1,o2) := fn(1, 2)
    }
    test1( {i1,i2 -> (i1,i2)} )

    test2(fn: () -> (I32)) -> () {
        o1 := fn()
    }
    test2( {->1} )

    test3(fn: (I32) -> ()) -> () {
        fn(1)
    }
    test3( (it: I32) ~> () {
        <~ Dly(1000)
        Prt(it)
    })
    test3( {it ~>
        <~ Dly(1000)
        Prt(it)
    })
    test4(fn: (I32) -> (I32)) -> () { 
        fn(18) 
    }
    test4({it->it+1})
}

test async() ~> (x: I32, y: I32, z: Str) {
    Slp(1000)
    [1<=10] @ i {
        Go({ ~> 
            <~ Dly(1000)
            Prt("task", i)
        })
        Go({ -> 
            <- ()
        })
    }
    funWait() ~> () {
        <~ Dly(1000)
    }
    <~ funWait()
    
    <- (1, 2, "123")
}

test linq() -> () {
    numbers := {0, 1, 2, 3, 4, 5, 6}
    arr := $from num $in numbers $where (num % 2) == 0 
    $orderby num $descending $select num
}

test interface(in: Protocol) -> () {}

const data 256
const data2 :Str "512"
const function() -> (v: I32) { 
    <- (const data) 
}

in package array -> {
    Arr: []I32 = {1,2,3,4,5,6,7}
}

Defer -> {
    Data := ""
} IDisposable {
    Dispose() -> () {}
}

App -> { 
    I := 555
    Arr := {1,1,1,1}
    _PriName := " Program "
    _B := 5

    test package() -> () {
        item := Program{Name = "new Program",Running = True}
        item2 := {
            Name = "new Program",
            Running = True
        }
        item3 := []I32{1,2,3,4,5}
        item4 := [Str]I32{["1"]1,["2"]2,["3"]3}
        item5 := <PackageChild>(1,2) # New
    }

    test func template<T1, T2>(data1: T1, data2: T2) -> (data: App) {
        <- (..)
    }
} ...Program {  
} Protocol {
    B(): I32 {
        get { 
            <- (_B) 
        }
        set { 
            _B = value 
        }
    }

    C(x: I32) -> (y: I32) {
        <- (x + ..B)
    }

    D() ~> (x: I32) {
        <~ Dly(1000)
        <- (3)
    }

    E() ~> () {
        <~ Dly(1000)
    }

    F(): Str = "get"
} 

Result -> {
    Data: Str
} (data: Str) {
    ..Data = data
}

test package template<T:class> -> {
    Data: T

    Generic(a: T) -> () {}
}

test protocol template<T:class> <- {
    Test<H:class>(in: H) -> ()
    Test(in: T) -> ()
}

test implement template -> {
} test protocol template<test implement template> {
    Test(in: test implement template) -> () {}
    Test<H:class>(in: H) -> () {}
}

Program -> {
    Name(): Str = "name" {
        set { 
            _Name = value 
        }
    }

    Running: Bl
}

Protocol <- {
    B(): I32 
    C(x: I32) -> (y: I32)
    D() ~> (y: I32)
    E() ~> ()
    F(): Str
}

[Table("test")]
test annotation -> {
    [Key, Column("id")]
    id(): Str
    [Column("nick_name")]
    nick name(): Str
    [Column("profile")]
    profile(): Str
}

test enum -> I32[
    ok
    err -1
]

Package -> {
    X: I32
    Y: I32
} (y: I32 = 3) {
    X = const data
    Y = y
}

PackageChild -> {
    X: I32
} (x: I32, y: I32)...(y) {
    X = x
} ...Package {
}
