## Grammar Overview

## Export Name Space
mod demo;

## Import Name Space
use {
    System;
    System.Text;
    System.Threading.Tasks;
    System.ComponentModel.DataAnnotations.Schema;
    System.ComponentModel.DataAnnotations;
    . = IO.File; ## 可以隐藏元素使用内容
}

let main() = {
    ## Define, 一般情况下编译器会自动判断类型
    let string String = "10";
    let number Float = 1.2;
    let integer Int = 123;
    let boolean Bool = true;
    let smallFloat = (1.2).toFloat32(); ## basic obj convert

    ## Const
    let pi = 3.141592653;

    ## Mark String
    let format = "the value is \{integer}, \{number}, \{boolean}";

    ## Array
    let array Array(Int) = arrayOf(1, 2, 3);
    let array2 Array(Int) = [1, 2, 3];

    ## List
    let list List(Int) = [1, 2, 3, 4, 5];
    print( list[0] ); ## 使用下标获取

    ## Map, 前面为 key，后面为 value
    let map Map(String, Bool) = [("1", false), ("2", true)];
    print( map["1"] ); ## 使用key获取

    ## Function
    let f(a Int) Int = a;

    ## Function with no params no return
    let do_something_void() Void = {
        do_something_a();
        do_something_b();
    }

    ## Full Function with params and return
    let do_something_with_params(x Int, y String) type(a Int, b String) = (x, y);

    ## Function type
    let f fn(x Int, y Int) Int = (x Int, y Int) Int -> x + y;
    let f fn(x Int, y Int) Int = (x, y) -> x + y;
    let f(x Int, y Int) Int = x + y;
    let f(x Int, y Int) = x + y;
    let g() Void = {}
    let g fn() Void = () -> {}

    ## Currying
    let add = (x Int) -> (y Int) -> x + y;
    let add fn(x Int) fn(y Int) Int = (x) -> (y) -> x + y;
    let add fn(x Int)(y Int) Int = x -> y -> x + y;
    let add(x Int)(y Int) -> x + y;
    let v = add(1)(2);

    ## Lambda Function
    listOf(1, 2, 3, 4).filter(x -> x % 2 == 0).map(x -> x * x).sum();

    ## Func params
    let f(i fn(x Int) Int) = i(1);
    f((x Int) Int -> x);
    f(x -> x);

    do_something_void();
    ## use _ discard return value
    _ = do_something_with_params(3, "test");

    ## if-do, single branch structure
    if a < b do {
        ...
    }

    ## with-init
    if let a = 1; a < 0 do {
        ...
    }

    ## if-then-else, double branch structure
    let v = if true then 0 else 0;
    if true then {
        ...
    } else {
        ...
    }

    if a then ...
    else if b then ...
    else ...;

    let op Option(Int) = Some(1);
    if op is Some(v) do {
        printLine(v)
    }

    ## while-do, single branch structure
    while a < b do {
        ...
    }

    ## with-init
    while let mut i = 0; i < 10; i += 1 do {
        printLine(i)
    }

    ## while-then-else, double branch structure, break can with value
    let v = while true then break 1 else 2;
    while true then {
        ...
    } else {
        ...
    }

    let iter Iterator(Int) = listOf(1,2,3).iterator();
    while iter.next() is Some(v) do {
        printLine(v)
    }

    ## match
    x match {
        case 1 then "a"
        case 2 then "b"
        case 3 then "c"
        case _ then "d"
    }

    x match {
        case 1 then "a"
        case 2 then "b"
        case 3 then "c"
        case _ then "d"
    }
    ## same as let-in
    somePair match (a, b) do a + b;

    ## foreach-do
    array foreach item do {
        ...
    }

    ## Loop, use identify to take out single item
    array foreach item do printLine(item);
    
    ## take index and value, both worked at Dictionary
    array.withIndex() foreach (index, value) do {
        printLine((index, value))
    }
    
    0..10 foreach i do {
        printLine(i)
    }

    0..100 foreach i do if i % 2 == 0 do print(i);
    
    array foreach {
        case 1 then "a"
        case 2 then "b"
        case 3 then "c"
        case _ then "d"
    }

    let nb = 42;
    nb match {
        case >= 0 & <= 7 | 8 | 9 then 
            print("single digit")
        case 10 then 
            print("double digits")
        case >= 11 & <= 99 then 
            print("double digits")
        case >= 100 & <= 999 then 
            print("triple digits")
        case _ then 
            print("four or more digits")
    }

    if foo() is A(x) and bar(x) is B(y) then {
        do_stuff_with(x, y)
    } else {
        some_long_expression
    }

    let param_env(tcx TyCtxt, def_id DefId) ParamEnv = {
        if tcx.describe_def(def_id) is Some(Def.Existential(_))
            and tcx.hir.as_local_node_id(def_id) is Some(node_id)
            and tcx.hir.get(node_id) is hir.map.NodeItem(item)
            and item.node is hir.ItemExistential(exist_ty)
            and exist_ty.impl_trait_fn is Some(parent)
        do return param_env(tcx, parent);

        ...
    }

    ## data type define
    type Button(width Int, height Int, background String, title String);
    given Button with {
        this.click() Void = {
            printLine(title);
            doSomeThingA();
            doSomeThingB();
        }
    }
    ## privite members
    type Image(_width Int, _height Int, _source String);

    ## abstract type define
    type Animation = {
        this.move(s Int) Void;
        this.stop() Void;
    }

    ## Combine Template
    type ImageButton(as image Image, as button Button);
    given ImageButton: Animation with {
        ## Implement Interface
        this.move(s Int) Void = {
            let t = 5000/s;
            play( s + t );
        }
        this.stop() Void = {}
    }

    ## Create an Template object
    let btn = Button(1, 2, "Cancel");
    let img = Image(1, 2, "?.jpg");
    let mut ib ImageButton = Image(img, btn);
    ib = (img, btn);
    ## Calling property
    ib.title = "OK";
    ## Calling method
    ib.show();
    ## Calling protocol
    ib.move(6);

    ## Use Interface
    let play_animation(a Animation) = {
        a.move(1000);
        a.stop();
    }
    play_animation(ib);

    ## Annotation
    #Table("user") #Property(false, name = "d", hide = true)
    type mut User(
        #Column("id") #Required #Key
        id String,
        #Column("nick_name") #Required
        nick_name String,
        #Column("time_update") #Required
        time_update Int,
    );
    
    ## Generic Type
    type mut Table(T Any)(data T);
    given(T Any) Table(T) with {
        mut this.setData(d T) Void = {
            this.data = d;
        }
    }
    Table(Int)(1);

    ## Generic function
    let add(T Addable)(x1 T, x2 T) T = x1 + x2;
    add(Int)(1, 2);

    type Void();

    type Color = { Red(); Green(); Blue() }

    type Point(x Int, y Int);

    type Pair(T1, T2)(first T1, second T2);

    type Option(T Any) = { Some(value T); None() }

    let opt() = {
        let mut a Option(Int) = Some(1);
        a = None();
        a match {
            case Some(v) then printLine(v)
            case None then printLine("none")
        }

        let b Option(Option(Int)) = Some(Option(Int))(Some(Int)(2));
        b match {
            case Some(Some(v)) then printLine(v)
            case Some(None) then printLine("some(none)")
            case None then printLine("none")
        }
    }

    type mut MyList(T Any)(arr [T]);
    ## operator override
    given(T Any) MyList(T): Addable(T) with {
        ## a + e
        mut this.plus(element T) Void = {
            this.arr = this.arr.append(element);
        }
    }
    given(T Any) MyList(T): MutIndexable(T) with {
        ## e = a[i]
        this.get(index Int) T = this.arr[index];
        ## a[i] = e
        mut this.set(index Int, element T) Void = this.arr[index] = element;
    }
    
    ## Iterator pattern
    type mut Iterator(T Any) = {
        mut this.next() Option(T);
    }

    type Iterable(T Any) = {
        this.iter(): mut Iterator(T);
    }

    type ListNode(T Any) = {
        Empty();
        Node(head T, tail ListNode(T));
    } with {
        this.iter() mut Iterator(T) = mut ListNodeIterator(this);
    }

    type mut ListIterator(T Any)(li ListNode(T));

    given(T Any) ListIterator(T) with
        mut this.next() Option(T) =
            if this.li is Node(h, t) then {
                this.li = t;
                Some(h)
            } else {
                None()
            }

    type TreeNode = { Empty(); Node(val Int, left TreeNode, right TreeNode) }

    type Nat = { Zero(); Suc(n Nat) }
}

