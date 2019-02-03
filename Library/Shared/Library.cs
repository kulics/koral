using System;
using System.Threading.Tasks;

namespace Library
{
    public static partial class lib
    {
        public static T[] arrOf<T>(params T[] item) => item;

        public static lst<T> lstOf<T>(params T[] item) => new lst<T>(item);

        public static T def<T>() => default(T);

        public static T to<T>(object it) => (T)it;

        public static bool @is<T>(object it) => it is T;

        public static T @as<T>(object it) where T : class => it as T;

        public static void prt(params object[] paramList) => cmd.prt(paramList);

        public static string rd() => cmd.rd();

        public static void clr() => cmd.clr();

        public static async void go(Func<Task> @do)
        {
            await @do();
        }
    }
}
