# LINQ language integration query
In a relational database system, data is organized into well-formulated tables and accessed through a simple and powerful SQL language. Because data follows some strict rules in the table, SQL can work well with them.

However, contrary to the database in the program, the data stored in the class object or structure is very different. Therefore, there is no general query language to get data from the data structure. The method of getting data from an object is always designed as part of the program, but using LINQ makes it easy to query the collection of objects.

The following are the important features of LINQ.

- LINQ is an extension of the .NET Framework that allows us to query data collection like query database by using SQL
- With LINQ, you can query data from databases, program object collections, and XML documents

More details on LINQ can be read at the following URL.

[Microsoft Documentation](https:#docs.microsoft.com/en-us/dotnet/csharp/programming-guide/concepts/linq/getting-started-with-linq)

## Statement
We can use Linq to query like C#, just use `=>` to declare the LINQ statement.

E.g:
```
Linq() -> () {
    Numbers := { 0, 1, 2, 3, 4, 5, 6 }
    Arr := from num => in Numbers =>
            where (num % 2) == 0 =>
            orderby num => descending =>
            select num
}
```

### [Next Chapter](optional-type.md)