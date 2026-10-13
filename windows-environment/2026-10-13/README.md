# 换 SSD / 重装 Windows：环境变量备份与恢复记录（公开版）

**公开版范围：本仓库公开可见。保留 30 项变量记录，其中 29 项保留原始值；IGCCSVC_DB 的原始编码值已去除，只保留变量名和脱敏标记。恢复脚本本来就跳过该项。包含其原值的完整原始备份仍保留在本地，未上传到 GitHub。**

采集时间：2026-10-13T09:47:33+08:00（Asia/Shanghai）。当前用户目录：`C:\Users\liuya`；Windows 目录：`C:\Windows`。

已读取注册表中的 **3 项用户级变量 + 27 项系统级变量，共 30 项**。29 项原始值及 1 项脱敏记录、顺序、作用域和 REG_SZ / REG_EXPAND_SZ 类型保存在 environment-backup.json；本次没有修改环境变量。当前终端进程中的临时变量与软件注入路径只供检查，不作为永久配置恢复。

**重装前，将整个备份文件夹或 ZIP 另存到不会被更换/格式化的物理硬盘、U 盘或云端。当前保存位置在 C: 的 Documents 下，重装后可能丢失。C:、D: 是盘符，不能据此断定它们位于不同的物理硬盘。**

## 1. 已确认的配置与需要注意的地方

