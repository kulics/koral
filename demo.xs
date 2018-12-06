\demo {
    System
    Library
}

program. -> {
    Main() -> () {
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
        preOrderTraverse(n0)
        cmd.prt("Middle Order Traverse")
        middleOrderTraverse(n0)
        cmd.prt("Post Order Traverse")
        postOrderTraverse(n0)

        n7 := inverseNode(n0)
        cmd.prt("Inverse node")
        preOrderTraverse(n7)

        Arr := _{9,1,5,8,3,7,4,6,2}
        simpleSort(Arr)
        Arr = _{9,1,5,8,3,7,4,6,2}
        bubbleSort(Arr)
        Arr = _{9,1,5,8,3,7,4,6,2}
        quickSort(Arr)

        cmd.prt("Filter Array")
        Arr = filterList(Arr, $it > 4)
        @ Arr { cmd.prt(ea) }

        cmd.prt("oop")
        app := app{"test", "Windows"}
        app.start()
        app.stop()
        shutdown(app)
        cmd.rd()
    }

    preOrderTraverse(node: node?) -> () {
        ? node -> nil { <- () }
        cmd.prt(node.value)
        preOrderTraverse(node.Left)
        preOrderTraverse(node.Right)
    }

    postOrderTraverse(node: node?) -> () {
        ? node -> nil { <- () }
        postOrderTraverse(node.Left)
        postOrderTraverse(node.Right)
        cmd.prt(node.value)
    }

    middleOrderTraverse(node: node?) -> () {
        ? node -> nil { <- () }
        middleOrderTraverse(node.Left)
        cmd.prt(node.value)
        middleOrderTraverse(node.Right)
    }

    inverseNode(node: node?) -> (node: node?) {
        ? node -> nil { <- (nil) }
        node.Left = inverseNode(node.Left)
        node.Right = inverseNode(node.Right)

        temp := node{node.value <- Left = node.Right, Right = node.Left}
        <- (temp)
    }

    swap(list: [i32], i: i32, j: i32) -> () {
        _(list[i], list[j]) = _(list[j], list[i])
    }

    simpleSort(list: [i32]) -> () {
        cmd.prt("Simple Sort")
        @ i <- [0 < list.count] {
            @ j <- [i+1 < list.count] {
                ? list[i] > list[j] {
                    swap(list, i , j)
                }
            }
        }
        @ list { cmd.prt(ea) }
    }

    bubbleSort(list: [i32]) -> () {
        cmd.prt("Bubble Sort")
        @ i <- [0 < list.count] {
            @ j <- [list.count-2 >= i] {
                ? list[j] > list[j+1] {
                    swap(list, j , j+1)
                }
            }
        }
        @ list { cmd.prt(ea) }
    }

    quickSort(list: [i32]) -> () {
        cmd.prt("Quick Sort")
        qSort(list,0,list.count-1)
        @ list { cmd.prt(ea) }
    }

    qSort(list: [i32], low: i32, high: i32) -> () {
        Pivot := 0
        ? low < high {
            Pivot = partition(list,low,high)

            qSort(list, low, Pivot-1)
            qSort(list, Pivot+1, high)
        }
    }

    partition(list: [i32], low: i32, high: i32) -> (position: i32) {
        pivotkey := list[low]
        
        @ ? low < high {
            @ ? low<high & list[high] >= pivotkey {
                high -= 1
            }
            swap(list, low , high)
            @ ? low<high & list[low] <= pivotkey {
                low += 1
            }
            swap(list, low , high)
        }

        <- (low)
    }

    filterList(list: [i32], fn: (take: i32) -> (act: bl)) -> (l: [i32]) {
        Filter := [i32]{}

        @ list {
            ? fn(ea) {
                Filter += ea
            }
        }
        <- (Filter)
    }

    shutdown(ctrl: control) -> () {
        ctrl.shutdown()
    }
}

node{value: i32} -> {
    value: i32
    Left: node?
    Right: node?

    ..{
        ..value = value
    }
}

control -> {
    shutdown() -> () {}
}

program{name: str} -> {
    name: str
    _Running := false
    ..{
        ..name = name
    }

    start() -> () {
        cmd.prt("Start")
        .._Running = true
    }

    stop() -> () {
        cmd.prt("Stop")
        .._Running = false
    }
} :control {
    shutdown() -> () {
        cmd.prt("Shutdown")
        .._Running = false
    }
}

app{name: str, platform: str} -> program{name} {
    Platform: str

    .. {
        Platform = platform
    }
}