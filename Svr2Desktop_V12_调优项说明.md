# Svr2Desktop V12 调优项说明（中文）

> 适用版本：**V12**（`Svr2Desktop.ps1`，`$script:VER = '12.0'`）
> 目标系统：Windows Server 2016 / 2019 / 2022 / 2025
> 交付件：`Svr2Desktop.ps1`（主脚本）+ `Svr2Desktop.cmd`（双击入口）

---

## 一、先说这份脚本的四条铁律

所有调优项都按这四条实现，理解它们才能理解每一项的行为：

| 铁律 | 含义 | 具体表现 |
|---|---|---|
| **① 每项都要回读** | 改完必须重新读一次，与期望值比对，而不是"执行成功就算完成" | 每个步骤带 `Test`（少部分带三态 `Probe`）；报告里逐项印"实测值 vs 期望值" |
| **② 结论必须带证据** | 判定为"未达标"时，必须能给出实测值；给不出就要明说"这条我没采集到" | 证据行（`evidence`）挂在读值原语层，自动获得；报告有"零证据闸"报警 |
| **③ 每项都要能还原** | 改动前的原值必须登记，并能一键回放 | 注册表/服务/功能/计划任务/电源走五个备份通道；密码策略、TCP 全局、SMBv1、Defender 偏好走"原生命令回放"通道 |
| **④ 安全降级绝不默认** | 任何"拿安全换便利"的项都不进默认路径 | SEC10–13 与 V1 只在显式选 `-Stage Downgrade` / `-Stage VBS`（或菜单 [9]/[10]）时执行，且执行前打印风险摘要并要求确认 |

**不进默认路径的含义**：配置文件的键名白名单里**没有**这些安全降级项 —— 一个放在旁边的 json 不能把它们悄悄打开。

---

## 二、怎么用

```powershell
# 0) 以管理员身份启动 PowerShell，然后进到脚本所在目录
.\Svr2Desktop.ps1                              # 交互菜单
.\Svr2Desktop.ps1 -Verify                      # 只回读：什么都不改（先跑这个存基线）
.\Svr2Desktop.ps1 -WhatIf                      # 全链路预演：不进菜单、不写盘
.\Svr2Desktop.ps1 -Stage All -Json -Force      # 无人值守全量执行
.\Svr2Desktop.ps1 -Stage Desktop,Ops -Force    # 只跑指定阶段（逗号分隔）
.\Svr2Desktop.ps1 -Stage Downgrade,VBS         # 只跑安全降级档
.\Svr2Desktop.ps1 -Stage All -Json -Force -ExitOnFail   # 有 FAIL 则退出码 2
```

**推荐流程**：`-Verify`（存基线）→ `-WhatIf`（预演）→ 执行 → **重启** → `-Verify`（与基线对照）。

> **重启是两步确认（V13.1 起；V13.3 起第二步的词是 `OK`）**：脚本末尾会问 `Reboot now …? [Y/N]`，
> 答 Y 之后**还要打出 `OK`** 才会真正重启 —— 因为重启是本脚本最打断人的动作，而它偏偏在所有写操作
> 完成之后才问，一次 Y/N 太容易误触（前面已经按过好几轮确认，手感上很容易一路 Y 下去）。
> 第二次打别的内容（含 `yes`，也包括直接回车）都会取消，两次回答都落日志。
> 想完全不问：加 `-Force` 或 `-NoRestartPrompt`。
**两次 `-Verify` 的差集，就是本次改动到底生效了什么的证明。**

其他常用开关：

| 开关 | 作用 |
|---|---|
| `-Full` | 展开全部证据行（默认摘要视图会折叠"已达标"的证据） |
| `-NoEvidence` | 静音屏幕上的证据输出（日志仍完整留痕） |
| `-Json` | 额外输出 `Svr2Desktop_result.json`（机器可读，便于批量部署汇总） |
| `-SkipDowngrade` / `-SkipVBS` | 即便 `-Stage All` 也排除安全降级档 |
| `-DisableSpooler` / `-DisableWLAN` | 额外启用 S6 / S7 两个 opt-in 项 |
| `-NoRestartPrompt` | 结束后不提示重启 |
| `-ExitOnFail` | 退出码契约：`0` 无失败 / `2` 有 FAIL 或 CHECK-ERROR / `1` 致命错误 |
| `-ConfigPath` / `-BackupRoot` | 指定配置文件 / 备份根目录 |

---

## 三、调优项总览

| 阶段 | 项数 | 性质 |
|---|---|---|
| Desktop（桌面体验） | 15 | 全部默认执行 |
| Performance（性能与电源） | 8 | 全部默认执行 |
| Network（网络栈） | 3 | 全部默认执行 |
| Services（服务精简） | 4 + 2 | 4 项默认；Spooler / WLAN 为 opt-in |
| Security（加固） | 5 | 全部默认执行 |
| Ops（可运维性） | 3 | 全部默认执行 |
| Cleanup（白名单清理 + 备份保留） | 2 | 默认执行（动作型，不可逆） |
| **Downgrade（安全降级）** | **4** | **必须显式选择** |
| **VBS（安全降级）** | **1** | **必须显式选择** |
| 合计 | **45 + 2 opt-in** | |

---

## 四、逐项说明

### 4.1 Desktop —— 桌面体验（15 项）

让 Server 长得像、用起来像桌面。

