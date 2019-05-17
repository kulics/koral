\Xs <- {
    System
}

Main() -> () {
    N0 := <Node>(0)
    N1 := <Node>(1)
    N2 := <Node>(2)
    N3 := <Node>(3)
    N4 := <Node>(4)
    N5 := <Node>(5)
    N6 := <Node>(6)

    N0.left = N1
    N0.right = N2

    N1.left = N3
    N1.right = N4

    N2.left = N5
    N2.right = N6

    Prt("Pre Order Traverse")
    Pre order traverse(N0)
    Prt("Middle Order Traverse")
    Middle order traverse(N0)
    Prt("Post Order Traverse")
    Post order traverse(N0)

    N7 := Inverse node(N0)
    Prt("Inverse Node")
    Pre order traverse(N7)

    Arr := {9,1,5,8,3,7,4,6,2}
    Simple sort(Arr)
    Arr = {9,1,5,8,3,7,4,6,2}
    Bubble sort(Arr)
    Arr = {9,1,5,8,3,7,4,6,2}
    Quick sort(Arr)

    Prt("Filter Array")
    Arr = Filter list(Arr, {it->it > 4})
    Arr @ ea {
        Prt(ea) 
    }

    Prt("oop")
    App := <App>("test", "Windows")
    App.start()
    App.stop()
    Shutdown(App)
    Rd()
}

Pre order traverse(node: ^Node) -> () {
    node ? () { 
        <- () 
    }
    Prt(node.value)
    Pre order traverse(node.left)
    Pre order traverse(node.right)
}

Post order traverse(node: ^Node) -> () {
    node ? () { 
        <- () 
    }
    Post order traverse(node.left)
    Post order traverse(node.right)
    Prt(node.value)
}

Middle order traverse(node: ^Node) -> () {
    node ? () { 
        <- () 
    }
    Middle order traverse(node.left)
    Prt(node.value)
    Middle order traverse(node.right)
}

Inverse node(node: ^Node) -> (node: ^Node) {
    node ? () { 
        <- (()) 
    }
    node.left = Inverse node(node.left)
    node.right = Inverse node(node.right)

    temp := <Node>(node.value)
    temp.left = node.right
    temp.right = node.left
    <- (temp)
}

Swap(list: []Int, i: Int, j: Int) -> () {
    (list[i], list[j]) = (list[j], list[i])
}

Simple sort(list: []Int) -> () {
    Prt("Simple Sort")
    [0 < list.len] @ i {
        [i+1 < list.len] @ j {
            ? list[i] > list[j] {
                Swap(list, i , j)
            }
        }
    }
    list @ ea { 
        Prt(ea) 
    }
}

Bubble sort(list: []Int) -> () {
    Prt("Bubble Sort")
    [0 < list.len] @ i {
        [list.len-2 >= i] @ j {
            ? list[j] > list[j+1] {
                Swap(list, j , j+1)
            }
        }
    }
    list @ ea { 
        Prt(ea) 
    }
}

Quick sort(list: []Int) -> () {
    Prt("Quick Sort")
    Q sort(list, 0, list.len-1)
    list @ ea { 
        Prt(ea) 
    }
}

Q sort(list: []Int, low: Int, high: Int) -> () {
    Pivot := 0
    ? low < high {
        Pivot = Partition(list, low, high)

        Q sort(list, low, Pivot-1)
        Q sort(list, Pivot+1, high)
    }
}

Partition(list: []Int, low: Int, high: Int) -> (position: Int) {
    Pivot key := list[low]
    
    @ low < high {
        @ low < high & list[high] >= Pivot key {
            high -= 1
        }
        Swap(list, low , high)
        @ low < high & list[low] <= Pivot key {
            low += 1
        }
        Swap(list, low , high)
    }

    <- (low)
}

Filter list(list: []Int, fn: (Int) -> (Bool)) -> (l: []Int) {
    Filter := []Int{}

    list @ ea {
        ? fn(ea) {
            Filter += ea
        }
    }
    <- (Filter)
}

Shutdown(ctrl: Control) -> () {
    ctrl.shutdown()
}

Node -> {
    value: Int
    left: ^Node
    right: ^Node
} (value: Int) {
    ..value = value
}

Control <- {
    shutdown() -> ()
}

Program -> {
    name: Str
    _running := False

    start() -> () {
        Prt("Start")
        _running = True
    }

    stop() -> () {
        Prt("Stop")
        _running = False
    }
} (name: Str) {
    ..name = name
} Control {
    shutdown() -> () {
        Prt("shutdown")
        _running = False
    }
}

App -> {
    platform: Str
} (name: Str, platform: Str)...(name) {
    ..platform = platform
} ...Program {
}