| 软件 / 变量 | 原始配置 | 本次目标检查 | 原作用域 |
| --- | --- | --- | --- |
| `NODE_HOME` | `D:\nodejs` | 目标存在 | Machine（系统级） |
| `NPM_CONFIG_PREFIX` | `D:\nodejs\npm-global` | 目标存在 | Machine（系统级） |
| `NPM_CONFIG_CACHE` | `D:\nodejs\npm-cache` | 目标存在 | Machine（系统级） |
| `COREPACK_HOME` | `D:\nodejs\corepack-cache` | 目标存在 | Machine（系统级） |
| `JAVA_HOME` | `E:\learn.java\jdk-11.0.2` | 本次未确认目标存在 | Machine（系统级） |
| `M2_HOME` | `E:\MAVEN` | 本次未确认目标存在 | Machine（系统级） |
| `Classpath` | `E:\LINGO64_20\Lingo20.jar` | 本次未确认目标存在 | Machine（系统级） |
| `ENCC_HOME` | `E:\南邮VPN\enlink\encc\` | 本次未确认目标存在 | Machine（系统级） |
| `ENCLIENT_HOME` | `E:\南邮VPN\enlink\ENWAgent.exe` | 本次未确认目标存在 | Machine（系统级） |

固定卷枚举可见 `C:\`、`D:\`。多项配置仍引用 E:，本次未确认这些 E: 目标存在。仅凭这次检查，不能确定它们是旧配置残留、盘符改变还是磁盘暂时未连接；恢复时需逐项核对。物理磁盘和分区对应关系读取被拒绝，本次未确定 C:、D: 是否属于同一块 SSD。

Node/npm 的 `D:\nodejs` 及 npm-global、npm-cache、corepack-cache 目录均存在。需要保留或重新安装软件，并按新盘符恢复上述四项配置及 PATH 中的 `D:\nodejs`、`D:\nodejs\npm-global`。备份环境变量并没有备份这些目录或全局 npm 包。

Java 的 `JAVA_HOME` 指向 E: 上的旧 JDK 目录，但当前进程可解析的 java.exe 位于 `C:\Program Files\Common Files\Oracle\Java\javapath` 和 `C:\Program Files (x86)\Common Files\Oracle\Java\java8path`。这是已确认的路径差异；它不能证明正在使用哪一个 Java 版本。本次没有执行 Java 版本检查。重装后需选择实际所需的 JDK，并核对 JAVA_HOME 与 java / javac 的解析路径。

用户级 TEMP / TMP 为 `%USERPROFILE%\AppData\Local\Temp`，用户级 PATH 为 `%USERPROFILE%\AppData\Local\Microsoft\WindowsApps;`。应保留新系统默认值，避免把旧用户名 liuya 硬写回。系统级 PATH 中也有两个用户专属目录，今后配置时应使用新用户目录，并优先放入用户级 PATH。

## 2. PATH 中已发现的问题

PATH 共记录 40 个非空条目，另有 2 个尾部空条目。本次有 19 个条目未被确认是存在的目录（包括一个实际是文件的条目），不能把这个数量直接理解为 19 个软件损坏。原始 PATH 的每个条目、位置和检查结果见第 6 节及 environment-audit.redacted.json。

- 系统 PATH 原文含 `C:;Windows\system32`。这实际是 `C:` 和 `Windows\system32` 两个相对路径条目，不等于 `C:\Windows\system32`。后面另有正确的 `C:\Windows\System32`，因此不能据此断定系统工具全部不可用。Windows 对驱动器相对路径的定义见 [Microsoft 文件路径说明](https://learn.microsoft.com/en-us/dotnet/standard/io/file-path-formats)。
- 原文含 `E:\;uangong\bin`。它被分为 E: 根目录和相对路径 `uangong\bin`；原本想配置的目录无法从现有记录确定，不应擅自猜补。
- `C:\Users\liuya\AppData\Local\Microsoft\WindowsApps\python.exe` 是文件，不能作为正常的目录条目加入 PATH。目录 WindowsApps 在 PATH 中已有记录。
- `E:\pythonProjectIORICLE\venv\Scripts` 是项目虚拟环境目录。本次未确认其存在，恢复脚本跳过；未来应在对应项目中激活或重建环境。
- 原 PATH 中的 WindowsApps 目录在系统级和用户级重复出现；重装时应整理，并保留新系统和新用户的默认目录。
- 系统级 PATH 原值长 **1255 字符**。恢复脚本直接按注册表类型写入，不使用 setx；Microsoft 文档说明 setx 有 1024 字符的赋值限制，还会展开变量引用，直接用它复制长 PATH 可能截断数据。[setx 官方说明](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/setx)。

## 3. Conda / Python：与环境变量不同的额外事项

当前进程中存在 `CONDA_EXE=C:\conda\Scripts\conda.exe`，但它不是本次注册表备份中的永久变量。另已确认 `C:\conda\Scripts\conda.exe` 与 `C:\conda\python.exe` 文件存在，envs 下有 `Paper_reproduction_1`、`reading`、`tf` 三个目录。

`py -0p` 本次没有找到已注册的 Python 安装，但这不等于没有 Python；C:\conda 下实际有 python.exe。Conda 包、环境定义、项目文件和相关配置不包含在本备份中，本次也没有验证上述环境能否正常运行。重装前需要另外保留项目和环境定义，之后重新安装或重建 Conda。不要把旧的 CONDA_EXE 或某个 venv 路径直接全局写回。

软件安装文件、数据库、许可证、Git 配置/SSH 密钥、npm 配置、代理工具配置等也不包含在这个环境变量备份中。如果它们位于待更换的 SSD，应另行迁移。仅复制环境变量不能恢复这些文件、服务或注册信息。

## 4. 以后如何让我重新配置

保存完整 ZIP 或文件夹。重装后把备份提供给我，并明确说：**“按这份备份重新配置环境变量。”** 如果软件安装目录或盘符有变化，同时告诉我新位置；我会结合新系统实际路径和已安装软件重新核对并配置。

不要只依赖聊天“记忆”：本次记录以这个可携带的备份为准，不能保证重装后本地聊天资料、文件或跨聊天记忆仍然可用。当前没有授权或执行立即写入；本次交付的是记录及供后续使用的脚本。

恢复流程是：先恢复/安装软件和必要文件 → 确认新用户名及盘符 → 生成预览 → 检查采用与跳过的项目 → 用户要求恢复时再写入 → 重开终端并验证命令。

## 5. 恢复脚本使用说明

脚本默认只预览，不改变用户级或系统级环境变量。它保留新 Windows / 驱动的默认变量，只处理第 1 节中的九个已审阅软件变量；需要相应路径存在，NODE_HOME、JAVA_HOME、M2_HOME 还会检查对应软件可执行文件。

PATH 采用保留新系统现值、追加经验证目录的方式；跳过相对路径、盘符根目录、可执行文件、项目 venv、不存在的目录以及旧系统目录。个人目录映射到新用户，并优先进入用户 PATH。它不会主动清理新系统已经存在的 PATH 条目，今后修复现有问题仍需逐项判断。

自动跳过硬件/系统生成变量及 IGCCSVC_DB 等不透明或潜在敏感值。IGCCSVC_DB 的原始长编码值只保存在本地完整版；公开版 JSON 已去除其原值，正文/摘要也隐藏；本次未验证其具体内容、来源或迁移可用性。请私密保存备份。

在解压后的文件夹中打开 CMD，先预览：

```bat
preview-or-restore.cmd -PlanFile restore-plan.json
```

如果目录改变，复制并填写 path-mappings.example.json。以下只是映射格式示例，D:\Apps\Java 的位置需要改为实际安装目录，不要直接照抄：

```json
{
  "prefixes": [
    {"from": "E:\\learn.java\\jdk-11.0.2", "to": "D:\\Apps\\Java"}
  ]
}
```

然后按映射预览：

```bat
preview-or-restore.cmd -MappingsFile path-mappings.example.json -PlanFile restore-plan.json
```

确认预览符合要求、并决定恢复后，才使用 -Apply。系统级变更需要以目标用户身份打开管理员 CMD：

```bat
preview-or-restore.cmd -Apply -MappingsFile path-mappings.example.json -PlanFile restore-plan.json
```

仅恢复用户级可用 -Scope User；仅系统级可用 -Scope Machine。不要切换成另一个管理员账号后再恢复用户变量，HKCU 取决于运行脚本的账号。普通预览不需要管理员权限。

写入前，脚本校验原备份 SHA-256，并在 restore-history 中保存新系统写入前的完整变量快照和计划。如果逐项写入发生错误，会尝试撤销本次已写入的值；机器中断等情况下仍可依据 before.json 恢复。原备份不要手动修改，使用单独的路径映射文件。

运行后关闭并重新打开终端及相关应用，必要时注销再登录。脚本会广播 Environment 变更通知，依据 [Microsoft WM_SETTINGCHANGE 说明](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange)。本次仅执行过预览，未运行 -Apply，不能把预览验证说成实际写入已经验证。

新系统配置后可在新 CMD 中验证 `where node`、`where npm`、`where java`、`where javac`、`where mvn`，并检查需要的工具版本。只验证已经安装并打算继续使用的工具。

## 6. 完整永久变量清单（敏感/不透明值隐藏）

| 作用域 | 变量 | 类型 | 原始值 |
| --- | --- | --- | --- |
| Machine | `Classpath` | REG_SZ | `E:\LINGO64_20\Lingo20.jar` |
| Machine | `ComSpec` | REG_EXPAND_SZ | `%SystemRoot%\system32\cmd.exe` |
| Machine | `COREPACK_HOME` | REG_SZ | `D:\nodejs\corepack-cache` |
| Machine | `DriverData` | REG_SZ | `C:\Windows\System32\Drivers\DriverData` |
| Machine | `ENCC_HOME` | REG_SZ | `E:\南邮VPN\enlink\encc\` |
| Machine | `ENCLIENT_HOME` | REG_SZ | `E:\南邮VPN\enlink\ENWAgent.exe` |
| Machine | `IGCCSVC_DB` | REG_SZ | 公开版已去除原值；仅本地原始备份保留 |
| Machine | `JAVA_HOME` | REG_SZ | `E:\learn.java\jdk-11.0.2` |
| Machine | `M2_HOME` | REG_SZ | `E:\MAVEN` |
| Machine | `NODE_HOME` | REG_SZ | `D:\nodejs` |
| Machine | `NPM_CONFIG_CACHE` | REG_SZ | `D:\nodejs\npm-cache` |
| Machine | `NPM_CONFIG_PREFIX` | REG_SZ | `D:\nodejs\npm-global` |
| Machine | `NUMBER_OF_PROCESSORS` | REG_SZ | `16` |
| Machine | `OS` | REG_SZ | `Windows_NT` |
| Machine | `Path` | REG_SZ | 见下面的分条清单；原始整串在 JSON 中 |
| Machine | `PATHEXT` | REG_SZ | `.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC` |
| Machine | `PERL5LIB` | REG_EXPAND_SZ | `(空字符串)` |
| Machine | `PROCESSOR_ARCHITECTURE` | REG_SZ | `AMD64` |
| Machine | `PROCESSOR_IDENTIFIER` | REG_SZ | `Intel64 Family 6 Model 154 Stepping 3, GenuineIntel` |
| Machine | `PROCESSOR_LEVEL` | REG_SZ | `6` |
| Machine | `PROCESSOR_REVISION` | REG_SZ | `9a03` |
| Machine | `PSModulePath` | REG_EXPAND_SZ | `%ProgramFiles%\WindowsPowerShell\Modules;%SystemRoot%\system32\WindowsPowerShell\v1.0\Modules` |
| Machine | `TEMP` | REG_EXPAND_SZ | `%SystemRoot%\TEMP` |
| Machine | `TMP` | REG_EXPAND_SZ | `%SystemRoot%\TEMP` |
| Machine | `USERNAME` | REG_SZ | `SYSTEM` |
| Machine | `windir` | REG_EXPAND_SZ | `%SystemRoot%` |
| Machine | `ZES_ENABLE_SYSMAN` | REG_SZ | `1` |
| User | `Path` | REG_EXPAND_SZ | 见下面的分条清单；原始整串在 JSON 中 |
| User | `TEMP` | REG_EXPAND_SZ | `%USERPROFILE%\AppData\Local\Temp` |
| User | `TMP` | REG_EXPAND_SZ | `%USERPROFILE%\AppData\Local\Temp` |

PATH 顺序清单：

| 作用域 | 顺序 | 原始条目 | 本次目录检查 | 结构备注 |
| --- | --- | --- | --- | --- |
| Machine | 1 | `C:\Program Files\Common Files\Oracle\Java\javapath` | 目录存在 |  |
| Machine | 2 | `C:\Program Files (x86)\Common Files\Oracle\Java\java8path` | 目录存在 |  |
| Machine | 3 | `C:\Program Files (x86)\Common Files\Oracle\Java\javapath` | 未确认目录存在 |  |
| Machine | 4 | `E:\app\liuya\product\11.2.0\dbhome_1\bin` | 未确认目录存在 |  |
| Machine | 5 | `E:\database\dbhomeFree\bin` | 未确认目录存在 |  |
| Machine | 6 | `C:\Program Files (x86)\Razer Chroma SDK\bin` | 目录存在 |  |
| Machine | 7 | `C:\Program Files\Razer Chroma SDK\bin` | 目录存在 |  |
| Machine | 8 | `C:\Program Files (x86)\Razer\ChromaBroadcast\bin` | 目录存在 |  |
| Machine | 9 | `C:\Program Files\Razer\ChromaBroadcast\bin` | 目录存在 |  |
| Machine | 10 | `C:` | 目录存在 | 相对路径 |
| Machine | 11 | `Windows\system32` | 未确认目录存在 | 相对路径 |
| Machine | 12 | `C:\Windows` | 目录存在 |  |
| Machine | 13 | `C:\Windows\System32\Wbem` | 目录存在 |  |
| Machine | 14 | `C:\Windows\System32\WindowsPowerShell\v1.0\` | 目录存在 |  |
| Machine | 15 | `C:\Windows\System32\OpenSSH\` | 目录存在 |  |
| Machine | 16 | `C:\Program Files\dotnet\` | 目录存在 |  |
| Machine | 17 | `C:\Program Files (x86)\NVIDIA Corporation\PhysX\Common` | 目录存在 |  |
| Machine | 18 | `C:\Program Files\NVIDIA Corporation\NVIDIA NvDLISR` | 目录存在 |  |
| Machine | 19 | `E:\learn.java\jdk-11.0.2\bin` | 未确认目录存在 |  |
| Machine | 20 | `E:\learn.java\jdk-11.0.2\jre\bin` | 未确认目录存在 |  |
| Machine | 21 | `E:\SPSS24\JRE\bin` | 未确认目录存在 |  |
| Machine | 22 | `E:\LINGO64_20\` | 未确认目录存在 |  |
| Machine | 23 | `E:\cloud virtual\` | 未确认目录存在 |  |
| Machine | 24 | `C:\Windows\system32\config\systemprofile\AppData\Local\Microsoft\WindowsApps` | 未确认目录存在 |  |
| Machine | 25 | `C:\Users\liuya\AppData\Local\Microsoft\WindowsApps` | 目录存在 |  |
| Machine | 26 | `C:\Users\liuya\AppData\Local\JetBrains\Toolbox\scripts` | 目录存在 |  |
| Machine | 27 | `E:\MAVEN\bin` | 未确认目录存在 |  |
| Machine | 28 | `D:\科协学习\Microsoft VS Code\bin` | 未确认目录存在 |  |
| Machine | 29 | `E:\` | 未确认目录存在 |  |
| Machine | 30 | `uangong\bin` | 未确认目录存在 | 相对路径 |
| Machine | 31 | `C:\Users\liuya\AppData\Local\Microsoft\WindowsApps\python.exe` | 是文件，非目录 |  |
| Machine | 32 | `E:\pythonProjectIORICLE\venv\Scripts` | 未确认目录存在 | 项目虚拟环境 |
| Machine | 33 | `E:\git\Git\cmd` | 未确认目录存在 |  |
| Machine | 34 | `C:\Windows\System32` | 目录存在 |  |
| Machine | 35 | `C:\Program Files\GitHub CLI\` | 目录存在 |  |
| Machine | 36 | `D:\nodejs` | 目录存在 |  |
| Machine | 37 | `D:\nodejs\npm-global` | 目录存在 |  |
| Machine | 38 | `E:\matlab\runtime\win64` | 未确认目录存在 |  |
| Machine | 39 | `E:\matlab\bin` | 未确认目录存在 |  |
| Machine | 40 | `(空条目)` | 不检查 | 尾部空条目 |
| User | 1 | `%USERPROFILE%\AppData\Local\Microsoft\WindowsApps` | 目录存在 |  |
| User | 2 | `(空条目)` | 不检查 | 尾部空条目 |

## 7. 本次验证与文件说明

本地原始版已逐项回读注册表并比较 30 项值及类型，确认读取/预览后配置未改变；公开版另验证 29 项保留原值与原备份一致，IGCCSVC_DB 已脱敏。CMD 预览成功，当前机器计划写入 0 项；脚本通过 PowerShell 语法解析，原始 JSON 的 SHA-256 校验一致。实际写入没有执行。

| 文件 | 用途 |
| --- | --- |
| README.md | 这份可读记录、注意事项和后续恢复说明 |
| environment-backup.json | 29 项原始值、1 项脱敏记录，以及变量类型和作用域 |
| environment-backup.sha256 | 原始 JSON 的 SHA-256，恢复脚本会校验 |
| environment-audit.redacted.json | 目录检查、当前进程工具路径与已隐藏不透明值的摘要 |
| restore-environment.ps1 | 默认预览，-Apply 才写入的恢复脚本 |
| preview-or-restore.cmd | 通过 Windows 自带 PowerShell 执行脚本的 CMD 入口 |
| path-mappings.example.json | 默认空映射，可填写软件目录迁移关系 |
| restore-preview.json | 原机器上的恢复预览：未写入 |
| verification.json | 公开导出的脱敏、保留值、校验文件与预览验证结果 |
| disk-mapping.json | 磁盘映射读取受限的记录及 Conda 文件/目录存在性检查 |
| MANIFEST.sha256 | 文件夹内其他交付文件的 SHA-256 清单 |

公开版压缩包包含 29 项原始值和 1 项脱敏记录，不含软件安装目录、Conda 环境包、项目数据或其他应用账号凭据文件。保存时确保文件夹内 JSON、校验文件和脚本一起保留。
