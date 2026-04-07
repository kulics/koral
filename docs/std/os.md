# Std.Os API

## Overview
This page lists the public API of module `Std.Os` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let [T ToPath]create_dir(path T) [Void]Result

public let [T ToPath]create_dir_all(path T) [Void]Result

public let [T ToPath]remove_dir(path T) [Void]Result

public let [T ToPath]remove_dir_all(path T) [Void]Result

public let [T ToPath]read_dir(path T) [DirIterator]Result

public let [T ToPath]walk_dir(path T) [WalkDirIterator]Result

public let [T ToPath]create_temp_dir(dir T, prefix: String) [Path]Result

public let env(name String) [String]Option

public let set_env(name String, value String) [Void]Result

public let remove_env(name String) [Void]Result

public let all_env() [[String, String]Pair]List

public let home_dir() [Path]Option

public let temp_dir() Path

public let current_dir() [Path]Result

public let [T ToPath]set_current_dir(path T) [Void]Result

public let hostname() [String]Result

public let current_exe() [Path]Result

public let [T ToPath]read_file(path T) [[UInt8]List]Result

public let [T ToPath]write_file(path T, content: [UInt8]List) [Void]Result

public let [T ToPath]append_file(path T, content: [UInt8]List) [Void]Result

public let [T ToPath]read_text_file(path T) [String]Result

public let [T ToPath]write_text_file(path T, content: String) [Void]Result

public let [T ToPath]append_text_file(path T, content: String) [Void]Result

public let [T1 ToPath, T2 ToPath]copy_file(src T1, to: T2) [Void]Result

public let [T ToPath]remove_file(path T) [Void]Result

public let [T1 ToPath, T2 ToPath]rename_path(src T1, to: T2) [Void]Result

public let [T ToPath]path_exist(path T) Bool

public let [T ToPath]absolute_path(path T) [Path]Result

public let [T ToPath]canonicalize_path(path T) [Path]Result

public let [T ToPath]open_file(path T, mode OpenMode) [File]Result

public let [T ToPath]create_file(path T) [File]Result

public let [T ToPath]file_info(path T) [FileInfo]Result

public let [T ToPath]symlink_info(path T) [FileInfo]Result

public let [T ToPath]set_permissions(path T, perm Permission) [Void]Result

public let [T1 ToPath, T2 ToPath]create_hard_link(link T1, to: T2) [Void]Result

public let [T1 ToPath, T2 ToPath]create_symlink(link T1, to: T2) [Void]Result

public let [T ToPath]read_symlink(path T) [Path]Result

public let [T ToPath]truncate_file(path T, size UInt64) [Void]Result

public let [T ToPath]create_temp_file(dir T, prefix: String) [File]Result

public let path_separator() String

public let path_list_separator() String
```

## Traits
```koral
public trait ToPath {
    to_path(self) Path
}
```

## Types
```koral
public type DirEntry

public type DirIterator

public type WalkDirIterator

public type OpenMode {
    Read(),
    Write(),
    Create(),
    Append(),
    ReadWrite(),
}

public type File

public type FileType {
    RegularFile(),
    Directory(),
    Symlink(),
    Other(),
}

public type Permission

public type FileInfo

public type Path
```

## Given Implementations
```koral
given DirEntry {
    public name(self) String
    public path(self) Path
    public file_type(self) FileType
    public is_file(self) Bool
    public is_dir(self) Bool
    public is_symlink(self) Bool
    public info(self) [FileInfo]Result
}

given DirEntry ToString {
    public to_string(self) String
}

given DirIterator [DirEntry]Iterator {
    public next(self ref) [DirEntry]Option
}

given WalkDirIterator [DirEntry]Iterator {
    public next(self ref) [DirEntry]Option
}

given File {
    public fd(self) Int
    public path(self) Path
    public info(self) [FileInfo]Result
    public sync(self) [Void]Result
    public lock(self) [Void]Result
    public lock_shared(self) [Void]Result
    public try_lock(self) [Bool]Result
    public try_lock_shared(self) [Bool]Result
    public unlock(self) [Void]Result
}

given File Reader {
    public read(self, into: [UInt8]List ref, range [UInt]Range) [UInt]Result
}

given File Writer {
    public write(self, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self) [Void]Result
}

given File Seeker {
    public seek(self, pos Io.SeekOrigin) [UInt64]Result
}

given FileType {
    public is_file(self) Bool
    public is_dir(self) Bool
    public is_symlink(self) Bool
}

given FileType ToString {
    public to_string(self) String
}

given Permission {
    public from_mode(mode UInt32) Permission
    public mode(self) UInt32
    public has_owner_read(self) Bool
    public has_owner_write(self) Bool
    public has_owner_exec(self) Bool
    public has_group_read(self) Bool
    public has_group_write(self) Bool
    public has_group_exec(self) Bool
    public has_other_read(self) Bool
    public has_other_write(self) Bool
    public has_other_exec(self) Bool
    public readonly() Permission
    public read_write() Permission
    public executable() Permission
}

given Permission ToString {
    public to_string(self) String
}

given FileInfo {
    public file_size(self) UInt64
    public file_type(self) FileType
    public permissions(self) Permission
    public modified_time(self) Time.DateTime
    public accessed_time(self) Time.DateTime
    public created_time(self) Time.DateTime
    public is_file(self) Bool
    public is_dir(self) Bool
    public is_symlink(self) Bool
}

given FileInfo ToString {
    public to_string(self) String
}

given Permission Eq {
    public equals(self, other Permission) Bool
}

given String ToPath {
    public to_path(self) Path
}

given Path ToPath {
    public to_path(self) Path
}

given Path {
    public is_empty(self) Bool
    public is_absolute(self) Bool
    public [T ToPath]join(self, path T) Path
    public dir_name(self) Path
    public base_name(self) String
    public ext_name(self) String
    public stem_name(self) String
    public with_ext_name(self, ext String) Path
    public with_base_name(self, name String) Path
    public normalize(self) Path
    public components(self) [String]List
    public starts_with(self, prefix Path) Bool
    public ends_with(self, suffix Path) Bool
    public [T ToPath]relative_to(self, base T) [Path]Result
}

given Path Eq {
    public equals(self, other Path) Bool
}

given Path Hash {
    public hash(self) UInt
}

given Path ToString {
    public to_string(self) String
}
```
