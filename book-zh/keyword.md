# 关键字
## 命令

## 原始类型
nil 空  
number 数字  
string 字符串  
bool 布尔  
true 真  
false 假  
any 任意类型
result 结果类型，包含(code,data)

## 隐藏类型
    [T] = XyArray<T>
    [T:T] = XyDictionary<T,T>
    (T...) = XyTuple{T...}
    (T...) -> (T...) = XyFunction<T...><T...>
    #{T...} = XyPackage{T...}
    <->{T...} = XyProtocol{T...}