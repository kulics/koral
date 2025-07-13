
# Compare

## Hello World

### Koral

```
printLine("Hello, world!");
```

### C#

```csharp
Console.WriteLine("Hello, world!");
```

### Go

```go
print("Hello, world!")
```

### Kotlin

```kotlin
println("Hello, world!")
```

### Swift

```swift
print("Hello, world!")
```

## Variables And Constants

### Koral

```
let mut myVariable = 42;
myVariable = 50;
let myConstant = 42;
```

### C#

```csharp
var myVariable = 42;
myVariable = 50;
const int myConstant = 42;
```

### Go

```go
myVariable := 42
myVariable = 50
const myConstant = 42
```

### Kotlin

```kotlin
var myVariable = 42
myVariable = 50
val myConstant = 42
```

### Swift

```swift
var myVariable = 42
myVariable = 50
let myConstant = 42
```

## Explicit Types

### Koral

```
let explicitDouble Float64 = 70.0;
```

### C#

```csharp
double explicitDouble = 70;
```

### Go

```go
var explicitDouble float64 = 70.0
```

### Kotlin

```kotlin
val explicitDouble: Double = 70.0
```

### Swift

```swift
let explicitDouble: Double = 70
```

## Basic Types

### Koral

```
Int32 Int16 Int64 Int8 
Float64 Float32 
Bool
String
```

### C#

```csharp
int short long byte 
double float 
bool 
string
```

### Go

```go
int32 int16 int64 int8 
float64 float32 
bool 
string
```

### Kotlin

```kotlin
Int Short Long Byte 
Double Float 
Boolean 
String
```

### Swift

```swift
Int32 Int16 Int64 Int8 
Double Float 
Bool 
String
```

## Type Coercion

### Koral

```
let f = 6.0;
let i = 94;
let count = i + (Int)f;
```

### C#

```csharp
double f = 6;
int i = 94;
int count = i + (int)f;
```

### Go

```go
f := 6.0
i := 94
count := i + int(f)
```

### Kotlin

```kotlin
val f = 6.0
val i = 94
val count: Int = i + f
```

### Swift

```swift
let f = 6.0
let i = 94
let count = i + Int(f)
```

## Inclusive Range Operator

### Koral

```
for 1..<=5 as index then
    printLine("\{index} times 5 is \{index * 5}");
```

### C#

```csharp
for (int index = 1; index <= 5; index++) 
    Console.Write($"{index} times 5 is {index * 5}");
```

### Go

```go
for index := 1; index <= 5; index++ {
    fmt.Printf("%d times 5 is %d", index, index*5)
}
```

### Kotlin

```kotlin
for (index in 1..5) 
    println("$index times 5 is ${index * 5}")
```

### Swift

```swift
for index in 1...5 {
    print("\(index) times 5 is \(index * 5)")
}
```

## Arrays

### Koral

```
let shoppingList = Array.of("catfish", "water", "tulips", "blue paint");
shoppingList[1] = "bottle of water";
```

### C#

```csharp
var shoppingList = new string[]{"catfish", "water", "tulips", "blue paint"};
shoppingList[1] = "bottle of water";
```

### Go

```go
shoppingList := []string{"catfish", "water", "tulips", "blue paint"}
shoppingList[1] = "bottle of water"
```

### Kotlin

```kotlin
val shoppingList = arrayOf("catfish", "water", "tulips", "blue paint")
shoppingList[1] = "bottle of water"
```

### Swift

```swift
var shoppingList = ["catfish", "water", "tulips", "blue paint"]
shoppingList[1] = "bottle of water"
```

## Maps

### Koral

```
let occupations = Map.of(
    ("Malcolm", "Captain"),
    ("Kaylee", "Mechanic"),
);
occupations["Jayne"] = "Public Relations";
```

### C#

```csharp
var occupations = new Dictionary<string,string>(){
    {"Malcolm", "Captain"},
    {"Kaylee", "Mechanic"}
};
occupations["Jayne"] = "Public Relations";
```

### Go

```go
occupations := map[string]string{
    "Malcolm": "Captain",
    "Kaylee": "Mechanic",
}
occupations["Jayne"] = "Public Relations"
```

### Kotlin

