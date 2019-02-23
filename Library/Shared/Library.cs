using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Library {
    public static partial class lib {
        public static T[] arrOf<T>(params T[] item) => item;

        public static lst<T> lstOf<T>(params T[] item) => new lst<T>(item);

        public static T def<T>() => default(T);

        public static T to<T>(object it) => (T)it;

        public static bool @is<T>(object it) => it is T;

        public static T @as<T>(object it) where T : class => it as T;

        public static void prt(params object[] paramList) => cmd.prt(paramList);

        public static string rd() => cmd.rd();

        public static void clr() => cmd.clr();

        public static async Task go(Func<Task> @do) => await @do();

        public static double pow(double a, double b) => Math.Pow(a, b);

        public static double root(double a, double b) => Math.Pow(a, 1 / b);

        public static double log(double a, double b) => Math.Log(a, b);

        public static int len<T>(T[] it) => it.Length;
        public static int len<T>(ICollection<T> it) => it.Count;
        public static int cap<T>(List<T> it) => it.Capacity;

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
