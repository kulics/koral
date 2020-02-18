# Grammar Overview

# Name Space
demo . {
    System
    System.Linq
    System.Text
    System.Threading.Tasks
    System.ComponentModel.DataAnnotations.Schema
    System.ComponentModel.DataAnnotations
    _ = IO.File # 可以隐藏元素使用内容
}

Main : (->>) {
    # Define, 一般情况下编译器会自动判断类型
    String = "10"   # str
    Number = 1.2    # num
    Integer = 123   # int
    Boolean = true  # bool
    SmallFloat = (1.2).to_f32() # basic type convert

    # Const
    PI : 3.141592653

    # Mark String
    Format = "the value is \{Integer}, \{Number}, \{Boolean}"

    # List
    List = []int{ 1;2;3;4;5 }
    List2 = { 1;2;3;4;5 }
    print( List[0] ) # 使用下标获取

    # Set
    Set = [int]_{ [1]_;[2]_;[3]_;[4]_;[5]_ }
    Set2 = { [1]_;[2]_;[3]_;[4]_;[5]_ }

    # Dictionary, 前面为key，后面为value
    Dictionary = {["1"]false; ["2"]true}
    Dictionary = [str]bool{ ["1"]false; ["2"]true}
    print( Dictionary["1"] ) # 使用key获取

    Stack = [>]int{}
    Queue = [<]int{}

    Array [.]int = array_of(1,2,3)
    # Anonymous Package
    New = {
        title : "nnn"
        number : 8
    }

    # Function
    Fn : (in int -> out int) {} # (int->int)

    # Function with no params no return
    do_something_void : (->) {
        do_something_a()
        do_something_b()
    }

    # Full Function with in params and out params
    do_something_with_params : (x int, y str -> a int, b str) {
        <- x, y
    }

    B2C()
    # 使用 _ 舍弃返回值
    _ = A2B(3, "test")

    # Judge，当表达式的结果只有Bool时，相当于if，只当True时才执行
    ? 1+1 >< 2 {
        do_something_a()
    } _ { # else
        do_something_b()
    }

    # pattern match
    ? x.. 0~6, 7, 8, 9 {
        do_something_a()
    } 14 {
        do_something_b()
    } _ { # default
        do_somethingC()
    }

    # type match
    ? object.. _ str { 
        print("string") 
    } _ int { 
        print("integer") 
    } _ num { 
        print("float") 
    } _ bool { 
        print("boolean") 
    } _ any {
        print("object")
    } nil { 
        print("null") 
    }

    # Loop, use identify to take out single item, default is it
    @ item = array.. {
        print(item)
    }
    # take index and value, both worked at Dictionary
    @ [index]value = array.. {
        print(index, value)
    }

    # Iterator, Increment from ~(step) to, Decrement from ~~(step) to, (step) can omit
    @ it = 0 ~(2) 100.. {
        print(it)
    }
    @ it = 10 ~~ 1.. {}

    # Infinite
    @ true {
        ? a > b {
            ~@ # jump out loop
        } _ {
            ..@ # continue
        }
    }
    # Conditional
    a = 0
    @ a < 10 {
        a += 1
    } _ {
        # Loop else
    }
    
    # Struct，支持 variable 类型，通常用来包装数据
    View : $ {
        width int
        height int
        background str
    }

    # 也支持包装方法，可以通过 me 来访问包自身属性或方法
    Button : $ (me) {
        width int
        height int
        background str
        title str
        click : (->) {
            print( me.title )
            doSomeThingA()
            doSomeThingB()
        }
    }

    Image : $ (me) {
        # 私有属性，不能被外部访问，也不能被重包装
        _width = 0
        _height = 0
        _source = "" 
    } & (w int, h int, s str->me) { # 初始化方法
        me._width, me._height, me._source = w,h,s
    }

    # Interface, implemented by package
    Animation : $ {
        speed () int { get set }    # 需求变量，导入的包必须实现定义
        move (s int ->)             # 需求方法，导入的包必须实现定义
    }

    # Combine Package，通过引入来复用属性和方法
    Image_Button : Image & Button & $ {
        title str
        _speed int
    } & $ Animation(me) { # Implement protocol
        speed : (me._speed) int
        move : (s int ->) {
            t = 5000/s
            play( s + t )
        }
    } & (w int, h int->me)(w, h , "img") {
        me.title = "img btn"
    }

    # Create an package object
    IB = Image_Button{}
    # Calling property
    IB.title = "OK"
    # Calling method
    IB.button.show()
    # Calling protocol
    IB.move(6)

    # Create an object with simple assign
    IB2 = Image_Button{
        title="Cancel"
        background="red"
    }

    # Create an object with params
    Img = Image(30, 20, "./icon.png")
    ImgBtn = Image_Button(1, 1)

    # judge type
    ? IB Image_Button? {
        # convert type
        (IB View!).show()
    }

    # get type
    print( [typeof Image_Button]() )

    # Check, listen the Exception Function
    Fi = File("./test.xs")
    ! F = Read_File("demo.xs")
    ! {
        do_some_thing()
    } ex {
        ! <- ex # Use ! <- to throw an Exception
    } _ {
        Fi.Dispose()
    }
    # yield
    yield_function : (-> @ r int) {
        # yield return
        @ <- 123
        # yield break
        @ <-
    }

    # Use ->> to declare Async Function
    task : (in int ->> out int) {
        # make a function to await
        << do_some_thing_A()
        do_some_thing_B()
        << do_some_thing_C()
        <- in
    }

    x = task(6)

    # Annotation
    <assemby-> Table("user"), D(false,Name="d",Hide=true)>
    User : $ {
        <Column("id"), Required, Key>
        id str
        <Column("nick_name"), Required>
        nick_name str
        <Column("time_update"), Required>
        time_update int
    }

    # Pointer Type
    A ?int = nil
    # Get Pointer
    C = A?
    # Safe Call
    E = A?.to_str()
    # OrElseValue
    F = A??128

    # Reference
    swap : (x !int, y !int->) {
        x, y = y, x
    }
    swap(A!, B!)
    
    # Generic package
    [table T] : $ {
        data T
        set_data : (d T ->) {
            data = d
        }
    }
    # Generic function
    [Add T] : (x1 T, x2 T -> y T) {
        <- x1 + x2
    }

    # Lambda Function
    arr.select( {it -> it > 2} )
    arr.select{it -> it > 2}

    # Func params
    Func : (in (int -> int) ->) {
        in(1)
    }
    Func( (x int -> y int) {
        <- (y)
    })

    # linq
    arr = @ id = expr.. -> where expr -> order expr -> select expr

    # event
    EventHandle : $ {
        property_changed [->]PropertyChangedEventHandler
    }

    # control
    Data : $ {
        <get,set>
        c int 
        d int
        <add,remove>
        e PropertyChangedEventHandler
    }

    Color : .. {
        Red 
        Green
        Blue
    }
}
