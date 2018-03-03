# Package Type
If we only have a few basic data, in fact it is very difficult to describe more specific things.

Therefore, we need a feature that can wrap data of different attributes to better describe what we need.

Obviously, this feature for package data, called package.
## Definition
We can use the `#~()` symbol to define a package that has nothing.

E.g:

    Package => #~(){};

Of course, we hope more is to be able to pack a few data, for example, a name, student number, class, grade attributes of students.
We can define these data in the same way we define normal identifiers.

E.g:

    Student => #~()
    {
        Name => "";
        Number => "";
        Class => 0;
        Grade => 0;
    };

So we get a student bag with these data attributes. This student bag now becomes a usable type like `number, text, bool`.

Unlike our original base type can only store one data, the student package can store name, student number, class, grade data.

This is very much like the concept of assembling different parts together in our reality as a whole, so it is called a package.

## Create
So how do we create a new package? As always, all of our types can be created using the type-creation syntax.

E.g:

    Peter => Student~();

This create a `Peter` identifier. All the properties of this student are initialized to `"", "", 0,0` as set in the definition.

Let us recall that our base type, collection types can be created using the type-creation syntax, in fact they are all packages.

As long as it is a type that is extended by a package, it can be created in the same way as the create syntax, which is a rule in this language.

## Using Property
Now that we have a `Peter`, how do we use the attributes inside?

Very simple, we only need to use `.` syntax, we can summon the attributes we need.

E.g:

    Console.WriteLine(value: Peter.Name); 
    // print the name of a student

To change the value of the property is the same, it is equivalent to a nested identifier. We can directly use the assignment statement to change the value.

E.g:

    Peter.Name = "Peter"; Peter.Number = "060233";
    Peter.Class = 2; Peter.Grade = 6;

## Private Property
Anyone has some little secret, Peter is the same, maybe he hid a secret little girl's name and did not want others to know.

We can define private properties to store properties that we do not want to be accessed by the outside world.

E.g:

    Student => #~()
    {
        ...
        _GirlFirend => "";
    };

That's right, if you remember the definition of identifiers, this is how private identifiers are defined, and private identifiers can not be accessed by outsiders.

Therefore, we can define a `Peter`, nor can we get or modify the value via `Peter._GirlFirend`.

Then the private properties of this package can not be accessed, and can not be modified, what is the use? Do not worry, there is another attribute package.

## Function Property
We can use the definition method learned in the function section directly defined in the package.

E.g:

    Student => #~()
    {
        ...
        GetGirlFirend => $()~(name: text)
        {
            -> (^._GirlFirend);
        };
    };

Because the function is part of the package, and the function can call data or functionality, we can define a method for getting the private property.

The `^` used here to declare the package itself, so you can easily access their own properties. This can be thought of as `this | self` in other languages.

Through the function properties, we can get to the private property, you can also easily according to business needs to deal with other data in the package.

With this function, we can get the private property by calling the function.

E.g:

    Console.WriteLine(value: Peter.GetGirlFirend());
    // printed the name of a girlfriend of a puppy love student

As with data attributes, functions can also be private identifiers, and functions that use private identifiers also mean that only the packet can access itself.

## Construct
Sometimes, we do not want to always create a blank students, in fact, the student number often contains the grade and class information,

We hope that given a name and student number, class and grade information will be automatically created exactly.

This can be achieved using regular functions, but why not use the built-in constructor?

Add parameters in the definition, and write the definition of the constructor, which only needs the auxiliary symbol `~#` can do it.

E.g:

    Student => #~(name: text, number: text)
    {
        ...
        ~#
        {
            ^.Name = name; ^.Number = number;
            // calculate the class
            ^.Class = GetSubText(data: number, from: 2, to: 3);
            // calculate the grade
            ^.Grade = GetSubText(data: number, from: 0, to: 1);
        };
    };

This gives us a package with constructors, and when we create a new student, class and grade data are automatically generated.

E.g:

    Peter => Student~(name: "Peter", number: "060233");
    Console.WriteLine(value: Peter.Class); // Print out 2

It should be noted that a package can only support one constructor, we recommend to maintain the simplicity of the structure, a stable package easier to be used by the caller,

If you really have more construction requirements, you can use regular functions to accomplish this requirement.
## Combination
Now let us play our imagination, we want a customized package for Chinese students how to define it?

E.g:

    ChinaStudent => #~()
    {
        Name => "";
        Number => "";
        Class => 0;
        Grade => 0;
        KungFu => false; // kung fu students
    };

No, no repeatable definition of data so elegant, we can reuse student attributes, with an additional kung fu attributes on it.

We need to use a combination of this feature, but not so complicated, just created a student attribute only.

E.g:

    ChinaStudent => #~()
    {
        Student => Student~(); // include student attributes in it
        KungFu => false; // kung fu students
    };

This way you can use generic attributes via student attributes in Chinese students.

E.g:

    Chen => ChinaStudent~();
    Console.WriteLine(value: Chen.Student.Name);
    // of course, since there is no assignment, nothing is output

By combining layers after layer, you are free to assemble whatever you want to describe.

### [Next Chapter](protocol-type.md)