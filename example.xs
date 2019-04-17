\Xs {
    StaticG = Readonly.V
} <- {
    System
    System\IO
    System\Linq
    System\ComponentModel\DataAnnotations\Schema
    System\ComponentModel\DataAnnotations

    Xs.example
}

## 
    main function 
##
Main() ~> () {
    Prt("main function")
    # run test
    TestType()
    TestOperator()
    TestString()
    TestOptional()
    TestSwitch()
    TestIf()
    TestArray()
    TestDictionary()
    TestLoop()
    x := TestFunc("testcall")
    _ = TestFuncParams(1, 2, 
    (a: I32, b: I32, c: I32, d: I8) -> (z: Str, a: I32, b: I32, c: I32) {
        <- ("",a,b,c)
    })
    TestCheck()
    TestTypeConvert()
    TestDefault()
    TestLambda()
    _ = <~ TestAsync()

    y := TestTuple(1).ToStr()

    p := App{}

    _ = p.C(1)
    TestInterface(p)

    p.TestFuncTemplate<I32, Str>(1, "2").TestPackage()
    
    Rd()
}

StaticX() := 0 {
    get { 
        <- (_StaticX)
    }
}

StaticY() := "hello" {
    get { 
        <- (_StaticY) 
    }
    set { 
        _StaticY = value 
    }
}

Readonly: ReadOnly<I32> = RO(5)
StaticG: I64

TestTuple(i: I32) -> (v: Str) {
    <- ("tuple")
}

