\demo {
    System
    System\IO
    System\Linq
    System\ComponentModel\DataAnnotations\Schema
    System\ComponentModel\DataAnnotations
}

program. {
    StaticG = 5
} -> {
    ## 
        main function 
    ##
    Main() ~> () {
        prt("main function")
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
        _ = testFuncParams(1, 2, 
        (a: i32, b: i32, c: i32, d: i8) -> (z: str, a: i32, b: i32, c: i32) {
            <- ("",a,b,c)
        })
        testCheck()
        testTypeConvert()
        testDefault()
        testLambda()
        _ = <~ testAsync()

        y := testTuple(1).toStr()

        p := app{}

        _ = p.c(1)
        testInterface(p)

        p.testFuncTemplate<i32, str>(1, "2").testPackage()
        
        rd()
    }

    StaticX := 0
    StaticY := "hello"
    readonlyZ := "1024"
    StaticG: i64
    StaticP: str {
        get { 
            <- (StaticY) 
        }
        set { 
            StaticY = value 
        }
    }

    testTuple(i: i32) -> (v: str) {
        <- ("tuple")
    }

    testSharpType() -> () {
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

    testOperator() -> () {
        I :str = "128.687"
        I += ".890"
        B :i32
        B = 0
        B += const_data
        B = + - B
        B -= 1
        B *= 2
        B /= 2
        B %= 5
        I += " mark string i32 {B} "
        C := false
        C = ~C
        C = 1 ~= 2
        C = 3 == 3
        C = 3 >= 1
        C = 1 <= 3
        C = true | false
        C = true & false
        D := 11
        D = D.and(1).or(2).xor(3).not().lft(1).rht(2)
        prt(B.toStr())
    }

    testString() -> () {
        @ ea <- "love xs" {
            ? ea == 'e' {
                prt("love xs")
            }
        }
    }

    testOptional() -> () {
        a: i32? = 1
        a?.toStr()
        b: str? = ""
        b!.toStr()
        c: obj? = nil
        d: app! = nil
        e: [i32?]? = [i32?]?{<-0}
        e?[0]?.toStr()?.toStr()
    }

    testTypeConvert() -> () {
        x := app{}
        y := x.as<program>()
        z1 := (12.34).toF32()
        z2 := z1.toI64()
        prt( z2.to<obj>().to<i64>() )
        prt( y.is<program>() )
        prt( x.as<program>().Running )
        prt( ?(:program) )
        prt( ?(x) )
    }

    testDefault() -> () {
        x := def<program>()
        y := def<protocol>()
        z := def<(a:i32)->(b:i32)>()
    }

    testSwitch() -> () {
        x :obj = 3
        ? x -> 1 {
            prt(1)
        } :str {
            prt("string")
        } :i32 {
            prt("int")
        } nil {
            prt("nil")
        } _ {
            prt("default")
        }
    }

    testIf() -> () {
        x := 5
        ? x == 2 {
            prt(2)
        } x == 3 {
            prt(3)
        } _ {
            prt("else")
        }
        ? x == 5 {
            prt("yes")
        }
    }

    testArray() -> () {
        arrSingle := {1}
        ArrNumber := {1,2,5,6,8,4}
        ArrNumber = ArrNumber + 0
        ArrNumber += 3 + 7
        ArrNumber -= 6
        Take := ArrNumber[0]
        Take = inPackageArray{}.arr[2]
        arrObj := {"123", 432, app{}}
        arrArr := {{1,1,1}, {1,1,1}}
        arrEmpty := [i32]{}
        arrType := {1,2,3}
        array : [|i32|] = {|1,2,3|}
        @ item <- ArrNumber {
            prt(item)
        }
        @ [i]v <- ArrNumber {
            prt(i)
            prt(v)
        }
        slice := ArrNumber[0<=]
        slice2 := ArrNumber[<3]
    }

    testDictionary() -> () {
        empty := [[str]i32]{}
        DicTemp := {["k1"]1,["k2"]2}
        DicTemp += {["k3"]3}
        @ [k]v <- DicTemp {
            prt(k)
            prt(v)
        }
        DicTemp -= "k1"
        prt(DicTemp["k2"])
    }

    testLoop() -> () {
        prt(" 0 to 10")
        @ i <- [0 <= 10] {
            prt(i, ", ", "")
        }
        prt(" ")
        prt(" 0 to 8 step 2")
        @ ea <- [0 < 8, 2] {
            prt(ea, ", ", "")
        }
        prt(" ")
        prt(" 8 to 2 step 2")
        @ ea <- [8 > 0, 2] {
            prt(ea, ", ", "")
            ? ea == 6 {
                -> @
            }
        }
        prt(" ")
        @ {
            <- @
        }
        A := 0
        b := 8
        @ ? A < b {
            A += 1
        }
    }

    testCheck() -> () {
        Z :defer? = nil
        ! z2 := defer{} {
            Z = defer{}
            ! z3 := defer{} {
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
            ? Z ~= nil {
                Z.Dispose()
            }
        }
    }

    testFunc(S: str) -> (out1: str, out2: i32) {
        S = S + "test"
        i := 1+1*3*9/8
        out2 := i + 5 + (i + 8)
        # func in func
        InFunc() -> () {
            <- ()
        }
        InFunc()

        <- (S, i)
    }

    testFuncParams(a: i32, b: i32, fn: (a: i32, b: i32, c: i32, d: i8) ->
     (z: str, a: i32, b: i32, c: i32)) -> (a: i32, b: str, c: str) {
        <- (0,"", "")
    }

    testLambda() -> () {
        test1(fn: (i1: i32, i2: i32) -> (o1: i32, o2: i32)) -> () {
            (o1,o2) := fn(1, 2)
        }
        test1( {i1,i2-> (i1,i2)} )

        test2(fn: () -> (o1: i32)) -> () {
            o1 := fn()
        }
        test2( {->1} )

        test3(fn: (it: i32) -> ()) -> () {
            fn(1)
        }
        test3( (it: i32) ~> () {
            <~ tsks.delay(5000)
            prt(it)
        })
        test3( {it ~>
            <~ tsks.delay(5000)
            prt(it)
        })
        test4(fn: (it: i32) -> (v: i32)) -> () { 
            fn(18) 
        }
        test4({it->it+1})
    }

    testAsync() ~> (x: i32, y: i32, z: str) {
        <~ tsks.delay(5000)
        async1() ~> () {
            <~ tsks.delay(5000)
        }
        <~ async1()
        
        <- (1, 2, "123")
    }

    testLinq() -> () {
        numbers := {0, 1, 2, 3, 4, 5, 6}
        arr := from num in numbers where (num % 2) == 0 
        orderby num descending select num
    }

    testInterface(in: protocol) -> () {}

    const_data 256
    const_data2 :str "512"
    constFunction() -> (v: i32) { 
        <- (const_data) 
    }
}

inPackageArray{} {
    arr = {1,2,3,4,5,6,7}
} -> {
    arr: [i32]
}

defer{} -> {
    data := ""
} :IDisposable {
    Dispose() -> () {}
}

app{} -> { 
    i := 555
    arr := {1,1,1,1}
    _PriName := " program "
    _B := 5

    testPackage() -> () {
        item := program{<- Name = "new program",Running = true}
        item2 := {
            Name := "new program"
            running := true
        }
        item3 := [i32]{<- 1,2,3,4,5}
        item4 := [[str]i32]{<- ["1"]1,["2"]2,["3"]3}
    }

    testFuncTemplate<T1, T2>(data1: T1, data2: T2) -> (data: app) {
        <- (..)
    }
} ::program{} {
    
} :protocol {
    B: i32 {
        get { 
            <- (_B) 
        }
        set { 
            _B = value 
        }
    }

    c(x: i32) -> (y: i32) {
        <- (x + ..B)
    }

    d() ~> (x: i32) {
        <~ tsks.delay(5000)
        <- (3)
    }

    e() ~> () {
        <~ tsks.delay(5000)
    }

    f: str = "get"
} 

result{data: str} {
    ..data = data
} -> {
    data: str
}

testPackageTemplate<T>{} -> {
    data: T

    Generic(a: T) -> () {}
}

testStaticTemplate<T>. -> {
    const_data: T
}

testProtocolTemplate<T> -> {
    test<T>(in: T) -> ()
}

testImplementTemplate{} -> {
} :testProtocolTemplate<testImplementTemplate> {
    test<testImplementTemplate>(in: testImplementTemplate) -> () {}
}

program{} -> {
    Name: str?
    Running: bl?

    Property: str? {
        get { 
            <- (Name) 
        }
        set { 
            Name = value 
        }
    }
}

protocol -> {
    B: i32 
    c(x: i32) -> (y: i32)
    d() ~> (y: i32)
    e() ~> ()
    f: str
}

`Table{"test"}`
testAnnotation{} -> {
    `Key, Column{"id"}`
    Id: str?
    `Column{"nick_name"}`
    NickName: str?
    `Column{"profile"}`
    Profile: str?
}

testEnum. -> ?{
    Ok
    Err = -1
}

package{y: i32} {
    ..x = testStaticTemplate<i32>.const_data
    ..y = y
} -> {
    x: i32
    y: i32
}

packageChild{x: i32, y: i32}  {
    ..x = x
} -> {
    x: i32
} ::package{y} {

}