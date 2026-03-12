# Std.Proc API

## Overview
This page lists the public API of module `Std.Proc` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let current_pid() UInt32

public let send_process_signal(pid UInt32, signal Int) [Void]Result

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
    public set_current_dir(self, path Path) Command
    public set_stdin(self, cfg IoRedirect) Command
    public set_stdout(self, cfg IoRedirect) Command
    public set_stderr(self, cfg IoRedirect) Command
    public spawn(self) [Process]Result
    public run(self) [ExitStatus]Result
    public run_output(self) [CommandOutput]Result
}

given CommandOutput {
    public is_success(self) Bool
    public code(self) [Int]Option
}

given CommandOutput ToString {
    public to_string(self) String
}

given ExitStatus {
    public code(self) [Int]Option
    public is_success(self) Bool
    public signal(self) [Int]Option
}

given ExitStatus ToString {
    public to_string(self) String
}

given StdinPipe Writer {
    public write(self, src [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self) [Void]Result
}

given StdoutPipe Reader {
    public read(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
}

given StderrPipe Reader {
    public read(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
}

given Process {
    public pid(self) UInt32
    public wait(self) [ExitStatus]Result
    public wait_output(self) [CommandOutput]Result
    public try_wait(self) [[ExitStatus]Option]Result
    public take_stdin_pipe(self) [StdinPipe]Option
    public take_stdout_pipe(self) [StdoutPipe]Option
    public take_stderr_pipe(self) [StderrPipe]Option
}

given IoRedirect ToString {
    public to_string(self) String
}
```
