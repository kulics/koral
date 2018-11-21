# Package Type
If we only have a few basic data, in fact it is very difficult to describe more specific things.

Therefore, we need a feature that can wrap data of different attributes to better describe what we need.

Obviously, this feature for package data, called package.
## Definition
We can use the `id {}-> {}` statement to define a package that has nothing.

E.g:
```
package {}-> {
}
```
Of course, we hope more is to be able to pack a few data, for example, a name, student number, class, grade attributes of students.
We can define these data in the same way we define normal identifiers.

E.g:
```
student {}-> {
    name :str = ""
    number :str = ""
    class :i32 = 0
    grade :i32 = 0
}
```
So we get a student bag with these data attributes. This student bag now becomes a usable type like `i32, str, bl`.

Unlike our original base type can only store one data, the student package can store name, student number, class, grade data.

This is very much like the concept of assembling different parts together in our reality as a whole, so it is called a package.

## Create
So how do we create a new package? As always, all of our types can be created using the type-creation syntax.

E.g:
```
Peter := student{}
```
This create a `Peter` identifier. All the properties of this student are initialized to `"", "", 0,0` as set in the definition.

Let us recall that our base type, collection types can be created using the type-creation syntax, in fact they are all packages.

As long as it is a type that is extended by a package, it can be created in the same way as the create syntax, which is a rule in this language.

## Using Property
Now that we have a `Peter`, how do we use the attributes inside?

Very simple, we only need to use `.` syntax, we can summon the attributes we need.

E.g:
```
cmd.print(Peter.name)
# print the name of a student
```
To change the value of the property is the same, it is equivalent to a nested identifier. We can directly use the assignment statement to change the value.

E.g:
```
Peter.name = "Peter" 
Peter.number = "060233"
Peter.class = 2
Peter.grade = 6
```
## Simplify creation
Creating a new package like the one above, and then loading the data one by one, is very cumbersome. We can use a simplified syntax to configure.
Just add `<-` to the creation grammar to use the `key=value` method to quickly load data. Separate multiple data with `,`.

E.g:
```
Peter := student{ <-
    name="Peter", number="060233",
    class=2, grade=6
}
```

So the fingers are not so sour.

Similarly, the way the collection is created is actually a simplified creation, so we can also create arrays and dictionaries like this.

E.g:
```
Array := []i32{ <- 1, 2, 3, 4, 5 }
Dictionary := [str]i32{ <- "1"->1, "2"->2, "3"->3 }
```
## Anonymous Package
If we only want to wrap some data directly, instead of defining the package first and then using it, is it like an anonymous function?

Of course, we can use the `{}` package directly, the same syntax as the collection, only the elements inside have different syntax.

E.g:
```
Peter := {
    name := "Peter"
    number := "060233"
    class := 2
    grade := 6
}
```

This directly creates a `Peter` data that we can use directly, but we cannot change this data.

Since the anonymous package is not a package of a clear type, we only recommend it for use on occasional occasions, such as LINQ.
## Private Property
Anyone has some little secret, Peter is the same, maybe he hid a secret little girl's name and did not want others to know.

We can define private properties to store properties that we do not want to be accessed by the outside world.

E.g:
```
student {}-> {
    ...
    _girlFirend :str    # The identifier beginning with this '_' is private
}
```
That's right, if you remember the definition of identifiers, this is how private identifiers are defined, and private identifiers can not be accessed by outsiders.

Therefore, we can define a `Peter`, nor can we get or modify the value via `Peter._girlFirend`.

Then the private properties of this package can not be accessed, and can not be modified, what is the use? Do not worry, there is another attribute package.

## Extension Function
If we need to make this package come with a function that makes it easy to manipulate, we can't define it directly in the package.
We need to use the extension statement `id += {}` to make the package add extension functions.

E.g:
```
student += {
    getGirlFirend ()->(name:str) {
        <- (.._girlFirend)
    }
}
```
Because the extension function is part of the package, and the function can call data or functionality, we can define a method for getting the private property.

The `..` used here to declare the package itself, so you can easily access their own properties. This can be thought of as `this | self` in other languages.

Through the function properties, we can get to the private property, you can also easily according to business needs to deal with other data in the package.

With this function, we can get the private property by calling the function.

E.g:
```
cmd.print( Peter.getGirlFirend() )
# printed the name of a girlfriend of a puppy love student
```
As with data attributes, functions can also be private identifiers, and functions that use private identifiers also mean that only the packet can access itself.

## Construct
Sometimes, we do not want to always create a blank students, in fact, the student number often contains the grade and class information,

We hope that given a name and student number, class and grade information will be automatically created exactly.

This can be achieved using regular functions, but why not use the built-in constructor?

Add parameters at the time of definition, and write the definition of the constructor, which only needs the `.. {}` statement.

E.g:
```
student {name, number: str}-> {
    ...

    .. {
        ..name = name
        ..number = number
        # calculate the class
        ..class = GetSubText(number, 2, 3)
        # calculate the grade
        ..grade = GetSubText(number, 0, 1)
    }
}
```
This gives us a package with constructors, and when we create a new student, class and grade data are automatically generated.

E.g:
```
Peter := student{"Peter", "060233"}
cmd.print(Peter.class)     # print out 2
```

Can the declaration be simpler, such as defining properties directly in the construct?
Of course, we can mark the constructor parameter `..`, and the compiler will automatically generate the relevant variables.

E.g:
```
# automatically generate the attributes name and number , which is equivalent to the previous example
student {..name, ..number:str}-> {
     ...
}
```

If you need to use both constructors and simplified creations, you can do so.

E.g:
```
Peter := student{"Peter", "060233" <- name="New Peter"}
```

It should be noted that a package can only support one constructor, we recommend to maintain the simplicity of the structure, a stable package easier to be used by the caller,

If you really have more construction requirements, you can use regular functions to accomplish this requirement.

## Combination
Now let us play our imagination, we want a customized package for Chinese students how to define it?

E.g:
```
chineseStudent {}-> {
    name :str = ""
    number :str = ""
    class :i32 = 0
    grade :i32 = 0
    kungfu :bl = false    # kung fu students
}
```
No, no repeatable definition of data so elegant, we can reuse student attributes, with an additional kung fu attributes on it.

We need to use a combination of this feature, but not so complicated, just created a student attribute only.

E.g:
```
chineseStudent {}-> {
    student :student|null   # include student attributes in it
    kungfu :bl|null         # kung fu students
}
```
This way you can use generic attributes via student attributes in Chinese students.

E.g:
```
Chen := chinesestudent{}
cmd.print(Chen.student.name)
# of course, since there is no assignment, nothing is output
```
By combining layers after layer, you are free to assemble whatever you want to describe.

### [Next Chapter](protocol-type.md)

## Example of this chapter
```
Demo {
    System
    Library
}

Main ()->() {
    a := S{ <- A=5,B=12}
    b := PKG{"hello", 64, a}
    cmd.print( b.Z.A )
    cmd.print( b.Print() )
}

S {}-> {
    A := 0
    B := 0
}

PKG {x:str, ..Y:i32, ..Z:S}-> {
    X := ""
    
    .. {
        X = x
    }
}

PKG += {
    Print ()->(a:str) {
        <- ( "X {Y}" )
    }
}
```