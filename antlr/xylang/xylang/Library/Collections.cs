using System.Collections.Generic;

namespace XyLang.Library
{
    public class Lst<T> : List<T>
    {
        public Lst() : base() { }
        public Lst(IEnumerable<T> collection) : base(collection) { }
        public Lst(int capacity) : base(capacity) { }

        public static Lst<T> operator +(Lst<T> L, T R)
        {
            var list = new Lst<T>();
            list.AddRange(L);
            list.Add(R);
            return list;
        }

        public static Lst<T> operator +(Lst<T> L, Lst<T> R)
        {
            var list = new Lst<T>();
            list.AddRange(L);
            list.AddRange(R);
            return list;
        }

        public static Lst<T> operator +(T L, Lst<T> R)
        {
            var list = new Lst<T>
            {
                L
            };
            list.AddRange(R);
            return list;
        }

        public static Lst<T> operator -(Lst<T> L, int R)
        {
            var list = new Lst<T>();
            list.AddRange(L);
            list.RemoveAt(R);
            return list;
        }
    }

    public class Dic<T1, T2> : Dictionary<T1, T2>
    {
        public static Dic<T1, T2> operator +(Dic<T1, T2> L, Dic<T1, T2> R)
        {
            var dic = new Dic<T1, T2>();
            foreach (var item in L)
            {
                dic.Add(item.Key, item.Value);
            }
            foreach (var item in R)
            {
                dic.Add(item.Key, item.Value);
            }
            return dic;
        }

        public static Dic<T1, T2> operator -(Dic<T1, T2> L, T1 R)
        {
            var dic = new Dic<T1, T2>();
            foreach (var item in L)
            {
                dic.Add(item.Key, item.Value);
            }
            dic.Remove(R);
            return dic;
        }
    }
}
