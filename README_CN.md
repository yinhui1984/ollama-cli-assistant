[English](README.md) | [中文](README_CN.md)

# ollama-cli-assistant

一个面向 macOS 的 CLI 命令编译器：把自然语言转换为一条可直接执行的 zsh 命令。

本项目面向日常终端使用，强调严格输出契约，以及 Linux->macOS 的剪贴板兼容纠偏能力。

## 项目价值

- 严格单行命令输出（stdout 不混入解释）
- 默认优先 macOS 原生命令路由（`mdfind`、`lsof`、`shasum` 等）
- 面向 Foundry/Web3 的命令生成（`forge`、`cast`、`anvil`）
- 针对常见 Linux-only 参数的 macOS 剪贴板修正
- 兼容修正具备可复现集成测试

与“直接调用通用 LLM”相比的关键差异：

- 本仓库提供了自定义命令模型（`cli-assistant`），内置严格命令输出契约。
- 运行时包装器（`cli-assistant.sh`）提供了普通模型调用没有的工程化保障。

## 目录结构

- `cli-assistant.sh`：主入口（本地 Ollama 模型）
- `cli-assistant-deepseek.sh`：对比基线脚本（DeepSeek API 路径）
- `context.md`：持久化上下文说明（环境变量与偏好）
- `model/ollama-cli-assistant.Modelfile`：模型契约与 few-shot 示例
- `model/01_interactive_test.sh`：交互式手工测试
- `model/02_clean_model.sh`：非交互清理本地模型
- `model/03_batch_test.sh`：批量测试脚本
- `model/04_cases_holdout.txt`：默认批量测试集
- `test_clipboard_fix.sh`：剪贴板兼容集成测试
- `Makefile`：统一命令入口

## 依赖要求

