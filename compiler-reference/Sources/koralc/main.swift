import Dispatch
import Foundation
import KoralCompiler

// rustc policy, matched by compiler/koralc/main.koral: the compiler recurses
// deeply (unification, generic instantiation, MIR walks), so the real work
// runs on a fat 64MB stack instead of the platform main-thread stack --
// Windows gives that 1MB (PE header) and overflows on large packages. 64MB
// dwarfs any depth the driver reaches. The process exit code is unchanged:
// driver.run exits the process itself on its error paths, and a normal
// return falls through to the process exiting 0 here.
let driverDone = DispatchSemaphore(value: 0)
let driverThread = Thread {
  let driver = Driver()
  driver.run(args: CommandLine.arguments)
  driverDone.signal()
}
driverThread.stackSize = 64 * 1024 * 1024
driverThread.start()
driverDone.wait()
