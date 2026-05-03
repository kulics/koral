# Std.Os API

## Overview
This page lists the public API of module `Std.Os` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let [T IntoPath]create_dir(path T) [Void]Result

public let [T IntoPath]create_dir_all(path T) [Void]Result

public let [T IntoPath]remove_dir(path T) [Void]Result

public let [T IntoPath]remove_dir_all(path T) [Void]Result

public let [T IntoPath]read_dir(path T) [DirIterator]Result

public let [T IntoPath]walk_dir(path T) [WalkDirIterator]Result

public let [T IntoPath]create_temp_dir(dir T, prefix: String) [Path]Result

public let env(name String) [String]Option

public let set_env(name String, value String) [Void]Result

public let remove_env(name String) [Void]Result

public let all_env() [[String, String]Pair]List

public let home_dir() [Path]Option

public let temp_dir() Path

public let current_dir() [Path]Result

public let [T IntoPath]set_current_dir(path T) [Void]Result

public let hostname() [String]Result

public let current_exe() [Path]Result

public let [T IntoPath]read_file(path T) [[UInt8]List]Result

public let [T IntoPath]write_file(path T, content: [UInt8]List) [Void]Result

public let [T IntoPath]append_file(path T, content: [UInt8]List) [Void]Result

public let [T IntoPath]read_text_file(path T) [String]Result

public let [T IntoPath]write_text_file(path T, content: String) [Void]Result

public let [T IntoPath]append_text_file(path T, content: String) [Void]Result

public let [T1 IntoPath, T2 IntoPath]copy_file(src T1, to: T2) [Void]Result

public let [T IntoPath]remove_file(path T) [Void]Result

public let [T1 IntoPath, T2 IntoPath]rename_path(src T1, to: T2) [Void]Result

public let [T IntoPath]path_exist(path T) Bool

public let [T IntoPath]absolute_path(path T) [Path]Result

public let [T IntoPath]canonicalize_path(path T) [Path]Result

public let [T IntoPath]open_file(path T, mode OpenMode) [File]Result

public let [T IntoPath]create_file(path T) [File]Result

public let [T IntoPath]file_info(path T) [FileInfo]Result

public let [T IntoPath]symlink_info(path T) [FileInfo]Result

public let [T IntoPath]set_permissions(path T, perm Permission) [Void]Result

public let [T1 IntoPath, T2 IntoPath]create_hard_link(link T1, to: T2) [Void]Result

public let [T1 IntoPath, T2 IntoPath]create_symlink(link T1, to: T2) [Void]Result

public let [T IntoPath]read_symlink(path T) [Path]Result

public let [T IntoPath]truncate_file(path T, size UInt64) [Void]Result

public let [T IntoPath]create_temp_file(dir T, prefix: String) [File]Result

public let path_separator() String

public let path_list_separator() String
```

## Traits
```koral
public trait IntoPath {
    into_path(self) Path
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
    public name(self ref) String
    public path(self ref) Path
    public file_type(self ref) FileType
    public is_file(self ref) Bool
    public is_dir(self ref) Bool
    public is_symlink(self ref) Bool
    public info(self ref) [FileInfo]Result
}

given DirEntry ToString {
    public to_string(self ref) String
}

given DirIterator [DirEntry]Iterator {
    public next(self mut ref) [DirEntry]Option
}

given WalkDirIterator [DirEntry]Iterator {
    public next(self mut ref) [DirEntry]Option
}

given File {
    public fd(self ref) Int
    public path(self ref) Path
    public info(self ref) [FileInfo]Result
    public sync(self ref) [Void]Result
    public lock(self ref) [Void]Result
    public lock_shared(self ref) [Void]Result
    public try_lock(self ref) [Bool]Result
    public try_lock_shared(self ref) [Bool]Result
    public unlock(self ref) [Void]Result
}

given File Reader {
    public read(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
}

given File Writer {
    public write(self ref, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self ref) [Void]Result
}

given File Seeker {
    public seek(self ref, pos Io.SeekOrigin) [UInt64]Result
}

given FileType {
    public is_file(self ref) Bool
    public is_dir(self ref) Bool
    public is_symlink(self ref) Bool
}

given FileType ToString {
    public to_string(self ref) String
}

given Permission {
    public from_mode(mode UInt32) Permission
    public mode(self ref) UInt32
    public has_owner_read(self ref) Bool
    public has_owner_write(self ref) Bool
    public has_owner_exec(self ref) Bool
    public has_group_read(self ref) Bool
    public has_group_write(self ref) Bool
    public has_group_exec(self ref) Bool
    public has_other_read(self ref) Bool
    public has_other_write(self ref) Bool
    public has_other_exec(self ref) Bool
    public readonly() Permission
    public read_write() Permission
    public executable() Permission
}

given Permission ToString {
    public to_string(self ref) String
}

given FileInfo {
    public file_size(self ref) UInt64
    public file_type(self ref) FileType
    public permissions(self ref) Permission
    public modified_time(self ref) Time.DateTime
    public accessed_time(self ref) Time.DateTime
    public created_time(self ref) Time.DateTime
    public is_file(self ref) Bool
    public is_dir(self ref) Bool
    public is_symlink(self ref) Bool
}

given FileInfo ToString {
    public to_string(self ref) String
}

given Permission Eq {
    public equals(self, other Permission) Bool
}

given String IntoPath {
    public into_path(self) Path
}

given Path IntoPath {
    public into_path(self) Path
}

given Path {
    public is_empty(self ref) Bool
    public is_absolute(self ref) Bool
    public [T IntoPath]join(self ref, path T) Path
    public dir_name(self ref) Path
    public base_name(self ref) String
    public ext_name(self ref) String
    public stem_name(self ref) String
    public with_ext_name(self ref, ext String) Path
    public with_base_name(self ref, name String) Path
    public normalize(self ref) Path
    public components(self ref) [String]List
    public starts_with(self ref, prefix Path) Bool
    public ends_with(self ref, suffix Path) Bool
    public [T IntoPath]relative_to(self ref, base T) [Path]Result
}

given Path Eq {
    public equals(self, other Path) Bool
}

given Path Hash {
    public hash(self) UInt
}

given Path ToString {
    public to_string(self ref) String
}
```
