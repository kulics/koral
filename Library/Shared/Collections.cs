using System;
using System.Collections.Generic;
using System.Linq;

namespace Library {
    public class Lst<T> : List<T> {
        public Lst() { }
        public Lst(T[] v) : base(v) { }
        public Lst(IEnumerable<T> collection) : base(collection) { }
        public Lst(int capacity) : base(capacity) { }

        public static Lst<T> operator +(Lst<T> L, T R) {
            var list = new Lst<T>(L)
            {
                R
            };
            return list;
        }

        public static Lst<T> operator +(Lst<T> L, Lst<T> R) {
            var list = new Lst<T>(L);
            list.AddRange(R);
            return list;
        }

        public static Lst<T> operator -(Lst<T> L, int R) {
            var list = new Lst<T>(L);
            list.RemoveAt(R);
            return list;
        }

        public T First => NotEmpty ? this[0] : default(T);
        public T Last => NotEmpty ? this[Count - 1] : default(T);
        public int LastIndex => Count - 1;

        public bool IsEmpty => !NotEmpty;
        public bool NotEmpty => Count > 0;

        public int Len => Count;
        public int Length => Count;
        public int Cap => Capacity;
        //public int capacity => Capacity;

        public Lst<T> SubList(int startIndex, int endIndex) //=> GetRange(startIndex, count) as lst<T>;
        {
            var temp = new Lst<T>();
            int currIndex = startIndex;
            while (currIndex <= endIndex) {
                temp += this[currIndex];
                currIndex++;
            }
            return temp;
        }
        public Lst<T> Slice(int? startIndex, int? endIndex, bool order = true, bool attach = true) {
            if (startIndex == null && endIndex == null) {
                return this;
            } else if (endIndex == null) {
                if (attach) {
                    return SubList(startIndex ?? 0, LastIndex);
                } else {
                    return SubList(startIndex ?? 0, LastIndex - 1);
                }
            } else // (startIndex == null)
              {
                if (attach) {
                    return SubList(0, endIndex ?? 0);
                } else {
                    return SubList(0, endIndex ?? 0 - 1);
                }
            }
        }
        public int FirstIndexOf(T item) => IndexOf(item);
        //public new int lastIndexOf(T item) => LastIndexOf(item);

        public T FindFirst(Predicate<T> match) => Find(match);
        //public new T findLast(Predicate<T> match) => FindLast(match);
        public Lst<T> FindAll(Func<T, bool> match) => this.Where(match) as Lst<T>;
        public int FindFirstIndex(Predicate<T> match) => FindIndex(match);
        //public new int findLastIndex(Predicate<T> match) => FindLastIndex(match);

        //public void add(T item) => Add(item);
        //public void addRange(IEnumerable<T> collection) => AddRange(collection);
        //public void remove(T item) => Remove(item);
        //public void removeAll(Predicate<T> match) => RemoveAll(match);
        //public void insert(int index, T item) => Insert(index, item);
        //public void insertRange(int index, IEnumerable<T> collection) => InsertRange(index, collection);
        //public void removeAt(int index) => RemoveAt(index);
        //public void removeRange(int index, int count) => RemoveRange(index, count);
        //public void clear() => Clear();
        public bool Has(T item) => Contains(item);

        //public bool exists(Predicate<T> match) => Exists(match);
        //public T[] toArray() => ToArray();
        //public void reverse() => Reverse();
        //public void sort(Comparison<T> comparison) => Sort(comparison);
    }

    public class Dic<TKey, TValue> : Dictionary<TKey, TValue> {
        public Dic() : base() { }
        public Dic(IDictionary<TKey, TValue> dictionary) : base(dictionary) { }
        public Dic(IEqualityComparer<TKey> comparer) : base(comparer) { }
        public Dic(int capacity) : base(capacity) { }
        public Dic(IDictionary<TKey, TValue> dictionary, IEqualityComparer<TKey> comparer) : base(dictionary, comparer) { }
        public Dic(int capacity, IEqualityComparer<TKey> comparer) : base(capacity, comparer) { }

        public static Dic<TKey, TValue> operator +(Dic<TKey, TValue> L, Dic<TKey, TValue> R) {
            var dic = new Dic<TKey, TValue>(L);
            foreach (var item in R) {
                dic.Add(item.Key, item.Value);
            }
            return dic;
        }

