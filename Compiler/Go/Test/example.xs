"main" {
    # "./project/package path" package. #
    "fmt" fmt.
}

main() -> () {
    test(1, "2")
    test judge()
    test loop()
    m := man{}
    test protocol(m?)
}

pi :: 3.14
eight: Int: 8

num1 := 1
num2: Num = 12.34 5678

work => (Str)->()
do work -> (Str)->()

test(x:Int, y:Str) -> (r1:Str, r2:Int) {
    a := x * 3
    b: Int = 2
    <- ("hello", a+b)
}

test judge() -> () {
    ? 1 + 1 == 2 {

    } 2 * 3 == 6 {

    } _ {

    }
    a := 5
    a ? 1 {
        a += 1
    } 2 {
        a += 2
    } _ {
        a += 0
    }
}

test loop() -> () {
    a := 0
    arr := []Int{1,2,3,4,5}
    arr @ i {
        a += i
    }
    arr @ [i]v {
        a += i + v
    }
    dic := [Str]Int{["1"]1,["2"]2}
    dic @ i {
        a += i
    }
    [0 <= 10] @ i {
        a += i
        ? i == 7 {
            -> @
        }
    }
    [5 > 0] @ i {
        a += i
    }
    @ a > 0 {
        a -= 1
    }
    @ {
        <- @
    }
}

human -> {
    name: Str
}

(me: ?human) say name() -> (n: Str) {
    <- (me.name)
}

man -> {
    human
    age: Int
}

(me: ?man) do something(work: Str) -> () {
    Println(work)
}

person <- {
    say name() -> (n:Str)
}

worker <- {
    person
    do something(work: Str) -> ()
}

test protocol(w: worker) -> (i:{}) {
    w.do something("protocol")
    <- (w)
}

test go() -> () {
    
}