| 编号 | 调优项 | 具体改动 | 期望值 | 生效 | 注意 |
|---|---|---|---|---|---|
| **D1** | 关闭"服务器管理器"登录自启 | `HKLM\SOFTWARE\Microsoft\ServerManager` → `DoNotOpenServerManagerAtLogon`；`...\Oobe` → `DoNotOpenInitialConfigurationTasksAtLogon`；`HKCU\...\ServerManager` → 同上 | 全为 1 | 下次登录 | 三项都要满足（HKLM 管机器、HKCU 管当前用户） |
| **D2** | 关闭关机事件跟踪器（关机不再问"原因"） | `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Reliability` → `ShutdownReasonOn=0`、`ShutdownReasonUI=0` | 0 / 0 | 立即 | 只影响交互式关机提示，不影响日志记录策略 |
| **D3** | 关闭 IE 增强安全配置（IE ESC） | `HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7…}` 与 `{A509B1A8…}` → `IsInstalled=0` | 0 / 0 | 重新登录（Active Setup 机制） | 两个 GUID 分别是"管理员"与"用户"侧；只影响 IE，不影响 Edge |
| **D4** | 关闭锁屏 | `HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization` → `NoLockScreen=1` | 1 | 立即 | 只取消"锁屏界面"，登录界面仍在 |
| **D5** | 去掉登录后的桌面切换延迟 | `HKLM\...\CurrentVersion\Explorer` → `DelayedDesktopSwitchTimeout=0` | 0 | 下次登录 | 消除登录后屏幕"黑一下"的等待 |
| **D6** | 关闭建议 / 提示 / 静默推广安装 | `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent` → `DisableWindowsConsumerFeatures=1`、`DisableSoftLanding=1`；`HKCU\...\ContentDeliveryManager` 下 **11 个键**置 0（`SubscribedContent-338388/338389/338393/353694/353696/310093Enabled`、`SoftLandingEnabled`、`SystemPaneSuggestionsEnabled`、`SilentInstalledAppsEnabled`、`PreInstalledAppsEnabled`、`OemPreinstalledAppsEnabled`） | 见左 | 立即（部分需重新登录） | 这是"开始菜单里冒出推荐应用"的根治项 |
| **D7** | 精简任务栏（搜索框 / 小组件 / 资讯 / 聊天） | `HKCU\...\Search` → `SearchboxTaskbarMode=1`（只留图标）；`HKLM\...\Dsh` → `AllowNewsAndInterests=0`；`HKCU\...\Explorer\Advanced` → `TaskbarDa=0`、`TaskbarMn=0`，Win11 界面额外 `TaskbarAl=0`（任务栏左对齐） | 见左 | **注销 / 重启 explorer** | `TaskbarAl` 只在 build ≥ 22000（Win11 风格 shell）才写，断言同样条件化 |
| **D8** | 资源管理器默认值 | `HKCU\...\Explorer\Advanced` → `HideFileExt=0`（显示扩展名）、`Hidden=1`（显示隐藏文件）、`ShowSuperHidden=0`、`LaunchTo=1`（打开"此电脑"）、`ShowRecent=0`、`ShowFrequent=0`；`HKCU\...\Explorer\CabinetState` → `FullPath=1`（标题栏显示完整路径） | 见左 | **注销 / 重启 explorer** | ★ 标题栏完整路径必须写 **HKCU**：Explorer 只读这一处，`HKLM` 同名键是**死键**（写入与回读自洽、报 SATISFIED，功能却从不生效）。原实现写在 HKLM，V13 已改（根因由宝马线挖出）。关掉"最近/常用文件"可减少资源管理器在慢盘上的卡顿 |
| **D9** | 关闭开始菜单推荐与使用记录 | `HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer` → `HideRecommendedSection=1`；`HKCU\...\Explorer\Advanced` → `Start_TrackProgs=0`、`Start_TrackDocs=0` | 见左 | **注销 / 重启 explorer** | 隐私与流畅度双收益 |
| **D16** | 任务栏右键「结束任务」（Win11 风格任务栏专用） | `HKCU\...\Explorer\Advanced\TaskbarDeveloperSettings` → `TaskbarEndTask=1` | 1 | **重启 explorer** | 给任务栏右键菜单加"结束任务"，卡死的程序不必再开任务管理器。**仅 build ≥ 22000 的 Win11 风格 shell 存在**（Server 2025 即此类）；经典 Server 任务栏（2016/2019/2022）没有这个开关，脚本判 `ABSENT`（本项不适用），**不会**给不存在的目标写值 |
| **D11** | 桌面显示"此电脑"图标 | `HKCU\...\HideDesktopIcons\NewStartPanel\{20D04FE0-3AEA-1069-A2D8-08002B30309D}` → `0` | 0 | **注销 / 重启 explorer** | —— |
| **D12** | 菜单与鼠标悬停响应 | `HKCU\Control Panel\Desktop` → `MenuShowDelay='100'`、`DragFullWindows='1'`；`HKCU\Control Panel\Mouse` → `MouseHoverTime='100'` | 全为 `'100'` / `'1'` | **注销 / 重启 explorer** | **100 是"统一基准值"**：Windows 默认是 400，所以从默认出发是加速；但若你已手工调得比 100 更快，这一步会把它**归到 100（相对变慢）**。50ms 与 100ms 都在"即时"阈值内，人不可感 |
| **D13** | 确保图形界面组件在位 | 依次检测并按需启用 `Server-Gui-Shell` / `Server-Gui-Mgmt-Infra` / `Desktop-Experience` 三者中**本 build 存在的那一个** | 已安装 | 可能需重启 | 主判据是 `InstallationType`（一手来源），不靠特性目录有没有某个名字 —— 2025 的目录里已无 `Desktop-Experience` |
| **D14** | 启用主题与音频服务 | 服务 `Themes`、`Audiosrv`、`AudioEndpointBuilder` 启动类型设为**自动** | Auto | 立即（音频栈首次需重启） | Server 默认不开音频；不启用这三项就没有声音与主题 |
| **D15** | 抑制 OneDrive 同步与"Windows 备份"推广 | `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive` → `DisableFileSyncNGSC=1`；`HKCU\...\Explorer\Advanced` → `ShowSyncProviderNotifications=0`；`HKLM\...\WindowsBackup` → `DisableMonitoring=1`；并**移除** `HKCU\...\Run` 下的 `OneDrive` / `OneDriveSetup` 自启项 | 见左；两个自启项应为"不存在" | 立即 | 服务器上通常没装 OneDrive，策略键写入后被系统忽略、无副作用 |

