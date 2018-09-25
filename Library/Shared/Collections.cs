using System;
using System.Collections.Generic;

namespace XyLang.Library
{
    public class lst<T> : List<T>
    {
        public lst() { }
        public lst(T[] v) : base(v) { }
        public lst(IEnumerable<T> collection) : base(collection) { }
        public lst(i32 capacity) : base(capacity) { }

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

        public T first => notEmpty ? this[0] : default(T);
        public T last => notEmpty ? this[Count - 1] : default(T);
        public i32 lastIndex => Count - 1;

        public bool isEmpty => !notEmpty;
        public bool notEmpty => Count > 0;

        public i32 count => Count;
        public i32 capacity => Capacity;

        public lst<T> subList(i32 startIndex, i32 count) => base.GetRange(startIndex, count) as lst<T>;
        public lst<T> slice(i32 startIndex, i32 endIndex)
        {
            if (startIndex == null && endIndex == null)
            {
                return this;
            }
            else if (endIndex == null)
            {
                return subList(startIndex, lastIndex - startIndex);
            }
            else // (startIndex == null)
            {
                return subList(0, lastIndex - endIndex);
            }
        }
        public i32 firstIndexOf(T item) => base.IndexOf(item);
        public new i32 lastIndexOf(T item) => base.LastIndexOf(item);

        public T findFirst(Predicate<T> match) => base.Find(match);
        public new T findLast(Predicate<T> match) => base.FindLast(match);
        public new lst<T> findAll(Predicate<T> match) => base.FindAll(match) as lst<T>;
        public i32 findFirstIndex(Predicate<T> match) => base.FindIndex(match);
        public new i32 findLastIndex(Predicate<T> match) => base.FindLastIndex(match);

        public void add(T item) => Add(item);
        public void addRange(IEnumerable<T> collection) => AddRange(collection);
        public void remove(T item) => Remove(item);
        public void removeAll(Predicate<T> match) => RemoveAll(match);
        public void insert(i32 index, T item) => Insert(index, item);
        public void insertRange(i32 index, IEnumerable<T> collection) => InsertRange(index, collection);
        public void removeAt(i32 index) => RemoveAt(index);
        public void removeRange(i32 index, i32 count) => RemoveRange(index, count);
        public void clear() => Clear();
        public bool has(T item) => Contains(item);

        public bool exists(Predicate<T> match) => Exists(match);
        public T[] toArray() => ToArray();
        public void reverse() => Reverse();
        public void sort(Comparison<T> comparison) => Sort(comparison);
    }

    public class dic<TKey, TValue> : Dictionary<TKey, TValue>
    {
        public dic() : base() { }
        public dic(IDictionary<TKey, TValue> dictionary) : base(dictionary) { }
        public dic(IEqualityComparer<TKey> comparer) : base(comparer) { }
        public dic(int capacity) : base(capacity) { }
        public dic(IDictionary<TKey, TValue> dictionary, IEqualityComparer<TKey> comparer) : base(dictionary, comparer) { }
        public dic(int capacity, IEqualityComparer<TKey> comparer) : base(capacity, comparer) { }

        public static dic<TKey, TValue> operator +(dic<TKey, TValue> L, dic<TKey, TValue> R)
        {
            var dic = new dic<TKey, TValue>();
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

        public static dic<TKey, TValue> operator -(dic<TKey, TValue> L, TKey R)
        {
            var dic = new dic<TKey, TValue>();
            foreach (var item in L)
            {
                dic.Add(item.Key, item.Value);
            }
            dic.Remove(R);
            return dic;
        }

        public bool hasKey(TKey key) => ContainsKey(key);
        public bool hasValue(TValue value) => ContainsValue(value);

        public bool isEmpty => !notEmpty;
        public bool notEmpty => Count > 0;

        public i32 count => Count;

        public void add(TKey key, TValue value) => Add(key, value);
        public bool remove(TKey key) => Remove(key);
        public void clear() => Clear();
    }
}
