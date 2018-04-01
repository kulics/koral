# Protocol Type
In reality, we often use the protocol to specify some specific rules, so that people or things can do things according to the expected rules.
We often need to do this in programming languages as well. This feature is the protocol.

The protocol specifies the methods and properties necessary to implement a particular feature, allowing the package to comply.

Our package can introduce the protocol we need, just like signing an protocol, and then declare all the properties required by the protocol, so that we think the package signed the protocol.
## Definition
We only need to use the symbol `&` to define a protocol.

E.g:
```
Protocol => &{};
```
This is an empty protocol.

Next, let's design a difficult task that students need to accomplish ... homework.

E.g:
```
HomeWork => &
{
    Count => 0;
    Do => $()~(){};
};
```
The protocol for this job has two properties, one is the number of homework and the other is the function to do homework.

The protocol properties defined and package properties defined in exactly the same way.

Unlike a package, the definition of the protocol properties do not need specific values or function content, only need to determine the type.

Next, let's have the students implement the protocol.
## Contains the protocol
We can include this protocol in the package we need, using the auxiliary symbols `~&` and the protocol name.

E.g:
```
Student => #~()
{
    ...
    ~& HomeWork
    {
        Count => 999999; // many, many homeworks

        Do => $()~()
        {
            SpendTime(1); // spent an hour
            ..HomeWork.Count -= 1; // completed one
        };
    };
};
```
Our student homework is really hard ...

Let's explain what this section of the protocol contains:
1. We define a protocol property whose identifier is the name of the protocol `HomeWork`, so we can use it like we defined a property.
1. In the protocol we include the protocol of the two properties `Count, Do`, according to the provisions of a nor less.
1. We have written the actual values ​​and functions for each of the two properties of the protocol, so that these two properties become one of the valid sub-properties of `Student`.
1. We did something inside `Do` and reduced the total number of jobs by calling the `HomeWork` property.

Note that the protocol properties are properties, we can not achieve in a package of two protocols of the same name, nor can there be other properties or methods and protocols with the same name. 

However, the protocol of different names can contains the properties of same names.

## Use Protocol
With the protocol included, we can use the student bundle that owns the protocol.

E.g:
```
Peter => Student~();
Console.WriteLine(Peter.HomeWork.Count);
// print 999999, too much
Peter.HomeWork.Do();
// did a homework
Console.WriteLine(Peter.HomeWork.Count);
// print 999998, or too much
```
If this is the case, there is no advantage in defining these two properties directly in the package.

Let's think back and forth about the role of an protocol that has the same set of properties and methods for each package that contains the protocol.

This makes it unnecessary for protocol makers to be concerned with how packages follow the protocol, and they can be used in the same way by knowing that they all follow.

Now we can create a wide variety of students, all of whom follow the same protocol, and we can use the protocol feature without discrimination.

E.g:
```
// create three different types of student packages
StudentA => ChineseStudent~();
StudentB => AmericaStudent~();
StudentC => JapanStudent~();
// let them do homework separately
StudentA.HomeWork.Do();
StudentB.HomeWork.Do();
StudentC.HomeWork.Do();
```
More efficient approach is to write this function into the function, let the function to help us repeatedly call the function of the protocol.

We can use the auxiliary notation `&` in the parameter type of a function to mark a parameter as a package that owns the protocol, so that the package's protocol can be passed in.

E.g:
```
DoHomeWork => $(student: &HomeWork)~()
{
    student.Do(); // because the protocol has been marked, we can use the protocol method
};
// Now we can make it easier for every student to do their homework
DoHomeWork(StudentA.HomeWork);
DoHomeWork(StudentB.HomeWork);
DoHomeWork(StudentC.HomeWork);
```
Of course, it is better to put these students in an array so that we can use loops to handle these repetitive tasks.

E.g:
```
Arr => []&HomeWork~();
Arr.Add(StudentA.HomeWork);
... // stuffed many, many students
@ Arr ~ Student
{
    DoHomeWork(Student);
};
```
╮ (¯ ▽ ¯) ╭
Perfect
## Private Property
Similar to the actual protocol, the protocol can also have some public resources for everyone to use.

In our language, this can be some public data or public method, just because these properties are already constrained when the protocol is written, so they are immutable.

We only need to define the private property can provide these public resources.

E.g:
```
HomeWork => &
{
    ...
    _NeedHours => 1; // can not be modified
    _DoHomeWork => $(student: &HomeWork)~()
    {
        Student.Do();
    };
};
```
So that we have two public properties, we can now call these properties directly using the protocol name, just like identifiers, and let's transform some of the previous code.

E.g:
```
...
~& HomeWork
{
    ...
    Do => $()~()
    {
        SpendTime(HomeWork._NeedHours); // spent the value provided by the protocol
        ...
    };
};
...
@ Arr ~ Student
{
    HomeWork._DoHomeWork(Student);
};
```
╮ (¯ ▽ ¯) ╭
Perfect again

## Type Convert
Because packet types can be converted to protocol types, the original type of data can not be judge during use.

But sometimes we need to get the original type of data to handle, we can use type judgment to help us accomplish this.

We can use `type?()` To judge the type of data, using `type!()` To convert the data to our type.

E.g:
```
func => $(hw :&HomeWork)~()
{
    // judge type
    ? ChineseStudent?(hw) 
    {
        // convert to chinese student data
        cs => ChineseStudent!(hw);
    };
};
```
Note that if the type can not be converted correctly, it will cause a program exception.

### [Next Chapter](check.md)