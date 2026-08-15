# SSH 首次配置与健康检查

## 设计原则

- Skill 只使用固定 SSH 别名 `yang-login` 和 `lan-login`。
- 每个用户的实际远程用户名、私钥路径和认证方式保存在 `%USERPROFILE%\.ssh\config`。
- `config/servers.psd1` 保存组内共享的 Yang/Lan 地址和运行环境；个人覆盖写入不入库的 `config/servers.local.psd1`，且不保存用户密码或私钥。
- 配置向导只管理带 `# BEGIN CODEX VASP:` 和 `# END CODEX VASP:` 标记的配置块。
- 已存在但未受管理的同名 `Host` 块必须由用户确认后才能接管。

## 首次配置

分别运行一次：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/setup_ssh_hosts.ps1" -Server yang
& "$HOME/.codex/skills/fang_ssh_skill/scripts/setup_ssh_hosts.ps1" -Server lan
```

向导会：

1. 询问该服务器上的实际用户名。
2. 默认使用 `~/.ssh/id_ed25519_yang` 或 `~/.ssh/id_ed25519_lan`。
3. 密钥不存在时询问是否生成 ED25519 密钥。
4. 公钥不存在时从私钥派生 `.pub` 文件。
5. 询问是否将公钥安装到远端 `~/.ssh/authorized_keys`；此步骤可能需要首次密码登录。
6. 备份现有 SSH config，然后写入受管理配置块。
7. 使用 `ssh -G` 检查解析，并使用 `BatchMode=yes` 验证真正的无人值守登录。

密码由原生 `ssh` 直接读取。不要把密码输入聊天、脚本参数或配置文件。

## 使用已有密钥

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/setup_ssh_hosts.ps1" `
    -Server yang `
    -IdentityFile "~/.ssh/my_existing_key"
```

如果 `.pub` 文件不存在，脚本会调用 `ssh-keygen -y` 从私钥生成公钥。

## 生成无口令专用密钥

仅当用户明确接受风险并需要完全无人值守时使用：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/setup_ssh_hosts.ps1" `
    -Server lan `
    -GenerateKey `
    -NoPassphrase
```

默认生成密钥时由 `ssh-keygen` 交互询问口令。带口令密钥需要加入 `ssh-agent`，否则 `BatchMode=yes` 检查会失败。

## 只更新本地配置

如果公钥已经由管理员安装，可以跳过远端修改：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/setup_ssh_hosts.ps1" `
    -Server yang `
    -SkipKeyInstall
```

## 健康检查

检查全部服务器：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/check_ssh_hosts.ps1" -Server all |
    Format-Table -AutoSize
```

检查单台服务器：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/check_ssh_hosts.ps1" -Server lan |
    Format-List
```

检查内容包括：

- SSH 别名能否由 `ssh -G` 解析；
- 解析后的主机是否与公共服务器配置一致；
- 是否解析到远程用户名；
- 至少一个解析到的私钥文件是否存在；
- `ssh -o BatchMode=yes` 是否可以无交互登录。

任一检查失败时，不要提交、取消或修改远程任务。先运行配置向导或修复 SSH config。

## 自动化参数

配置向导支持 `-RemoteUser`、`-IdentityFile`、`-GenerateKey`、`-NoPassphrase`、`-SkipKeyInstall`、`-SkipConnectionTest`、`-ForceAdoptExisting` 和 `-NonInteractive`。

非交互模式不会询问问题，因此必须提供所有必需参数。它仍然可能在首次安装公钥时由原生 SSH 请求服务器密码；如需完全非交互，请预先安装公钥并使用 `-SkipKeyInstall`。

## 回滚

每次修改已有 SSH config 前，向导都会在同一目录创建带时间戳的备份：

```text
config.codex-backup-YYYYMMDD-HHmmssfff
```

如需恢复，关闭正在运行的 SSH 操作，用备份文件替换 `%USERPROFILE%\.ssh\config`，再运行健康检查。
