# Codex 配置上传文件到百度网盘

本文记录在 Windows 上通过 Codex 的本地 MCP（STDIO）服务，将本地文件上传到百度网盘的完整配置过程。

## 一、工作原理

本方案使用百度网盘 MCP 上传程序运行在本机的 **STDIO 模式**：

```text
Codex → 本地 uv/Python MCP 程序 → 百度网盘开放 API
```

因为本地 MCP 程序运行在你的电脑上，所以它可以读取例如下面的本地文件：

```text
C:\Users\Leo\Documents\report.pdf
```

远程 SSE 服务无法直接访问你电脑上的本地路径，因此上传本地文件必须使用 STDIO 模式。

## 二、准备条件

需要准备以下内容：

1. Windows 电脑上的 Codex。
2. 百度账号及百度网盘。
3. 百度网盘 Access Token。
4. `uv` 或 Python 运行环境。
5. 百度官方 MCP 上传程序。

百度网盘 MCP 项目：

- [baidu-netdisk/mcp](https://github.com/baidu-netdisk/mcp)

## 三、安装 uv

### 方法一：使用 WinGet

在 PowerShell 中执行：

```powershell
winget install --id=astral-sh.uv -e
```

安装完成后，关闭并重新打开 PowerShell，检查：

```powershell
uv --version
Get-Command uv
```

本机实际检测到的 `uv.exe` 路径为：

```text
C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe\uv.exe
```

不同电脑的路径可能不同。不要直接照抄此路径，优先使用 `Get-Command uv` 查看实际路径。

## 四、下载百度网盘 MCP 程序

推荐将官方仓库下载到 `C:\Tools`：

```powershell
New-Item -ItemType Directory -Force -Path "C:\Tools" | Out-Null
git clone https://github.com/baidu-netdisk/mcp.git `
  "C:\Tools\baidu-netdisk-mcp"
```

上传程序所在目录应为：

```text
C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk
```

确认关键文件存在：

```powershell
Test-Path "C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk\fileupload_tool.py"
```

返回 `True` 即表示目录正确。

注意：

- `C:\Tools\baidu-netdisk-mcp` 是本地代码目录，不是百度网盘云端目录。
- `C:\Tools\netdisk-mcp-server-stdio` 只是示例占位路径，不需要建立空目录。
- 真正的上传脚本文件名是 `fileupload_tool.py`。

如果电脑没有 Git，也可以从 GitHub 下载 ZIP，解压后确保目录结构仍然包含：

```text
C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk\fileupload_tool.py
```

## 五、获取百度网盘 Access Token

`BAIDU_NETDISK_ACCESS_TOKEN` 不是百度网盘普通设置页面中的密码，而是通过百度网盘开放 API OAuth 授权生成的访问令牌。

获取步骤：

1. 打开百度官方 MCP 仓库 README。
2. 找到“发起授权请求”或 Access Token 授权入口。
3. 登录百度账号并确认授权。
4. 授权完成后，浏览器会跳转到一个新地址。
5. 在地址栏中找到：

   ```text
   access_token=一长串字符&expires_in=...
   ```

6. 只复制 `access_token=` 后面、下一个 `&` 之前的字符串。

不要复制 `access_token=` 本身，也不要复制后面的 `expires_in` 参数。

## 六、保存 Access Token

推荐把 Token 保存为 Windows 用户环境变量，不要直接写入 Codex 配置文件。

在 PowerShell 中执行：

```powershell
[Environment]::SetEnvironmentVariable(
  "BAIDU_NETDISK_ACCESS_TOKEN",
  "你的AccessToken",
  "User"
)
```

检查是否设置成功，但不要直接打印 Token：

```powershell
$token = [Environment]::GetEnvironmentVariable(
  "BAIDU_NETDISK_ACCESS_TOKEN",
  "User"
)

if ($token) {
  "Token 已设置，长度为 $($token.Length)"
} else {
  "Token 尚未设置"
}
```

设置环境变量后，需要重新打开 PowerShell 和 Codex，新的进程才能读取它。

## 七、配置 Codex MCP

Codex 配置文件通常位于：

```text
C:\Users\Leo\.codex\config.toml
```

加入或修改以下配置。请将 `command` 改为本机 `Get-Command uv` 查到的实际路径：

```toml
[mcp_servers.baidu_netdisk]
enabled = true
command = 'C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe\uv.exe'
args = [
  "--directory",
  'C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk',
  "run",
  "fileupload_tool.py"
]
env_vars = ["BAIDU_NETDISK_ACCESS_TOKEN"]
tool_timeout_sec = 300
```

配置要点：

- `command`：启动 `uv.exe` 的本地路径。
- `--directory`：`fileupload_tool.py` 所在的父目录。
- `run fileupload_tool.py`：使用 uv 环境启动百度网盘 MCP 上传服务。
- `env_vars`：让 Codex 把 Windows 环境变量传给 MCP 进程。
- `tool_timeout_sec`：上传操作的超时时间，单位为秒。

不要使用下面这些错误写法：

```toml
args = ['"--directory", "...", "run", "netdisk.py"']
```

这会把所有参数当作一个字符串传入；同时，当前上传脚本名称是 `fileupload_tool.py`，不是 `netdisk.py`。

## 八、检查 MCP 配置

在 PowerShell 中执行：

```powershell
codex mcp list
```

确认列表中出现 `baidu_netdisk`，并且显示的参数包含：

```text
--directory C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk run fileupload_tool.py
```

也可以在 Codex 中输入：

```text
/mcp
```

修改配置后请重启 Codex。

## 九、上传文件

连接成功后，可以直接使用自然语言请求：

```text
把 C:\Users\Leo\Documents\report.pdf
上传到百度网盘的 /项目资料/2026/。
如果目录不存在就创建，不要覆盖同名文件。
```

上传工具的参数含义：

- `local_file_path`：Windows 本地文件的完整路径。
- `remote_path`：百度网盘中的目标目录，必须以 `/` 开头。

例如：

```text
请先确认百度网盘 /项目资料/2026/ 中没有同名文件，
然后上传 C:\Users\Leo\Documents\report.pdf，
不要覆盖已有文件。
```

## 十、手动测试上传

如果 Codex 尚未重新加载 MCP，可以直接使用下面的 PowerShell 命令测试本地上传程序：

```powershell
$env:BAIDU_NETDISK_ACCESS_TOKEN = [Environment]::GetEnvironmentVariable(
  "BAIDU_NETDISK_ACCESS_TOKEN",
  "User"
)

$uv = (Get-Command uv).Source
$mcpDir = "C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk"
$localFile = "C:\Users\Leo\Documents\report.pdf"

& $uv run --python 3.12 --directory $mcpDir python -c `
  "import json, fileupload_tool; print(json.dumps(fileupload_tool.upload_file(r'$localFile', '/项目资料/2026'), ensure_ascii=False))"
```

成功时返回结果中应包含：

```json
{
  "status": "success",
  "message": "文件上传成功"
}
```

Windows 上建议使用 Python 3.12。某些依赖在 Python 3.14 环境下可能没有可用的预编译包，导致 `pydantic-core` 编译失败。

## 十一、常见问题

### 1. 找不到 `uv`

执行：

```powershell
Get-Command uv
```

如果没有结果，重新安装 uv，或重新打开 PowerShell 让 PATH 生效。

### 2. 找不到 `fileupload_tool.py`

检查：

```powershell
Test-Path "C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk\fileupload_tool.py"
```

如果返回 `False`，说明 `--directory` 路径不正确，或者仓库解压层级多了一层。

### 3. `pydantic-core` 编译失败

通常是 uv 使用了 Python 3.14。使用 Python 3.12：

```powershell
uv run --python 3.12 --directory "C:\Tools\baidu-netdisk-mcp\src\baidu-netdisk" python -c "import mcp; print('MCP OK')"
```

### 4. Token 尚未设置

检查用户级环境变量：

```powershell
[Environment]::GetEnvironmentVariable(
  "BAIDU_NETDISK_ACCESS_TOKEN",
  "User"
)
```

如果为空，需要重新设置 Token，并重启 Codex。

### 5. 上传到错误的远程路径

`remote_path` 表示百度网盘中的目录，不是本地目录。它必须以 `/` 开头，例如：

```text
/项目资料/2026
```

上传工具会自动把本地文件名追加到这个目录后面。

## 十二、安全建议

- 不要在聊天、截图、Git 仓库或公开日志中粘贴 Access Token。
- 不要把真实 Token 直接写进 `config.toml`。
- 上传、覆盖、移动和删除等写操作应保留人工确认。
- 不要使用来源不明的“一键安装”百度网盘 MCP 包。
- 如果 Token 泄露，应立即在百度授权管理中撤销旧授权并重新生成。
- 生产环境上传前，先用一个很小的测试文件验证目标目录和权限。