### 4.2 Performance —— 性能与电源（8 项）

| 编号 | 调优项 | 具体改动 | 期望值 | 生效 | 注意 |
|---|---|---|---|---|---|
| **P2** | 关闭 CPU 核心停泊 | `powercfg` 设 `SUB_PROCESSOR` / `CPMINCORES` = 100（AC 与 DC 都设），并 `/setactive` | 100 / 100 | 立即 | **虚拟机上常报 N/A**：本方案不暴露 `CPMINCORES` 时记"不适用"并附 `powercfg` 原文；单核主机同样记 N/A |
| **P4** | 关闭磁盘 / PCIe / USB 空闲省电 | `SUB_DISK`/`DISKIDLE=0`（AC+DC）、`SUB_PCIEXPRESS`/`ASPM=0`、USB 选择性挂起（GUID `2a737441…`/`48e6b7a6…`）=0 | 全 0 | 立即 | 换来的核心唤醒与设备链路延迟下降；耗电增量很小 |
| **P5** | 关闭"快速启动" | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power` → `HiberbootEnabled=0` | 0 | 下次关机 | **不改变休眠状态**：脚本刻意不下 `powercfg /hibernate`（虚机上该调用常返回"不支持"，且它会吞掉后面这半项）。休眠关闭时会提示你自行 `powercfg /hibernate on` |
| **P6** | 精简视觉特效但**保留字体平滑** | `HKCU\...\Explorer\VisualEffects` → `VisualFXSetting=3`；`HKCU\Control Panel\Desktop\WindowMetrics` → `MinAnimate='0'`；`HKCU\...\Explorer\Advanced` → `TaskbarAnimations=0`、`ListviewShadow=0`、`ListviewAlphaSelect=0`；`HKCU\SOFTWARE\Microsoft\Windows\DWM` → `EnableAeroPeek=0`；并显式把 `FontSmoothing='2'`、`FontSmoothingType=2` 写回 | 见左 | **注销 / 重启 explorer** | 原版 bat 一律套"最佳性能"会把 ClearType 一起关掉、字发毛；本脚本专门把字体平滑写回来 |
| **P7** | NTFS 调优 | `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem` → `NtfsDisableLastAccessUpdate=1`、`NtfsDisable8dot3NameCreation=1`。**`NtfsMftZoneReservation` 不写、只报告**（V13.1 起）| 1 / 1 / （第三项只看不判） | 前两项立即（8dot3 只对新文件）| ① `NtfsDisableLastAccessUpdate` 是**位域**，系统会把它规范成 `0x80000001` 之类的"系统管理"编码，判定只看 bit0；② **8.3 短名关闭对已存在文件不追溯，此后依赖短名的老安装器/工具可能失败**（本脚本少见的兼容性代价项）；③ **MFT zone 对现有卷不改变布局** —— 这一格绿与"能被感知的收益"没有因果关系 |
| **P8** | 关机时不清空页面文件 | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` → `ClearPageFileAtShutdown=0` | 0 | 下次关机 | 显著缩短关机等待；代价是页面文件内容不擦除（本机物理安全由你掌握） |
| **P9** | 关闭遥测策略与 CEIP 计划任务 | `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` → `AllowTelemetry=0`；并禁用 **11 个**计划任务：Application Experience 下 `Microsoft Compatibility Appraiser` / `ProgramDataUpdater` / `StartupAppTask` / `PcaPatchDbTask`，CEIP 下 `Consolidator` / `UsbCeip` / `KernelCeipTask`，Feedback\Siuf 下 `DmClient` / `DmClientOnScenarioDownload`，DiskDiagnostic 的 `Microsoft-Windows-DiskDiagnosticDataCollector`，Windows Error Reporting 的 `QueueReporting` | 策略 0；11 个任务为 Disabled | 立即 | **这是自愈项，不是一次性项**：真机实测 `PcaPatchDbTask` 跨重启会被 Windows 维护栈重新启用。报告会明确写出这一性质，避免被误读成"脚本失效"。任务"本机不存在"计为达标（并印出数量） |
| **P10** | 关闭 SysMain（Superfetch） | 服务 `SysMain` → 停止 + 启动类型**禁用** | Disabled | 立即 | 机械盘上 SysMain 有正面价值；SSD/虚机上收益为"少一层后台预读"。服务不存在则静默跳过 |

