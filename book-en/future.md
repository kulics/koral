# Future
## Static Duck Type
When a package has all the attributes of another package, then the two packages are fully inclusive and can be used as an inheritance type of the included package.

E.g:
```
A -> {
    Number: I32
    Function() -> (){}
}

B -> {
    Number: I32
    Text: Str
    Function() -> (){}
}

main() -> () {
    use(a: A) -> () {
        a.Function()
    }

    use( B{} )
}
```