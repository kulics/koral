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

        public T first => not_empty ? this[0] : default(T);
        public T last => not_empty ? this[Count - 1] : default(T);
        public int last_index => Count - 1;

        public bool is_empty => !not_empty;
        public bool not_empty => Count > 0;

        public int len => Count;
        public int length => Count;
        public int cap => Capacity;
        public int capacity => Capacity;

        public Lst<T> sub_list(int startIndex, int endIndex) //=> GetRange(startIndex, count) as lst<T>;
        {
            var temp = new Lst<T>();
            int currIndex = startIndex;
            while (currIndex <= endIndex) {
                temp += this[currIndex];
                currIndex++;
            }
            return temp;
        }
        public Lst<T> slice(int? startIndex, int? endIndex, bool order = true, bool attach = true) {
            if (startIndex == null && endIndex == null) {
                return this;
            } else if (endIndex == null) {
                if (attach) {
                    return sub_list(startIndex ?? 0, last_index);
                } else {
                    return sub_list(startIndex ?? 0, last_index - 1);
                }
            } else // (startIndex == null)
              {
                if (attach) {
                    return sub_list(0, endIndex ?? 0);
                } else {
                    return sub_list(0, endIndex ?? 0 - 1);
                }
            }
        }
        public int first_index_of(T item) => IndexOf(item);
        public int last_index_of(T item) => LastIndexOf(item);

        public T find_first(Predicate<T> match) => Find(match);
        public T find_last(Predicate<T> match) => FindLast(match);
        public Lst<T> find_all(Func<T, bool> match) => this.Where(match) as Lst<T>;
        public int find_first_index(Predicate<T> match) => FindIndex(match);
        public int find_last_index(Predicate<T> match) => FindLastIndex(match);

        public void add(T item) => Add(item);
        public void add_range(IEnumerable<T> collection) => AddRange(collection);
        public void remove(T item) => Remove(item);
        public void remove_all(Predicate<T> match) => RemoveAll(match);
        public void insert(int index, T item) => Insert(index, item);
        public void insert_range(int index, IEnumerable<T> collection) => InsertRange(index, collection);
        public void remove_at(int index) => RemoveAt(index);
        public void remove_range(int index, int count) => RemoveRange(index, count);
        public void clear() => Clear();
        public bool has(T item) => Contains(item);

        public bool exists(Predicate<T> match) => Exists(match);
        public T[] to_array() => ToArray();
        public void reverse() => Reverse();
        public void sort(Comparison<T> comparison) => Sort(comparison);
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

        public bool has_key(TKey key) => ContainsKey(key);
        public bool has_value(TValue value) => ContainsValue(value);

        public bool is_empty => !not_empty;
        public bool not_empty => Count > 0;

        public int len => Count;
        public int length => Count;

        public void add(TKey key, TValue value) => Add(key, value);
        public bool remove(TKey key) => Remove(key);
        public void clear() => Clear();
    }

    public class Set<T> : HashSet<T> {
        public Set() : base() { }
        public Set(IEnumerable<T> collection) : base(collection) { }
        public Set(IEqualityComparer<T> comparer) : base(comparer) { }
        public Set(IEnumerable<T> collection, IEqualityComparer<T> comparer) : base(collection, comparer) { }

        public int len => Count;
        public int length => Count;

        public IEqualityComparer<T> comparer => Comparer;

        public bool add(T item) => Add(item);
        public bool remove(T item) => Remove(item);
        public int remove_where(Predicate<T> match) => RemoveWhere(match);
        public void clear() => Clear();
        public bool contains(T item) => Contains(item);
        public void except_with(IEnumerable<T> other) => ExceptWith(other);
        public void intersect_with(IEnumerable<T> other) => IntersectWith(other);
        public bool is_proper_subset_of(IEnumerable<T> other) => IsProperSubsetOf(other);
        public bool is_proper_superset_of(IEnumerable<T> other) => IsProperSupersetOf(other);
        public bool is_subset_of(IEnumerable<T> other) => IsSubsetOf(other);
        public bool is_superset_of(IEnumerable<T> other) => IsSupersetOf(other);
        public bool overlaps(IEnumerable<T> other) => Overlaps(other);
        public bool set_equals(IEnumerable<T> other) => SetEquals(other);
        public void symmetric_except_with(IEnumerable<T> other) => SymmetricExceptWith(other);
        public void trim_excess() => TrimExcess();
        public void union_with(IEnumerable<T> other) => UnionWith(other);
    }

    public static partial class CollectionsExtension {
        public static bool is_empty<T>(this ICollection<T> it) => !it.not_empty();
        public static bool not_empty<T>(this ICollection<T> it) => it.Count > 0;

        public static int len<T>(this ICollection<T> it) => it.Count;
        public static int length<T>(this ICollection<T> it) => it.Count;

        public static bool has_key<TKey, TValue>(this Dictionary<TKey, TValue> it, TKey key) => it.ContainsKey(key);
        public static bool has_value<TKey, TValue>(this Dictionary<TKey, TValue> it, TValue value) => it.ContainsValue(value);

        public static int cap<T>(this List<T> it) => it.Capacity;
        public static int capacity<T>(this List<T> it) => it.Capacity;

        public static Lst<T> sub_list<T>(this List<T> it, int startIndex, int endIndex) //=> GetRange(startIndex, count) as lst<T>;
        {
            var temp = new Lst<T>();
            int currIndex = startIndex;
            while (currIndex <= endIndex) {
                temp += it[currIndex];
                currIndex++;
            }
            return temp;
        }
        public static Lst<T> slice<T>(this List<T> it, int? startIndex, int? endIndex, bool order = true, bool attach = true) {
            if (startIndex == null && endIndex == null) {
                return it.sub_list(0, it.len() - 1);
            } else if (endIndex == null) {
                if (attach) {
                    return it.sub_list(startIndex ?? 0, it.len() - 1);
                } else {
                    return it.sub_list(startIndex ?? 0, it.len() - 1 - 1);
                }
            } else // (startIndex == null)
              {
                if (attach) {
                    return it.sub_list(0, endIndex ?? 0);
                } else {
                    return it.sub_list(0, endIndex ?? 0 - 1);
                }
            }
        }
        public static int first_index_of<T>(this List<T> it, T item) => it.IndexOf(item);
        public static int last_index_of<T>(this List<T> it, T item) => it.LastIndexOf(item);

        public static T find_first<T>(this List<T> it, Predicate<T> match) => it.Find(match);
        public static T find_last<T>(this List<T> it, Predicate<T> match) => it.FindLast(match);
        public static Lst<T> find_all<T>(this List<T> it, Func<T, bool> match) => it.Where(match) as Lst<T>;
        public static int find_first_index<T>(this List<T> it, Predicate<T> match) => it.FindIndex(match);
        public static int find_last_index<T>(this List<T> it, Predicate<T> match) => it.FindLastIndex(match);

        public static void add<T>(this List<T> it, T item) => it.Add(item);
        public static void add_range<T>(this List<T> it, IEnumerable<T> collection) => it.AddRange(collection);
        public static void remove<T>(this List<T> it, T item) => it.Remove(item);
        public static void remove_all<T>(this List<T> it, Predicate<T> match) => it.RemoveAll(match);
        public static void insert<T>(this List<T> it, int index, T item) => it.Insert(index, item);
        public static void insert_range<T>(this List<T> it, int index, IEnumerable<T> collection) => it.InsertRange(index, collection);
        public static void remove_at<T>(this List<T> it, int index) => it.RemoveAt(index);
        public static void remove_range<T>(this List<T> it, int index, int count) => it.RemoveRange(index, count);
        public static void clear<T>(this List<T> it) => it.Clear();
        public static bool has<T>(this List<T> it, T item) => it.Contains(item);

        public static bool exists<T>(this List<T> it, Predicate<T> match) => it.Exists(match);
        public static T[] to_array<T>(this List<T> it) => it.ToArray();
        public static void reverse<T>(this List<T> it) => it.Reverse();
        public static void sort<T>(this List<T> it, Comparison<T> comparison) => it.Sort(comparison);
    }
}