```kotlin
val occupations = mutableMapOf(
    "Malcolm" to "Captain",
    "Kaylee" to "Mechanic"
)
occupations["Jayne"] = "Public Relations"
```

### Swift

```swift
var occupations = [
    "Malcolm": "Captain",
    "Kaylee": "Mechanic",
]
occupations["Jayne"] = "Public Relations"
```

## Empty Collections

### Koral

```
let emptyArray = [String]Array.empty();
let emptyMap = [String, Float32]Map.empty();
```

### C#

```csharp
var emptyArray = new string[]{};
var emptyDictionary = new Dictionary<string, float>();
```

### Go

```go
var (
    emptyArray []string
    emptyMap = make(map[string]float)
)
```

### Kotlin

```kotlin
val emptyArray = arrayOf<String>()
val emptyMap = mapOf<String, Float>()
```

### Swift

```swift
let emptyArray = [String]()
let emptyDictionary = [String: Float]()
```

## Functions

### Koral

```
let greet(name String, day String) String = 
    "Hello \{name}, today is \{day}.";
greet("Bob", "Tuesday");
```

### C#

```csharp
string greet(string name, string day) 
{
    return $"Hello {name}, today is {day}.";
}
greet("Bob", "Tuesday");
```

### Go

```go
func greet(name, day string) string {
    return fmt.Sprintf("Hello %v, today is %v.", name, day)
}
greet("Bob", "Tuesday")
```

### Kotlin

```kotlin
fun greet(name: String, day: String): String {
    return "Hello $name, today is $day."
}
greet("Bob", "Tuesday")
```

### Swift

```swift
func greet(_ name: String, _ day: String) -> String {
    return "Hello \(name), today is \(day)."
}
greet("Bob", "Tuesday")
```

## Tuple Return

### Koral

```
let getGasPrices() [Float, Float, Float]Tuple = (3.59, 3.69, 3.79);
```

### C#

```csharp
(double, double, double) getGasPrices() 
{
    return (3.59, 3.69, 3.79);
}
```

### Go

```go
func getGasPrices() (float64, float64, float64) {
    return 3.59, 3.69, 3.79
}
```

### Kotlin

```kotlin
fun getGasPrices() = Triple(3.59, 3.69, 3.79)
```

### Swift

```swift
func getGasPrices() -> (Double, Double, Double) {
    return (3.59, 3.69, 3.79)
}
```

## Function Type

### Koral

```
let makeIncrementer() [Int, Int]Func = {
    let addOne(number Int) = 1 + number;
    addOne
}
let increment = makeIncrementer();
increment(7);
```

### C#

```csharp
Func<int, int> makeIncrementer() 
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

```go
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

```kotlin
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

```swift
func makeIncrementer() -> (Int) -> Int {
    func addOne(number: Int) -> Int {
        return 1 + number
    }
    return addOne
}
let increment = makeIncrementer()
increment(7)
```

## Classes Declaration

### Koral

```
type Shape(mut numberOfSides Int) {
    self.simpleDescription() String =
        "A shape with \{self.numberOfSides} sides.";
}
```

### C#

```csharp
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

```go
type Shape struct {
    numberOfSides int
}
func (p *Shape) simpleDescription() string {
    return fmt.Sprintf("A shape with %d sides.", p.numberOfSides)
}
```

### Kotlin

```kotlin
class Shape(var numberOfSides: Int) {
    fun simpleDescription() =
        "A shape with $numberOfSides sides."
}
```

### Swift

```swift
class Shape {
    var numberOfSides = 0
    func simpleDescription() -> String {
        return "A shape with \(numberOfSides) sides."
    }
}
```

## Classes Usage

### Koral

```
let shape = Shape(0);
shape.numberOfSides = 7;
let shapeDescription = shape.simpleDescription();
```

### C#

```csharp
var shape = new Shape();
shape.numberOfSides = 7;
var shapeDescription = shape.simpleDescription();
```

### Go

```go
shape := Shape{}
shape.numberOfSides = 7
shapeDescription := shape.simpleDescription()
```

### Kotlin

```kotlin
var shape = Shape()
shape.numberOfSides = 7
var shapeDescription = shape.simpleDescription()
```

### Swift

