using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace XyLang.Library
{
    public class tsk : Task
    {
        public tsk(Action action) : base(action) { }
        public tsk(Action action, CancellationToken cancellationToken) : base(action, cancellationToken) { }
        public tsk(Action action, TaskCreationOptions creationOptions) : base(action, creationOptions) { }
        public tsk(Action<object> action, object state) : base(action, state) { }
        public tsk(Action action, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(action, cancellationToken, creationOptions) { }
        public tsk(Action<object> action, object state, CancellationToken cancellationToken)
            : base(action, state, cancellationToken) { }
        public tsk(Action<object> action, object state, TaskCreationOptions creationOptions)
            : base(action, state, creationOptions) { }
        public tsk(Action<object> action, object state, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(action, state, cancellationToken, creationOptions) { }
    }

    public class tsk<TResult> : Task<TResult>
    {
        public tsk(Func<TResult> function) : base(function) { }
        public tsk(Func<TResult> function, CancellationToken cancellationToken) : base(function, cancellationToken) { }
        public tsk(Func<TResult> function, TaskCreationOptions creationOptions) : base(function, creationOptions) { }
        public tsk(Func<object, TResult> function, object state) : base(function, state) { }
        public tsk(Func<TResult> function, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(function, cancellationToken, creationOptions) { }
        public tsk(Func<object, TResult> function, object state, CancellationToken cancellationToken)
            : base(function, state, cancellationToken) { }
        public tsk(Func<object, TResult> function, object state, TaskCreationOptions creationOptions)
            : base(function, state, creationOptions) { }
        public tsk(Func<object, TResult> function, object state, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(function, state, cancellationToken, creationOptions) { }
    }

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