### 4.3 Network —— 网络栈（3 项）

| 编号 | 调优项 | 具体改动 | 期望值 | 生效 | 注意 |
|---|---|---|---|---|---|
| **N1** | TCP 全局参数 | `netsh int tcp set global autotuninglevel=normal`、`rss=enabled`、`heuristics disabled`（后两条用"容忍非零退出"模式） | autotuning=normal；RSS=enabled | 立即 | 回读走**语言无关**的一手来源 `Get-NetOffloadGlobalSetting` / `Get-NetTCPSetting`（5.1 与中文系统下都可用）；**heuristics 这一项写得到、读不回**，证据行会明说 |
| **N2** | 关闭所有接口的 Nagle 算法 | 遍历 `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces` 下**每个**接口子键 → `TcpAckFrequency=1`、`TCPNoDelay=1` | 全为 1 | 立即（已建立的连接需重连） | **交互延迟敏感场景（远程桌面、SSH）收益明显**；**但每个包都回 ACK，在高吞吐/大文件/iSCSI 场景会略增 CPU 与网络开销** —— 参见第八节 |
| **N3** | 只禁用 IPv6 **过渡隧道** | `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters` → `DisabledComponents=1` | 1 | **重启** | `0x01` 的语义是"只禁用隧道接口（6to4 / ISATAP / Teredo）"，**不触碰 IPv6 本体** |

### 4.4 Services —— 服务精简（4 项 + 2 opt-in）

| 编号 | 调优项 | 具体改动 | 生效 | 注意 |
|---|---|---|---|---|
| **S1** | 禁用证书传播服务 | `CertPropSvc` → 停止 + 禁用 | 立即 | 禁用后智能卡 / UKey 上的证书不再自动传播到用户证书存储；依赖智能卡登录或签名的场景会失效。服务器侧不做 UKey 客户端操作，故禁用 |
| **S3** | 禁用蓝牙服务 | `BthServ`、`BTAGService`、`BthAvctpSvc` → 停止 + 禁用 | 立即 | 三个服务中本 build 不存在的会被跳过；探针会区分"全不存在"（ABSENT）与"部分未禁用"（NOT-SET） |
| **S4** | 禁用 DiagTrack（连接用户体验与遥测） | `DiagTrack` → 停止 + 禁用 | 立即 | 遥测数据收集主服务 |
| **S5** | 禁用 dmwappushservice | `dmwappushservice` → 停止 + 禁用 | 立即 | WAP 推送消息路由，桌面用途无意义 |
| **S6** | 禁用打印后台处理程序（**opt-in**） | `Spooler` → 停止 + 禁用 | 立即 | 只在传 `-DisableSpooler` 时注册。**不打印的机器关掉它可缩小攻击面**（PrintNightmare 类漏洞面） |
| **S7** | 禁用 WLAN AutoConfig（**opt-in**） | `WlanSvc` → 停止 + 禁用 | 立即 | 只在传 `-DisableWLAN` 时注册。有线服务器可关 |

> **守卫清单**：`Spooler`、`WlanSvc`、`dot3svc`、`Dnscache`、`LanmanServer`、`LanmanWorkstation`、`RpcSs`、`EventLog` 在 `Disable-Svc` 的"永不禁用"守卫里；守卫清单是**地板**，配置文件只能往上加，不能往下削。

### 4.5 Security —— 加固（5 项，全部"无使用代价"）

| 编号 | 调优项 | 具体改动 | 期望值 | 生效 | 注意 |
|---|---|---|---|---|---|
| **SEC1** | 禁用 LLMNR | `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient` → `EnableMulticast=0` | 0 | 立即 | 根治 UNC / 主机名投毒（Responder 类攻击）的入口。若在内网依赖 LLMNR 做名称解析会受影响（现代网络几乎不用） |
| **SEC2** | 禁用所有接口的 NetBIOS over TCP/IP | 遍历 `HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces` 下**每个** `Tcpip_{GUID}` → `NetbiosOptions=2` | 全为 2 | **重启 / 重启网卡** | 与 SEC1 同族（关掉 NBT-NS 投毒面）。**老应用用 NetBIOS 名访问共享会受影响** |
| **SEC3** | 关闭 SMBv1 服务端 | `Set-SmbServerConfiguration -EnableSMB1Protocol $false` | False | 立即 | **原生命令回放通道**：改动前的状态会被读出并登记，还原脚本会按原值回写。若仍有老设备/老备份软件依赖 SMBv1，会断 |
| **SEC4** | 禁用所有驱动器的 AutoPlay / AutoRun | `HKLM\...\Policies\Explorer` → `NoDriveTypeAutoRun=255`、`NoAutorun=1`；`HKCU\...\AutoplayHandlers` → `DisableAutoplay=1` | 见左 | 立即（部分需重新登录） | 255 = 所有驱动器类型都禁；插 U 盘不再弹自动播放 |
| **SEC5** | 禁用 WDigest 明文凭据缓存 | `HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest` → `UseLogonCredential=0` | 0 | **重启** | 阻止明文口令留在内存（Mimikatz 类抓取）；现代系统默认已是 0，此处是显式确认 |

### 4.6 Ops —— 可运维性（3 项）

