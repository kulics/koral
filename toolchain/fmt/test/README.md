# fmt tests (Go)

该目录用于 `koralfmt` 的稳定回归测试，避免再使用临时文件做手工验证。

## 结构

- `cases/*.koral`：输入样例
- `cases/*.expected`：格式化成功场景的期望输出
- `cases/*.error`：格式化失败场景的期望错误子串

## 运行方式

```bash
cd fmt/test
go run ./cmd/preparefmt
go test ./...
```

单用例调试：

```bash
go test ./... -run TestFmtCaseValidGivenWhen
```

说明：测试不会自动构建 `koralfmt`，执行前需要先运行 `go run ./cmd/preparefmt`。

`preparefmt` 默认检测到 `bin/koralfmt(.exe)` 已存在时会直接跳过；如需强制重建，使用：

```bash
go run ./cmd/preparefmt --force
```