```swift
var shape = Shape()
shape.numberOfSides = 7
var shapeDescription = shape.simpleDescription()
```

## Subclass

### Koral

```
type NamedShape(name String, numberOfSides Int) {
    self.simpleDescription() String =
        "A shape with \{self.numberOfSides} sides.";
}

type Square(as namedShape NamedShape, sideLength Float) {
    new(sideLength Float, name String) Square = Square(NamedShape(name, 4), sideLength);

    self.simpleDescription() String =
        "A square with sides of length \{self.sideLength}.";

    self.area() Float = sideLength * sideLength;
}

let test = Square.new(5.2, "square");
test.area();
test.simpleDescription();
```

### C#

```csharp
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

```go
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

```kotlin
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

```swift
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

### Koral

```
let mut movieCount = 0;
let mut songCount = 0;

for library as item then
    if item is Movie then 
        movieCount += 1
    else if item is Song then
        songCount += 1;
```

### C#

```csharp
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

```go
var movieCount = 0
var songCount = 0

for _, item := range library {
    if _, ok := item.(Movie); ok {
        movieCount++
    } else if _, ok := item.(Song); ok {
        songCount++
    }
}
```

### Kotlin

```kotlin
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

```swift
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

### Koral

```
let nb = 42;
when nb is {
    >= 0 and <= 7 or 8 or 9 ->
        print("single digit");
    10 ->
        print("double digits");
    >= 11 and <= 99 ->
        print("double digits");
    >= 100 and <= 999 ->
        print("triple digits");
    _ ->
        print("four or more digits");
}
```

### C#

```csharp
var nb = 42;
switch (nb)
{
    case <= 7 and >= 0 or 8 or 9: 
        Console.WriteLine("single digit");
        break;
    case 10: 
        Console.WriteLine("double digits");
        break;
    case >= 11 and <= 99: 
        Console.WriteLine("double digits");
        break;
    case >= 100 and <= 999: 
        Console.WriteLine("triple digits");
        break;
    default: 
        Console.WriteLine("four or more digits");
        break;
}
```

### Kotlin

```kotlin
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

```swift
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

### Koral

```
for someObjects as current then
    if current is movie Movie then
        printLine("Movie: '\{movie.name}', dir. \{movie.director}");
```

### C#

```csharp
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

```go
for _, object := range someObjects {
    if movie, ok := object.(Movie); ok {
        fmt.Printf("Movie: '%s', dir. %s", movie.name, movie.director)
    }
}
```

### Kotlin

```kotlin
for (current in someObjects) 
    if (current is Movie) 
        println("Movie: '${current.name}', " +
	    "dir. ${current.director}")
```

### Swift

```swift
for case movie as Movie in someObjects {
    print("Movie: '\(movie.name)', dir. \(movie.director)")
}
```

## Interface

### Koral

```
type Nameable {
    self.name() String;
}

let f(x Nameable) Void = printLine("Name is " + x.name());
```

### C#

```csharp
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

```go
type Nameable interface {
    Name() string
}

func F(x Nameable) {
    fmt.Println("Name is " + x.Name())
}
```

### Kotlin

```kotlin
interface Nameable {
    fun name(): String
}

fun f(x: Nameable) {
    println("Name is " + x.name())
}
```

### Swift

```swift
protocol Nameable {
    func name() -> String
}

func f(x: any Nameable) {
    print("Name is " + x.name())
}
```

## Implement

### Koral

```
type Dog();

given Dog {
    self.name() String = "Dog";

    self.weight() Int = 30;
}
```

### C#

```csharp
class Dog: Nameable, Weight
{
    public string name()
    {
        return "Dog";
    }

    public int weight() 
    {
        return 30;
    }
}
```

### Go

```go
type Dog struct {}

func (p *Dog) name() string {
    return "Dog"
}

func (p *Dog) weight() int {
    return 30
}
```

### Kotlin

```kotlin
class Dog: Nameable, Weight {
    override fun name(): String {
        return "Dog"
    }

    override fun weight(): Int {
        return 30
    }
}
```

### Swift

```swift
class Dog: Nameable, Weight {
    func name() -> String {
        return "Dog"
    }

    func weight() -> Int {
        return 30
    }
}
```