| 编号 | 调优项 | 具体改动 | 期望值 | 生效 | 注意 |
|---|---|---|---|---|---|
| **OPS3** | 启用长路径支持（260+ 字符） | `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem` → `LongPathsEnabled=1` | 1 | **重启**，且**应用本身要声明长路径感知**才真正生效 | 深层目录（如 node_modules、构建产物）不再报"路径过长" |
| **OPS4** | 关闭时区自动更新 | 服务 `tzautoupdate` → 停止 + 禁用 | Disabled | 立即 | 避免系统在你工作时偷偷改时区（日志时间戳、计划任务会跟着漂） |
| **OPS5** | 有人登录时不自动重启（Windows Update） | `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU` → `NoAutoRebootWithLoggedOnUsers=1` | 1 | 立即 | 更新仍会装，只是不趁你在用时重启 |

### 4.7 Cleanup —— 白名单清理与备份保留（2 项，不可逆）

| 编号 | 调优项 | 具体行为 | 注意 |
|---|---|---|---|
| **CL1** | 清理白名单临时与缓存目录 | 只清这 **6 个固定目录**的顶层条目：`%SystemRoot%\Temp`、`%SystemRoot%\SoftwareDistribution\Download`、`%LOCALAPPDATA%\Temp`、`%ProgramData%\Microsoft\Windows\WER\ReportQueue`、`...\WER\ReportArchive`、`%SystemRoot%\Logs\CBS`。逐条记录去留，被占用删不掉的单列并计 **PARTIAL** | ① **这是全脚本唯一不可逆的动作**（删除没有撤销），也不在还原脚本覆盖范围内；② 明确排除 `System32\LogFiles`（IIS 与系统诊断日志）；③ 绝不递归扫整盘扩展名（原版 bat 的 `del /f /s /q C:\*.log` 就是那种会删掉中间件日志与许可证校验文件的写法）；④ 遇到**重解析点（junction / symlink）只登记不删**（防越界删除目标内容） |

| **CL2** | 备份保留：只留当天 | 扫备份根的直接子目录，凡名字匹配 `Svr2Desktop_<日期>_<时间>` 或 `Svr2Desktop_verify_<日期>_<时间>` 且**日期不是今天**的，整目录删除；今天的全部保留（同一天更早那几次也留）。逐条留证据（删了哪些、释放多少字节、跳过了哪些），失败计 **PARTIAL**，回读断言"凡报告已删的必须真的不存在" | ⚠️ **这条策略有代价**：删旧备份 = 失去回滚到更早状态的能力（能回滚的最远点 = 今天最早那次运行之前）。安全约束四条：只动备份根直接子目录、名字认不出的一律跳过并列出、只删目录不碰文件、预演下不执行。要保住全部历史备份，把配置里的 `CleanupEnabled` 置 `false`（CL1+CL2 一起停用） |

### 4.8 Downgrade —— 安全降级档（4 项，**必须显式选择**）

⚠️ 这一档是"拿一个安全控制换一点便利"。它们**不在任何默认路径里**：菜单需选 [10]、命令行需 `-Stage Downgrade` 或 `All`；配置文件的键名白名单不含它们；执行前会打印风险摘要与回滚命令并要求确认。