type Foo(value Int);

type Color = { Red(); Green(); Blue() }

type Color(rgb String) = {
    Red("ff0000");
    Green("00ff00");
    Blue("0000ff");
}

type Planet(mass Float, radius Float) = {
    Mercury(3.303e+23, 2.4397e6);
    Venus(4.869e+24, 6.0518e6);
    Earth(5.976e+24, 6.37814e6);
    Mars(6.421e+23, 3.3972e6);
    Jupiter(1.9e+27, 7.1492e7);
    Saturn(5.688e+26, 6.0268e7);
    Uranus(8.686e+25, 2.5559e7);
    Neptune(1.024e+26, 2.4746e7);
}

type Option(T Any) = { Some(value T); None() }

type Expr(T Any) = {
    IntExpr(value Int): Expr(Int);
    BoolExpr(value Bool): Expr(Bool);
    EqualExpr(left Expr(T), right Expr(T)): Expr(Bool);
    AddExpr(left Expr(Int), right Expr(Int)): Expr(Int);
}

type UserName(name String);
type Password(hash Hash);
type Identify = UserName | Password;
type HashKey(T Any) = Equatable(T) & Hashable;

given(T ToString) Option(T) with {
    this.toString() String = 
        if this is Some(v)
        then "Some(\{v})" 
        else "None()";
}

