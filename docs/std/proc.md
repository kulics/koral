# Std.Proc API

## Overview
This page lists the public API of module `Std.Proc` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let current_pid() UInt32

public let send_process_signal(signal Int, to: UInt32) Result[Void]

public let kill_process(pid UInt32) Result[Void]

public let is_process_alive(pid UInt32) Bool

public let run_command(program String, args List[String]) Result[ExitStatus]

public let run_command_output(program String, args List[String]) Result[CommandOutput]
```

## Traits
(none)

## Types
```koral
public type Command

public type CommandOutput(
    public status ExitStatus,
    public stdout String,
    public stderr String,
)

public type ExitStatus

public type StdinPipe

public type StdoutPipe

public type StderrPipe

public type Process

public type IoRedirect {
    Inherit(),
    Piped(),
    Null(),
    File(file File),
    StdoutPipe(pipe StdoutPipe),
    StderrPipe(pipe StderrPipe),
}
```

## Given Implementations
```koral
given Command {
    public new(program String) Command
    public arg(self, value String) Command
    public args(self, values List[String]) Command
    public set_env(self, name String, value String) Command
    public clear_env(self) Command
    public remove_env(self, name String) Command
    public set_current_dir[T IntoPath](self, path T) Command
    public set_stdin(self, cfg IoRedirect) Command
    public set_stdout(self, cfg IoRedirect) Command
    public set_stderr(self, cfg IoRedirect) Command
    public spawn(self) Result[Process]
    public run(self) Result[ExitStatus]
    public run_output(self) Result[CommandOutput]
}

given CommandOutput {
    public is_success(*self) Bool
    public code(*self) Option[Int]
}

given CommandOutput as ToString {
    public to_string(*self) String
}

given ExitStatus {
    public code(*self) Option[Int]
    public is_success(*self) Bool
    public signal(*self) Option[Int]
}

given ExitStatus as ToString {
    public to_string(*self) String
}

given StdinPipe {
    public fd(*self) Int
}

given StdinPipe as Writer {
    public write(*self, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(*self) Result[Void]
}

given StdoutPipe {
    public fd(*self) Int
}

given StdoutPipe as Reader {
    public read(*self, into: *mut List[UInt8], range Range[UInt]) Result[UInt]
}

given StderrPipe {
    public fd(*self) Int
}

given StderrPipe as Reader {
    public read(*self, into: *mut List[UInt8], range Range[UInt]) Result[UInt]
}

given Process {
    public pid(*self) UInt32
    public wait(*self) Result[ExitStatus]
    public wait_output(*self) Result[CommandOutput]
    public try_wait(*self) Result[Option[ExitStatus]]
    public take_stdin_pipe(*self) Option[StdinPipe]
    public take_stdout_pipe(*self) Option[StdoutPipe]
    public take_stderr_pipe(*self) Option[StderrPipe]
}

given IoRedirect as ToString {
    public to_string(*self) String
}
```
