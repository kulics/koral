demo=run {
    Library
    System
    System\IO
    System\Linq
    System\ComponentModel\DataAnnotations\Schema
    System\ComponentModel\DataAnnotations
}

# main function
Main ()~>() {
    cmd.prt("main function")
    # run test
    testSharpType()
    testOperator()
    testString()
    testOptional()
    testSwitch()
    testIf()
    testArray()
    testDictionary()
    testLoop()
    x := testFunc("testcall")
    _ = testFuncParams(1, 2, _(a,b,c: i32, d: i8)->(z: str, a,b,c: i32) {
        <- ("",a,b,c)
    })
    testCheck()
    testTypeConvert()
    testDefault()
    testLambda()
    _ = <~ testAsync()

    y := testTuple_(1).toStr()

    p := app{}

    _ = p.protocol.c(1)
    testInterface(p.protocol)

    p.testFuncTemplate<i32,str>(1, "2").testPackage()
    
    cmd.rd()
}

StaticX := 0
StaticY := "hello"
readonlyZ := "1024"
StaticG :i64
StaticP :str {
    get { <- (staticY) }
    set { staticY = value }
}

testTuple_ (i:i32)->(v:str) {
    <- ("tuple")
}

testSharpType ()->() {
    i1 : \System.SByte = 1               # sbyte
    i2 : \System.Int16 = 1               # short
    i3 : \System.Int32 = 1               # int
    i4 : \System.Int64 = 1               # long
    u1 : \System.Byte = 1                # byte
    u2 : \System.UInt16 = 1              # ushort
    u3 : \System.UInt32 = 1              # uint
    u4 : \System.UInt64 = 1              # ulong
    f1 : \System.Single = 1              # float
    f2 : \System.Double = 1              # double
    char1 : \System.Char = 'a'           # char
    string1 : \System.String = "123"     # string
}

testOperator ()->() {
    I :str = "128.687"
    i += ".890"
    B :i32
    b = 0
    b += ConstData
    b = + - b
    b -= 1
    b *= 2
    b /= 2
    b %= 5
    i += " mark string i32 {b} "
    c := false
    c = ~c
    c = 1 ~= 2
    c = 3 == 3
    c = 3 >= 1
    c = 1 <= 3
    c = true | false
    c = true & false
    d := 11
    d = d.and(1).or(2).xor(3).not().lft(1).rht(2)
    cmd.prt(b.toStr())
}

testString ()->() {
    @ "love xs" {
        ? ea == 'e' {
            cmd.prt("love xs")
        }
    }
}

testOptional ()->() {
    a: i32? = 1
    a?.toStr()
    b: str? = ""
    b!.toStr()
    c: obj? = nil
    d: app! = nil
    e: [i32?]? = [i32?]?{<-0}
    e?[0]?.toStr()?.toStr()
}

testTypeConvert ()->() {
    x := app{}
    y := x.as<program>()
    z1 := _(12.34).toF32()
    z2 := z1.toI64()
    cmd.prt( z2.to<obj>().to<i64>() )
    cmd.prt( y.is<program>() )
    cmd.prt( x.as<program>().running )
    cmd.prt( ?(:program) )
    cmd.prt( ?(x) )
}

testDefault ()->() {
    x := lib.def<program>()
    y := lib.def<protocol>()
    z := lib.def<(a:i32)->(b:i32)>()
}

testSwitch ()->() {
    x :obj = 3
    ? x -> 1 {
        cmd.prt(1)
    } :str {
        cmd.prt("string")
    } :i32 {
        cmd.prt("int")
    } nil {
        cmd.prt("nil")
    } _ {
        cmd.prt("default")
    }
}

testIf ()->() {
    x := 5
    ? x == 2 {
        cmd.prt(2)
    } x == 3 {
        cmd.prt(3)
    } _ {
        cmd.prt("else")
    }
    ? x == 5 {
        cmd.prt("yes")
    }
}

testArray ()->() {
    arrSingle := _{1}
    arrNumber := _{1,2,5,6,8,4}
    arrNumber = arrNumber + 0
    arrNumber += 3 + 7
    arrNumber -= 6
    take := arrNumber[0]
    take = inPackageArray{}.arr[2]
    arrObj := _{"123", 432, app{}}
    arrArr := _{_{1,1,1},_{1,1,1}}
    arrEmpty := [i32]{}
    arrType := _{1,2,3}
    array : [|i32|] = _{|1,2,3|}
    @ arrNumber {
        cmd.prt(ea)
    }
    @ item <- arrNumber {
        cmd.prt(item)
    }
    @ i->v <- arrNumber {
        cmd.prt(i)
        cmd.prt(v)
    }
    slice := arrNumber[0<=]
    slice2 := arrNumber[<3]
}

testDictionary ()->() {
    empty := [str->i32]{}
    dicSN := _{"k1"->1,"k2"->2}
    dicSN += _{"k3"->3}
    @ k->v <- dicSN {
        cmd.prt(k)
        cmd.prt(v)
    }
    dicSN -= "k1"
    cmd.prt(dicSN["k2"])
}

