# Std.Os API

## Overview
This page lists the public API of module `Std.Os` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let create_dir(path Path) [Void]Result

public let create_dir_all(path Path) [Void]Result

public let remove_dir(path Path) [Void]Result

public let remove_dir_all(path Path) [Void]Result

public let read_dir(path Path) [DirIterator]Result

public let walk_dir(path Path) [WalkDirIterator]Result

public let create_temp_dir(dir Path, prefix String) [Path]Result

public let env(name String) [String]Option

public let set_env(name String, value String) [Void]Result

public let remove_env(name String) [Void]Result

public let all_env() [[String, String]Pair]List

public let home_dir() [Path]Option

public let temp_dir() Path

public let current_dir() [Path]Result

public let set_current_dir(path Path) [Void]Result

public let hostname() [String]Result

public let current_exe() [Path]Result

public let read_file(path Path) [[UInt8]List]Result

public let write_file(path Path, bytes [UInt8]List) [Void]Result

public let append_file(path Path, bytes [UInt8]List) [Void]Result

public let read_text_file(path Path) [String]Result

public let write_text_file(path Path, content String) [Void]Result

public let append_text_file(path Path, content String) [Void]Result

public let copy_file(src Path, dst Path) [Void]Result

public let remove_file(path Path) [Void]Result

public let rename_path(src Path, dst Path) [Void]Result

public let path_exist(path Path) Bool

public let absolute_path(path Path) [Path]Result

public let canonicalize_path(path Path) [Path]Result

public let open_file(path Path, mode OpenMode) [File]Result

public let create_file(path Path) [File]Result

public let file_info(path Path) [FileInfo]Result

public let symlink_info(path Path) [FileInfo]Result

public let set_permissions(path Path, perm Permission) [Void]Result

public let create_hard_link(src Path, dst Path) [Void]Result

public let create_symlink(src Path, dst Path) [Void]Result

public let read_symlink(path Path) [Path]Result

public let truncate_file(path Path, size UInt64) [Void]Result

public let create_temp_file(dir Path, prefix String) [File]Result

public let path_separator() String

public let path_list_separator() String
```

## Traits
(none)

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
    public read(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
}

given File Writer {
    public write(self, src [UInt8]List, range [UInt]Range) [UInt]Result
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

given Path {
    public new(s String) Path
    public is_empty(self) Bool
    public is_absolute(self) Bool
    public join(self, path String) Path
    public dir_name(self) Path
    public base_name(self) String
    public ext_name(self) String
    public with_ext_name(self, ext String) Path
    public with_base_name(self, name String) Path
    public normalize(self) Path
    public components(self) [String]List
    public relative_to(self, base Path) [Path]Result
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
