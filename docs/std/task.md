# std.task API

## 概述
本页摘录模块 `std.task` 的公开 API（仅保留声明语法），按自由函数 / trait / 类型 / given 组织。

## 自由函数
```koral
public let [T Any]run_task(f [T]Func) [T]Thread

public let current_thread_id() UInt64

public let yield_thread_now() Void

public let available_parallelism() UInt
```

## trait
（无）

## 类型
```koral
public type [T Any]Task

public type [T Any]Thread

public type Timer
```

## given
```koral
given[T Any] [T]Task {
    public new(f [T]Func) [T]Task
    public set_name(self, name String) [T]Task
    public set_stack_size(self, size UInt) [T]Task
    public spawn(self) [T]Thread
}

given[T Any] [T]Thread {
    public wait(self) [T]Result
    public detach(self) Void
    public id(self) UInt64
    public name(self) [String]Option
}

given Timer {
    public once(delay Duration, f [Void]Func) Timer
    public repeating(delay Duration, interval Duration, f [Void]Func) Timer
    public repeating_n(n UInt, delay Duration, interval Duration, f [Void]Func) Timer
    public repeating_next(delay Duration, f [[Duration]Option]Func) Timer
    public cancel(self) Void
    public wait(self) Void
}
```
