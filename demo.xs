demo {
    System
    Library
}

Main ()->() {
    n0 := node{0}
    n1 := node{1}
    n2 := node{2}
    n3 := node{3}
    n4 := node{4}
    n5 := node{5}
    n6 := node{6}

    n0.Left = n1
    n0.Right = n2

    n1.Left = n3
    n1.Right = n4

    n2.Left = n5
    n2.Right = n6

    cmd.prt("Pre Order Traverse")
    PreorderTraverse(n0)
    cmd.prt("Middle Order Traverse")
    MiddleorderTraverse(n0)
    cmd.prt("Post Order Traverse")
    PostorderTraverse(n0)

    n7 := InverseNode(n0)
    cmd.prt("Inverse node")
    PreorderTraverse(n7)

    Arr := _{9,1,5,8,3,7,4,6,2}
    SimpleSort(Arr)
    Arr = _{9,1,5,8,3,7,4,6,2}
    BubbleSort(Arr)
    Arr = _{9,1,5,8,3,7,4,6,2}
    QuickSort(Arr)

    cmd.prt("Filter Array")
    Arr = FilterList(Arr, $it > 4)
    @ Arr { cmd.prt(ea) }

    cmd.prt("oop")
    app := App{"test", "Windows"}
    app.Start()
    app.Stop()
    Shutdown(app)
    cmd.rd()
}

node {value :i32}-> {
    value :i32
    Left :node?
    Right :node?

    ..{
        ..value = value
    }
}

PreorderTraverse (node:node?)->() {
    ? node -> nil { <- () }
    cmd.prt(node.value)
    PreorderTraverse(node.Left)
    PreorderTraverse(node.Right)
}

PostorderTraverse (node:node?)->() {
    ? node -> nil { <- () }
    PreorderTraverse(node.Left)
    PreorderTraverse(node.Right)
    cmd.prt(node.value)
}

MiddleorderTraverse (node:node?)->() {
    ? node -> nil { <- () }
    PreorderTraverse(node.Left)
    cmd.prt(node.value)
    PreorderTraverse(node.Right)
}

InverseNode (node:node?)->(node:node?) {
    ? node -> nil { <- (nil) }
    node.Left = InverseNode(node.Left)
    node.Right = InverseNode(node.Right)

    temp := node{node.value <- Left = node.Right, Right = node.Left}
    <- (temp)
}

Swap (list:[i32], i, j:i32)->() {
    _(list[i], list[j]) = _(list[j], list[i])
}

SimpleSort (list:[i32])->() {
    cmd.prt("Simple Sort")
    @ i <- [0 < list.count] {
        @ j <- [i+1 < list.count] {
            ? list[i] > list[j] {
                Swap(list, i , j)
            }
        }
    }
    @ list { cmd.prt(ea) }
}

BubbleSort (list:[i32])->() {
    cmd.prt("Bubble Sort")
    @ i <- [0 < list.count] {
        @ j <- [list.count-2 >= i] {
            ? list[j] > list[j+1] {
                Swap(list, j , j+1)
            }
        }
    }
    @ list { cmd.prt(ea) }
}

QuickSort (list:[i32])->() {
    cmd.prt("Quick Sort")
    QSort(list,0,list.count-1)
    @ list { cmd.prt(ea) }
}

QSort (list:[i32], low, high:i32)->() {
    Pivot := 0
    ? low < high {
        Pivot = Partition(list,low,high)

        QSort(list, low, Pivot-1)
        QSort(list, Pivot+1, high)
    }
}

Partition (list:[i32], low, high:i32)->(position:i32) {
    pivotkey := list[low]
    
    @ ? low < high {
        @ ? low<high & list[high] >= pivotkey {
            high -= 1
        }
        Swap(list, low , high)
        @ ? low<high & list[low] <= pivotkey {
            low += 1
        }
        Swap(list, low , high)
    }

    <- (low)
}

FilterList (list:[i32], fn:(take:i32)->(act:bl))->(l:[i32]) {
    Filter := [i32]{}

    @ list {
        ? fn(ea) {
            Filter += ea
        }
    }
    <- (Filter)
}

Shutdown (ctrl:Control)->() {
    ctrl.Shutdown()
}

Program {name:str}-> {
    name:str
    _Running := false
    ..{
        ..name = name
    }
}

Program += {
    Start ()->() {
        cmd.prt("Start")
        .._Running = true
    }

    Stop ()->() {
        cmd.prt("Stop")
        .._Running = false
    }
}

Control -> {
    Shutdown ()->(){}
}

Program += Control {
    Shutdown ()->() {
        cmd.prt("Shutdown")
        .._Running = false
    }
}

App {name, platform:str}-> Program{name}{
    Platform:str

    .. {
        Platform = platform
    }
}