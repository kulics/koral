# 命名空间
命名空间的设计目的是提供一种让一组名称与其他名称分隔开的方式。在一个命名空间中声明的名称与另一个命名空间中声明的名称不冲突。

## 导出
为了方便我们管理代码，我们必须将我们的代码写在命名空间内，我们可以通过公有属性暴露给外部使用，也可以使用私有属性只完成自己的业务。

导出的名称可以循环嵌套，这样可以像文件夹一样有效分割功能，多个命名空间需要使用`\`隔开。

例如：
```
name\space{}

getSomething ()->(content:str) {
    <- ("something")
}
```
## 导入
我们可以通过导入功能来使用其它命名空间内容，导入后可以直接调用命名空间内容。

需要注意的是，顶层函数、顶层变量、顶层常量会以当前文件名作为宿主容器，实装为一个对象。
因此默认需要使用文件名来跨命名空间访问，这里的文件名为`Demo`。

例如：
```
run { name\space }

Main ()->() {
    # 打印 something
    cmd.print( Demo.getSomething() )
}
```

如果我们需要指定宿主容器的名称，可以使用 `=name` 的方式指定。

例如：
```
name\space=helper {}

getSomething ()->(content:str) {
    <- ("something")
}

------------------------

run{ name\space }

Main ()->() {
    cmd.print( helper.getSomething() )
}
```
## 简化导入
如果我们不希望每次都使用命名空间名称来调用内容，我们可以使用简化语法，在导入时加入`.LastName`即可。

例如：
```
run{ name\space.Demo }

Main ()->() {
    # 打印 something
    cmd.print( getSomething() )
}
```
这样就不需要每次都使用`space`来调用了。
## 临时导入
我们也可以直接使用命名空间调用功能而不需要导入。

例如：
```
demo {}

Main ()->() {
    # 直接使用即可
    cmd.print( \name\space.Demo.getSomething() )    
}
```

## [完整示例](../example.xs)
