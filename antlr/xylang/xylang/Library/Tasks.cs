using System;
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
}
