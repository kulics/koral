# 未来
## 静态鸭子类型
当一个包拥有另一个包的所有属性，那么这两个包是完全包含关系，就可以将包含包作为被包含包的继承类型来使用。

例如：
```
A() -> {
    Number: i32
    Function() -> (){}
}

B() -> {
    Number: i32
    Text: str
    Function() -> (){}
}

main() -> () {
    use(a: A) -> () {
        a.Function()
    }

    use( B() )
}
```