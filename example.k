example . {
    System
    System.IO
    System.Linq
    System.ComponentModel.DataAnnotations.Schema
    System.ComponentModel.DataAnnotations

    _ : example.example_static
}

#=
    main function
=#
Main : (->>) {
    print("main function")
    # run test
    test_type()
    test_operator()
    test_string()
    test_optional()
    test_list()
    test_set()
    test_dictionary()
    test_switch()
    test_if()
    test_foreach()
    test_while()
    x! : test_func("testcall")
    test_func_params(1, 2,
    (a int, b int, c int, d i8 -> z str, a int, b int, c int) {
        <- "", a, b, c
    })
    test_check()
    test_type_convert()
    test_empty()
    test_lambda()
    test_linq()
    << test_async()

    y! : test_tuple(1).to_str()

    p! : example.app{}

    p.c(1)
    test_interface(p)

    p.[test_func_template int, str](1, "2").test_package()
    
    @ true {
        ~@
    }
    
    ? 1 == 1 {
        print("test exception expression")
    }

    read()
}

<get,set>
static_x! : 0

<get{i->i},set{i,v->i=v;}>
static_y! : "hello"

<_get{->static_x},set{v->static_x=v;}>
static_z! int

static_g! i64

test_tuple : (i int -> v str) {
    <- "tuple"
}

test_type : (->) {
    I1 i8 : 1              # sbyte
    I2 i16 : 1             # short
    I3 i32 : 1             # int
    I4 i64 : 1             # long
    U1 u8 : 1              # byte
    U2 u16 : 1             # ushort
    U3 u32 : 1             # uint
    U4 u64 : 1             # ulong
    F1 f32 : 1             # float
    F2 f64 : 1             # double
    Char1 chr : 'a'        # char
    String1 str : "123"    # string
    Bool1 bool : false     # bool
    Int1 int : 1           # int
    Num1 num : 1.0         # double
    Byte1 byte : 1         # byte
    Any1 any : 1           # object
}

test_operator : (->) {
    I! str : "128.687"
    I += ".890"
    A : 003.141592653e3
    B! int
    B = 2020_01_16
    B = 0b1010_1101
    B = 0X56_fa_C4
    B += ConstData
    B = + - B
    B = B + 1
    B = B * 2
    B = B / 2
    B = B % 2
    B = B ^ 2 int!
    print(" mark string int \b ${B}123{} \${B} ${I;I}")
    print(""" "raw" mark string \b
     int ${B}123{} $ {}
      ${I}
    """)
    print(""" 
       " raw "
        string
      """, """""")
    C! : false
    C = ~C
    C = 1 >< 2
    C = 3 == 3
    C = 3 >= 1
    C = 1 <= 3
    C = true | false
    C = true & false
    D! : (2018.0309).to_int() 
    D = ~~ D && 1 || 2 ^^ 3 << 1 >> 2
    D = 1 <> 2
    print(B.to_str(), D)
}

test_string : (->) {
    @ ea : "love programming".. {
        ? ea == 'e' {
            print("love programming")
        }
    }
}

test_optional : (->) {
    A! ?int
    A = 1
    A?.to_str()
    B! ?str : ""
    B?.to_str()
    C ?any : nil
    D ?app : nil
    E ?[]?int : []?int{0}
    E?[0]?.to_str()?.to_str()
    F : D ?? app{}
}

test_reference : (->) {
    x! int : 1
    y! ?int : 2
    swap : (a! int, b! ?int ->) {
        b, a = a, b ?? 2
    }
    swap(x!, y!)
}

test_type_convert : (->) {
    x : app{}
    y : x program!
    z1 : (12.34).to_f32()
    z2 : z1.to_i64()
    print( z2.[to any]().[to i64]() )
    print( y program? )
    print( (x program!).running )
    print( [typeof program]() )
}

test_empty : (->) {
    x : [empty program]()
    y : [empty protocol]()
    Z : [empty (int->int)]()
}

test_list : (->) {
    Single : {1}
    Numbers! : {1;2;5;6;8;4}
    Numbers = Numbers + 0
    Numbers += 3 + 7
    Numbers -= 6
    three : 3
    Numbers[three] = 5
    Take! : Numbers[0]
    Take = in_package_array{}.arr[2]
    Object : {"123"; 432; app{}}
    NumbersInNumbers! : {{1;1;1}; {1;1;1}}
    NumbersInNumbers[0][0] = 3
    Empty : [][]int{}
    Array [.]int : array_of(1,2,3)
    @ [i]v : Numbers.. {
        print(i, ":", v)
    }
    Slice : Numbers[0~_]
    Slice2 : Numbers[_~3]
}