| 编号 | 调优项 | 具体改动 | 期望值 | 生效 | 代价与还原 |
|---|---|---|---|---|---|
| **SEC10** | 管理员提权不再弹 UAC 提示 | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` → `EnableLUA=1`（保留 UAC 框架）、`ConsentPromptBehaviorAdmin=0`、`PromptOnSecureDesktop=0` | 1 / 0 / 0 | 立即（部分需注销） | **代价**：管理员账户提权不再有提示。`EnableLUA` 保持 1，完整性级别与文件虚拟化机制都在。**耦合警告**：`PromptOnSecureDesktop=0` 单独存在时是经典 UAC 绕过口，只有在 `ConsentPromptBehaviorAdmin=0`（本就无提示）时风险才不放大 —— 日后若把后者改回 2 或 5，**必须同步把前者改回 1**。还原：两值置 5 / 1 |
| **SEC11** | 关闭 Defender 实时防护与服务 | 6 项 Defender 偏好置真（`DisableRealtimeMonitoring` / `DisableBehaviorMonitoring` / `DisableScriptScanning` / `DisableIOAVProtection` / `DisableArchiveScanning` / `DisableScanningNetworkFiles`）；策略键 `DisableRealtimeMonitoring=1`；服务 `WinDefend`、`WdNisSvc` 停止 + 禁用 | 见左 | 立即 | **刻意不卸载组件**（`Uninstall-WindowsFeature` 需安装介质、不可逆）。若开了**篡改保护**，本步会如实记 FAIL 而不假绿。还原：策略键复位 + `Set-Service WinDefend -StartupType Automatic` + 6 项偏好转回原值（走原生命令回放） |
| **SEC12** | 密码永不过期（长度与复杂度保持默认） | `secedit` 写入 `MaximumPasswordAge = -1`；`Set-LocalUser -Name <当前用户> -PasswordNeverExpires $true` | 策略 = -1；账户标志 = False（"密码过期被禁用"） | 立即 | 只取消"过期"，**长度与复杂度不动**（那两项只在设置密码那一刻生效，不产生日常打扰）。**改动前的原值会被导出并登记**，还原脚本按原值回放（`net accounts /maxpwage:<原值>`）。判据用 `Win32_UserAccount.PasswordExpires`（结构化字段、不依赖系统语言） |
| **SEC13** | 屏蔽安全中心告警与托盘图标 | `HKLM\...\Windows Defender Security Center\Notifications` → `DisableNotifications=1`；`...\Systray` → `HideSystray=1`；移除 `HKLM\...\Run` 下的 `SecurityHealth` | 见左；`SecurityHealth` 应为"不存在" | 立即 | 关掉 Defender 后安全中心会持续报红叉与通知，屏蔽它才是真正减少打扰。**刻意不写** Windows 7 时代的 `Security Center\Notifications_Disable`（在 2016+ 上已废弃、无效） |

### 4.9 VBS —— 安全降级档（1 项，**必须显式选择**）

| 编号 | 调优项 | 具体改动 | 期望值 | 生效 | 代价与还原 |
|---|---|---|---|---|---|
| **V1** | 关闭 VBS / Credential Guard / HVCI | `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard` → `EnableVirtualizationBasedSecurity=0`；`...\Control\Lsa` → `LsaCfgFlags=0`；`...\DeviceGuard\Scenarios\CredentialGuard` → `Enabled=0`；`...\HypervisorEnforcedCodeIntegrity` → `Enabled=0` | 全为 0 | **必须重启** | **代价**：VBS 关闭会移除基于虚拟化的凭据保护（NTLM 哈希 / Kerberos TGT），换来响应速度。执行前会打印 `VBS status before/after` 并提示重启。**注意**：若这四个键原本**不存在**，还原脚本会把它们**删除**（回到"未配置"）—— 删除不等于"显式关闭"，是否回升取决于系统默认 |

---

## 五、备份与还原机制

每次真实执行都会建一个**带时间戳的会话目录**（默认 `C:\Svr2DesktopBackup\Svr2Desktop_<时间戳>\`），里面有：

| 文件 | 内容 |
|---|---|
| `Svr2Desktop.log` | 完整日志（含每一行证据，屏幕静音也照样落日志） |
| `Restore_<时间戳>.ps1` | **还原脚本**：回放注册表 / 服务 / 功能 / 计划任务 / 电源 + **原生命令回放段** |
| `Svr2Desktop_result.json` | 机器可读结果（带 `-Json` 时） |
| `environment.txt` / `services.csv` / `features.csv` / `powerplans*.txt` | 改动前的环境快照 |
| `misc_snapshot.txt` | 其它归档（如 VBS 执行前状态） |

**还原脚本的覆盖范围（V12 已如实标注）**：

- ✅ **可回放**：注册表（含"原本不存在→删除"）、服务启动类型与运行状态、Windows 功能、计划任务、电源方案内各项值；
- ✅ **原生命令回放段**：密码策略（`net accounts /maxpwage:<原值>`）、TCP 全局参数（`netsh int tcp set global …`）、SMBv1（`Set-SmbServerConfiguration`）、Defender 偏好（`Set-MpPreference`）—— 由**改动方自己给出回放语句**，只登记真正执行过的那些；
- ❌ **不可回放**：清理阶段删掉的临时文件（删除没有撤销），以及本 build 上读不出状态的 TCP `heuristics` 开关。

**备份保留策略（CL2，V13.1 起）**：每次运行（含 `-Verify`）都会在备份根下建一个带时间戳的目录，
累积无上限。CL2 会**只保留当天的、清掉其余全部**（同一天更早那几次也留，它们各自带着还原脚本）。
安全约束：只动备份根的**直接子目录**；目录名必须匹配两种已知会话命名，认不出的一律跳过并列出；只删目录不碰文件。

> ⚠️ **这条策略有代价，必须知道**：每次运行生成的还原脚本只回到"**本次运行之前**"，所以清掉旧备份之后，
> **能回滚的最远点就是今天最早那次运行之前**。要撤销整场调优（回到未调优态），只能手工处理 ——
> 别指望任何时刻都能一键回到出厂态。若哪天真需要，把 `CL2` 跳过（或把配置里的 `CleanupEnabled` 置 `false`）即可保住全部历史备份。

**空壳还原脚本会自报家门（V13.1 起，V13.2 校正措辞）**：本次**没有可回放的值**时（例如只跑一个阶段
且全部 SKIP），生成的还原脚本仍是空壳，但它会在顶部明写 `★ THIS SCRIPT HAS NOTHING TO REPLAY`，
屏幕上也会给一句同样的提示 —— 免得操作员连读五段 `(no … were changed)` 才能确认。

> ⚠️ 措辞刻意区分"**没有可回放的值**"与"**什么都没发生**"：清理阶段（CL1/CL2）可能确实删了文件、
> 动了备份根，但这些动作**不进备份通道**，所以脚本仍然无从回放。说成"什么都没改"会掩盖真实发生过的事 ——
> 那是本脚本最不能接受的一类假话，哪怕方向是"往坏处说"。

**只读模式也会留痕**：`-Verify` 会建一个 `Svr2Desktop_verify_<时间戳>\` 目录只放日志与 JSON（不写快照、不生成还原脚本），因为"两次 `-Verify` 的差集"必须先存得住。

---

## 六、报告怎么看

| 标记 | 含义 |
|---|---|
| `[  OK  ]` | **本次真的执行了动作**，且回读达到期望值（带 before / after 两段证据） |
| `[ SKIP ]` | 本来就已经是期望状态，没动手 |
| `[PARTIAL]` | 动作做了，但存在本脚本无法消除的未尽项（典型是临时文件被进程占用） |
| `[FAIL]` | 回读没达到期望 —— 报告会说明"值有没有移动"：一字未变=动作没触达这个值；变了但没到位=动作生效了、只是没到位 |
| `[N/A  ]` / `[ABSENT]` | 本机没有这一项 / 本机场景下无意义（**这不是缺口**） |
| `[NOT-SET ]` | 只读模式下：存在且未达标（需要动作） |
| `[ONE-SHOT]` | 动作型步骤（清理），没有可回读的稳态 |
| `[WHATIF]` | 预演模式，未执行 |

**两条自证机制**：
- **零证据闸**：判定为负（FAIL / PARTIAL）却一条实测值都没有 → 用黄字点出来（这种结论不可证伪）；
- **自洽性守门人**：判负却拿不出任何 MISMATCH 时，报告必须说明"决定本步的条件没有挂钩子"，**绝不沉默**。

---

## 七、真机验收状态（2026-09-22，Windows Server 2025 Datacenter build 26100）

| 阶段 | 结果 |
|---|---|
| 执行前基线 | SATISFIED 10 · NOT-SET 30 · N/A 1 · ABSENT 1 · ONE-SHOT 1 |
| 执行档（`-Stage All -Json -Force`） | **OK 30 · SKIP 10 · N/A 2 · PARTIAL 1 · FAIL 0 · CHECK-ERROR 0** |
| 重启后 `-Verify` | **SATISFIED 39 · NOT-SET 1**（只剩 P9 的 `PcaPatchDbTask`，已知自愈项） |
| 还原脚本实测 | **applied 87 / failed 0**，还原 + 重启后与原始基线**逐项一致** |
| 双轨一致性 | PowerShell 7 与 5.1 两份报告**逐项相同** |

**唯一长期未达标项**：`P9` 的 `PcaPatchDbTask` —— Windows 维护栈会在启动时把它重新启用，脚本每次运行都会重新禁用它（幂等），报告里也明确写了这是自愈项。

---

## 八、在物理服务器 / 网卡聚合环境下的注意事项（重要）

**结论：脚本不会修改网卡聚合（成组 / LBFO / NetSwitchTeam）的配置本身。**

已逐条核实（源码 AST 全量扫描）：脚本中**没有任何** `NetAdapter`、`NetLbfo`、`NetSwitchTeam`、`netcfg` 之类调用。所以下列都不会被动：

- 成组（team）成员、工作模式（静态 / LACP / 交换机独立）、负载均衡算法；
- IP 地址、DNS 服务器、网关、接口跃点数、适配器绑定顺序；
- 网卡驱动**高级属性**（RSS 队列数、中断节流、LSO、VMQ、SR-IOV、巨帧等）；
- 网卡本身不会被重启（没有 `Restart-NetAdapter`）。

**但下面几项会动到"网络"，需要你知情**：

| 项 | 会做什么 | 在聚合/生产环境要注意什么 |
|---|---|---|
| **N2**（关 Nagle） | 遍历 `Tcpip\Parameters\Interfaces` 下**每一个**接口 GUID，写 `TCPNoDelay=1`、`TcpAckFrequency=1` | **它是逐接口写的，没有排除机制**。对一台做聚合的服务器（通常为吞吐/冗余），关 Nagle 会让每个包都回 ACK，在高吞吐场景**略增 CPU 与网络开销** —— 属反向优化。若这台机器主要跑大流量业务，建议**跳过 Network 阶段**或跑完删掉这两个值 |
| **SEC2**（关 NetBIOS） | 遍历 `NetBT\Parameters\Interfaces` 下每个 `Tcpip_{GUID}`，写 `NetbiosOptions=2` | 同样是"所有接口、无排除"。若集群/老应用依赖 NetBIOS 名称解析会断 |
| **N1**（TCP 全局） | `netsh int tcp set global autotuninglevel=normal rss=enabled heuristics disabled` | `rss=enabled` 与成组的交互由驱动/组决定；脚本用 `Get-NetAdapterRss` 判断"有没有 RSS 能力的网卡"，**但看不到"这张卡属于一个 team"**。该子项已用"容忍非零退出"模式，网卡不支持时不会让整步失败 |
| **N3**（IPv6 隧道） | `DisabledComponents=1` | 只禁 6to4/ISATAP/Teredo，**不动 IPv6 本体**。若你的环境真在用这些隧道（罕见），需跳过 |
| **SEC3**（SMBv1） | 关闭 SMBv1 服务端 | 与聚合无关，但**老设备/老备份软件走 SMBv1 会断**。原值会被登记，可还原 |
| **P4**（省电） | PCIe ASPM=0、USB 选择性挂起=0 | 电源管理层面，不改配置。关 ASPM 会让 PCIe 设备更不易进低功耗 —— 对延迟有利，功耗略增 |

**在生产服务器上的安全做法**：

```powershell
# 1) 先只读看现状，什么都不改（对聚合/生产环境，这一步必做）
.\Svr2Desktop.ps1 -Verify