given Foo: ToString with {
    this.toString() String = "foo";
}
given(T Any, R Any) fn(x T) R with {
    this.toAny() Any = this;
}

type LinkedList(T Any) = {
    Cons(head T, tail LinkedList(T));
    Empty();
}

given(T Any) LinkedList(T) with {
    new() This = Empty();
}

type mut List(T Any) = {
    this.get(index Int) T;

    mut this.set(index Int, element T) Void;
}

type mut ArrayList(T Any) = { ArrayList(_arr Array(T), size Int) }
type mut ArrayList(T Any)(_arr Array(T), size Int);

given(T Any) ArrayList(T): List(T) with {
    new() mut This = mut This([], 0);

    this.get(index Int) T = this._arr.get(index);

    mut this.set(index Int, element T) Void = this._arr.set(index, element);

    this.map(R)(f fn(x T) R) Iterator(R) = MapIter(T, R)(this, f);
}

given ArrayList(Int) with {
    this.sum() Int = reduce(this.iterator(), 0, (l, r) -> l + r);
}

type ToString = {
    this.toString() String;
}

given Int: ToString with {
    this.toString() String = cprintf(this);
}

given(T ToString) ArrayList(T): ToString with {
    this.toString() String = join_String(this.iterator());
}

given Int with {
    default() This = 0;
}

given String with {
    default() This = "";
}

given(T Any) Array(T) with {
    default() This = arrayOf(T)();
}

type Any = {}

given(T Any) T: Any with {}

type Iterator(T) = {
    mut this.next() Option(T)
}

given(T Any) Iterator(T) with {
    mut this.reduce(R Any)(mut r R, f fn(a R, b T) R) = {
        while this.next() is Some(v) do {
            r = f(r, v)
        }
        r
    }
}

type mut InputStream = {
    mut this.read(to Array(Byte)) Int;
}

type mut OutputStream = {
    mut this.write(from mut Array(Byte)) Int;
    mut this.flush() Void;
}

type mut Array(T Any)(_source RawArray(T), _start Int, _len Int) with {
    create(size Int, item T) = mut Array(T)(RawArray.new(size, item), 0, size);

    this.size() = this._len;

    this.get(index Int) = this._source[index + _start];
    
    mut this.set(index Int, value T) = this._source[index + _start] = value;
    
    this.slice(start Int, len Int) Array(T) = 
        Array(T)(this._source, start, len);

    mut this.sliceMut(start Int, len Int) mut Array(T) = 
        mut Array(T)(this._source, start, len);
}

type mut ArrayIterator(T Any)(_source Array(T), index Int): Iterator(T) with {
    of(source Array(T)) = ArrayIterator(source, -1);
    
    mut this.next() Option(T) = 
        if this.index < this._source.size() then {
            this.index += 1;
            Some(this._source[this.index])
        } else {
            None()
        }
}

type String(_data Array(Char)) with {
    of(data Array(Char)) String = String(data.clone());

    this.toString() String = String(this._data.clone());

    this.clone() String = String(this._data.clone());

    this.iter() mut StringIterator = StringIterator.of(this);
}

type mut StringIterator(_source String, index Int): Iterator(Char) with {
    of(source String) = mut StringIterator(source, -1);
    
    mut this.next() Option(Char) = 
        if this.index < this._source._data.size() then {
            this.index += 1;
            Some(this._source[this.index])
        } else {
            None()
        }
}

type mut Node(T Any)(value T, next Option(Node(T)));

type mut LinkedList(T Any)(head Option(Node(T)), size Int) with {
    mut this.prepend(v T) Void = {
        let node = mut Node(v, None());
        if this.head is None then {
            this.head = node;
        } else {
            node.next = this.head;
            this.head = node;
        }
        this.size += 1;
    }
}

