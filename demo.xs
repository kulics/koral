\Xs <- {
    System
}

Main() -> () {
    n0 := <Node>(0)
    n1 := <Node>(1)
    n2 := <Node>(2)
    n3 := <Node>(3)
    n4 := <Node>(4)
    n5 := <Node>(5)
    n6 := <Node>(6)

    n0.Left = n1
    n0.Right = n2

    n1.Left = n3
    n1.Right = n4

    n2.Left = n5
    n2.Right = n6

    Prt("Pre Order Traverse")
    pre order traverse(n0)
    Prt("Middle Order Traverse")
    middle order traverse(n0)
    Prt("Post Order Traverse")
    post order traverse(n0)

    n7 := inverse node(n0)
    Prt("Inverse Node")
    pre order traverse(n7)

    arr := {9,1,5,8,3,7,4,6,2}
    simple sort(arr)
    arr = {9,1,5,8,3,7,4,6,2}
    bubble sort(arr)
    arr = {9,1,5,8,3,7,4,6,2}
    quick sort(arr)

    Prt("Filter Array")
    arr = filter list(arr, {it->it > 4})
    arr @ ea {
        Prt(ea) 
    }

    Prt("oop")
    app := <App>("test", "Windows")
    app.Start()
    app.Stop()
    shutdown(app)
    Rd()
}

pre order traverse(node: ^Node) -> () {
    node ? () { 
        <- () 
    }
    Prt(node.Value)
    pre order traverse(node.Left)
    pre order traverse(node.Right)
}

post order traverse(node: ^Node) -> () {
    node ? () { 
        <- () 
    }
    post order traverse(node.Left)
    post order traverse(node.Right)
    Prt(node.Value)
}

middle order traverse(node: ^Node) -> () {
    node ? () { 
        <- () 
    }
    middle order traverse(node.Left)
    Prt(node.Value)
    middle order traverse(node.Right)
}

inverse node(node: ^Node) -> (node: ^Node) {
    node ? () { 
        <- (()) 
    }
    node.Left = inverse node(node.Left)
    node.Right = inverse node(node.Right)

    temp := <Node>(node.Value)
    temp.Left = node.Right
    temp.Right = node.Left
    <- (temp)
}

swap(list: []I32, i: I32, j: I32) -> () {
    (list[i], list[j]) = (list[j], list[i])
}

simple sort(list: []I32) -> () {
    Prt("Simple Sort")
    [0 < list.Len] @ i {
        [i+1 < list.Len] @ j {
            ? list[i] > list[j] {
                swap(list, i , j)
            }
        }
    }
    list @ ea { 
        Prt(ea) 
    }
}

bubble sort(list: []I32) -> () {
    Prt("Bubble Sort")
    [0 < list.Len] @ i {
        [list.Len-2 >= i] @ j {
            ? list[j] > list[j+1] {
                swap(list, j , j+1)
            }
        }
    }
    list @ ea { 
        Prt(ea) 
    }
}

quick sort(list: []I32) -> () {
    Prt("Quick Sort")
    q sort(list, 0, list.Len-1)
    list @ ea { 
        Prt(ea) 
    }
}

q sort(list: []I32, low: I32, high: I32) -> () {
    pivot := 0
    ? low < high {
        pivot = partition(list,low,high)

        q sort(list, low, pivot-1)
        q sort(list, pivot+1, high)
    }
}

partition(list: []I32, low: I32, high: I32) -> (position: I32) {
    pivot key := list[low]
    
    @ low < high {
        @ low < high & list[high] >= pivot key {
            high -= 1
        }
        swap(list, low , high)
        @ low < high & list[low] <= pivot key {
            low += 1
        }
        swap(list, low , high)
    }

    <- (low)
}

filter list(list: []I32, fn: (I32) -> (Bl)) -> (l: []I32) {
    filter := []I32{}

    list @ ea {
        ? fn(ea) {
            filter += ea
        }
    }
    <- (filter)
}

shutdown(ctrl: Control) -> () {
    ctrl.shutdown()
}

Node -> {
    Value: I32
    Left: ^Node
    Right: ^Node
} (value: I32) {
    Value = value
}

Control <- {
    shutdown() -> ()
}

Program -> {
    Name: Str
    _Running := False

    Start() -> () {
        Prt("Start")
        _Running = True
    }

    Stop() -> () {
        Prt("Stop")
        _Running = False
    }
} (name: Str) {
    Name = name
} Control {
    shutdown() -> () {
        Prt("shutdown")
        _Running = False
    }
}

App -> {
    Platform: Str
} (name: Str, platform: Str)...(name) {
    Platform = platform
} ...Program {
}
