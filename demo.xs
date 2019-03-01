\demo <- {
    System
}

program -> {
    Main() -> () {
        n0 := node(0){}
        n1 := node(1){}
        n2 := node(2){}
        n3 := node(3){}
        n4 := node(4){}
        n5 := node(5){}
        n6 := node(6){}

        n0.left = n1
        n0.right = n2

        n1.left = n3
        n1.right = n4

        n2.left = n5
        n2.right = n6

        prt("Pre Order Traverse")
        preOrderTraverse(n0)
        prt("Middle Order Traverse")
        middleOrderTraverse(n0)
        prt("Post Order Traverse")
        postOrderTraverse(n0)

        n7 := inverseNode(n0)
        prt("Inverse node")
        preOrderTraverse(n7)

        $arr := {9,1,5,8,3,7,4,6,2}
        simpleSort(arr)
        arr = {9,1,5,8,3,7,4,6,2}
        bubbleSort(arr)
        arr = {9,1,5,8,3,7,4,6,2}
        quickSort(arr)

        prt("Filter Array")
        arr = filterList(arr, {it->it > 4})
        @ ea <- arr {
            prt(ea) 
        }

        prt("oop")
        app := app("test", "Windows"){}
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
        preOrderTraverse(node.left)
        preOrderTraverse(node.right)
    }

    postOrderTraverse(node: node?) -> () {
        ? node -> nil { 
            <- () 
        }
        postOrderTraverse(node.left)
        postOrderTraverse(node.right)
        prt(node.value)
    }

    middleOrderTraverse(node: node?) -> () {
        ? node -> nil { 
            <- () 
        }
        middleOrderTraverse(node.left)
        prt(node.value)
        middleOrderTraverse(node.right)
    }

    inverseNode(node: node?) -> (node: node?) {
        ? node -> nil { 
            <- (nil) 
        }
        node.left = inverseNode(node.left)
        node.right = inverseNode(node.right)

        temp := node(node.value){left = node.right, right = node.left}
        <- (temp)
    }

    swap(list: [i32], i: i32, j: i32) -> () {
        (list[i], list[j]) = (list[j], list[i])
    }

    simpleSort(list: [i32]) -> () {
        prt("Simple Sort")
        @ i <- [0 < list.len] {
            @ j <- [i+1 < list.len] {
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
        @ i <- [0 < list.len] {
            @ j <- [list.len-2 >= i] {
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
        qSort(list,0,list.len-1)
        @ ea <- list { 
            prt(ea) 
        }
    }

    qSort(list: [i32], low: i32, high: i32) -> () {
        $pivot := 0
        ? low < high {
            pivot = partition(list,low,high)

            qSort(list, low, pivot-1)
            qSort(list, pivot+1, high)
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
        $filter := [i32]{}

        @ ea <- list {
            ? fn(ea) {
                filter += ea
            }
        }
        <- (filter)
    }

    shutdown(ctrl: control) -> () {
        ctrl.shutdown()
    }
}

node(value: i32) {
    ..value = value
} -> {
    value: i32
    $left: node?
    $right: node?
}

control <- {
    shutdown() -> ()
}

program(name: str) {
    ..name = name
} -> {
    name: str
    $_running := false

    start() -> () {
        prt("Start")
        .._running = true
    }

    stop() -> () {
        prt("Stop")
        .._running = false
    }
} control {
    shutdown() -> () {
        prt("Shutdown")
        .._running = false
    }
}

app(name: str, platform: str) {
    platform = platform
} -> {
    $platform: str
} program(name) {
}
