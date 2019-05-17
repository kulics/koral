using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Library {
    public class read_only<T> {
        public T value { get; }
        public T v { get => value; }
        public read_only(T value) {
            this.value = value;
        }
    }

    public static partial class lib {
        public static read_only<T> ro<T>(T it) => new read_only<T>(it);

        public static read_only<T> read_only<T>(T it) => ro(it);

        public static T[] arr_of<T>(params T[] item) => item;

        public static T[] array_of<T>(params T[] item) => arr_of(item);

        public static lst<T> lst_of<T>(params T[] item) => new lst<T>(item);

        public static lst<T> list_of<T>(params T[] item) => lst_of(item);

        public static T def<T>() => default(T);

        public static T @default<T>() => def<T>();

        public static T to<T>(object it) => (T)it;

        public static bool @is<T>(object it) => it is T;

        public static T @as<T>(object it) where T : class => it as T;

        public static void prt(params object[] paramList) => Cmd.print(paramList);

        public static void print(params object[] paramList) => prt(paramList);

        public static string rd() => Cmd.read();

        public static string read() => rd();

        public static void clr() => Cmd.clear();

        public static void clear() => clr();

        public static Task<T> go<T>(Func<Task<T>> fn) => Task.Run(fn);

        public static Task go(Func<Task> fn) => Task.Run(fn);

        public static Task go(Action fn) => Task.Run(fn);

        public static void wait(params Task[] tasks) => Task.WaitAll(tasks);

        public static void slp(int milliseconds) => Thread.Sleep(milliseconds);

        public static void sleep(int milliseconds) => slp(milliseconds);

        public static Task dly(int milliseconds) => Task.Delay(milliseconds);

        public static Task delay(int milliseconds) => dly(milliseconds);

        public static double pow(double a, double b) => Math.Pow(a, b);

        public static double root(double a, double b) => Math.Pow(a, 1 / b);

        public static double log(double a, double b) => Math.Log(a, b);

        public static int len<T>(T[] it) => it.Length;
        public static int length<T>(T[] it) => it.Length;
        public static int len<T>(ICollection<T> it) => it.Count;
        public static int length<T>(ICollection<T> it) => it.Count;
        public static int cap<T>(List<T> it) => it.Capacity;
        public static int capacity<T>(List<T> it) => it.Capacity;

        public static IEnumerable<int> range(int begin, int end, int step = 1, bool order = true, bool attach = true) {
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

        public static IEnumerable<(int index, T item)> range<T>(IEnumerable<T> self)
=> self.Select((item, index) => (index, item));

        public static IEnumerable<(TKey, TValue)> range<TKey, TValue>(IEnumerable<KeyValuePair<TKey, TValue>> self)
   => self.Select((item) => (item.Key, item.Value));

        public static void todo(string it) => throw new Exception(it);

        public static decimal abs(decimal it) => Math.Abs(it);
        public static sbyte abs(sbyte it) => Math.Abs(it);
        public static short abs(short it) => Math.Abs(it);
        public static int abs(int it) => Math.Abs(it);
        public static long abs(long it) => Math.Abs(it);
        public static float abs(float it) => Math.Abs(it);
        public static double abs(double it) => Math.Abs(it);

        public static decimal max(params decimal[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static sbyte max(params sbyte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static byte max(params byte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static short max(params short[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static ushort max(params ushort[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static int max(params int[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static uint max(params uint[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static long max(params long[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static ulong max(params ulong[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static float max(params float[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static double max(params double[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Max(it[i], it[i - 1]);
            }
            return x;
        }

        public static decimal min(params decimal[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static sbyte min(params sbyte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static byte min(params byte[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static short min(params short[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static ushort min(params ushort[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static int min(params int[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static uint min(params uint[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static long min(params long[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static ulong min(params ulong[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static float min(params float[] it) {
            if (it.Length == 0) {
                return 0;
            }
            var x = it[0];
            for (int i = 1; i < it.Length; i++) {
                x = Math.Min(it[i], it[i - 1]);
            }
            return x;
        }

        public static double min(params double[] it) {
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
