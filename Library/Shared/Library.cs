using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Library {
    public static partial class Lib {
        public static T[] ArrOf<T>(params T[] item) => item;

        public static Lst<T> LstOf<T>(params T[] item) => new Lst<T>(item);

        public static T Def<T>() => default(T);

        public static T To<T>(object it) => (T)it;

        public static bool Is<T>(object it) => it is T;

        public static T As<T>(object it) where T : class => it as T;

        public static void Prt(params object[] paramList) => Cmd.Prt(paramList);

        public static string Rd() => Cmd.Rd();

        public static void Clr() => Cmd.Clr();

        public static async Task Go(Func<Task> @do) => await @do();

        public static Task Slp(int milliseconds) => Task.Delay(milliseconds);

        public static double Pow(double a, double b) => Math.Pow(a, b);

        public static double Root(double a, double b) => Math.Pow(a, 1 / b);

        public static double Log(double a, double b) => Math.Log(a, b);

        public static int Len<T>(T[] it) => it.Length;
        public static int Len<T>(ICollection<T> it) => it.Count;
        public static int Cap<T>(List<T> it) => it.Capacity;

        public static void Todo(string it) => throw new Exception(it);

        public static decimal Abs(decimal it) => Math.Abs(it);
        public static sbyte Abs(sbyte it) => Math.Abs(it);
        public static short Abs(short it) => Math.Abs(it);
        public static int Abs(int it) => Math.Abs(it);
        public static long Abs(long it) => Math.Abs(it);
        public static float Abs(float it) => Math.Abs(it);
        public static double Abs(double it) => Math.Abs(it);

        public static decimal Max(params decimal[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static sbyte Max(params sbyte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static byte Max(params byte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static short Max(params short[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static ushort Max(params ushort[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static int Max(params int[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static uint Max(params uint[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static long Max(params long[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static ulong Max(params ulong[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static float Max(params float[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static double Max(params double[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static decimal Min(params decimal[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static sbyte Min(params sbyte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static byte Min(params byte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static short Min(params short[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static ushort Min(params ushort[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static int Min(params int[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static uint Min(params uint[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static long Min(params long[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static ulong Min(params ulong[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static float Min(params float[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static double Min(params double[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }
    }
}
