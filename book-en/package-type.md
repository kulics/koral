# Package Type
If we only have a few basic data, in fact it is very difficult to describe more specific things.

Therefore, we need a feature that can wrap data of different attributes to better describe what we need.

Obviously, this feature for package data, called package.
## Definition
We can use the `id -> {}` statement to define a package that has nothing.

E.g:
```
Package -> {
}
```
Of course, we hope more is to be able to pack a few data, for example, a name, student number, class, grade attributes of students.
We can define these data in the same way we define normal identifiers.

E.g:
```
Student -> {
    name: Str = ""
    number: Str = ""
    class: Int = 0
    grade: Int = 0
}
```
So we get a student bag with these data attributes. This student bag now becomes a usable type like `Int, Str, Bool`.

Unlike our original base type can only store one data, the student package can store name, student number, class, grade data.

This is very much like the concept of assembling different parts together in our reality as a whole, so it is called a package.

## Create
So how do we create a new package? As always, all of our types can be created using the construct function `type{}`.

E.g:
```
Peter := Student{}
```
This create a `Peter` identifier. All the properties of this student are initialized to `"", "", 0,0` as set in the definition.

Let us recall that our base type, collection types can be created using the type-creation syntax, in fact they are all packages.

## Using Property
Now that we have a `Peter`, how do we use the attributes inside?

Very simple, we only need to use `.` syntax, we can summon the attributes we need.

E.g:
```
Prt(Peter.name)
# print the name of a student
```
To change the value of the property is the same, it is equivalent to a nested identifier. We can directly use the assignment statement to change the value.  
Parentheses can be omitted when the constructor is empty.

E.g:
```
Peter.name = "peter" 
Peter.number = "060233"
Peter.class = 2
Peter.grade = 6
```
## Construction assignment
Creating a new package like the one above, and then loading the data one by one, is very cumbersome. We can use a simplified syntax to configure.

Add `key=value` to the build syntax and separate the data with `,`.

E.g:
```
Peter := Student{
    name="peter", number="060233",
    class=2, grade=6
}
```

Similarly, the way the collection is created is actually a simplified creation, so we can also create arrays and dictionaries like this.

E.g:
```
Array := []Int{ 1, 2, 3, 4, 5 }
Dictionary := [Str]Int{ ["1"]1, ["2"]2, ["3"]3 }
```
## Anonymous Package
If we only want to wrap some data directly, instead of defining the package first and then using it, is it like an anonymous function?

Of course, we can use the `{}` package directly, the same syntax as the collection, only the elements inside have different syntax.

E.g:
```
Peter := {
    name = "peter",
    number = "060233",
    class = 2,
    grade = 6
}
```

This directly creates a `Peter` data that we can use directly, but we cannot change this data.

Since the anonymous package is not a package of a clear type, we only recommend it for use on occasional occasions, such as LINQ.
## Private Property
Anyone has some little secret, Peter is the same, maybe he hid a secret little girl's name and did not want others to know.

We can define private properties to store properties that we do not want to be accessed by the outside world.

E.g:
```
Student -> {
    ......
    _girl Friend: Str    # The identifier beginning with this '_' is private
}
```
That's right, if you remember the definition of identifiers, this is how private identifiers are defined, and private identifiers can not be accessed by outsiders.

Therefore, we can define a `Peter`, nor can we get or modify the value via `Peter._girl Firend`.

Then the private properties of this package can not be accessed, and can not be modified, what is the use? Do not worry, there is another attribute package.

## Function
If we need to make this package come with a function that makes it easy to manipulate, we can define it directly in the package.

E.g:
```
Student -> {
    ......
    _girl Friend: Str
    get Girl Friend() -> (name: Str) {
        <- (.._girl Friend)
    }
}
```

The `..` used here to declare the package itself, so you can easily access their own properties. This can be thought of as `this | self` in other languages.

Through the function properties, we can get to the private property, you can also easily according to business needs to deal with other data in the package.

With this function, we can get the private property by calling the function.

E.g:
```
Prt( Peter.get Girl Friend() )
# printed the name of a girlfriend of a puppy love student
```
As with data attributes, functions can also be private identifiers, and functions that use private identifiers also mean that only the packet can access itself.

## Combination
Now let us play our imagination, we want a customized package for Chinese students how to define it?

E.g:
```
Chinese Student -> {
    name: Str = ""
    number: Str = ""
    class: Int = 0
    grade: Int = 0
    kungfu: Bool = False    # kung fu students
}
```
No, no repeatable definition of data so elegant, we can reuse student attributes, with an additional kung fu attributes on it.

We need to use a combination of this feature, but not so complicated, just created a student attribute only.

E.g:
```
Chinese Student -> {
    student := Student{}   # include student attributes in it
    kungfu := False        # no kung fu
}
```
This way you can use generic attributes via student attributes in Chinese students.

E.g:
```
Chen := Chinese Student{}
Prt(Chen.student.name)
# of course, since there is no assignment, nothing is output
```
By combining layers after layer, you are free to assemble whatever you want to describe.

## Compatible with .NET
The following are compatibility features, if not necessary, it is not recommended.

### Inheritance
If we want to define a new package and fully inherit all the properties of a package, we can use the inheritance syntax, append `...id {}` to the definition.
If you want to override the properties of the original package, rewrite it in `{}`.

E.g:
```
chineseStudent -> {
    kungfu := False
} ...Student {   # inhert student
    # override
    get Girl Friend() -> (name: Str) {
        <- ("none")
    }
}
```

### Construct
Sometimes we might use the constructor in .NET.

We can append the `(id:type){}` statement after the definition.

E.g:
```
Student -> {
    ......
} (name: Str, number: Str) {
    ..name = name
    ..number = number
    # calculate the class
    ..class = get Sub Text(number, 2, 3)
    # calculate the grade
    ..grade = get Sub Text(number, 0, 1)
}
```
This gives us a package with constructors, and when we create a new student, class and grade data are automatically generated.

We need to use the constructor with the `New<type>()` function.

E.g:
```
Peter := New<student>("peter", "060233")
Prt(Peter.class)     # print 2
```

If you need to use a constructor with inheritance, you can append `...(params)` to the argument syntax.

E.g:
```
Parent -> {
} (a:Int) {
}

Child -> {
} (a:Int)...(a) {
} ...Parent {
}
```

### [Next Chapter](namespace.md)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    A := S{a=5,b=12}
    B := PKG(x="hello", y=64, z=A)
    Prt( B.z.a )
    Prt( B.print() )
}

S -> {
    a := 0
    b := 0
}

PKG -> {
    x := ""
    y := 0
    z :S

    print() -> (a: Str) {
        <- ( "x {y}" )
    }
} 
```