testLoop ()->() {
    cmd.prt(" 0 to 10")
    @ i <- [0 <= 10] {
        cmd.prt(i, ", ", "")
    }
    cmd.prt(" ")
    cmd.prt(" 0 to 8 step 2")
    @ [0 < 8; 2] {
        cmd.prt(ea, ", ", "")
    }
    cmd.prt(" ")
    cmd.prt(" 8 to 2 step 2")
    @ [8 > 0; 2] {
        cmd.prt(ea, ", ", "")
        ? ea == 6 {
            -> @
        }
    }
    cmd.prt(" ")
    @ {
        <- @
    }
    a := 0
    b := 8
    @ ? a < b {
        a += 1
    }
}

testFunc (s: str)->(out1: str, out2: i32) {
    s = s + "test"
    i := 1+1*3*9/8
    out2 := i + 5 + _(i + 8)
    # func in func
    InFunc ()->() {
        <- ()
    }
    InFunc()

    <- (s, i)
}

testFuncParams (a,b: i32, fn: (a,b,c: i32, d: i8)->(z: str, a,b,c: i32))->(a: i32, b,c: str) {
    <- (0,"", "")
}

testLambda ()->() {
    test1 (fn: (i1: i32, i2: i32)->(o1: i32, o2: i32))->() {
        _(o1,o2) := fn(1, 2)
    }
    test1( $i1,i2-> _(i1,i2) )

    test2 (fn: ()->(o1: i32))->() {
        o1 := fn()
    }
    test2( $->1 )

    test3 (fn: (it: i32)->())->() {
        fn(1)
    }
    test3( _(it:i32)~>(){
        <~ tsks.delay(5000)
        cmd.prt(it)
    })
    test3( ${ it ~>
        <~ tsks.delay(5000)
        cmd.prt(it)
    })
    test4(fn: (it:i32)->(v:i32))->(){ fn(18) }
    test4($it+1)
}

testCheck ()->() {
    z :defer = nil
    ! z2 := defer{} {
        z = defer{}
        ! z3 := defer{} {
            x := 1 * 1
        }
        ! {
            y := 1 + 1
        } -> {
            !(ex)
        }
    } -> :IOException {
        !(ex)
    } e:Exception {
        !(e)
    } _ {
        ? z ~= nil {
            z.IDisposable.Dispose()
        }
    }
}

testAsync ()~>(x:i32,y:i32,z:str) {
    <~ tsks.delay(5000)
    async1 ()~>() {
        <~ tsks.delay(5000)
    }
    <~ async1()
    
    <- (1, 2, "123")
}

testLinq ()->() {
    numbers :=  _{0, 1, 2, 3, 4, 5, 6}
    arr := from num in numbers where _(num % 2) == 0 
    orderby num descending select num
}

testInterface (in: protocol)->() {}

inPackageArray {} -> {
    arr :[i32]

    .. {
        arr = _{1,2,3,4,5,6,7}
    }
}

defer {} -> {
    str :str
}

defer += IDisposable {
    Dispose ()->(){}
}

app {}-> program{} { 
    i := 555
    d := 128.687
    b := "12"
    c := true
    arr := _{1,1,1,1}
    _PriName := " program "
    _b := 5
} 

app += {
    testPackage ()->() {
        item := program{<- Name = "new program",running = true}
        item2 := _{
            Name := "new program"
            running := true
        }
        item3 := [i32]{<- 1,2,3,4,5}
        item4 := [str->i32]{<- "1"->1,"2"->2,"3"->3}
    }

    testFuncTemplate<T1,T2> (data1: T1, data2: T2)->(data: app) {
        <- (..)
    }
}

app += protocol {
    b :i32 {
        get { <- (_b) } 
        set { _b = value }
    }

    c (x: i32)->(y: i32) {
        <- (x + ..protocol.b)
    }

    d ()~>(x: i32) {
        <~ tsks.delay(5000)
        <- (3)
    }

    e ()~>() {
        <~ tsks.delay(5000)
    }

    f :str
}

result {data: str} ->{
    data :str

    ..{
        ..data = data
    }
}

testPackageTemplate<T> {}-> {
    data :T
}

testPackageTemplate<T> += {
    Generic (a:T)->(){}
}

testProtocolTemplate<T> -> {
    test<T> (in:T)->(){}
}

testImplementTemplate {}->{}
testImplementTemplate += testProtocolTemplate<testImplementTemplate> {
    test<testImplementTemplate> (in:testImplementTemplate)->(){}
}

program {}-> {
    Name :str?
    running :bl?

    Property :str? {
        get { <- (Name) }
        set { Name = value }
    }
}

protocol -> {
    b :i32 { get{} set{} }
    c (x:i32)->(y:i32){}
    d ()~>(y:i32){}
    e ()~>(){}
    f :str
}

`Table{"test"}`
testAnnotation {}-> {
    `Key, Column{"id"}`
    Id :str?
    `Column{"nick_name"}`
    NickName :str?
    `Column{"profile"}`
    Profile :str?
}

testEnum [Ok, Err = -1]

ConstData 256
ConstData2 :str "512"

OtherFunction ()->(v:i32) { <- (ConstData) }

Package {y: i32}-> {
    x :i32
    y :i32

    .. {
        ..x = ConstData
        ..y = y
    }
}

PackageChild {x, y: i32}-> Package{y}{
    x :i32

    ..{
        ..x = x
    }
}