test_set : (->) {
    Empty : [str]_{}
    Numbers [int]_ : {[1]_;[2]_;[5]_;[6]_;[8]_;[4]_}
    @ item : Numbers.. {
        print(item)
    }
}

test_dictionary : (->) {
    Empty : [str][int]int{}
    Temp! : {["k1"]1;["k2"]2}
    Temp += {["k3"]3}
    @ [k]v : Temp.. {
        print(k)
        print(v)
    }
    Temp -= "k1"
    print(Temp["k2"])
}

test_stack : (->) {
    temp : [>]int{}
    temp.push(1)
    temp.pop()
}

test_queue : (->) {
    temp : [<]int{}
    temp.enqueue(1)
    temp.dequeue()
}

test_combined_type : (->) {
    # swift: [int:[[str:[str:[str]]]]]
    # go: map[int][]map[str]map[str][]str
    # c#: map<int,list<map<str,map<str,list<str>>>>>
    type1! [int][][str][str][]str
    type2! [dictionary int, [list [dictionary str, [dictionary str, [list str]]]]]
}

test_switch : (->) {
    x any : 3
    ? x.. 1, 2, 3 {
        print("1,2,3")
    } _ str {
        print("string")
    } _ int {
        print("int")
    } nil {
        print("null")
    } _ {
        print("default")
    }
    y : ? x.. -> 3 {
        12
    } _ {
        0
    }
}

test_if : (->) {
    x : 5
    ? x == 2 {
        print(2)
    } x == 3 {
        print(3)
    } _ {
        print("else")
    }
    ? x == 5 {
        print("yes")
    }
    y : ? -> x == 5 {
        x * x
    } _ {
        0
    }
}

test_foreach : (->) {
    print(" 0 to 10")
    @ i : 0 ~ 10.. {
        print(i, ", ", "")
    }
    print(" ")
    print(" 0 to 8 step 2")
    @ ea : 0 ~(2) 8.. {
        print(ea, ", ", "")
    }
    print(" ")
    print(" 8 to 2 step 2")
    @ ea : 8 ~~(2) 2.. {
        print(ea, ", ", "")
        ? ea == 6 {
            ..@
        }
    }
    print(" ")
    arr! : []int{}
    @ i : arr.. {
        print(i)
    } _ {
        print("loop else")
    }
    @ i : 7 ~ 7.. {
        print(i)
    } _ {
        print("loop else")
    }
    arr = @ i : {1;2;3;4;5}.. -> {
        i * 2
    } _ {
        nil
    }
    arr = @ i : 0 ~ 5.. -> {
        i * 3
    }
}

test_while : (->) {
    A! : 0
    B : 8
    @ A < B {
        A += 1
        ~@
    } _ {
        print("loop else")
    }
}

test_check : (->!) {
    z1! ?defer : nil
    ! z2 : defer{}
    ! {
        z1 = defer{}
        ! z3 : defer{}
        x : 1 * 1
        y : 1 + 1
    } ex IOException {
        ! <- ex
    } e {
        ! <- e
    } _ {
        ? z1 >< nil {
            z1.Dispose()
        }
    }
    z1 = ! -> {
        defer{}
    } e {
        defer{}
    }
}

test_func : (s str = "test" -> out1 str, out2 int) {
    s = s + "test"
    I1 : 1+1*3*9/8
    I2 : I1 + 5 + (I1 + 8)
    # func in func
    Infunc : (->) {
        <-
    }
    Infunc()

    <- s, I2
}

test_func_params : (a int, b int, fn (int, int, int, i8 ->
    str, int, int, int), arr ...int -> a int, b str, c str) {
    <- 0, "", ""
}

test_lambda : (->) {
    Test1 : (fn (int, int -> int, int)->) {
        O1!, O2! : fn(1, 2)
    }
    Test1( {i1,i2 -> i1,i2} )

    Test2 : (fn (->int) -> ) {
        O1! : fn()
    }
    Test2{->1}

    Test3 : (fn (int ->> ) -> ) {
        fn(1)
    }
    Test3( (it int ->> ) {
        << delay(1000)
        print(it)
    })
    Test3{it ->>
        << delay(1000)
        print(it)
    }
    Test4 : (fn (int ->> int) -> ) { 
        fn(18) 
    }
    Test4{it->>it+1}
}

