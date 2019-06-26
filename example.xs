"Xs/Example" {
    "System"
    "System/IO"
    "System/Linq"
    "System/ComponentModel/DataAnnotations/Schema"
    "System/ComponentModel/DataAnnotations"

    "Xs/Example" Example Static.
}

#
    main function 
#
Main() ~> () {
    Prt("main function")
    # run test #
    Test type()
    Test operator()
    Test string()
    Test optional()
    Test switch()
    Test if()
    Test list()
    Test set()
    Test dictionary()
    Test loop()
    X := Test func("testcall")
    _ = Test func params(1, 2, 
    (a: Int, b: Int, c: Int, d: I8) -> (z: Str, a: Int, b: Int, c: Int) {
        <- ("", a, b, c)
    })
    Test check()
    Test type convert()
    Test default()
    Test lambda()
    Test linq()
    _ = <~ Test async()

    Y := Test tuple(1).to Str()

    P := App{}

    _ = P.c(1)
    Test interface(P)

    P.test func template<Int, Str>(1, "2").test package()
    
    @ True {
        <- @
    }
    
    ? 1 == 1 {
        Prt("test exception expression")
    }

    Rd()
}

Static x() := 0 -> get {
    <- (_Static x)
}

Static y() := "hello" -> get { 
    <- (_Static y) 
} set { 
    _Static y = value 
}

Readonly: Read Only<Int> = RO(5)
Static g: I64

Test tuple(i: Int) -> (v: Str) {
    <- ("tuple")
}

Test type() -> () {
    I1: I8 = 1              # sbyte #
    I2: I16 = 1             # short #
    I3: I32 = 1             # int #
    I4: I64 = 1             # long #
    U1: U8 = 1              # byte #
    U2: U16 = 1             # ushort #
    U3: U32 = 1             # uint #
    U4: U64 = 1             # ulong #
    F1: F32 = 1             # float #
    F2: F64 = 1             # double #
    Char1: Chr = 'a'        # char #
    String1: Str = "123"    # string #
    Bool1: Bool = False     # bool #
    Int1: Int = 1           # int #
    Num1: Num = 1.0         # double #
    Byte1: Byte = 1         # byte #
    Any1: Any = 1           # byte #
}