- macOS (Darwin)
- `zsh`
- 已安装并运行 [Ollama](https://ollama.com/)
- 本地可用基础模型（默认：`qwen2.5-coder:7b`）

Foundry 工具链（用于 Web3 提示）：

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

建议安装 GNU 工具增强兼容修正：

```bash
brew install coreutils gnu-sed grep findutils
```

将提供：`gdate`、`gsed`、`ggrep`、`gfind`、`greadlink`、`gstat`。

## 环境变量

按你的工作流设置：

```bash
export RPC_ETH="https://rpc.ankr.com/eth"
export APIKEY_DEEPSEEK="sk-demo-deepseek-key"   # 仅 cli-assistant-deepseek.sh 需要
```

当上下文中使用该变量时，多数 Foundry/Web3 提示会采用 `RPC_ETH`。

## 双层架构

1. 自定义模型层（`model/ollama-cli-assistant.Modelfile`）
- 定义命令输出契约、路由规则与领域行为（macOS + Foundry/Web3）
- 构建为本地模型 `cli-assistant`

2. 运行时助手层（`cli-assistant.sh`）
- 注入运行时与上下文信息
- 将模型输出规整为一条可执行命令
- 在 macOS 上做“仅剪贴板”兼容修正
- 保持 stdout 原样，便于审计；复制内容可直接执行

## 快速开始

### 第一步：构建自定义模型（必需）

```bash
cd <path_to_ollama-cli-assistant>
make create
```

### 第二步：使用助手运行时

```bash
./cli-assistant.sh "check whether port 8545 is listening"
```

安全提示：

- 执行前请先审阅生成命令，尤其是有副作用的操作。

交互模式：

```bash
./cli-assistant.sh -i
```

为什么模型构建后仍然需要运行时：

- 仅模型质量无法覆盖 shell/runtime 边界问题
- 包装器提供确定性的命令提取和剪贴板安全修正
- 这是日常可用性的关键工程边界

## Make 目标

```bash
make help
make create
make batch
make batch-cases CASES=./model/04_cases_holdout.txt
make clipboard-fix
make clean-model
make recreate
```

## 示例环境（真实运行）

来自本仓库的一次真实运行：

- macOS：`15.7.2 (24G325)`
- shell：`zsh 5.9`
- Ollama：`0.15.4`
- model：`cli-assistant:latest`
- GNU 工具可用：`gdate`、`gsed`、`ggrep`、`greadlink`、`gstat`、`gfind`

## 示例输出（真实运行）

### 基础/macOS

Command:

```bash
./cli-assistant.sh "find app named Visual Studio Code"
```

Output:

```bash
mdfind 'Visual Studio Code.app'
```

Command:

```bash
./cli-assistant.sh "check whether port 8545 is listening"
```

Output:

```bash
lsof -nP -iTCP:8545 -sTCP:LISTEN
```

Command:

```bash
./cli-assistant.sh "list all listening TCP ports"
```

Output:

```bash
lsof -nP -iTCP -sTCP:LISTEN
```

Command:

```bash
./cli-assistant.sh "compute sha256 of README"
```

Output:

```bash
shasum -a 256 README.md
```

### Foundry/Web3

Command:

```bash
./cli-assistant.sh "query current block number"
```

Output:

```bash
cast block-number --rpc-url $RPC_ETH
```

Command:

```bash
./cli-assistant.sh "fork mainnet at block 18000000"
```

Output:

```bash
anvil --fork-url $RPC_ETH --fork-block-number 18000000
```

Command:

```bash
./cli-assistant.sh "compile only and show contract sizes"
```

Output:

```bash
forge build --sizes
```

Command:

```bash
./cli-assistant.sh "run only test_Deposit in test/Bridge.t.sol with full trace"
```

Output:

```bash
forge test --match-path test/Bridge.t.sol --match-test test_Deposit -vvvv
```

## 剪贴板兼容修正（Linux -> macOS）

`cli-assistant.sh` 保持 stdout 原样（便于审计），但会对复制到剪贴板的命令做 macOS 兼容修正。

默认开启：

```bash
CLIA_CLIPBOARD_FIX=1
```

调试时关闭：

```bash
CLIA_CLIPBOARD_FIX=0
```

真实示例：

- stdout：

```bash
echo "0x65ff4b03" | xxd -r -p | date -f - +"%Y-%m-%d %H:%M:%S"
```

- 剪贴板（`pbpaste`）：

```bash
gdate -d "@$((16#65ff4b03))" +"%Y-%m-%d %H:%M:%S"
```

当前覆盖规则：

- `date -d` 及常见十六进制时间戳转换
- `sed -i`
- `grep -P`（有 `ggrep` 时优先）
- `readlink -f`
- `stat -c`
- `find -printf`
- `xargs -r` 的安全子集改写

安全边界：潜在破坏性命令不会自动改写。

## 测试

### 1) 模型批量测试

```bash
make batch
make batch-cases CASES=./model/04_cases_holdout.txt
```

### 2) 剪贴板集成测试

```bash
make clipboard-fix
```

当前结果：

- `RESULT: PASS (10/10 cases)`
- 双模式运行：`with_gnu` 与 `no_gnu`

## 对比基线脚本

仓库内保留 `cli-assistant-deepseek.sh` 作为对比基线路径。

用于和本地 Ollama 路径对比行为/风格：

```bash
./cli-assistant-deepseek.sh "query current block number"
```

对比建议：

- `cli-assistant.sh` 是本仓库主生产路径
- `cli-assistant-deepseek.sh` 用于 benchmark/baseline
- 用同一批 prompt 与输出记录做证据化对比
- `cli-assistant-deepseek.sh` 依赖 `APIKEY_DEEPSEEK` 与外部 API 可用性

同题快照（来自已采集输出）：

| Prompt | `cli-assistant.sh` (stdout -> clipboard) | `cli-assistant-deepseek.sh` |
|---|---|---|
| `0x65ff4b03 to datetime` | `echo "0x65ff4b03" \| xxd -r -p \| date -f - +"%Y-%m-%d %H:%M:%S"` -> `gdate -d "@$((16#65ff4b03))" +"%Y-%m-%d %H:%M:%S"` | `cast block 0x65ff4b03 --rpc-url $RPC_ETH --field timestamp \| xargs -I {} date -r {}` |
| `grep -P 'a.*b' sample.txt` | `grep -P 'a.*b' sample.txt` -> `**ggrep -P 'a.*b' sample.txt**` | `**rg -P 'a.*b' sample.txt**` |
| `readlink -f ./foo/bar` | `readlink -f ./foo/bar` -> `**greadlink -f ./foo/bar**` | `readlink -f ./foo/bar` |
| `echo -e 'a\nb\n' \| xargs -r -n1 echo` | `echo -e 'a\nb\n' \| xargs **-r** -n1 echo` -> `echo -e 'a\nb\n' \| xargs -n1 echo` | `echo -e 'a\nb\n' \| xargs **-r** -n1 echo` |

解释：

- 主脚本保留可审计 stdout，并在复制时做 macOS 纠偏
- 基线脚本适合做 prompt 路径对比，但不包含同等剪贴板兼容层

## 配置

- 默认模型：`cli-assistant`
- 覆盖模型：

```bash
./cli-assistant.sh -m cli-assistant "check whether port 8545 is listening"
```

- Inline context：

```bash
./cli-assistant.sh --context 'Use "$RPC_ETH" as Ethereum mainnet RPC' "query current block number"
```

- Context file：

```bash
./cli-assistant.sh --context-file ./context.md "query current block number"
```

### `context.md` 基础示例（推荐）

`context.md` 是持久化偏好和环境变量路由的核心功能。

示例：

```markdown
# Context Instructions

- Use "$RPC_ETH" as Ethereum mainnet RPC
- Use "$APIKEY_DEEPSEEK" as DeepSeek API key

# Optional Notes

- Put long-lived preferences and constraints here, not one-off tasks.
```

典型效果：

- Prompt：`query current block number`
- Output：`cast block-number --rpc-url $RPC_ETH`

这样可以避免每次 prompt 都重复写同样约束。

## 已知限制

- Linux-only 参数差异无法在所有复杂命令形态下 100% 自动转换
- 复杂正则与复杂 shell 结构可能仍需手工审阅
- 剪贴板纠偏策略默认偏保守，优先安全

## 许可证

MIT，见 [`LICENSE`](LICENSE)。
