# fmt tests

该目录用于 `koralfmt` 的稳定回归测试，避免再使用临时文件做手工验证。

## 结构

- `cases/*.koral`：输入样例
- `cases/*.expected`：格式化成功场景的期望输出
- `cases/*.error`：格式化失败场景的期望错误子串

## 运行方式

使用 koral 编译器编译并运行 `test_fmt.koral`：

```bash
# 编译
compiler/.build/debug/koralc build toolchain/koralfmt/test_fmt.koral -o toolchain/koralfmt/build

# 运行测试
toolchain/koralfmt/build/test_fmt.exe
```

所有测试通过 koral 自身的测试框架（`test_fmt.koral`）运行，无需 Go 环境。