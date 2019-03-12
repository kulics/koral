
# Compare
## Hello World
### Xs
```
prt("Hello, world!")
```
### C#
```
Console.WriteLine("Hello, world!");
```
### Go
```
print("Hello, world!")
```
### Kotlin
```
println("Hello, world!")
```
### Swift
```
print("Hello, world!")
```
## Variables And Constants
### Xs
```
MyVariable := 42
MyVariable = 50
myConstant 42
```
### C#
```
var myVariable = 42;
myVariable = 50;
const int myConstant = 42;
```
### Go
```
myVariable := 42
myVariable = 50
const myConstant = 42
```
### Kotlin
```
var myVariable = 42
myVariable = 50
val myConstant = 42
```
### Swift
```
var myVariable = 42
myVariable = 50
let myConstant = 42
```
## Explicit Types
### Xs
```
explicitDouble: f64 = 70
```
### C#
```
double explicitDouble = 70;
```
### Go
```
var explicitDouble float64 = 70.0
```
### Kotlin
```
val explicitDouble: Double = 70.0
```
### Swift
```
let explicitDouble: Double = 70
```
## Basic Types
### Xs
```
i32 i16 i64 i8 
f64 f32 
bl 
str
```
### C#
```
int short long byte 
double float 
bool 
string
```
### Go
```
int32 int16 int64 int8 
float64 float32 
bool 
string
```
### Kotlin
```
Int Short Long Byte 
Double Float 
Boolean 
String
```
### Swift
```
Int32 Int16 Int64 Int8 
Double Float 
Bool 
String
```
## Type Coercion
### Xs
```
f := 6.0
i := 94
count := i + f.to<i32>()
```
### C#
```
double f = 6;
int i = 94;
int count = i + (int)f;
```
### Go
```
f := 6.0
i := 94
count := i + int(f)
```
### Kotlin
```
val f = 6.0
val i = 94
val count:Int = i + f
```
### Swift
```
let f = 6.0
let i = 94
let count = i + Int(f)
```
## Inclusive Range Operator
### Xs
```
@ index <- [ 1 <= 5 ] {
    prt("" index " times 5 is " index * 5 "")
}
```
### C#
```
for (int index = 1; index <= 5; index++) 
{
    Console.Write($"{index} times 5 is {index * 5}");
}
```
### Go
```
for index := 1; index <= 5; index++  {
    fmt.Printf("%d times 5 is %d", index, index*5)
}
```
### Kotlin
```
for (index in 1..5) {
    println("$index times 5 is ${index * 5}")
}
```
### Swift
```
for index in 1...5 {
    print("\(index) times 5 is \(index * 5)")
}
```
## Arrays
### Xs
```
shoppingList := {"catfish", "water",
    "tulips", "blue paint"}
shoppingList[1] = "bottle of water"
```
### C#
```
var shoppingList = new List<string>(){"catfish", "water",
    "tulips", "blue paint"};
shoppingList[1] = "bottle of water";
```
### Go
```
shoppingList := []string{"catfish", "water",
    "tulips", "blue paint"}
shoppingList[1] = "bottle of water"
```
### Kotlin
```
val shoppingList = arrayOf("catfish", "water",
    "tulips", "blue paint")
shoppingList[1] = "bottle of water"
```
### Swift
```
var shoppingList = ["catfish", "water",
    "tulips", "blue paint"]
shoppingList[1] = "bottle of water"
```
## Maps
### Xs
```
occupations := {
    ["Malcolm"]"Captain",
    ["Kaylee"]"Mechanic"
}
occupations["Jayne"] = "Public Relations"
```
### C#
```
var occupations = new Dictionary<string,string>(){
    {"Malcolm", "Captain"},
    {"Kaylee", "Mechanic"}
};
occupations["Jayne"] = "Public Relations";
```
### Go
```
occupations := map[string]string{
    "Malcolm": "Captain",
    "Kaylee": "Mechanic",
}
occupations["Jayne"] = "Public Relations"
```
### Kotlin
```
val occupations = mutableMapOf(
    "Malcolm" to "Captain",
    "Kaylee" to "Mechanic"
)
occupations["Jayne"] = "Public Relations"
```
### Swift
```
var occupations = [
    "Malcolm": "Captain",
    "Kaylee": "Mechanic",
]
occupations["Jayne"] = "Public Relations"
```
## Empty Collections
### Xs
```
emptyArray := [str]()
emptyDictionary := [[str]f32]()
```
### C#
```
var emptyArray = new List<string>();
var emptyDictionary = new Dictionary<string, float>();
```
### Go
```
var (
    emptyArray []string
    emptyMap = make(map[string]float)
)
```
### Kotlin
```
val emptyArray = arrayOf<String>()
val emptyMap = mapOf<String, Float>()
```
### Swift
```
let emptyArray = [String]()
let emptyDictionary = [String: Float]()
```
## Functions
### Xs
```
greet(name: str, day: str) -> (r: str) {
    <- ("Hello " name ", today is " day ".")
}
greet("Bob", "Tuesday")
```
### C#
```
string greet(string name, string day) 
{
    return $"Hello {name}, today is {day}.";
}
greet("Bob", "Tuesday");
```
### Go
```
func greet(name, day string) string {
    return fmt.Sprintf("Hello %v, today is %v.", name, day)
}
greet("Bob", "Tuesday")
```
### Kotlin
```
fun greet(name: String, day: String): String {
    return "Hello $name, today is $day."
}
greet("Bob", "Tuesday")
```
### Swift
```
func greet(_ name: String,_ day: String) -> String {
    return "Hello \(name), today is \(day)."
}
greet("Bob", "Tuesday")
```
## Tuple Return
### Xs
```
getGasPrices() -> (a: f64, b: f64, c: f64) {
    <- (3.59, 3.69, 3.79)
}
```
### C#
```
(double, double, double) getGasPrices() 
{
    return (3.59, 3.69, 3.79);
}
```
### Go
```
func getGasPrices() (float64, float64, float64) {
    return 3.59, 3.69, 3.79
}
```
### Kotlin
```
fun getGasPrices() = Triple(3.59, 3.69, 3.79)
```
### Swift
```
func getGasPrices() -> (Double, Double, Double) {
    return (3.59, 3.69, 3.79)
}
```
## Function Type
### Xs
```
makeIncrementer() -> (fn: (i32) -> (i32)) {
    addOne(number: i32) -> (number: i32) {
        <- (1 + number)
    }
    <- (addOne)
}
increment := makeIncrementer()
increment(7)
```
### C#
```
Func<int,int> makeIncrementer() 
{
    int addOne(int number) 
    {
        return 1 + number;
    }
    return addOne;
}
Func<int,int> increment = makeIncrementer();
increment(7);
```
### Go
```
func makeIncrementer() func(int) int {
    addOne := func (number int) int {
        return 1 + number
    }
    return addOne
}
increment := makeIncrementer()
increment(7)
```
### Kotlin
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
### Swift
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
## Classes Declaration
### Xs
```
Shape() -> {
    NumberOfSides := 0
    simpleDescription() -> (s: str) {
        <- ("A shape with " NumberOfSides " sides.")
    }
}
```
### C#
```
class Shape 
{
    public int numberOfSides = 0;
    public string simpleDescription() 
    {
        return $"A shape with {numberOfSides} sides.";
    }
}
```
### Go
```
type Shape struct {
    numberOfSides int
}
func (p *Shape) simpleDescription() string {
    return fmt.Sprintf("A shape with %d sides.", p.numberOfSides)
}
```
### Kotlin
```
class Shape {
    var numberOfSides = 0
    fun simpleDescription() =
        "A shape with $numberOfSides sides."
}
```
### Swift
```
class Shape {
    var numberOfSides = 0
    func simpleDescription() -> String {
        return "A shape with \(numberOfSides) sides."
    }
}
```
## Classes Usage
### Xs
```
shape := Shape()
shape.NumberOfSides = 7
shapeDescription := shape.simpleDescription()
```
### C#
```
var shape = new Shape();
shape.numberOfSides = 7;
var shapeDescription = shape.simpleDescription();
```
### Go
```
shape := Shape{}
shape.numberOfSides = 7
shapeDescription := shape.simpleDescription()
```
### Kotlin
```
var shape = Shape()
shape.numberOfSides = 7
var shapeDescription = shape.simpleDescription()
```
### Swift
```
var shape = Shape()
shape.numberOfSides = 7
var shapeDescription = shape.simpleDescription()
```
## Subclass
### Xs
```
NamedShape(name: str) {
    ..name = name
} -> {
    name: str
    NumberOfSides: i32 = 0

    SimpleDescription() -> (s: str) {
        <- ("A shape with " NumberOfSides " sides.")
    }
}

Square(sideLength: f64, name: str) {
    ..NumberOfSides = 4
    ..sideLength = sideLength
} -> {
    sideLength: f64

    area() -> (f: f64) {
        <- (sideLength * sideLength)
    }
} NamedShape(name) {
    SimpleDescription() -> (s: str) {
        <- ("A square with sides of length " sideLength ".")
    }
}

test := Square(5.2, "square")
test.area()
test.SimpleDescription()
```
### C#
```
class NamedShape 
{
    public int numberOfSides = 0;
    public string name {get;}

    public NamedShape(string name) 
    {
        this.name = name;
    }

    public virtual string simpleDescription() 
    {
        return $"A shape with {numberOfSides} sides.";
    }
}

class Square: NamedShape 
{
    double sideLength;

    public Square(double sideLength, string name):base(name) 
    {
        this.sideLength = sideLength;
        this.numberOfSides = 4;
    }

    public double area() 
    {
        return sideLength * sideLength;
    }

    public override string simpleDescription() 
    {
        return $"A square with sides of length {sideLength}.";
    }
}

var test = new Square(5.2, "square");
test.area();
test.simpleDescription();
```
### Go
```
type NamedShape struct {
    numberOfSides int
    name string
}
func NewNamedShape(name string) *NamedShape {
    return &NamedShape{
        name: name,
    }
}
func (p *NamedShape) SimpleDescription() string {
    return fmt.Sprintf("A shape with %d sides.", p.numberOfSides)
}

type Square struct {
    *NamedShape
    sideLength float64
}
func NewSquare(sideLength float64, name string) *Square {
    return &Square{
        NamedShape: NewNamedShape(name),
        sideLength: sideLength,
    }
}
func (p *Square) Area() float64 {
    return p.sideLength * p.sideLength
}
func (p *Square) SimpleDescription() string {
    return fmt.Sprintf("A square with sides of length %d.", p.sideLength)
}

a := NewSquare(5.2, "square")
a.Area()
a.SimpleDescription()
```
### Kotlin
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
### Swift
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
        return "A square with sides of length \(sideLength)."
    }
}

