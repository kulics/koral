# The XyLang Programming Language
XyLang is a simpler and more friendly .NET programming language.  

This is the main source code repository for XyLang. It contains the compiler, standard library, and documentation.

The language is designed to improve reading performance and reduce the grammatical burden so that users can focus their real attention on business needs.

Therefore, we abandon many subtle grammatical features, retaining only the most used part, and enhance its versatility.

Eventually making XyLang with very few grammar, only the presence of symbols on the keyboard instead of keywords is sufficient to express all the logic.

## Features
+ Focus on writing and reading..
+ Less grammar, no keywords.
+ Clear semantics, one logic corresponds to only one expression.
+ Support for compilation to .NET platform, with .NET framework and library resources, we can use this language in a very wide range of scenarios.

## Getting Started
Read detail from The [Book](./book-en/introduction.md).  
阅读 [语言说明文档](./book-zh/介绍.md)。

## Quick Preview
```
// namespace
Main :
~System
{
    // main function
    $  
    {
        // array
        greetings: ["Hello", "Hola", "Bonjour",
                    "Ciao", "こんにちは", "안녕하세요",
                    "Cześć", "Olá", "Здравствуйте",
                    "Chào bạn", "您好"];
        // for-each
        @ greetings ~ item
        {
            // call function
            print.(item);
            // if-switch
            ? item ~ [0~8] 
            {
                print.(" in 0-8");
            }
            ~ _
            {
                print.(" over 10");
                ~@;
            };
        };
    };
};
```
## Roadmap
1. 2017.07 ~ 2018.03 
    1. Design syntax.
    1. Completed translator to C # compiler.
1. 2018.03 ~ 2019.03
    1. Rewrite all xy projects using xylang.
    1. Develop vscode syntax plugin.
    1. Compiler features improvements (identifier records, cross-file references, project compilation).
1. 2019.03 ~ 2020.03
    1. Compile to CIL or LLVM.
    1. Increase the standard library.