# 2) 预演：看它到底想改什么，仍然不写盘
.\Svr2Desktop.ps1 -WhatIf

# 3) 若只想桌面体验，明确避开网络与安全阶段
.\Svr2Desktop.ps1 -Stage Desktop,Performance,Ops -Force

# 4) 若跑了 Network / Security 后想撤掉，用当次会话的还原脚本
#    （N2/SEC2 那两个值原本不存在 → 还原即删除）
powershell -ExecutionPolicy Bypass -File C:\Svr2DesktopBackup\Svr2Desktop_<时间戳>\Restore_<时间戳>.ps1
```

**建议的改进（V12.1 候选）**：给 N2 / SEC2 增加一个**接口排除清单**（按 GUID 或网卡名匹配），因为"所有接口"这个粒度对多网卡/聚合/带外管理口的生产服务器**确实太粗**；至少在证据行里把"本机有几个接口、叫什么、哪些属于成组"印出来。

---

*本文档对应 V12 封板版本；安全降级档的任何条目都需你显式选择后才会执行。*

---

# 九、V13 新增：一键引导器与软件部署

> V13 **没有改动本说明里的任何一个调优项** —— `Svr2Desktop.ps1` 仍是 12.0，
> 只是多了两个件：一个引导器、一个部署脚本。这一节说明它们。

## 9.1 目录结构

```
BobWinSvrTurn.cmd     ← 一键入口（双击这个）
Svr2Desktop.ps1       ← 调优（本说明第一~八节的全部内容）
InitBobSoft.ps1       ← 软件部署
BobSoft\              ← 载荷目录（与 .cmd 同目录）
  ToolA\              ← 子目录：整目录复制到 C:\Tools\ToolA
  ToolB\
  7za.exe             ← 解压器（随载荷，脚本自己找，不依赖系统 PATH）
  pack1.7z            ← 压缩包：解压到 C:\Tools
  app.msi             ← 离线包：静默安装
