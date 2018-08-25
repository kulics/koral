using System.Collections.Generic;

namespace XyLang.Library
{
    public class lst<T> : List<T>
    {
        public lst() : base() { }
        public lst(IEnumerable<T> collection) : base(collection) { }
        public lst(int capacity) : base(capacity) { }

        public static lst<T> operator +(lst<T> L, T R)
        {
            var list = new lst<T>();
            list.AddRange(L);
            list.Add(R);
            return list;
        }

        public static lst<T> operator +(lst<T> L, lst<T> R)
        {
            var list = new lst<T>();
            list.AddRange(L);
            list.AddRange(R);
            return list;
        }

        public static lst<T> operator +(T L, lst<T> R)
        {
            var list = new lst<T>
            {
                L
            };
            list.AddRange(R);
            return list;
        }

        public static lst<T> operator -(lst<T> L, int R)
        {
            var list = new lst<T>();
            list.AddRange(L);
            list.RemoveAt(R);
            return list;
        }
    }

    public class dic<T1, T2> : Dictionary<T1, T2>
    {
        public static dic<T1, T2> operator +(dic<T1, T2> L, dic<T1, T2> R)
        {
            var dic = new dic<T1, T2>();
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

        public static dic<T1, T2> operator -(dic<T1, T2> L, T1 R)
        {
            var dic = new dic<T1, T2>();
            foreach (var item in L)
            {
                dic.Add(item.Key, item.Value);
            }
            dic.Remove(R);
            return dic;
        }
    }
}
