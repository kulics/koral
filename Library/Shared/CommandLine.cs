using System;

namespace XyLang.Library
{
    public static class cmd
    {
        public static void print(params object[] paramList)
        {
            foreach (var item in paramList)
            {
                Console.Write(item);
                Console.Write(" ");
            }
            Console.WriteLine();
        }

        public static str read() => Console.ReadLine();

        public static void clear() => Console.Clear();
    }
}