```

## 9.2 引导器 `BobWinSvrTurn.cmd`

| 用法 | 行为 |
|---|---|
| `BobWinSvrTurn.cmd` | 调优（交互菜单，按 [Q] 退出后）→ 继续做部署 |
| `BobWinSvrTurn.cmd -Stage All -Json -Force` | 无人值守：全量调优 → 部署 |
| `BobWinSvrTurn.cmd -TuneOnly` | 只调优 |
| `BobWinSvrTurn.cmd -DeployOnly` | 只部署 |
| `BobWinSvrTurn.cmd -Verify` / `-WhatIf` | 只读调优，**跳过部署**（预演不装软件） |

退出码：`0` 无失败 / `2` 有失败 / `1` 致命（两个子脚本同一契约，合并即取"非 0"，2 优先）。

> 若只想要调优、不带部署（例如在**生产机**上），用 `Svr2Desktop.cmd` 或直接跑
> `Svr2Desktop.ps1` 即可 —— 部署脚本不在场时引导器只给一条 WARN，不会让调优结果变红。

## 9.3 部署脚本 `InitBobSoft.ps1`

```powershell
.\InitBobSoft.ps1                    # 部署（载荷 = 同目录 BobSoft）
.\InitBobSoft.ps1 -WhatIf            # 只列计划，不动任何东西（**首次上机先跑这个**）
.\InitBobSoft.ps1 -PayLoadRoot D:\pkg -TargetRoot D:\Tools
```

**三种模式**（按 `Dir → Archive → Msi` 的顺序执行）：

| 模式 | 载荷长什么样 | 做什么 |
|---|---|---|
| a 目录 | `BobSoft\ToolA\` | `robocopy /E` 全量覆盖到 `C:\Tools\ToolA` |
| b 压缩包 | `BobSoft\pack.7z`（或 .zip/.rar/.tar/.gz/.xz/.bz2/.cab） | `7za.exe x pack.7z -oC:\Tools -y`（**解到 `C:\Tools` 本体，包内自带独立目录**） |
| c 离线包 | `BobSoft\app.msi` | `msiexec /i /qn /norestart /l*v <C:\Tools\_deploy_logs>` |

**不在上表里的文件**（说明、脚本、图片…）会被标 `SKIP` 并**列出原因**：载荷里多放了什么，报告要看得见。

**几处容易踩的地方（脚本已经处理）**：

- **分卷压缩**：`big.7z.001` / `.002` … 只对 `.001` 执行（7z 会自己找后续分卷），其余显式跳过 —— 否则每个分卷都会被单独解一遍；
- **解压器**：优先找 `7za.exe`（单文件、无 dll 依赖），回退 `7z.exe`；若旁边没有 `Codecs\` 目录会提示"**rar 可能解不开**"；
- **robocopy 的退出码是位掩码**：`0–7` 全部是成功，`≥8` 才是失败；
- **msiexec 的"成功"不止 0**：`3010`（装好但需重启）与 `1641`（装好且已发起重启）都算成功，报告标为 WARN；
- **MSI 的回读以日志为准**：解析 MSI 详细日志末尾固定的 `Installation success or error status: N`，比进程退出码更可信；
- **同名冲突**：`C:\Tools` 下同名文件会被覆盖（全量覆盖策略）；多个压缩包的目录不混在一起，靠**包内自带独立目录**隔离。

**日志**：`C:\Tools\_deploy_logs\InitBobSoft_<时间戳>.log`（总日志）+ 每个 MSI 一份 `<包名>.msi.log`。

## 9.4 与"一键还原"的边界

**部署不在还原范围内。** `Svr2Desktop.ps1` 生成的 `Restore_<时间戳>.ps1` 只回放**它自己改过的值**，
不碰 `C:\Tools`。要撤销部署，只能手工删除目录或卸载 MSI。
反过来也一样：部署脚本不做任何注册表 / 服务 / 计划任务调优。

*本节对应 V13；引导器与部署脚本的变更记录见 `CHANGELOG.md` 的 v13.0 条目。*