let test = Square(sideLength: 5.2, name: "square")
test.area()
test.simpleDescription()
```
## Checking Type
### Xs
```
MovieCount := 0
SongCount := 0

@ item <- library {
    ? item -> :Movie {
        MovieCount += 1
    } :Song {
        SongCount += 1
    }
}
```
### C#
```
var movieCount = 0;
var songCount = 0;

foreach (var item in library) 
{
    if (item is Movie) 
    {
        movieCount++;
    } 
    else if (item is Song) 
    {
        songCount++;
    }
}
```
### Go
```
var movieCount = 0
var songCount = 0

for _, item := range(library) {
    if _, ok := item(Movie); ok {
        movieCount++
    } else if _, ok := item(Song); ok {
        songCount++
    }
}
```
### Kotlin
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
### Swift
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
## Pattern Matching
### Xs
```
nb := 42
? nb -> [0<=7], 8, 9 { 
    prt("single digit") 
} 10 { 
    prt("double digits") 
} [11<=99] { 
    prt("double digits") 
} [100<=999] { 
    prt("triple digits") 
} _ { 
    prt("four or more digits") 
}
```
### C#
```
var nb = 42;
switch (nb) 
{
    case int x when x <= 7 && x >=0: 
    case 8:
    case 9:
        Console.WriteLine("single digit");
        break;
    case 10: 
        Console.WriteLine("double digits");
        break;
    case int x when x >=11 && x <=99: 
        Console.WriteLine("double digits");
        break;
    case int x when x >= 100 && x <= 999: 
        Console.WriteLine("triple digits");
        break;
    default: 
        Console.WriteLine("four or more digits");
        break;
}
```
### Kotlin
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
### Swift
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
## Downcasting
### Xs
```
@ current <- someObjects {
    ? current -> movie:Movie {
        prt("Movie: '" movie.name "', " +
            "dir. " movie.director "")
    }
}
```
### C#
```
foreach (var current in someObjects) 
{
    if (current is Movie movie) 
    {
        Console.WriteLine($"Movie: '{movie.name}', " +
            $"dir. {movie.director}")
    }
}
```
### Go
```
for _, object := range someObjects {
    if movie,ok := object.(Movie); ok {
        fmt.Printf("Movie: '%s', dir. %s", movie.name, movie.director)
    }
}
```
### Kotlin
```
for (current in someObjects) {
    if (current is Movie) {
        println("Movie: '${current.name}', " +
	    "dir. ${current.director}")
    }
}
```
### Swift
```
for current in someObjects {
    if let movie = current as? Movie {
        print("Movie: '\(movie.name)', " +
            "dir. \(movie.director)")
    }
}
```
## Protocol
### Xs
```
Nameable <- {
    name() -> (s: str)
}

