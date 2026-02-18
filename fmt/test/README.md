# fmt tests (Go)

该目录用于 `koralfmt` 的稳定回归测试，避免再使用临时文件做手工验证。

## 结构

- `cases/*.koral`：输入样例
- `cases/*.expected`：格式化成功场景的期望输出
- `cases/*.error`：格式化失败场景的期望错误子串

## 运行方式

```bash
cd fmt/test
go test ./...
```

单用例调试：

```bash
go test ./... -run 'TestFmtCases/valid_given_when'
```

说明：测试会调用仓库根目录下的 `bin/koralc(.exe)` 自动构建 `bin/koralfmt(.exe)`，再逐个执行 `cases`。

