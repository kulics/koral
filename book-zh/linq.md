# LINQ 语言集成查询
在关系型数据库系统中，数据被组织放入规范化很好的表中，并且通过简单且强大的 SQL 语言来进行访问。因为数据在表中遵从某些严格的规则，所以 SQL 可以和它们很好的配合使用。

然而，在程序中却与数据库相反，保存在类对象或结构中的数据差异很大。因此，没有通用的查询语言来从数据结构中获取数据。从对象获取数据的方法一直都是作为程序的一部分而设计的，然而使用 LINQ 可以很轻松地查询对象集合。

以下是 LINQ 的重要特性。

- LINQ 是 .NET 框架的扩展，它允许我们以使用 SQL 查询数据库的方式来查询数据集合
- 使用 LINQ，你可以从数据库、程序对象集合以及 XML 文档中查询数据

关于更多 LINQ 的细节说明可以到以下网址阅读。

[微软文档](https://docs.microsoft.com/zh-cn/dotnet/csharp/programming-guide/concepts/linq/getting-started-with-linq)

## 声明
在这门语言里，因为没有关键字的设计，所以我们需要使用特殊方法来标记 LINQ 语句。

我们可以使用 **\`** **\`** 来包裹一段语句，这样就可以在里面使用查询关键字了。

例如：
```
Linq => $()~()
{
    numbers =>  [ 0, 1, 2, 3, 4, 5, 6 ];
    arr => `from num in numbers
            where (num % 2) = 0
            orderby num descending
            select num`;
};
```

### [下一章](命名空间.md)

