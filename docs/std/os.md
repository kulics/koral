# std.os API

## 概述
本页摘录模块 `std.os` 的公开 API（仅保留声明语法），按自由函数 / trait / 类型 / given 组织。

## 自由函数
```koral
public let create_dir(path Path) [Void]Result

public let create_dir_all(path Path) [Void]Result

public let remove_dir(path Path) [Void]Result

public let remove_dir_all(path Path) [Void]Result

public let read_dir(path Path) [[DirEntry]List]Result

public let walk_dir(path Path, visitor [DirEntry, WalkAction]Func) [Void]Result

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

public let absolute_path(path Path) [Path]Result

public let canonicalize_path(path Path) [Path]Result

public let open_file(path Path, mode OpenMode) [File]Result

public let create_file(path Path) [File]Result

public let read_file_info(path Path) [FileInfo]Result

public let read_symlink_info(path Path) [FileInfo]Result

public let set_permissions(path Path, perm Permission) [Void]Result

public let create_hard_link(src Path, dst Path) [Void]Result

public let create_symlink(src Path, dst Path) [Void]Result

public let read_symlink(path Path) [Path]Result

public let truncate_file(path Path, size UInt64) [Void]Result

public let create_temp_file(dir Path, prefix String) [File]Result

public let path_separator() String

public let path_list_separator() String
```

## trait
（无）

## 类型
```koral
public type DirEntry

public type WalkAction {
    Continue(),
    SkipDir(),
    Stop(),
    Error(err Error ref),
}

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

## given
```koral
given DirEntry {
    public name(self) String
    public path(self) Path
    public file_type(self) FileType
    public is_file(self) Bool
    public is_dir(self) Bool
    public is_symlink(self) Bool
    public info(self) [FileInfo]Result
    public to_string(self) String
}

given File {
    public path(self) Path
    public info(self) [FileInfo]Result
    public sync(self) [Void]Result
    public lock_exclusive(self) [Void]Result
    public lock_shared(self) [Void]Result
    public try_lock_exclusive(self) [Bool]Result
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
    public seek(self, pos io.SeekOrigin) [UInt64]Result
}

given FileType {
    public is_file(self) Bool
    public is_dir(self) Bool
    public is_symlink(self) Bool
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
    public to_string(self) String
}

given FileInfo {
    public file_size(self) UInt64
    public file_type(self) FileType
    public permissions(self) Permission
    public modified_time(self) time.DateTime
    public accessed_time(self) time.DateTime
    public created_time(self) time.DateTime
    public is_file(self) Bool
    public is_dir(self) Bool
    public is_symlink(self) Bool
    public to_string(self) String
}

given Permission Eq {
    public equals(self, other Permission) Bool
}

given Path {
    public exists(self) Bool
    public is_file(self) Bool
    public is_dir(self) Bool
    public is_symlink(self) Bool
}

given Path {
    public new(s String) Path
    public is_empty(self) Bool
    public is_absolute(self) Bool
    public join(self, name String) Path
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

given Path Hashable {
    public hash(self) UInt
}

given Path ToString {
    public to_string(self) String
}
```