test_yield : (-> @ v int) {
    @ i : 1 ~ 10.. {
        ? i < 7 {
            @ <- i
        } _ {
            @ <-
        }
    }
}

test_async : (->> x int, y int, z str) {
    sleep(1000)
    @ i : 1 ~ 10.. {
        go{ ->> 
            << delay(1000)
            print("task", i)
        }
        go{ -> 
            <-
        }
    }
    AsyncVoid : (->>_) {
        << delay(1000)
    }
    FunWait : (->> x int, y int, z str) {
        << delay(1000)
        <- 1, 2, "123"
    }
    <<- FunWait()
}

test_linq : (->) {
    Numbers : {0; 1; 2; 3; 4; 5; 6}
    Linq : @ i : Numbers.. -> where (i % 2) == 0 ->
    orderby i -> descending -> select i
    Lambda : Numbers.Where{ i -> i%2==0 }.OrderBy{ i -> i }.ToList()
}

test_define : (->) {
    a! : 1
    ? a == 1 {
        b! : 2
        b = 3
        a = 3
    } a == 2 {
        b! : 2
        b = 3
        ? b == 2 {
            a = 1
        }
    } _ {
        b! : 2
        b = 3
        a = 3
    }
    ? a.. 1 {
        b! : 2
        b = 3
        a = 3
        ? a == 3 {
            b = 1
            a = 1
        } _ {
            a = 2
        }
    } c int {
        c = 2
        a = 1
    } _ {
        b! : 2
        b = 3
        a = 3
    }
    ! {
        a = 2
    } e {
        e = Exception{}
    }
}

test_interface : (in protocol->) {}

ConstData : 256
ConstData2 str : "512"
ConstData3 int : ConstData
ConstFunction : (->v int) { 
    <- ConstData
}

测试中文 : (甲 int->乙 int) {
    乙! : 甲 + 1
    <- 乙
}

in_package_array : $ {
    arr! []int : {1;2;3;4;5;6;7}
}

defer : IDisposable & $ {
    data! : ""

    Dispose : (->) {}
}

app : program & $ (me) { 
    i! : 555
    arr! : {1;1;1;1}
    _priName! : " program "
    _b! : 5
    <get{i->i},set{i,v->i=v;}>
    a! : 1

    test_package : (->) {
        Item : program{name = "new program"; running = true}
        Item2 : {
            name : "new program"
            running : true
        }
        Item3 : []int{1;2;3;4;5}
        Item4 : [str]int{["1"]1;["2"]2;["3"]3}
        Item5 : package_child(1,2) # New
    }

    [test_func_template T1, T2] : (data1 T1, data2 T2 -> data app) {
        <- me
    }
} & $ protocol(me) {
    <get{->me._b}, set{v->me._b = v;}>
    b! int
    <get,set>
    f! str

    c : (x int -> y int) {
        <- x + me.b
    }

    d : (->> x int) {
        << delay(1000)
        <- 3
    }

    e : (->>) {
        << delay(1000)
    }

    g : (-> @ v int) {
        @ i : 1 ~ 3.. {
            @ <- i
        }
    }
}

result : $ {
    data! str
}
result += (data str->$me) {
    me.data = data
}

[test_package_template (T class)] : $ {
    data! T
    generic : (a T -> ) {}
}

[test_protocol_template (T class)] : $$ {
    [test (H class)] (in H -> )
    test (in T -> )
}

test_implement_template : $ [test_protocol_template test_implement_template](me) {
    test : (in test_implement_template -> ) {}
    [test (H class)] : (in H -> ) {}
}

program : $ {
    running! bool
}

program += $ {
    <get,set>
    name! str
}

protocol : $$ {
    b! int
    c (x int -> y int)
    d (->>y int)
    e (->>)
    f! str
    g (-> @ v int)
}

<Table("test")>
test_annotation : $ {
    <Key, Column("id")>
    id! str
    <Column("nick_name")>
    nick_name! str
    <Column("profile")>
    profile! str
}

test_enum : .. {
    ok
    err : -1
}

package : $ (me) {
    x! int
    y! int

    parentFunc : (->) {
        me.x = 21
        print("package")
    }
} & (y int = 3->$me) {
    me.x = ConstData
    me.y = y
}

package_child : package & (x int, y int->$me)(y) {
    me.x = x
} & $ (me,super) {
    x! int

    .parentFunc : (->) {
        super.x = 64
        print("package child")
    }
} & {
    a! : 7
    b : (->) {
        print("static")
    }
}
