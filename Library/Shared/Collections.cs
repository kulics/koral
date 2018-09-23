using System;
using System.Collections.Generic;

namespace XyLang.Library
{
    public class Lst<T> : List<T>
    {
        public Lst() { }
        public Lst(T[] v) : base(v) { }
        public Lst(IEnumerable<T> collection) : base(collection) { }
        public Lst(I32 capacity) : base(capacity) { }

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

        public T First => NotEmpty ? this[0] : default(T);
        public T Last => NotEmpty ? this[Count - 1] : default(T);
        public I32 LastIndex => Count - 1;

        public bool IsEmpty => !NotEmpty;
        public bool NotEmpty => Count > 0;

        public Lst<T> SubList(I32 startIndex, I32 count) => base.GetRange(startIndex, count) as Lst<T>;
        public Lst<T> Slice(I32 startIndex, I32 endIndex)
        {
            if (startIndex == null && endIndex == null)
            {
                return this;
            }
            else if (endIndex == null)
            {
                return SubList(startIndex, LastIndex - startIndex);
            }
            else // (startIndex == null)
            {
                return SubList(0, LastIndex - endIndex);
            }
        }
        public I32 FirstIndexOf(T item) => base.IndexOf(item);
        public new I32 LastIndexOf(T item) => base.LastIndexOf(item);

        public T FindFirst(Predicate<T> match) => base.Find(match);
        public new T FindLast(Predicate<T> match) => base.FindLast(match);
        public new Lst<T> FindAll(Predicate<T> match) => base.FindAll(match) as Lst<T>;
        public I32 FindFirstIndex(Predicate<T> match) => base.FindIndex(match);
        public new I32 FindLastIndex(Predicate<T> match) => base.FindLastIndex(match);
    }

    public class Dic<TKey, TValue> : Dictionary<TKey, TValue>
    {
        public Dic() : base() { }
        public Dic(IDictionary<TKey, TValue> dictionary) : base(dictionary) { }
        public Dic(IEqualityComparer<TKey> comparer) : base(comparer) { }
        public Dic(int capacity) : base(capacity) { }
        public Dic(IDictionary<TKey, TValue> dictionary, IEqualityComparer<TKey> comparer) : base(dictionary, comparer) { }
        public Dic(int capacity, IEqualityComparer<TKey> comparer) : base(capacity, comparer) { }

        public static Dic<TKey, TValue> operator +(Dic<TKey, TValue> L, Dic<TKey, TValue> R)
        {
            var dic = new Dic<TKey, TValue>();
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

        public static Dic<TKey, TValue> operator -(Dic<TKey, TValue> L, TKey R)
        {
            var dic = new Dic<TKey, TValue>();
            foreach (var item in L)
            {
                dic.Add(item.Key, item.Value);
            }
            dic.Remove(R);
            return dic;
        }

        public bool IsEmpty => !NotEmpty;
        public bool NotEmpty => Count > 0;
    }
}
