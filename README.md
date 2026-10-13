# 重装环境记录

保存更换 SSD、重装 Windows 时需要的环境变量记录和恢复脚本。

## 2026-10-13 Windows 环境变量备份

- [下载公开版备份 ZIP](windows-environment/2026-10-13/Windows-Environment-Backup-2026-10-13-public.zip)
- [详细配置记录与恢复说明](windows-environment/2026-10-13/README.md)
- [环境变量 JSON](windows-environment/2026-10-13/environment-backup.json)
- [恢复脚本](windows-environment/2026-10-13/restore-environment.ps1)

这份记录包含 3 项用户级变量、27 项系统级变量。由于仓库公开，IGCCSVC_DB 的原始编码值已去除，其余 29 项保留原值。完整未脱敏版仅保存在本地，未上传。

恢复脚本默认只预览。应先恢复/安装软件，确认新盘符和用户目录，再根据详细说明预览；明确要求恢复时才使用 -Apply。软件、Python/Conda 包和项目文件不包含在此备份内。

当前需关注 D:\nodejs、旧 E: 路径、PATH 中的相对路径与虚拟环境条目，以及 C:\conda 下的三个环境目录。具体事实、检查限制和后续配置步骤均在详细记录中。
