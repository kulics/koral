using System;
using System.Threading;
using System.Threading.Tasks;

namespace XyLang.Library
{
    public class Tsk : Task
    {
        public Tsk(Action action) : base(action) { }
        public Tsk(Action action, CancellationToken cancellationToken) : base(action, cancellationToken) { }
        public Tsk(Action action, TaskCreationOptions creationOptions) : base(action, creationOptions) { }
        public Tsk(Action<object> action, object state) : base(action, state) { }
        public Tsk(Action action, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(action, cancellationToken, creationOptions) { }
        public Tsk(Action<object> action, object state, CancellationToken cancellationToken)
            : base(action, state, cancellationToken) { }
        public Tsk(Action<object> action, object state, TaskCreationOptions creationOptions)
            : base(action, state, creationOptions) { }
        public Tsk(Action<object> action, object state, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(action, state, cancellationToken, creationOptions) { }
    }

    public class Tsk<TResult> : Task<TResult>
    {
        public Tsk(Func<TResult> function) : base(function) { }
        public Tsk(Func<TResult> function, CancellationToken cancellationToken) : base(function, cancellationToken) { }
        public Tsk(Func<TResult> function, TaskCreationOptions creationOptions) : base(function, creationOptions) { }
        public Tsk(Func<object, TResult> function, object state) : base(function, state) { }
        public Tsk(Func<TResult> function, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(function, cancellationToken, creationOptions) { }
        public Tsk(Func<object, TResult> function, object state, CancellationToken cancellationToken)
            : base(function, state, cancellationToken) { }
        public Tsk(Func<object, TResult> function, object state, TaskCreationOptions creationOptions)
            : base(function, state, creationOptions) { }
        public Tsk(Func<object, TResult> function, object state, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
            : base(function, state, cancellationToken, creationOptions) { }
    }
}