f(x: Nameable) -> () {
    prt("Name is " + x.name())
}
```
### C#
```
interface Nameable 
{
    string name();
}

void f(Nameable x) 
{
    Console.WriteLine("Name is " + x.name());
}
```
### Go
```
type Nameable interface {
    func Name() string
}

func F(x Nameable) {
    fmt.Println("Name is " + x.Name())
}
```
### Kotlin
```
interface Nameable {
    fun name(): String
}

fun f(x: Nameable) {
    println("Name is " + x.name())
}
```
### Swift
```
protocol Nameable {
    func name() -> String
}

func f(x: Nameable) {
    print("Name is " + x.name())
}
```
## Implement
### Xs
```
Dog() -> {
} Nameable {
    name() -> (n: str) {
        <- ("Dog")
    }
} Weight {
    getWeight() -> (w: i32) {
        <- (30)
    }
}
```
### C#
```
class Dog: Nameable, Weight
{
    public string name()
    {
        return "Dog";
    }

    public int getWeight() 
    {
        return 30;
    }
}
```

### Go
```
type Dog struct {}
// Implement Nameable
func (p *Dog) Name() string {
    return "Dog"
}
// Implement Weight
func (p *Dog) GetWeight() int {
    return 30
}
```
### Kotlin
```
class Dog: Nameable, Weight {
    override fun name(): String {
        return "Dog"
    }

    override fun getWeight(): Int {
        return 30
    }
}
```
### Swift
```
class Dog: Nameable, Weight {
    func name() -> String {
        return "Dog"
    }

    func getWeight() -> Int {
        return 30
    }
}
```