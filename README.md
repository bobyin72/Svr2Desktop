# Svr2Desktop

Windows Server 2016 / 2019 / 2022 / 2025 桌面化与流畅度优化脚本。

纯 PowerShell，零第三方依赖。目标是让 Server 获得接近桌面的交互流畅度：消除登录与关机的等待和弹窗、开启桌面体验、按服务器场景调优电源与网络、精简无用服务、补齐可运维性。**每一项改动都回读验证；除"清理阶段删除的文件"外均可还原。**

> 上游基线：社区版 `Windows Server 2016-2025 to desktop.bat` v8.1。本仓库为重写与审计版本，自 v11.0 起按机主要求将"安全降级"重构为显式独立阶段。

---

## ⚠️ 安全须知（使用前必读）

本脚本提供一组 **`Downgrade` / `VBS` 安全降级档**，包含：

| 编号 | 内容 |
|---|---|
| SEC10 | UAC 管理员静默提权（`ConsentPromptBehaviorAdmin=0`，**保留 `EnableLUA=1`，不彻底关 UAC**） |
| SEC11 | 关闭 Defender 实时防护与服务（**可逆，不卸载组件**） |
| SEC12 | 密码永不过期（**长度与复杂度保持默认，不归零**） |
| SEC13 | 屏蔽安全中心告警与托盘图标 |
| VBS | 虚拟化安全相关降级 |

**设计上的约束（请勿绕过）：**

1. 这些项**绝不默认执行**。必须显式选择菜单 `[10]`/`[9]`、`-Stage Downgrade`、`-Stage VBS`，或 `-Stage All` 才会触发；`-Stage All` 时还可用 `-SkipDowngrade` / `-SkipVBS` 排除。
2. 执行前脚本会**打印风险摘要与回滚命令并要求确认**。
3. **配置文件的键名白名单里没有这些项**——一个放在脚本旁边的 JSON 无法悄悄打开安全降级。
4. 仍**不提供**：彻底关闭 UAC 框架、卸载 Defender 组件、关闭 SEHOP/DEP、密码复杂度与最小长度归零。

**风险警告**：上述四项叠加后构成一条完整攻击链——*弱口令 → UAC 无提示提权 → 无 AV 拦截 → 无安全告警*。它们是为**隔离的、可信的实验室 / 家用环境**设计的，**不应在暴露于网络的生产服务器上使用**。使用者须自行评估合规要求与安全责任；作者与维护者不对误用造成的后果负责。

另有一条必须记住的耦合：SEC10 把 `ConsentPromptBehaviorAdmin` 置 0 的同时把 `PromptOnSecureDesktop` 置 0（后者单独存在时是经典的 UAC 绕过口）。日后若单独把 `ConsentPromptBehaviorAdmin` 改回 `2` 或 `5`，**必须同步把 `PromptOnSecureDesktop` 改回 `1`**。

---

## 四条铁律

| 铁律 | 含义 |
|---|---|
| **每项都要回读** | 改完重新读一次与期望值比对，而非"执行成功就算完成" |
| **结论必须带证据** | 判定未达标时须给出实测值；给不出就明说"这条没采集到" |
| **每项都能还原** | 改动前原值登记入五个备份通道 + 原生命令回放通道 |
| **安全降级绝不默认** | 任何"拿安全换便利"的项都不进默认路径 |

---

## 用法

以管理员身份启动 PowerShell，进入脚本目录：

```powershell
.\Svr2Desktop.ps1                  # 交互菜单
.\Svr2Desktop.ps1 -Verify          # 只回读，什么都不改（先跑此步存基线）
.\Svr2Desktop.ps1 -WhatIf          # 全链路预演，不写盘
.\Svr2Desktop.ps1 -Stage All -Json -Force -ExitOnFail   # 无人值守全量
.\Svr2Desktop.ps1 -Stage Desktop,Ops -Force            # 只跑指定阶段
.\Svr2Desktop.ps1 -Stage Downgrade                     # ⚠️ 仅安全降级档
```

也可以双击 `Svr2Desktop.cmd`：它优先用 `pwsh.exe`（增强模式），不存在则回落到 PowerShell 5.1；只请求一次提权，双击时窗口停住、无人值守时不暂停。

**推荐流程**：`-Verify` 存基线 → `-WhatIf` 预演 → 执行 → 重启 → 再 `-Verify` 对照。**两次 `-Verify` 的差集，就是本次改动到底生效了什么的证明。**

常用开关：

| 开关 | 作用 |
|---|---|
| `-Full` | 展开全部证据行（默认摘要视图折叠"已达标"的证据） |
| `-NoEvidence` | 静音屏幕证据输出，日志仍完整 |
| `-Json` | 额外输出机器可读的 `Svr2Desktop_result.json` |
| `-SkipDowngrade` / `-SkipVBS` | 即便 `-Stage All` 也排除安全降级档 |
| `-DisableSpooler` / `-DisableWLAN` | 额外启用两个 opt-in 项 |
| `-NoRestartPrompt` | 结束后不提示重启 |
| `-ExitOnFail` | 退出码契约：`0` 无失败 / `2` 有 FAIL / `1` 致命错误 |
| `-ConfigPath` / `-BackupRoot` | 指定配置文件 / 备份根目录 |

> **重启两步确认（v13.1 起）**：末尾问 `Reboot now …? [Y/N]`，答 `Y` 后还要打出 `OK` 才真正重启（`yes` 不通过，空回车取消）。加 `-Force` 或 `-NoRestartPrompt` 可完全不问。

阶段与项数：Desktop 15 / Performance 8 / Network 3 / Services 4+2 opt-in / Security 5 / Ops 3 / Cleanup 2（动作型，**不可逆**）/ Downgrade 4 与 VBS 1（**必须显式选择**）。

---

## 文件说明

| 文件 | 用途 |
|---|---|
| `Svr2Desktop.ps1` | 主脚本（v13.3，UTF-8 **with BOM**，请保持此编码） |
| `Svr2Desktop.cmd` | 双击入口，自动选 PowerShell 宿主并请求提权 |
| `Svr2Desktop.config.json` | 可选配置样例；删掉即回落到内置缺省。键名白名单设计见文件内注释 |
| `CHANGELOG.md` | v11.0 → v13.3 逐版变更与真机验收记录 |
| `Svr2Desktop_V12_调优项说明.md` | 中文逐项说明（**见下方版本提示**） |
| `Svr2Desktop_Audit_2026-09-22.md` | v11.15 静态审计报告（含时点行动清单） |
| `Svr2Desktop_v9.0_bat_legacy.bat` | 上游 v9.0 批处理 legacy 存档，仅作对照，**不可执行** |

**版本提示**：`Svr2Desktop_V12_调优项说明.md` 的标题与正文主体对应 **V12 封板**；文中已包含 V13.1 / V13.3 的若干后续说明，但个别句子（如"脚本仍是 12.0"）未随主脚本更新。**脚本版本的唯一权威是 `Svr2Desktop.ps1` 头部的 `Version` 字段与 `$script:VER`；最新变更以 `CHANGELOG.md` 为准。** 本仓库保留该说明文档原文，未作修改，以保持与内部源逐字节一致。

---

## 许可

[MIT](LICENSE) © 2026 Bob Yin

上游基线来自社区版 `Windows Server 2016-2025 to desktop.bat` v8.1；本仓库仅包含重写与审计后的内容，未再分发上游原始文件。
