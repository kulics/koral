using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Library {
    public class ReadOnly<T> {
        public T Value { get; }
        public T V { get => Value; }
        public ReadOnly(T value) {
            Value = value;
        }
    }

    public static partial class Lib {
        public static ReadOnly<T> RO<T>(T it) => new ReadOnly<T>(it);

        public static ReadOnly<T> ReadOnly<T>(T it) => RO(it);

        public static T[] ArrOf<T>(params T[] item) => item;

        public static T[] ArrayOf<T>(params T[] item) => ArrOf(item);

        public static Lst<T> LstOf<T>(params T[] item) => new Lst<T>(item);

        public static Lst<T> ListOf<T>(params T[] item) => LstOf(item);

        public static T Def<T>() => default(T);

        public static T Default<T>() => Def<T>();

        public static T To<T>(object it) => (T)it;

        public static bool Is<T>(object it) => it is T;

        public static T As<T>(object it) where T : class => it as T;

        public static void Prt(params object[] paramList) => Cmd.Prt(paramList);

        public static void Print(params object[] paramList) => Prt(paramList);

        public static string Rd() => Cmd.Rd();

        public static string Read() => Rd();

        public static void Clr() => Cmd.Clr();

        public static void Clear() => Clr();

        public static Task Go(Func<Task> fn) => Task.Run(fn);

        public static Task Go(Action fn) => Task.Run(fn);

        public static void Wait(params Task[] tasks) => Task.WaitAll(tasks);

        public static void Slp(int milliseconds) => Thread.Sleep(milliseconds);

        public static void Sleep(int milliseconds) => Slp(milliseconds);

        public static Task Dly(int milliseconds) => Task.Delay(milliseconds);

        public static Task Delay(int milliseconds) => Dly(milliseconds);

        public static double Pow(double a, double b) => Math.Pow(a, b);

        public static double Root(double a, double b) => Math.Pow(a, 1 / b);

        public static double Log(double a, double b) => Math.Log(a, b);

        public static int Len<T>(T[] it) => it.Length;
        public static int Length<T>(T[] it) => it.Length;
        public static int Len<T>(ICollection<T> it) => it.Count;
        public static int Length<T>(ICollection<T> it) => it.Count;
        public static int Cap<T>(List<T> it) => it.Capacity;
        public static int Capacity<T>(List<T> it) => it.Capacity;

        public static IEnumerable<int> Range(int begin, int end, int step = 1, bool order = true, bool attach = true) {
            if (order) {
                if (attach) {
                    for (int index = begin; index <= end; index += step) {
                        yield return index;
                    }
                } else {
                    for (int index = begin; index < end; index += step) {
                        yield return index;
                    }
                }
            } else {
                if (attach) {
                    for (int index = begin; index >= end; index -= step) {
                        yield return index;
                    }
                } else {
                    for (int index = begin; index > end; index -= step) {
                        yield return index;
                    }
                }
            }
        }

        public static IEnumerable<(int index, T item)> Range<T>(IEnumerable<T> self)
=> self.Select((item, index) => (index, item));

        public static IEnumerable<(TKey, TValue)> Range<TKey, TValue>(IEnumerable<KeyValuePair<TKey, TValue>> self)
   => self.Select((item) => (item.Key, item.Value));

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
