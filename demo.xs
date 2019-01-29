\demo {
    System
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

        prt("Pre Order Traverse")
        preOrderTraverse(n0)
        prt("Middle Order Traverse")
        middleOrderTraverse(n0)
        prt("Post Order Traverse")
        postOrderTraverse(n0)

        n7 := inverseNode(n0)
        prt("Inverse node")
        preOrderTraverse(n7)

        Arr := {9,1,5,8,3,7,4,6,2}
        simpleSort(Arr)
        Arr = {9,1,5,8,3,7,4,6,2}
        bubbleSort(Arr)
        Arr = {9,1,5,8,3,7,4,6,2}
        quickSort(Arr)

        prt("Filter Array")
        Arr = filterList(Arr, {it->it > 4})
        @ ea <- Arr {
            prt(ea) 
        }

        prt("oop")
        app := app{"test", "Windows"}
        app.start()
        app.stop()
        shutdown(app)
        rd()
    }

    preOrderTraverse(node: node?) -> () {
        ? node -> nil { 
            <- () 
        }
        prt(node.value)
        preOrderTraverse(node.Left)
        preOrderTraverse(node.Right)
    }

    postOrderTraverse(node: node?) -> () {
        ? node -> nil { 
            <- () 
        }
        postOrderTraverse(node.Left)
        postOrderTraverse(node.Right)
        prt(node.value)
    }

    middleOrderTraverse(node: node?) -> () {
        ? node -> nil { 
            <- () 
        }
        middleOrderTraverse(node.Left)
        prt(node.value)
        middleOrderTraverse(node.Right)
    }

    inverseNode(node: node?) -> (node: node?) {
        ? node -> nil { 
            <- (nil) 
        }
        node.Left = inverseNode(node.Left)
        node.Right = inverseNode(node.Right)

        temp := node{node.value <- Left = node.Right, Right = node.Left}
        <- (temp)
    }

    swap(list: [i32], i: i32, j: i32) -> () {
        (list[i], list[j]) = (list[j], list[i])
    }

    simpleSort(list: [i32]) -> () {
        prt("Simple Sort")
        @ i <- [0 < list.count] {
            @ j <- [i+1 < list.count] {
                ? list[i] > list[j] {
                    swap(list, i , j)
                }
            }
        }
        @ ea <- list { 
            prt(ea) 
        }
    }

    bubbleSort(list: [i32]) -> () {
        prt("Bubble Sort")
        @ i <- [0 < list.count] {
            @ j <- [list.count-2 >= i] {
                ? list[j] > list[j+1] {
                    swap(list, j , j+1)
                }
            }
        }
        @ ea <- list { 
            prt(ea) 
        }
    }

    quickSort(list: [i32]) -> () {
        prt("Quick Sort")
        qSort(list,0,list.count-1)
        @ ea <- list { 
            prt(ea) 
        }
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

    filterList(list: [i32], fn: (i32) -> (bl)) -> (l: [i32]) {
        Filter := [i32]{}

        @ ea <- list {
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

node{value: i32} {
    ..value = value
} -> {
    value: i32
    Left: node?
    Right: node?
}

control -> {
    shutdown() -> ()
}

program{name: str} {
    ..name = name
} -> {
    name: str
    _Running := false

    start() -> () {
        prt("Start")
        .._Running = true
    }

    stop() -> () {
        prt("Stop")
        .._Running = false
    }
} :control {
    shutdown() -> () {
        prt("Shutdown")
        .._Running = false
    }
}

app{name: str, platform: str}  {
    Platform = platform
} -> {
    Platform: str
} ::program{name} {
    
}