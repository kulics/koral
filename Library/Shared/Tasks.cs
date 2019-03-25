//using System;
//using System.Collections.Generic;
//using System.Threading;
//using System.Threading.Tasks;

//namespace Library {
//    public class tsk : Task {
//        public tsk(Action action) : base(action) { }
//        public tsk(Action action, CancellationToken cancellationToken) : base(action, cancellationToken) { }
//        public tsk(Action action, TaskCreationOptions creationOptions) : base(action, creationOptions) { }
//        public tsk(Action<object> action, object state) : base(action, state) { }
//        public tsk(Action action, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
//            : base(action, cancellationToken, creationOptions) { }
//        public tsk(Action<object> action, object state, CancellationToken cancellationToken)
//            : base(action, state, cancellationToken) { }
//        public tsk(Action<object> action, object state, TaskCreationOptions creationOptions)
//            : base(action, state, creationOptions) { }
//        public tsk(Action<object> action, object state, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
//            : base(action, state, cancellationToken, creationOptions) { }

//        public bool isCompleted => IsCompleted;
//        public int id => Id;
//        public bool isCanceled => IsCanceled;
//        public object asyncState => AsyncState;
//        public bool isFaulted => IsFaulted;
//        public TaskStatus status => Status;
//        public void start() => Start();
//        public void start(TaskScheduler scheduler) => Start(scheduler);
//        public bool wait(int millisecondsTimeout) => Wait(millisecondsTimeout);
//        public bool wait(int millisecondsTimeout, CancellationToken cancellationToken) => Wait(millisecondsTimeout, cancellationToken);
//        public void wait() => Wait();
//    }

//    public static class tsks {
//        public static Task run(Func<Task> function, CancellationToken cancellationToken) => Task.Run(function, cancellationToken);
//        public static Task run(Action action, CancellationToken cancellationToken) => Task.Run(action, cancellationToken);
//        public static Task run(Action action) => Task.Run(action);
//        public static Task run(Func<Task> function) => Task.Run(function);

//        public static void waitAll(Task[] tasks, CancellationToken cancellationToken) => Task.WaitAll(tasks, cancellationToken);
//        public static bool waitAll(Task[] tasks, int millisecondsTimeout, CancellationToken cancellationToken) => Task.WaitAll(tasks, millisecondsTimeout, cancellationToken);
//        public static bool waitAll(Task[] tasks, int millisecondsTimeout) => Task.WaitAll(tasks, millisecondsTimeout);
//        public static void waitAll(params Task[] tasks) => Task.WaitAll(tasks);

//        public static Task whenAll(IEnumerable<Task> tasks) => Task.WhenAll(tasks);
//        public static Task whenAll(params Task[] tasks) => Task.WhenAll(tasks);

//        public static Task<Task> whenAny(IEnumerable<Task> tasks) => Task.WhenAny(tasks);
//        public static Task<Task> whenAny(params Task[] tasks) => Task.WhenAny(tasks);

//        public static Task delay(int millisecondsDelay) => Task.Delay(millisecondsDelay);
//        public static Task delay(int millisecondsDelay, CancellationToken cancellationToken) => Task.Delay(millisecondsDelay, cancellationToken);
//    }

//    public class tsk<TResult> : Task<TResult> {
//        public tsk(Func<TResult> function) : base(function) { }
//        public tsk(Func<TResult> function, CancellationToken cancellationToken) : base(function, cancellationToken) { }
//        public tsk(Func<TResult> function, TaskCreationOptions creationOptions) : base(function, creationOptions) { }
//        public tsk(Func<object, TResult> function, object state) : base(function, state) { }
//        public tsk(Func<TResult> function, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
//            : base(function, cancellationToken, creationOptions) { }
//        public tsk(Func<object, TResult> function, object state, CancellationToken cancellationToken)
//            : base(function, state, cancellationToken) { }
//        public tsk(Func<object, TResult> function, object state, TaskCreationOptions creationOptions)
//            : base(function, state, creationOptions) { }
//        public tsk(Func<object, TResult> function, object state, CancellationToken cancellationToken, TaskCreationOptions creationOptions)
//            : base(function, state, cancellationToken, creationOptions) { }

//        public bool isCompleted => IsCompleted;
//        public int id => Id;
//        public bool isCanceled => IsCanceled;
//        public object asyncState => AsyncState;
//        public bool isFaulted => IsFaulted;
//        public TaskStatus status => Status;
//        public void start() => Start();
//        public void start(TaskScheduler scheduler) => Start(scheduler);
//        public bool wait(int millisecondsTimeout) => Wait(millisecondsTimeout);
//        public bool wait(int millisecondsTimeout, CancellationToken cancellationToken) => Wait(millisecondsTimeout, cancellationToken);
//        public void wait() => Wait();
//    }
//}