TestType() -> () {
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

TestOperator() -> () {
    i :Str = "128.687"
    i += ".890"
    b :I32
    b = 0
    b += ConstData
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
    Prt(b.ToStr())
}

TestString() -> () {
    @ ea <- "love xs" {
        ? ea == 'e' {
            Prt("love xs")
        }
    }
}

TestOptional() -> () {
    a: I32! = 1
    a?.ToStr()
    b: Str! = ""
    b?.ToStr()
    c: Obj! = Nil
    d: App! = Nil
    e: [I32!]! = [I32!]!{0}
    e?[0]?.ToStr()?.ToStr()
    f := d.Def(App{})
}

TestTypeConvert() -> () {
    x := App{}
    y := x.As<Program>()
    z1 := (12.34).ToF32()
    z2 := z1.ToI64()
    Prt( z2.To<Obj>().To<I64>() )
    Prt( y.Is<Program>() )
    Prt( x.As<Program>().Running )
    Prt( ?(:Program) )
    Prt( ?(x) )
}

TestDefault() -> () {
    x := Def<Program>()
    y := Def<Protocol>()
    z := Def<(I32)->(I32)>()
}

TestSwitch() -> () {
    x :Obj = 3
    ? x -> 1 {
        Prt(1)
    } :Str {
        Prt("string")
    } :I32 {
        Prt("int")
    } Nil {
        Prt("null")
    } _ {
        Prt("default")
    }
}

TestIf() -> () {
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

TestArray() -> () {
    arrSingle := {1}
    arrNumber := {1,2,5,6,8,4}
    arrNumber = arrNumber + 0
    arrNumber += 3 + 7
    arrNumber -= 6
    take := arrNumber[0]
    take = InPackageArray{}.Arr[2]
    arrObj := {"123", 432, App{}}
    arrArr := {{1,1,1}, {1,1,1}}
    arrEmpty := [I32]{}
    arrType := {1,2,3}
    array: Arr<I32> = ArrOf(1,2,3)
    @ item <- arrNumber {
        Prt(item)
    }
    @ [i]v <- arrNumber {
        Prt(i)
        Prt(v)
    }
    slice := arrNumber[0<=]
    slice2 := arrNumber[<3]
}

TestDictionary() -> () {
    empty := [[Str]I32]{}
    dicTemp := {["k1"]1,["k2"]2}
    dicTemp += {["k3"]3}
    @ [k]v <- dicTemp {
        Prt(k)
        Prt(v)
    }
    dicTemp -= "k1"
    Prt(dicTemp["k2"])
}

TestLoop() -> () {
    Prt(" 0 to 10")
    @ i <- [0 <= 10] {
        Prt(i, ", ", "")
    }
    Prt(" ")
    Prt(" 0 to 8 step 2")
    @ ea <- [0 < 8, 2] {
        Prt(ea, ", ", "")
    }
    Prt(" ")
    Prt(" 8 to 2 step 2")
    @ ea <- [8 > 0, 2] {
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

TestCheck() -> () {
    z1 :Defer! = Nil
    ! z2 := Defer{} {
        z1 = Defer{}
        ! z3 := Defer{} {
            x := 1 * 1
        }
        ! {
            y := 1 + 1
        } ex {
            !(ex)
        }
    } ex: IOException {
        !(ex)
    } e {
        !(e)
    } _ {
        ? z1 >< Nil {
            z1.Dispose()
        }
    }
}

TestFunc(s: Str = "test") -> (out1: Str, out2: I32) {
    s = s + "test"
    i := 1+1*3*9/8
    out2 := i + 5 + (i + 8)
    # func in func
    inFunc() -> () {
        <- ()
    }
    inFunc()

    <- (s, i)
}

TestFuncParams(a: I32, b: I32, fn: (I32, I32, I32, I8) ->
    (Str, I32, I32, I32)) -> (a: I32, b: Str, c: Str) {
    <- (0, "", "")
}

TestLambda() -> () {
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

TestAsync() ~> (x: I32, y: I32, z: Str) {
    Slp(1000)
    async1() ~> () {
        <~ Dly(1000)
    }
    <~ async1()
    
    <- (1, 2, "123")
}

TestLinq() -> () {
    numbers := {0, 1, 2, 3, 4, 5, 6}
    arr := from num in numbers where (num % 2) == 0 
    orderby num descending select num
}

TestInterface(in: Protocol) -> () {}

ConstData 256
ConstData2 :Str "512"
ConstFunction() -> (v: I32) { 
    <- (ConstData) 
}

InPackageArray() {
    Arr = {1,2,3,4,5,6,7}
} -> {
    Arr: [I32]
}

Defer() -> {
    Data := ""
} IDisposable {
    Dispose() -> () {}
}

App() -> { 
    I := 555
    Arr := {1,1,1,1}
    _PriName := " Program "
    _B := 5

    TestPackage() -> () {
        item := Program{Name = "new Program",Running = True}
        item2 := {
            Name = "new Program",
            Running = True
        }
        item3 := [I32]{1,2,3,4,5}
        item4 := [[Str]I32]{["1"]1,["2"]2,["3"]3}
    }

    TestFuncTemplate<T1, T2>(data1: T1, data2: T2) -> (data: App) {
        <- (..)
    }
} Program() {  
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

Result(data: Str) {
    ..Data = data
} -> {
    Data: Str
}

TestPackageTemplate<T:class>() -> {
    Data: T

    Generic(a: T) -> () {}
}

TestProtocolTemplate<T:class> <- {
    Test<H:class>(in: H) -> ()
    Test(in: T) -> ()
}

TestImplementTemplate() -> {
} TestProtocolTemplate<TestImplementTemplate> {
    Test(in: TestImplementTemplate) -> () {}
    Test<H:class>(in: H) -> () {}
}

Program() -> {
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

`Table("test")`
TestAnnotation() -> {
    `Key, Column("id")`
    Id(): Str
    `Column("nick_name")`
    NickName(): Str
    `Column("profile")`
    Profile(): Str
}

TestEnum -> [
    Ok
    Err = -1
]

Package(y: I32 = 3) {
    X = ConstData
    Y = y
} -> {
    X: I32
    Y: I32
}

PackageChild(x: I32, y: I32) {
    X = x
} -> {
    X: I32
} Package(y) {
}
