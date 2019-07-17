
# Compare
## Hello World
### Lite
```
print("Hello, world!")
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
### Python
```
print("Hello, world!")
```
## Variables And Constants
### Lite
```
myVariable := 42
myVariable = 50
myConstant :: 42
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
### Python
```
myVariable = 42
myVariable = 50
MYCONSTANT = 42
```
## Explicit Types
### Lite
```
explicitDouble: num = 70
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
### Lite
```
i32 i16 i64 i8 
f64 f32 
bool 
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
### Python
```
int long 
double float 
bool
string
```
## Type Coercion
### Lite
```
f := 6.0
i := 94
count := i + f:(int)
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
### Python
```
f = 6.0
i = 94
count = i + int(f)
```
## Inclusive Range Operator
### Lite
```
[ 1 <= 5 ] @ index {
    print("" index " times 5 is " index * 5 "")
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
### Python
```
for index in range(1,6):
    print ("%d times 5 is %d" % (index,index*5))
```
## Arrays
### Lite
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
### Python
```
shoppingList = ["catfish", "water",
    "tulips", "blue paint"]
shoppingList[1] = "bottle of water"
```
## Maps
### Lite
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
### Python
```
occupations = {
    "Malcolm":"Captain",
    "Kaylee":"Mechanic"
}
occupations["Jayne"] = "Public Relations"
```
## Empty Collections
### Lite
```
emptyArray := []str{}
emptyDictionary := [str]f32{}
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
### Python
```
emptyArray = []
emptyDictionary ={}
```
## Functions
### Lite
```
greet(name: str, day: str -> r: str) {
    <- "Hello " name ", today is " day "."
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
### Python
```
def greet(name,day):
    return 'hello ' + name + ',today is '+ day
greet("Bob", "Tuesday")
```
## Tuple Return
### Lite
```
getGasPrices(-> a: num, b: num, c: num) {
    <- 3.59, 3.69, 3.79
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
### Python
```
def getGasPrices():
    return (3.59, 3.69, 3.79)
```
## Function Type
### Lite
```
makeIncrementer(-> fn: (int->int)) {
    addOne(number: int -> number: int) {
        <- 1 + number
    }
    <- addOne
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
### Python
```
def makeIncrementer():
    def addOne(number):
        return 1 + number
    return addOne
increment = makeIncrementer()
increment(7)
```
## Classes Declaration
### Lite
```
Shape -> {
    numberOfSides := 0
}
me: Shape -> {
    simpleDescription(-> s: str) {
        <- "A shape with " me.number of sides " sides."
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
### Python
```
class Shape(object):
    def __init__(self):
        self.numberOfSides = 0
    def simpleDescription(self):
        return 'A shape with' + numberOfSides +' sides.'
```
## Classes Usage
### Lite
```
shape := Shape{}
shape.numberOfSides = 7
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
### Python
```
shape = Shape()
shape.numberOfSides = 7
shapeDescription = shape.simpleDescription()
```
## Subclass
### Lite
```
NamedShape -> {
    name: str
    numberOfSides := 0
}
me: NamedShape -> {
    simpleDescription(-> s: str) {
        <- "A shape with " me.numberOfSides " sides."
    }
} 

Square -> {
    :NamedShape
    sideLength: num
} 
me: Square -> {
    simpleDescription(-> s: str) {
        <- "A square with sides of length " me.sideLength "."
    }

    init(sideLength: num, name: str -> v: square) {
        me.sideLength = sideLength
        me.numberOfSides = 4
        me.name = name
        <- me
    }

    area(-> f: num) {
        <- me.sideLength ** 2
    }
}

test := Square{}.init(5.2, "square")
test.area()
test.simpleDescription()
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
## Python
```
class NamedShape(object):
    def __init__(self,name):
        self.numberOfSides = 0
        self.name = name
    def simpleDescription(self):
        return 'A shape with ' + str(self.numberOfSides) + ' sides.'


class Square(NamedShape):
    def __init__(self,sideLength,name):
        NamedShape.__init__(self,name)
        self.sideLength = sideLength
        self.numberOfSides = 4
    def area(self):
        return self.sideLength * self.sideLength
    def simpleDescription(self):
        return 'A square with sides of length ' + str(self.sideLength)

test = Square(5.2,'square')
test.area()
test.simpleDescription()
```
## Checking Type
### Lite
```
movieCount := 0
songCount := 0

library @ item {
    item ? :Movie {
        movieCount += 1
    } :Song {
        songCount += 1
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

for _, item := range library {
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
### Python
```
movieCount = 0
songCount = 0

for item in library:
    if item is Movie:
        movieCount+=1
    elif item is Song:
        songCount+=1
```
## Pattern Matching
### Lite
```
nb := 42
nb ? [0 <= 7], 8, 9 { 
    print("single digit") 
} 10 { 
    print("double digits") 
} [11 <= 99] { 
    print("double digits") 
} [100 <= 999] { 
    print("triple digits") 
} _ { 
    print("four or more digits") 
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
### Lite
```
someObjects @ current {
    current ? movie:Movie {
        print("Movie: '" movie.name "', " +
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
### Python
```
for current in someObjects:
    if current is Movie:
        print('Movie: %s, dir. %s' % (movie.name, movie.director))
```
## Protocol
### Lite
```
Nameable <- {
    name(-> s: str)
}

f(x: Nameable ->) {
    print("Name is " + x.name())
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
### Lite
```
Dog -> {}
me:Dog -> Nameable {
    name(-> n: str) {
        <- "Dog"
    }
}
me:Dog -> Weight {
    getWeight(-> w: int) {
        <- 30
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