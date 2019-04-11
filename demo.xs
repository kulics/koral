\Demo <- {
    System
}

Program -> {
    Main() -> () {
        n0 := Node(0){}
        n1 := Node(1){}
        n2 := Node(2){}
        n3 := Node(3){}
        n4 := Node(4){}
        n5 := Node(5){}
        n6 := Node(6){}

        n0.Left = n1
        n0.Right = n2

        n1.Left = n3
        n1.Right = n4

        n2.Left = n5
        n2.Right = n6

        Prt("Pre Order Traverse")
        PreOrderTraverse(n0)
        Prt("Middle Order Traverse")
        MiddleOrderTraverse(n0)
        Prt("Post Order Traverse")
        PostOrderTraverse(n0)

        n7 := InverseNode(n0)
        Prt("Inverse Node")
        PreOrderTraverse(n7)

        arr := {9,1,5,8,3,7,4,6,2}
        SimpleSort(arr)
        arr = {9,1,5,8,3,7,4,6,2}
        BubbleSort(arr)
        arr = {9,1,5,8,3,7,4,6,2}
        QuickSort(arr)

        Prt("Filter Array")
        arr = FilterList(arr, {it->it > 4})
        @ ea <- arr {
            Prt(ea) 
        }

        Prt("oop")
        app := App("test", "Windows"){}
        app.Start()
        app.Stop()
        Shutdown(app)
        Rd()
    }

    PreOrderTraverse(node: Node!) -> () {
        ? node -> Nil { 
            <- () 
        }
        Prt(node.Value)
        PreOrderTraverse(node.Left)
        PreOrderTraverse(node.Right)
    }

    PostOrderTraverse(node: Node!) -> () {
        ? node -> Nil { 
            <- () 
        }
        PostOrderTraverse(node.Left)
        PostOrderTraverse(node.Right)
        Prt(node.Value)
    }

    MiddleOrderTraverse(node: Node!) -> () {
        ? node -> Nil { 
            <- () 
        }
        MiddleOrderTraverse(node.Left)
        Prt(node.Value)
        MiddleOrderTraverse(node.Right)
    }

    InverseNode(node: Node!) -> (node: Node!) {
        ? node -> Nil { 
            <- (Nil) 
        }
        node.Left = InverseNode(node.Left)
        node.Right = InverseNode(node.Right)

        temp := Node(node.Value){Left = node.Right, Right = node.Left}
        <- (temp)
    }

    Swap(list: [I32], i: I32, j: I32) -> () {
        (list[i], list[j]) = (list[j], list[i])
    }

    SimpleSort(list: [I32]) -> () {
        Prt("Simple Sort")
        @ i <- [0 < list.Len] {
            @ j <- [i+1 < list.Len] {
                ? list[i] > list[j] {
                    Swap(list, i , j)
                }
            }
        }
        @ ea <- list { 
            Prt(ea) 
        }
    }

    BubbleSort(list: [I32]) -> () {
        Prt("Bubble Sort")
        @ i <- [0 < list.Len] {
            @ j <- [list.Len-2 >= i] {
                ? list[j] > list[j+1] {
                    Swap(list, j , j+1)
                }
            }
        }
        @ ea <- list { 
            Prt(ea) 
        }
    }

    QuickSort(list: [I32]) -> () {
        Prt("Quick Sort")
        QSort(list,0,list.Len-1)
        @ ea <- list { 
            Prt(ea) 
        }
    }

    QSort(list: [I32], low: I32, high: I32) -> () {
        Pivot := 0
        ? low < high {
            Pivot = Partition(list,low,high)

            QSort(list, low, Pivot-1)
            QSort(list, Pivot+1, high)
        }
    }

    Partition(list: [I32], low: I32, high: I32) -> (position: I32) {
        pivotkey := list[low]
        
        @ low < high {
            @ low < high & list[high] >= pivotkey {
                high -= 1
            }
            Swap(list, low , high)
            @ low < high & list[low] <= pivotkey {
                low += 1
            }
            Swap(list, low , high)
        }

        <- (low)
    }

    FilterList(list: [I32], fn: (I32) -> (Bl)) -> (l: [I32]) {
        filter := [I32]{}

        @ ea <- list {
            ? fn(ea) {
                filter += ea
            }
        }
        <- (filter)
    }

    Shutdown(ctrl: Control) -> () {
        ctrl.Shutdown()
    }
}

Node(value: I32) {
    Value = value
} -> {
    Value: I32
    Left: Node!
    Right: Node!
}

Control <- {
    Shutdown() -> ()
}

Program(name: Str) {
    Name = name
} -> {
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
} Control {
    Shutdown() -> () {
        Prt("Shutdown")
        _Running = False
    }
}

App(name: Str, platform: Str) {
    Platform = platform
} -> {
    Platform: Str
} Program(name) {
}
