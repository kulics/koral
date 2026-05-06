# Std.Proc API

## Overview
This page lists the public API of module `Std.Proc` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let current_pid() UInt32

public let send_process_signal(signal Int, to: UInt32) [Void]Result

public let kill_process(pid UInt32) [Void]Result

public let is_process_alive(pid UInt32) Bool

public let run_command(program String, args [String]List) [ExitStatus]Result

public let run_command_output(program String, args [String]List) [CommandOutput]Result
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
    public args(self, values [String]List) Command
    public set_env(self, name String, value String) Command
    public clear_env(self) Command
    public remove_env(self, name String) Command
    public [T IntoPath]set_current_dir(self, path T) Command
    public set_stdin(self, cfg IoRedirect) Command
    public set_stdout(self, cfg IoRedirect) Command
    public set_stderr(self, cfg IoRedirect) Command
    public spawn(self) [Process]Result
    public run(self) [ExitStatus]Result
    public run_output(self) [CommandOutput]Result
}

given CommandOutput {
    public is_success(self ref) Bool
    public code(self ref) [Int]Option
}

given CommandOutput as ToString {
    public to_string(self ref) String
}

given ExitStatus {
    public code(self ref) [Int]Option
    public is_success(self ref) Bool
    public signal(self ref) [Int]Option
}

given ExitStatus as ToString {
    public to_string(self ref) String
}

given StdinPipe {
    public fd(self ref) Int
}

given StdinPipe as Writer {
    public write(self ref, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self ref) [Void]Result
}

given StdoutPipe {
    public fd(self ref) Int
}

given StdoutPipe as Reader {
    public read(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
}

given StderrPipe {
    public fd(self ref) Int
}

given StderrPipe as Reader {
    public read(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
}

given Process {
    public pid(self ref) UInt32
    public wait(self ref) [ExitStatus]Result
    public wait_output(self ref) [CommandOutput]Result
    public try_wait(self ref) [[ExitStatus]Option]Result
    public take_stdin_pipe(self ref) [StdinPipe]Option
    public take_stdout_pipe(self ref) [StdoutPipe]Option
    public take_stderr_pipe(self ref) [StderrPipe]Option
}

given IoRedirect as ToString {
    public to_string(self ref) String
}
```