Test operator() -> () {
    I: Str = "128.687"
    I += ".890"
    B: Int
    B = 2019 05 20
    B += Const Data
    B = + - B
    B -= 1
    B *= 2
    B /= 2
    B %= 5
    Prt("2 pow 2 = ", 2 ** 2) 
    Prt("4 extract root for 2 = ", 4 // 2) 
    Prt("4 log with base 2 = ", 4 %% 2) 
    Prt(" mark string int " B " ")
    C := False
    C = ~C
    C = 1 >< 2
    C = 3 == 3
    C = 3 >= 1
    C = 1 <= 3
    C = True | False
    C = True & False
    D := (20 18. 03 09).to Int() 
    D = D.and(1).or(2).xor(3).not().lft(1).rht(2)
    Prt(B.to Str())
}

Test string() -> () {
    "love xs" @ ea {
        ? ea == 'e' {
            Prt("love xs")
        }
    }
}

Test optional() -> () {
    A: ?Int = 1
    A?.to Str()
    B: ?Str = ""
    B?.to Str()
    C: ?Any = Nil
    D: ?App = Nil
    E: ?[]?Int = []?Int{0}
    E?[0]?.to Str()?.to Str()
    F := D.or else(App{})
}

Test reference() -> () {
    x: Int = 1
    y: ?Int = 2
    Swap(a: !Int, b: !?Int) -> () {
        (b, a) = (a, b.or else(2))
    }
    Swap(x!, y!)
}

Test type convert() -> () {
    X := App{}
    Y := X:(Program)
    Z1 := (12.34).to F32()
    Z2 := Z1.to I64()
    Prt( Z2.to<Any>().to<I64>() )
    Prt( Y == :Program )
    Prt( Y >< :Program )
    Prt( X:(Program).running )
    Prt( ?(:Program) )
    Prt( ?(X) )
}

Test default() -> () {
    X := Def<Program>()
    Y := Def<Protocol>()
    Z := Def<(Int)->(Int)>()
}

Test switch() -> () {
    X :Any = 3
    X ? 1 {
        Prt(1)
    } :Str {
        Prt("string")
    } :Int {
        Prt("int")
    } Nil {
        Prt("null")
    } _ {
        Prt("default")
    }
}

Test if() -> () {
    X := 5
    ? X == 2 {
        Prt(2)
    } X == 3 {
        Prt(3)
    } _ {
        Prt("else")
    }
    ? X == 5 {
        Prt("yes")
    }
}

Test list() -> () {
    Single := {1}
    Numbers := {1,2,5,6,8,4}
    Numbers = Numbers + 0
    Numbers += 3 + 7
    Numbers -= 6
    Take := Numbers[0]
    Take = In Package Array{}.arr[2]
    Object := {"123", 432, App{}}
    Numbers In Numbers := {{1,1,1}, {1,1,1}}
    Empty := []Int{}
    Array: [:]Int = Array of(1,2,3)
    Numbers @ [i]v {
        Prt(i, ":", v)
    }
    Slice := Numbers[0<=]
    Slice2 := Numbers[<3]
}

Test set() -> () {
    Empty := [Str]{}
    Numbers: [Int] = {[1],[2],[5],[6],[8],[4]}
    Numbers @ item {
        Prt(item)
    }
}

Test dictionary() -> () {
    Empty := [Str]Int{}
    Temp := {["k1"]1,["k2"]2}
    Temp += {["k3"]3}
    Temp @ [k]v {
        Prt(k)
        Prt(v)
    }
    Temp -= "k1"
    Prt(Temp["k2"])
}

Test loop() -> () {
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
    A := 0
    B := 8
    @ A < B {
        A += 1
    }
}

Test check() -> () {
    Z1: ?Defer = Nil
    Defer{} ! Z2
    ! {
        Z1 = Defer{}
        Defer{} ! Z3
        X := 1 * 1
        Y := 1 + 1
    } ex: IOException {
        !(ex)
    } e {
        !(e)
    } _ {
        ? Z1 >< Nil {
            Z1.Dispose()
        }
    }
}

Test func(s: Str = "test") -> (out1: Str, out2: Int) {
    s = s + "test"
    I1 := 1+1*3*9/8
    I2 := I1 + 5 + (I1 + 8)
    # func in func #
    In func() -> () {
        <- ()
    }
    In func()

    <- (s, I2)
}

Test func params(a: Int, b: Int, fn: (Int, Int, Int, I8) ->
    (Str, Int, Int, Int)) -> (a: Int, b: Str, c: Str) {
    <- (0, "", "")
}

Test lambda() -> () {
    Test1(fn: (Int, Int) -> (Int, Int)) -> () {
        (O1,O2) := fn(1, 2)
    }
    Test1( {i1,i2 -> (i1,i2)} )

    Test2(fn: () -> (Int)) -> () {
        O1 := fn()
    }
    Test2{->1}

    Test3(fn: (Int) ~> ()) -> () {
        fn(1)
    }
    Test3( (it: Int) ~> () {
        <~ Dly(1000)
        Prt(it)
    })
    Test3{it ~>
        <~ Dly(1000)
        Prt(it)
    }
    Test4(fn: (Int) ~> (Int)) -> () { 
        fn(18) 
    }
    Test4{it~>it+1}
}

Test async() ~> (x: Int, y: Int, z: Str) {
    Slp(1000)
    [1<=10] @ i {
        Go{ ~> 
            <~ Dly(1000)
            Prt("task", i)
        }
        Go{ -> 
            <- ()
        }
    }
    Fun wait() ~> () {
        <~ Dly(1000)
    }
    <~ Fun wait()
    
    <- (1, 2, "123")
}

Test linq() -> () {
    Numbers := {0, 1, 2, 3, 4, 5, 6}
    Linq := from i -> in Numbers -> where (i % 2) == 0 ->
    orderby i -> descending -> select i
    Lambda := Numbers.Where{ i -> i%2==0 }.OrderBy{ i -> i }.ToList()
}

Test interface(in: Protocol) -> () {}

Const Data :: 256
Const Data2: Str: "512"
Const Data3: Int: Const Data
Const function() -> (v: Int) { 
    <- (Const Data) 
}

In Package Array -> {
    arr: []Int = {1,2,3,4,5,6,7}
}

Defer -> {
    :IDisposable
    data := ""
}

(me: Defer) Dispose() -> () {}

App -> {
    :Program
    :Protocol
    i := 555
    arr := {1,1,1,1}
    _pri name := " Program "
    _b := 5
    b(): Int -> get { 
        <- (_b) 
    } set { 
        _b = value 
    }

    f(): Str = "get"
}

(me: App) test package() -> () {
    Item := Program{name = "new Program",running = True}
    Item2 := {
        name = "new Program",
        running = True
    }
    Item3 := []Int{1,2,3,4,5}
    Item4 := [Str]Int{["1"]1,["2"]2,["3"]3}
    Item5 := <Package Child>(1,2) # New #
}

(me: App) test func template<T1, T2>(data1: T1, data2: T2) -> (data: App) {
    <- (me)
}

(me: App) c(x: Int) -> (y: Int) {
    <- (x + me.b)
}

(me: App) d() ~> (x: Int) {
    <~ Dly(1000)
    <- (3)
}

(me: App) e() ~> () {
    <~ Dly(1000)
}

Result -> {
    data: Str
} 
(me: Result) <>(data: Str) {
    me.data = data
}

Test package template<T:class> -> {
    data: T
}
(me:Test package template<T>) generic(a: T) -> () {}

Test protocol template<T:class> <- {
    test<H:class>(in: H) -> ()
    test(in: T) -> ()
}

Test implement template -> {
    :Test protocol template<Test implement template>
}
(me: Test implement template) test(in: Test implement template) -> () {}
(me: Test implement template) test<H:class>(in: H) -> () {}

Program -> {
    name(): Str = "name" -> set { 
        _name = value 
    }

    running: Bool
}

Protocol <- {
    b(): Int 
    c(x: Int) -> (y: Int)
    d() ~> (y: Int)
    e() ~> ()
    f(): Str
}

[Table("test")]
Test Annotation -> {
    [Key, Column("id")]
    id(): Str
    [Column("nick_name")]
    nick name(): Str
    [Column("profile")]
    profile(): Str
}

Test Enum -> Int[
    OK
    Error = -1
]

Package -> {
    x: Int
    y: Int
}
(me:Package) <>(y: Int = 3) {
    me.x = Const Data
    me.y = y
}
(me:Package) parent func() -> () {
    me.x = 21
    Prt("package")
}

Package Child -> {
    :Package
    x: Int
} 
(me:Package Child) <>(x: Int, y: Int)(y) {
    me.x = x
}
(me:Package Child)(super) parent func() -> () {
    super.x = 64
    Prt("package child")
}