## Compare
### Hello World
#### Swift
```
print("Hello, world!")
```
#### Kotlin
```
println("Hello, world!")
```
#### XyLang
```
print.("Hello, world!");
```
### Variables And Constants
#### Swift
```
var myVariable = 42
myVariable = 50
let myConstant = 42
```
#### Kotlin
```
var myVariable = 42
myVariable = 50
val myConstant = 42
```
#### XyLang
```
myVariable : 42;
myVariable = 50;
myConstant := 42;
```
### Explicit Types
#### Swift
```
let explicitDouble: Double = 70
```
#### Kotlin
```
val explicitDouble: Double = 70.0
```
#### XyLang
```
explicitDouble : !f64(70.0);
```
### Basic Types
#### Swift
```
Int32 Int16 Int64 Int8 
Double Float 
Bool 
String
```
#### Kotlin
```
Int Short Long Byte 
Double Float 
Boolean 
String
```
#### XyLang
```
i32 i16 i64 i8 
f64 f32 
bool 
str
```
### Type Coercion
#### Swift
```
let label = "The width is "
let width = 94
let widthLabel = label + String(width)
```
#### Kotlin
```
val label = "The width is "
val width = 94
val widthLabel = label + width
```
#### XyLang
```
label : "The width is ";
width : 94;
widthLabel : label + !str(width);
```
### Inclusive Range Operator
#### Swift
```
for index in 1...5 {
    print("\(index) times 5 is \(index * 5)")
}
// 1 times 5 is 5
// 2 times 5 is 10
// 3 times 5 is 15
// 4 times 5 is 20
// 5 times 5 is 25
```
#### Kotlin
```
for (index in 1..5) {
    println("$index times 5 is ${index * 5}")
}
// 1 times 5 is 5
// 2 times 5 is 10
// 3 times 5 is 15
// 4 times 5 is 20
// 5 times 5 is 25
```
#### XyLang
```
@ [ 1~5 ] ~ index
{
    print.(!str(index) + " times 5 is " + !str(index * 5));
};
// 1 times 5 is 5
// 2 times 5 is 10
// 3 times 5 is 15
// 4 times 5 is 20
// 5 times 5 is 25
```
### Arrays
#### Swift
```
var shoppingList = ["catfish", "water",
    "tulips", "blue paint"]
shoppingList[1] = "bottle of water"
```
#### Kotlin
```
val shoppingList = arrayOf("catfish", "water",
    "tulips", "blue paint")
shoppingList[1] = "bottle of water"
```
#### XyLang
```
shoppingList : ["catfish", "water",
    "tulips", "blue paint"];
shoppingList.[1] = "bottle of water";
```
### Maps
#### Swift
```
var occupations = [
    "Malcolm": "Captain",
    "Kaylee": "Mechanic",
]
occupations["Jayne"] = "Public Relations"
```
#### Kotlin
```
val occupations = mutableMapOf(
    "Malcolm" to "Captain",
    "Kaylee" to "Mechanic"
)
occupations["Jayne"] = "Public Relations"
```
#### XyLang
```
occupations : [
    "Malcolm": "Captain",
    "Kaylee": "Mechanic"
];
occupations.["Jayne"] = "Public Relations";
```
### Empty Collections
#### Swift
```
let emptyArray = [String]()
let emptyDictionary = [String: Float]()
```
#### Kotlin
```
val emptyArray = arrayOf<String>()
val emptyMap = mapOf<String, Float>()
```
#### XyLang
```
emptyArray : #[]str.();
emptyMap : #[str]f32.();
```
### Functions
#### Swift
```
func greet(_ name: String,_ day: String) -> String {
    return "Hello \(name), today is \(day)."
}
greet("Bob", "Tuesday")
```
#### Kotlin
```
fun greet(name: String, day: String): String {
    return "Hello $name, today is $day."
}
greet("Bob", "Tuesday")
```
#### XyLang
```
greet : $(name: str, day: str)~(r:str) 
{
    -> ("Hello " + name + ", today is " + day + ".");
};
greet.("Bob", "Tuesday");
```
### Tuple Return
#### Swift
```
func getGasPrices() -> (Double, Double, Double) {
    return (3.59, 3.69, 3.79)
}
```
#### Kotlin
```
data class GasPrices(val a: Double, val b: Double,
     val c: Double)
fun getGasPrices() = GasPrices(3.59, 3.69, 3.79)
```
#### XyLang
```
getGasPrices:$()~(a:f64, b:f64, c:f64) 
{
    -> (3.59, 3.69, 3.79);
};
```
### Function Type
#### Swift
```
func makeIncrementer() -> (Int -> Int) {
    func addOne(number: Int) -> Int {
        return 1 + number
    }
    return addOne
}
let increment = makeIncrementer()
increment(7)
```
#### Kotlin
```
fun makeIncrementer(): (Int) -> Int {
    val addOne = fun(number: Int): Int {
        return 1 + number
    }
    return addOne
}
val increment = makeIncrementer()
increment(7)

// makeIncrementer can also be written in a shorter way:
fun makeIncrementer() = fun(number: Int) = 1 + number
```
#### XyLang
```
makeIncrementer:$()~(fn: $(n:i32)~(n:i32)) 
{
    addOne:$(number:i32)~(number:i32) 
    {
        -> (1 + number);
    };
    -> (addOne);
};
increment : makeIncrementer.();
increment.(7);
```
### Classes Declaration
#### Swift
```
class Shape {
    var numberOfSides = 0
    func simpleDescription() -> String {
        return "A shape with \(numberOfSides) sides."
    }
}
```
#### Kotlin
```
class Shape {
    var numberOfSides = 0
    fun simpleDescription() =
        "A shape with $numberOfSides sides."
}
```
#### XyLang
```
Shape:#()
{
    numberOfSides : 0;
    simpleDescription : $()~(s:str) 
    {
        -> ("A shape with " + !str(numberOfSides) + " sides.");
    };
};
```
### Classes Usage
#### Swift
```
var shape = Shape()
shape.numberOfSides = 7
var shapeDescription = shape.simpleDescription()
```
#### Kotlin
```
var shape = Shape()
shape.numberOfSides = 7
var shapeDescription = shape.simpleDescription()
```
#### XyLang
```
shape : #Shape.();
shape.numberOfSides = 7;
shapeDescription : shape.simpleDescription.();
```
### Subclass
#### Swift
```
class NamedShape {
    var numberOfSides: Int = 0
    let name: String

    init(name: String) {
        self.name = name
    }

    func simpleDescription() -> String {
        return "A shape with \(numberOfSides) sides."
    }
}

class Square: NamedShape {
    var sideLength: Double

    init(sideLength: Double, name: String) {
        self.sideLength = sideLength
        super.init(name: name)
        self.numberOfSides = 4
    }

    func area() -> Double {
        return sideLength * sideLength
    }

    override func simpleDescription() -> String {
        return "A square with sides of length " +
	       sideLength + "."
    }
}

let test = Square(sideLength: 5.2, name: "square")
test.area()
test.simpleDescription()
```
#### Kotlin
```
open class NamedShape(val name: String) {
    var numberOfSides = 0

    open fun simpleDescription() =
        "A shape with $numberOfSides sides."
}

class Square(var sideLength: BigDecimal, name: String) :
        NamedShape(name) {
    init {
        numberOfSides = 4
    }

    fun area() = sideLength.pow(2)

    override fun simpleDescription() =
        "A square with sides of length $sideLength."
}

val test = Square(BigDecimal("5.2"), "square")
test.area()
test.simpleDescription()
```
#### XyLang
```
NamedShape :#(name: str) {
    numberOfSides: ^i32;
    name: ^str~get;

    ..$ 
    {
        ..name = name;
    };

    simpleDescription: $()~(s:str) 
    {
        -> ("A shape with " + !str(numberOfSides) + " sides.");
    };
};

Square: #(sideLength: f64, name: str)~NamedShape(name:str)
{
    sideLength: ^f64;

    ..$() 
    {
        ..sideLength = sideLength;
        ..numberOfSides = 4;
    };

    area: $()~(f:f64) 
    {
        -> (sideLength * sideLength);
    };

    ..simpleDescription: $()~(s:str) 
    {
        -> ("A square with sides of length " +
	       !str(sideLength) + ".");
    };
};

test : #Square.(5.2, "square");
test.area.();
test.simpleDescription.();
```
### Checking Type
#### Swift
```
var movieCount = 0
var songCount = 0

for item in library {
    if item is Movie {
        movieCount += 1
    } else if item is Song {
        songCount += 1
    }
}
```
#### Kotlin
```
var movieCount = 0
var songCount = 0

for (item in library) {
    if (item is Movie) {
        ++movieCount
    } else if (item is Song) {
        ++songCount
    }
}
```
#### XyLang
```
movieCount : 0;
songCount : 0;

@ library ~ item 
{
    ? item.?Movie 
    {
        movieCount += 1
    }
    ? item.?Song 
    {
        songCount += 1
    };
};
```
### Pattern Matching
#### Swift
```
let nb = 42
switch nb {
    case 0...7, 8, 9: print("single digit")
    case 10: print("double digits")
    case 11...99: print("double digits")
    case 100...999: print("triple digits")
    default: print("four or more digits")
}
```
#### Kotlin
```
val nb = 42
when (nb) {
    in 0..7, 8, 9 -> println("single digit")
    10 -> println("double digits")
    in 11..99 -> println("double digits")
    in 100..999 -> println("triple digits")
    else -> println("four or more digits")
}
```
#### XyLang
```
nb : 42;
? nb 
~ [0~7],8,9 { print.("single digit"); }
~ 10 { print.("double digits"); }
~ [11~99] { print.("double digits"); }
~ [100~999] { print.("triple digits"); }
~ _ { print.("four or more digits"); };
```
### Downcasting
#### Swift
```
for current in someObjects {
    if let movie = current as? Movie {
        print("Movie: '\(movie.name)', " +
            "dir. \(movie.director)")
    }
}
```
#### Kotlin
```
for (current in someObjects) {
    if (current is Movie) {
        println("Movie: '${current.name}', " +
	    "dir. ${current.director}")
    }
}
```
#### XyLang
```
@ someObjects ~ current 
{
    movie : current.!Movie;
    ? movie ~= nil
    {
        print.("Movie: " + movie.name + ", " +
            "dir. " + movie.director);
    };
};
```
### Protocol
#### Swift
```
protocol Nameable {
    func name() -> String
}

func f(x: Nameable) {
    print("Name is " + x.name())
}
```
#### Kotlin
```
interface Nameable {
    fun name(): String
}

fun f(x: Nameable) {
    println("Name is " + x.name())
}
```
#### XyLang
```
Nameable : & 
{
    name: $()~(s:str){};
};

f : $(x: &Nameable)~() 
{
    print.("Name is " + x.name.());
};
```