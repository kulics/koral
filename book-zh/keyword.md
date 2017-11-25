# 关键字
## 命令
lp = loop 循环  
brk = break 跳出  
fl = fall 继续向下执行  

slf = self 自身  

chk = check 检查异常  

## 原始类型
nil 空  
number 数字  
string 字符串  
bool 布尔  
true 真  
false 假  
any 任意类型

## 隐藏类型
    [T] = XyArray<T>
    [T:T] = XyDictionary<T,T>
    (T...) = XyTuple{T...}
    (T...) -> (T...) = XyFunction<T...><T...>
    #{T...} = XyPackage{T...}
    <->{T...} = XyProtocol{T...}