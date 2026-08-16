# Std.Os API

## Overview
This page lists the public API of module `Std.Os` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let create_dir[T IntoPath](path T) Result[Void]

public let create_dir_all[T IntoPath](path T) Result[Void]

public let remove_dir[T IntoPath](path T) Result[Void]

public let remove_dir_all[T IntoPath](path T) Result[Void]

public let read_dir[T IntoPath](path T) Result[DirIterator]

public let walk_dir[T IntoPath](path T) Result[WalkDirIterator]

public let create_temp_dir[T IntoPath](dir T, prefix: String) Result[Path]

public let env(name String) Option[String]

public let set_env(name String, value String) Result[Void]

public let remove_env(name String) Result[Void]

public let all_env() List[Pair[String, String]]

public let home_dir() Option[Path]

public let temp_dir() Path

public let current_dir() Result[Path]

public let set_current_dir[T IntoPath](path T) Result[Void]

public let hostname() Result[String]

public let current_exe() Result[Path]

public let read_file[T IntoPath](path T) Result[List[UInt8]]

public let write_file[T IntoPath](path T, content: List[UInt8]) Result[Void]

public let append_file[T IntoPath](path T, content: List[UInt8]) Result[Void]

public let read_text_file[T IntoPath](path T) Result[String]

public let write_text_file[T IntoPath](path T, content: String) Result[Void]

public let append_text_file[T IntoPath](path T, content: String) Result[Void]

public let copy_file[T1 IntoPath, T2 IntoPath](src T1, to: T2) Result[Void]

public let remove_file[T IntoPath](path T) Result[Void]

public let rename_path[T1 IntoPath, T2 IntoPath](src T1, to: T2) Result[Void]

public let path_exist[T IntoPath](path T) Bool

public let absolute_path[T IntoPath](path T) Result[Path]

public let canonicalize_path[T IntoPath](path T) Result[Path]

public let open_file[T IntoPath](path T, mode OpenMode) Result[File]

public let create_file[T IntoPath](path T) Result[File]

public let file_info[T IntoPath](path T) Result[FileInfo]

public let symlink_info[T IntoPath](path T) Result[FileInfo]

public let set_permissions[T IntoPath](path T, perm Permission) Result[Void]

public let create_hard_link[T1 IntoPath, T2 IntoPath](link T1, to: T2) Result[Void]

public let create_symlink[T1 IntoPath, T2 IntoPath](link T1, to: T2) Result[Void]

public let read_symlink[T IntoPath](path T) Result[Path]

public let truncate_file[T IntoPath](path T, size UInt64) Result[Void]

public let create_temp_file[T IntoPath](dir T, prefix: String) Result[File]

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
    public name(*self) String
    public path(*self) Path
    public file_type(*self) FileType
    public is_file(*self) Bool
    public is_dir(*self) Bool
    public is_symlink(*self) Bool
    public info(*self) Result[FileInfo]
}

given DirEntry as ToString {
    public to_string(*self) String
}

given DirIterator as Iterator[DirEntry] {
    public next(*mut self) Option[DirEntry]
}

given WalkDirIterator as Iterator[DirEntry] {
    public next(*mut self) Option[DirEntry]
}

given File {
    public fd(*self) Int
    public path(*self) Path
    public info(*self) Result[FileInfo]
    public sync(*self) Result[Void]
    public lock(*self) Result[Void]
    public lock_shared(*self) Result[Void]
    public try_lock(*self) Result[Bool]
    public try_lock_shared(*self) Result[Bool]
    public unlock(*self) Result[Void]
}

given File as Reader {
    public read(*self, into: *mut List[UInt8], range Range[UInt]) Result[UInt]
}

given File as Writer {
    public write(*self, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(*self) Result[Void]
}

given File as Seeker {
    public seek(*self, pos SeekOrigin) Result[UInt64]
}

given FileType {
    public is_file(*self) Bool
    public is_dir(*self) Bool
    public is_symlink(*self) Bool
}

given FileType as ToString {
    public to_string(*self) String
}

given Permission {
    public from_mode(mode UInt32) Permission
    public mode(*self) UInt32
    public has_owner_read(*self) Bool
    public has_owner_write(*self) Bool
    public has_owner_exec(*self) Bool
    public has_group_read(*self) Bool
    public has_group_write(*self) Bool
    public has_group_exec(*self) Bool
    public has_other_read(*self) Bool
    public has_other_write(*self) Bool
    public has_other_exec(*self) Bool
    public readonly() Permission
    public read_write() Permission
    public executable() Permission
}

given Permission as ToString {
    public to_string(*self) String
}

given FileInfo {
    public file_size(*self) UInt64
    public file_type(*self) FileType
    public permissions(*self) Permission
    public modified_time(*self) DateTime
    public accessed_time(*self) DateTime
    public created_time(*self) DateTime
    public is_file(*self) Bool
    public is_dir(*self) Bool
    public is_symlink(*self) Bool
}

given FileInfo as ToString {
    public to_string(*self) String
}

given Permission as Eq {
    public equals(self, other Permission) Bool
}

given String as IntoPath {
    public into_path(self) Path
}

given Path as IntoPath {
    public into_path(self) Path
}

given Path {
    public is_empty(*self) Bool
    public is_absolute(*self) Bool
    public join[T IntoPath](*self, path T) Path
    public dir_name(*self) Path
    public base_name(*self) String
    public ext_name(*self) String
    public stem_name(*self) String
    public with_ext_name(*self, ext String) Path
    public with_base_name(*self, name String) Path
    public normalize(*self) Path
    public components(*self) List[String]
    public starts_with(*self, prefix Path) Bool
    public ends_with(*self, suffix Path) Bool
    public relative_to[T IntoPath](*self, base T) Result[Path]
}

given Path as Eq {
    public equals(self, other Path) Bool
}

given Path as Hash {
    public hash(self) UInt
}

given Path as ToString {
    public to_string(*self) String
}
```
