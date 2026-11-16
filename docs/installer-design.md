# macOS 与 Windows 图形安装器设计

本文描述 HWCloudCLI 在 macOS 和 Windows 上的引导式安装器。安装器是 `install.sh` 之外的图形入口，版本规则与安装包地址和命令行安装脚本一致。本文只约定设计，不包含实现。

## 目标

安装器提供五个步骤的向导：

1. 展示 CLI 介绍和声明。
2. 根据本机是否已有 `hcloud`，提供安装、更新或卸载。
3. 安装时选择目录；更新时选择最新版本或指定版本；卸载时选择是否删除用户配置目录 `.hcloud`。
4. 显示安装、更新或卸载的进度。
5. 提示完成或失败。

卸载必须同时删除 PATH 中为 `hcloud` 加入的目录项。

## 与当前仓库的关系

`debug/` 只保存待发布的 CLI 压缩包。发布 Release 时，workflow 把这些压缩包上传为 GitHub Release 附件。安装器不从 `debug/` 下载。

`install.sh` 继续负责 Linux，以及不使用图形界面的安装。它只从 GitHub Releases 下载：

- 不带参数或版本为 `latest`：`releases/latest/download/` 下当前系统的附件。
- 指定标签：`releases/download/<标签>/` 下的同名附件。

图形安装器使用同一套地址和文件名。

| 系统 | 附件名 | 包内程序名 |
| --- | --- | --- |
| Windows amd64 | `huaweicloud-cli-windows-amd64.zip` | `hcloud.exe` |
| macOS amd64 | `huaweicloud-cli-darwin-amd64.tar.gz` | `hcloud` |
| macOS arm64 | `huaweicloud-cli-darwin-arm64.tar.gz` | `hcloud` |

macOS 安装包尚未提供。包的顶层包含可执行文件，也可以同时包含说明文件。标签必须与 Release 标签完全一致，例如 `1.2.0`，不加 `v` 前缀。

安装器程序本身不包含 CLI 压缩包。用户在进度步骤中选定的版本，到那时再下载。这样「最新版本」和「指定版本」都不必把某一个 CLI 构建封进安装器。

## 目录

```text
installer/
├── windows/
│   ├── ui/        # 五步向导
│   ├── detect/    # 探测 hcloud.exe 与版本
│   └── actions/   # 下载、安装、更新、卸载、PATH
└── macos/
    ├── ui/
    ├── detect/
    └── actions/
```

两边各自实现界面和系统调用。下载地址、附件名、默认安装位置和 PATH 规则写成同一份约定，由 `installer/windows` 与 `installer/macos` 共同遵守，并与 `install.sh` 保持一致。

构建出的 `.exe` 和 `.pkg` 不放入 `installer/` 或 `debug/`。它们作为 Release 附件发布，例如 `huaweicloud-cli-setup-windows-amd64.exe` 和 `huaweicloud-cli-setup-macos.pkg`。现有 workflow 继续只上传 `debug/` 中的 CLI 压缩包。安装器的构建和上传使用单独的流水线。Windows 安装包需要代码签名，macOS 安装包需要 Developer ID 签名和公证。

## 向导流程

### 1. 介绍和声明

静态页面，说明 CLI 的用途和声明。这一步不探测、不下载。用户可以继续或退出。

### 2. 操作选择

进入这一步之前完成本机探测。

- 未发现 `hcloud`：只显示「安装」。
- 已发现 `hcloud`：只显示「更新」和「卸载」，并展示程序路径。能执行 `hcloud version` 时同时展示版本号；执行失败时版本显示为未知，更新和卸载仍然可用。

### 3. 分支步骤

**安装。** 选择安装目录。

- Windows 默认 `%LOCALAPPDATA%\hcloud`。
- macOS 默认 `/usr/local/bin`。

用户可以修改目录。

**更新。** 两个选项：

- 升级到最新版本。页面先查询 GitHub Release 的最新标签并展示给用户，例如 `1.2.0`。查询失败时，这个选项不可用。
- 升级到指定版本。用户输入标签。确认后、进入进度之前，先检查该标签的附件是否存在。不存在则留在当前页并说明原因。

更新覆盖探测到的现有程序，不再询问安装目录。

**卸载。** 一个勾选项：是否删除用户配置目录 `.hcloud`。

- Windows：`%USERPROFILE%\.hcloud`
- macOS：`~/.hcloud`

默认不勾选，配置保留。无论是否勾选，卸载都会删除程序文件、安装记录，以及 PATH 中对应的 `hcloud` 目录项。

### 4. 进度

安装、更新、卸载使用各自的进度文案。

安装和更新的顺序：

1. 拼出 Release 下载地址。
2. 下载压缩包。
3. 若该 Release 带有 `SHA256SUMS`，则校验；没有则提示后继续。
4. 解压并取出顶层可执行文件。
5. 如目标位置需要授权，向用户申请授权，通过后继续。
6. 复制到安装目录并设置可执行权限。
7. 把安装目录写入 PATH（该目录已在 PATH 中则不重复添加）。
8. 写入安装记录。

卸载的顺序：

1. 如删除系统目录或系统 PATH 需要授权，向用户申请授权，通过后继续。
2. 从 PATH 删除该次安装加入的目录项。
3. 删除程序文件。
4. 删除安装记录。
5. 仅当用户勾选时，删除 `.hcloud`。

### 5. 完成或失败

成功时显示程序路径或卸载结果，并提示新开一个终端后再执行 `hcloud version`。当前已打开的终端看不到刚修改的 PATH。