        public static Dic<TKey, TValue> operator -(Dic<TKey, TValue> L, TKey R) {
            var dic = new Dic<TKey, TValue>(L);
            dic.Remove(R);
            return dic;
        }

        public bool HasKey(TKey key) => ContainsKey(key);
        public bool HasValue(TValue value) => ContainsValue(value);

        public bool IsEmpty => !NotEmpty;
        public bool NotEmpty => Count > 0;

        public int Len => Count;
        public int Length => Count;

        //public void add(TKey key, TValue value) => Add(key, value);
        //public bool remove(TKey key) => Remove(key);
        //public void clear() => Clear();
    }

    public static partial class CollectionsExtension {
        public static bool IsEmpty<T>(this ICollection<T> it) => !it.NotEmpty();
        public static bool NotEmpty<T>(this ICollection<T> it) => it.Count > 0;

        public static int Len<T>(this ICollection<T> it) => it.Count;
        public static int Length<T>(this ICollection<T> it) => it.Count;

        public static bool HasKey<TKey, TValue>(this Dictionary<TKey, TValue> it, TKey key) => it.ContainsKey(key);
        public static bool HasValue<TKey, TValue>(this Dictionary<TKey, TValue> it, TValue value) => it.ContainsValue(value);

        public static int Cap<T>(this List<T> it) => it.Capacity;
        public static int Capacity<T>(this List<T> it) => it.Capacity;

        public static Lst<T> SubList<T>(this List<T> it, int startIndex, int endIndex) //=> GetRange(startIndex, count) as lst<T>;
        {
            var temp = new Lst<T>();
            int currIndex = startIndex;
            while (currIndex <= endIndex) {
                temp += it[currIndex];
                currIndex++;
            }
            return temp;
        }
        public static Lst<T> Slice<T>(this List<T> it, int? startIndex, int? endIndex, bool order = true, bool attach = true) {
            if (startIndex == null && endIndex == null) {
                return it.SubList(0, it.Len() - 1);
            } else if (endIndex == null) {
                if (attach) {
                    return it.SubList(startIndex ?? 0, it.Len() - 1);
                } else {
                    return it.SubList(startIndex ?? 0, it.Len() - 1 - 1);
                }
            } else // (startIndex == null)
              {
                if (attach) {
                    return it.SubList(0, endIndex ?? 0);
                } else {
                    return it.SubList(0, endIndex ?? 0 - 1);
                }
            }
        }
        public static int FirstIndexOf<T>(this List<T> it, T item) => it.IndexOf(item);
        //public static int LastIndexOf<T>(this List<T> it, T item) => it.LastIndexOf(item);

        public static T FindFirst<T>(this List<T> it, Predicate<T> match) => it.Find(match);
        public static T FindLast<T>(this List<T> it, Predicate<T> match) => it.FindLast(match);
        public static Lst<T> FindAll<T>(this List<T> it, Func<T, bool> match) => it.Where(match) as Lst<T>;
        public static int FindFirstIndex<T>(this List<T> it, Predicate<T> match) => it.FindIndex(match);
        //public static int FindLastIndex<T>(this List<T> it, Predicate<T> match) => it.FindLastIndex(match);

        //public static void Add<T>(this List<T> it, T item) => it.Add(item);
        //public static void AddRange<T>(this List<T> it, IEnumerable<T> collection) => it.AddRange(collection);
        //public static void Remove<T>(this List<T> it, T item) => it.Remove(item);
        //public static void RemoveAll<T>(this List<T> it, Predicate<T> match) => it.RemoveAll(match);
        //public static void Insert<T>(this List<T> it, int index, T item) => it.Insert(index, item);
        //public static void InsertRange<T>(this List<T> it, int index, IEnumerable<T> collection) => it.InsertRange(index, collection);
        //public static void RemoveAt<T>(this List<T> it, int index) => it.RemoveAt(index);
        //public static void RemoveRange<T>(this List<T> it, int index, int count) => it.RemoveRange(index, count);
        //public static void Clear<T>(this List<T> it) => it.Clear();
        public static bool Has<T>(this List<T> it, T item) => it.Contains(item);

        //public static bool Exists<T>(this List<T> it, Predicate<T> match) => it.Exists(match);
        //public static T[] ToArray<T>(this List<T> it) => it.ToArray();
        //public static void Reverse<T>(this List<T> it) => it.Reverse();
        //public static void Sort<T>(this List<T> it, Comparison<T> comparison) => it.Sort(comparison);
    }
}
