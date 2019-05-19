# Protocol Type
In reality, we often use the protocol to specify some specific rules, so that people or things can do things according to the expected rules.
We often need to do this in programming languages as well. This feature is the protocol.

The protocol specifies the methods and properties necessary to implement a particular feature, allowing the package to comply.

Our package can introduce the protocol we need, just like signing an protocol, and then declare all the properties required by the protocol, so that we think the package signed the protocol.
## Definition
We only need to use the symbol `id <- {}` to define a protocol.

E.g:
```
protocol <- {
}
```
This is an empty protocol.

Next, let's design a difficult task that students need to accomplish ... homework.

E.g:
```
homeWork <- {
    Count(): Int
    Do() -> ()
}
```
The protocol for this job has two properties, one is the number of homework and the other is the function to do homework.

The protocol properties defined and package properties defined in exactly the same way.

Unlike a package, the definition of the protocol properties do not need specific values or function content, only need to determine the type.

Next, let's have the students implement the protocol.
## Implement the protocol
We can implement this protocol by using the `protocol {}` statement after the package declaration.

E.g:
```
student -> {
    ......
} homeWork {
    Count(): Int

    Do() -> () {
        SpendTime(1)    # spent an hour
        Count -= 1      # completed one
    }
}
```
Our student homework is really hard ...

Let's explain what this section of the code:
1. We have implemented an protocol, and now `student` is also considered as `homework`. We can use a `student` as `homework`.
1. In the protocol we include the protocol of the two properties `Count, Do`, according to the provisions of a nor less.
1. We have written the actual values ​​and functions for each of the two properties of the protocol, so that these two properties become one of the valid sub-properties of `student`.
1. We did something in `Do`, which reduced the total count of homework.

## Use Protocol
With the protocol included, we can use the student bundle that owns the protocol.

E.g:
```
peter := student{ Count=999999 }
Prt( peter.Count )
# print 999999, too much
peter.Do()
# did a homework
Prt(peter.Count)
# print 999998, or too much
```
If this is the case, there is no advantage in defining these two properties directly in the package.

Let's think back and forth about the role of an protocol that has the same set of properties and methods for each package that contains the protocol.

This makes it unnecessary for protocol makers to be concerned with how packages follow the protocol, and they can be used in the same way by knowing that they all follow.

Now we can create a wide variety of students, all of whom follow the same protocol, and we can use the protocol feature without discrimination.

E.g:
```
# create three different types of student packages
StudentA := chineseStudent{}
StudentB := americaStudent{}
StudentC := japanStudent{}
# let them do homework separately
StudentA.Do()
StudentB.Do()
StudentC.Do()
```
More efficient approach is to write this function into the function, let the function to help us repeatedly call the function of the protocol.

E.g:
```
doHomeWork(student: homeWork) -> () {
    student.Do()
}
# Now we can make it easier for every student to do their homework
doHomeWork(StudentA)
doHomeWork(StudentB)
doHomeWork(StudentC)
```
Of course, it is better to put these students in an array so that we can use loops to handle these repetitive tasks.

E.g:
```
arr := []homeWork{}
arr.add( StudentA )
...... # stuffed many, many students
arr @ i {
    doHomeWork(i)
}
```
╮ (¯ ▽ ¯) ╭
Perfect

## Type Convert
Because packet types can be converted to protocol types, the original type of data can not be judge during use.

But sometimes we need to get the original type of data to handle, we can use type judgment to help us accomplish this.

We can use `value == :type` or `value >< :type` To judge the type of data, using `value:type:` To convert the data to our type.

E.g:
```
func(hw: homeWork) -> () {
    # judge type
    ? hw == :chineseStudent {
        # convert to chinese student data
        cs := hw:chineseStudent:
    }
}
```

### [Next Chapter](enumeration-type.md)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    S := B()
    B.Do()
    C( B )
}

A <- {
    X(): Int
    Do() -> () {}
}

B -> {
    Y := 5
} A {
    X() := 0
    Do() -> () {
        X += 1
    }
}

C(a: A) -> () {
    a.Do()
    ? a == :B {
        Prt( a:B:.Y )
    }
}
```