失败时显示失败所在的步骤和原因。已下载的临时文件路径保留，便于重试。

## 探测逻辑

探测在操作选择页之前完成。图形进程的 PATH 通常不完整，因此不能只搜索 PATH。

顺序如下，找到可用的程序文件即作为候选：

1. 读取安装记录。
   - Windows：当前用户注册表中的安装目录、版本和安装时间。
   - macOS：`~/Library/Application Support/hcloud/install.json`，系统级安装则使用 `/Library/Application Support/hcloud/install.json`。
2. 检查记录中的 `hcloud.exe` 或 `hcloud` 是否仍存在。
3. 检查默认位置。
   - Windows：`%LOCALAPPDATA%\hcloud\hcloud.exe`，然后是 `%USERPROFILE%\hcloud\hcloud.exe`。
   - macOS：`/usr/local/bin/hcloud`、`/opt/homebrew/bin/hcloud`、`~/bin/hcloud`。
4. 搜索 PATH。Windows 使用 `where.exe hcloud`。macOS 除当前进程的 PATH 外，还要检查 `/usr/local/bin` 和 `/opt/homebrew/bin`。

存在多个候选时：

1. 优先采用安装记录中的路径。
2. 其次采用默认安装目录中的路径。
3. 最后采用 PATH 中的第一个。

操作页展示最终选中的路径。只要有一个候选，就视为已安装，只提供更新和卸载。没有任何候选时，只提供安装。

版本号通过执行 `hcloud version` 获取，并设置超时。命令失败不改变「已安装」的判断。

选择「更新」后查询最新 Release 标签，供「升级到最新版本」展示。指定版本在进入进度前用附件地址确认该标签存在。

## PATH

安装和更新写入的是安装目录，不是程序文件名本身。

- Windows 每用户安装写入当前用户的 PATH。为所有用户安装时写入系统 PATH，并先提权。
- macOS 安装到 `/usr/local/bin` 时，该目录通常已在 PATH 中，此时不追加重复项。安装到其他目录时，把该目录写入用户 shell 配置或 `/etc/paths.d` 中由安装器创建的专用文件，并在安装记录中记下写入方式。

写入前按目录比较，忽略大小写和末尾斜杠。已经存在的相同目录不再追加。

卸载删除的是安装记录中的那个目录项，以及本次安装写到 shell 配置或 `/etc/paths.d` 的专用条目。不按「路径字符串里出现 hcloud」做模糊删除，以免删掉其他软件的目录。安装记录缺失时，只删除探测到的程序所在目录在 PATH 中的那一项。

Windows 同时检查用户 PATH 和系统 PATH，只删除与本次安装范围一致的那一处。修改 PATH 后，已经打开的 PowerShell、CMD 和终端会话不会自动更新。

## 授权

探测已安装程序、查询最新版本、下载 Release 压缩包都不需要管理员权限。需要授权的是随后写入或删除受保护位置。授权由安装器在进度步骤中主动发起。向导窗口保持打开，只有复制文件、修改系统 PATH 和系统级安装记录交给提权后的短进程。用户同意后，短进程结束，向导从下一步继续，直到完成页。用户拒绝或密码错误时，停在进度页并说明原因，已下载的压缩包保留，可以再次发起授权。

### Windows

默认安装到 `%LOCALAPPDATA%\hcloud`，并且只修改当前用户的 PATH 时，不弹出 UAC。下载、解压、复制和写入当前用户注册表都使用当前用户权限。

以下情况弹出 UAC：

- 安装目录位于 `C:\Program Files` 或其他受保护目录。
- 选择为所有用户安装，需要修改系统 PATH。
- 卸载当时以管理员权限装入系统目录的程序，或删除系统 PATH 中的对应项。

解决方式：界面进程不整体重启。需要提权的动作通过一次性的提权进程完成。用户在 UAC 中选择「是」后，该进程返回成功，向导继续写安装记录并进入完成页。用户选择「否」时，这一步失败，向导留在进度页。

未签名的安装器在启动时可能被 SmartScreen 拦截。这发生在向导出现之前。安装包使用代码签名，使用户只需确认打开，而不必到系统设置里手动放行。

### macOS

默认目录 `/usr/local/bin` 不能由普通图形进程写入。`/etc/paths.d` 和 `/Library/Application Support` 同样需要管理员权限。因此安装、更新和卸载这个位置的 `hcloud` 时，系统弹出管理员密码框。

用户目录中的安装不需要管理员密码，例如安装到 `~/bin`，并且 PATH 只写入 `~/.zshrc`。只删除这些用户文件的卸载也不需要密码。

解决方式与 Windows 相同：向导进程保持运行，用系统授权接口执行需要管理员权限的命令。密码正确后，这些命令完成，向导继续进度并进入完成页。密码错误或取消时，停在进度页，用户可以重试。

Gatekeeper 发生在安装器第一次被打开时，早于向导的第一步。未签名或未公证的应用可能无法启动，安装器不能在这个拦截之后从向导中间继续。安装器使用 Developer ID 签名并完成公证，使用户在「是否打开」确认之后直接进入介绍页。确认之前向导尚未开始，不保留半成品安装状态。

## 安装记录

安装和更新成功后写入记录，卸载时删除记录。记录内容包括：

- 安装目录
- 程序文件路径
- 已安装的 Release 标签
- PATH 的修改位置（用户 PATH、系统 PATH，或 macOS 的配置文件路径）
- 安装时间

卸载即使记录损坏，也要继续删除探测到的程序和对应 PATH 项。`.hcloud` 只在用户勾选后删除。
