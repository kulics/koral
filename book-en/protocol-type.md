# Protocol Type
In reality, we often use the protocol to specify some specific rules, so that people or things can do things according to the expected rules.
We often need to do this in programming languages as well. This feature is the protocol.

The protocol specifies the methods and properties necessary to implement a particular feature, allowing the package to comply.

Our package can introduce the protocol we need, just like signing an protocol, and then declare all the properties required by the protocol, so that we think the package signed the protocol.
## Definition
We only need to use the symbol `id -> {}` to define a protocol.

E.g:
```
protocol -> {
}
```
This is an empty protocol.

Next, let's design a difficult task that students need to accomplish ... homework.

E.g:
```
homeWork -> {
    count :i32
    do ()->(){}
}
```
The protocol for this job has two properties, one is the number of homework and the other is the function to do homework.

The protocol properties defined and package properties defined in exactly the same way.

Unlike a package, the definition of the protocol properties do not need specific values or function content, only need to determine the type.

Next, let's have the students implement the protocol.
## Implement the protocol
Similar to the extension function, we can implement this protocol by using the `id += protocol {}` statement in the required package.

E.g:
```
student += homeWork {
    count :i32

    do ()->() {
        SpendTime(1)            # spent an hour
        ..homeWork.count -= 1   # completed one
    }
}
```
Our student homework is really hard ...

Let's explain what this section of the protocol contains:
1. We define a protocol property whose identifier is the name of the protocol `homeWork`, so we can use it like we defined a property.
1. In the protocol we include the protocol of the two properties `count, do`, according to the provisions of a nor less.
1. We have written the actual values ​​and functions for each of the two properties of the protocol, so that these two properties become one of the valid sub-properties of `student`.
1. We did something inside `do` and reduced the total number of jobs by calling the `homeWork` property.

Note that the protocol properties are properties, we can not achieve in a package of two protocols of the same name, nor can there be other properties or methods and protocols with the same name. 

However, the protocol of different names can contains the properties of same names.

## Use Protocol
With the protocol included, we can use the student bundle that owns the protocol.

E.g:
```
Peter := student{ <-count=999999 }
cmd.print( Peter.homeWork.count )
# print 999999, too much
Peter.homeWork.do()
# did a homework
cmd.print(Peter.homeWork.count)
# print 999998, or too much
```
If this is the case, there is no advantage in defining these two properties directly in the package.

Let's think back and forth about the role of an protocol that has the same set of properties and methods for each package that contains the protocol.

This makes it unnecessary for protocol makers to be concerned with how packages follow the protocol, and they can be used in the same way by knowing that they all follow.

Now we can create a wide variety of students, all of whom follow the same protocol, and we can use the protocol feature without discrimination.

E.g:
```
# create three different types of student packages
StudentA := chinesestudent{}
StudentB := americastudent{}
StudentC := japanstudent{}
# let them do homework separately
StudentA.homeWork.do()
StudentB.homeWork.do()
StudentC.homeWork.do()
```
More efficient approach is to write this function into the function, let the function to help us repeatedly call the function of the protocol.

E.g:
```
doHomeWork (student: homeWork)->() {
    student.do()
}
# Now we can make it easier for every student to do their homework
doHomeWork(StudentA.homeWork)
doHomeWork(StudentB.homeWork)
doHomeWork(StudentC.homeWork)
```
Of course, it is better to put these students in an array so that we can use loops to handle these repetitive tasks.

E.g:
```
Arr := []homeWork{}
Arr.add( StudentA.homeWork )
... # stuffed many, many students
@ [Arr] {
    doHomeWork(ea)
}
```
╮ (¯ ▽ ¯) ╭
Perfect

## Type Convert
Because packet types can be converted to protocol types, the original type of data can not be judge during use.

But sometimes we need to get the original type of data to handle, we can use type judgment to help us accomplish this.

We can use `value.is<type>()` To judge the type of data, using `value.as<type>()` To convert the data to our type.

E.g:
```
func (hw :homeWork)->() {
    # judge type
    ? hw.is<chineseStudent>() {
        # convert to chinese student data
        cs := hw.as<chineseStudent>()
    }
}
```
Note that if the type can not be converted correctly, it will return a `null` value.

### [Next Chapter](enumeration-type.md)

## Example of this chapter
```
Demo {
    System
    Library
}

Main ()->() {
    S := B{}
    B.A.do()
    C( B.A )
}

A -> {
    X : i32
    do ()->() {}
}

B {}-> {
    Y := 5
}

B += A {
    X := 0
    do ()->() {
        ..A.X += 1
    }
}

C (a:A)->() {
    a.do()
    ? a.is<B>() {
        cmd.print( a.as<B>().Y )
    }
}
```