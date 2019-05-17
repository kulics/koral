using System;

namespace Library {
    public static class Cmd {
        public static void print(params object[] paramList) {
            foreach (var item in paramList) {
                Console.Write(item);
            }
            if (paramList.Length > 0 && paramList[paramList.Length - 1] as string == "") {
                return;
            }
            Console.WriteLine();
        }

        public static string read() => Console.ReadLine();

        public static void clear() => Console.Clear();
    }
}
