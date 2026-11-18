# Svr2Desktop.ps1 审计报告

- **审计对象**：`WinTools/Svr2Desktop.ps1` v11.15 / 2026-09-21 / 3904 行 / 45 处 `Add-Step`（默认注册 43 步）
- **审计时点**：2026-09-22，主机侧（macOS）静态审计 —— **未在 Windows 真机运行**，全部结论来自源码通读 + 行号核对
- **审计口径**：只审"承诺与实现是否一致"、"结论是否可证伪"、"改动是否可还原"三件事；不替作者改设计取向
- **编号规则**：`A-nn` 严重度 P1（不可逆/安全契约）> P2（正确性/一致性）> P3（文档/覆盖）> P4（清洁度）

---

## 0. 审计前置：本目录交付件不完整

现在 `WinTools/` 下**只有 `Svr2Desktop.ps1` 一个文件**，而脚本自身的正文引用了多个不在场的同伴：

| 引用位置 | 引用物 | 现状 | 影响 |
|---|---|---|---|
| 头注 USAGE 第 88 行 | `.\Svr2Desktop.cmd`（双击即交互菜单） | **缺** | Windows 下双击 `.ps1` 的默认动作是「编辑」，不是运行；文档承诺的主入口不存在，且缺提权/执行策略处理 |
| 第 64–65 行 | `CHANGELOG.md`（v11.0→v11.11 逐版记录已移出） | **缺** | "为什么这么改"的历史断链 |
| 第 64 行、1859 行 | `_history/`（逐字节版本快照） | **缺** | 无法对照基线版 |
| 第 929 行 | `fn_behavior_suite.ps1`（行为套件，I 段断言的落点） | **缺** | 注释里作为"可断言"依据的套件不在 |
| 第 3607 行 | `ps_gate_nesting.ps1`（门控嵌套检查器） | **缺** | 注释里作为"量化断言交给检查器"的检查器不在 |
| 第 1392/3228/3248 行 | 「技能 §6.1 / §8-45 / §3.2(e)」 | **缺** | 三处关键判据的外部依据不可查 |
| 第 138 行 | `Svr2Desktop.config.json` | 缺（可选，走内置默认值） | 无影响，属正常 |

> 结论：脚本头部大量"见同目录/见技能"的指向全部悬空。**这不是脚本的逻辑缺陷，而是交付完整性问题** —— 一旦交给别人用，注释里最重要的那部分知识无法追溯。

---

## 1. 先说站得住的（避免只挑刺）

以下设计是真实成立、且在同类脚本里罕见的，审计不推翻：

1. **执行与验证同源**：`Probe`/`Test` 共用判据（`Get-TcpGlobalProbe`、`Get-TelemetryTaskReport`），杜绝"两套读法走偏"。
2. **证据分期**（`Invoke-StepOne` 第 3143–3211 行）：`-- before --` / `-- after --` 两段对照，"值有没有移动"直接可读 —— 这是判"到底写没写进去"的唯一硬依据。
3. **读值原语挂证据钩子**（`Add-Evidence` 挂在 `Test-RegValue`/`Test-SvcDisabled`/`Get-TaskState` 等层），新步骤自动获得证据链。
4. **自洽性守门人**（`Get-EvidenceConflict` 第 732–756 行）："判负却拿不出 MISMATCH"必须开口，拒绝沉默结论。
5. **-WhatIf 控制权回收**（第 183–194 行）：把 `$WhatIfPreference` 交还 PowerShell，改由步骤级显式拦截 —— 这个反直觉写法是对的，否则 `-WhatIf` 会污染所有 cmdlet 的 ShouldProcess。
6. **跨版本编码处理**（`Write-TextFileUtf8Bom`）：5.1 与 7 的 `-Encoding UTF8` BOM 行为相反，交给 .NET API 决定，正确。
7. **安全降级不可由 json 打开**：白名单里确实没有 SEC10–13 的开关。

**但第 7 条有对称缺口**，见 A-04。

---

## 2. 发现清单

### A-01 【P1】还原契约不符："所有改动可一键还原"对 5 处改动不成立

脚本头注承诺「所有改动均可回读验证、可一键还原」，`New-RestoreScript` 生成的还原脚本头注也声称 *"Rolls the machine back to the state captured immediately BEFORE the run"*。实际上**还原脚本只覆盖 `Bak.Reg / Svc / Feat / Task / Power` 五个通道**，以下改动一个都没登记：

| 步骤 | 改动 | 是否进备份通道 | 后果 |
|---|---|---|---|
| **SEC12** | `secedit` 写 `MaximumPasswordAge=-1` + `Set-LocalUser -PasswordNeverExpires $true`（第 2687、2700 行） | **完全没有** | 还原脚本对 SEC12 **零覆盖**；且**改动前的原值从未被任何通道留档**（`Save-EnvironmentSnapshot` 不导密码策略）—— 连手工回滚都得靠猜原值 |
| **SEC11** | `Set-MpPreference` 六项开关（第 2608–2621 行） | 没有（只有策略键与服务进了通道） | 还原后策略键复位、服务起回，但**实时防护仍是关的** —— 还原不完整，而报告会说"已还原" |
| **SEC3** | `Set-SmbServerConfiguration -EnableSMB1Protocol $false`（第 2509 行） | 没有 | 原本开着 SMBv1 的老机器，还原后仍是关的 |
| **N1** | `netsh int tcp set global` ×3（第 2352–2357 行） | 没有 | 写的是 Windows 默认值，风险低，但契约口径不成立 |
| **CL1** | 删除 6 个白名单目录下的条目（第 2919 行） | 结构上不可能 | 删除不可逆，这是全脚本唯一的不可逆动作 |

**行动项（时点：交回 Windows 侧修改时）**
1. 给 SEC12 加"改动前留档"：`Action` 开头 `secedit /export` 一份 SECURITYPOLICY 存进备份目录（现有 `Test` 里已有导出代码，可复用为 `Backup-*` 前置）。
2. SEC11 的 `Set-MpPreference` 六项取值先 `Get-MpPreference` 读回，走 `Bak.Misc`（该通道已有落盘，`misc_snapshot.txt`）登记，并在还原脚本里追加一个 `Invoke-RestoreMpPreference`。
3. SEC3：`Action` 前 `Get-SmbServerConfiguration.EnableSMB1Protocol` 登记，还原脚本按原值回写。
4. 头注把承诺**改成精确口径**：`全部注册表 / 服务 / 功能 / 计划任务 / 电源 改动可一键还原；清理与少数外部命令（SEC3/SEC11 偏好的 N1）只有留档，需人工回放`。宁可口径窄，不要宽承诺。

### A-02 【P2】正文里的"手动回滚"命令方向写反

第 3738 行，在**安全降级批**的风险摘要里：

```
Rollback: ... Manual:
    net accounts /maxpwage:UNLIMITED   (or secedit with your own inf)
```

`UNLIMITED` **正是降级后的状态**，不是回滚。这是整个脚本唯一在"降级前"展示给操作员的手动兜底，写反了等于没有兜底。同段第 3739–3740 行的两条 `reg add`（`ConsentPromptBehaviorAdmin=5` / `PromptOnSecureDesktop=1`）方向是对的 —— 只有这一条错。

**行动项**：改为 `net accounts /maxpwage:<你原来的天数>`，并注明"原值见备份目录，或执行前先 `net accounts` 记一笔"（与 A-01 第 1 条同源修复）。

### A-03 【P2】`-Verify` 模式的证据与报告**不落任何文件**

这是与脚本自身方法论冲突最重的一处。脚本推荐的核心流程是：

> 「1) `-Verify` 存基线 → 2) 执行 → 3) `-Verify` 与基线对照，差集就是本次改了什么」

但 `-Verify` 路径（第 3858–3862 行）**不创建备份会话**，而 `$script:LogFile` 只在 `New-BackupSession`（第 359 行）里被赋值 → `Write-Log` 在第 262 行直接 `return`。于是：

- `-Verify` 的全部证据行**只存在于屏幕**，日志文件不存在；
- `-Json` 在 `-Verify` 下也无效：入口在 `Save-JsonResult` 之前就 `return`，而 `Save-JsonResult` 又要求 `$script:Bak.Dir` 非空（第 3495 行），**双重失效**。

结果：**基线无法留存**。那条"两次 -Verify 差集"的方法论在文件层面不成立，只能靠人肉复制屏幕输出。头注却写着"证据行始终完整写进日志文件 —— 静音屏幕不等于放弃留痕"。

**行动项**：`-Verify` 分支开一个只写日志的会话目录（如 `%TEMP%\Svr2Desktop_verify_<stamp>\` 或 `CWD`），让 `Write-Log` 有落点；`Save-JsonResult` 改为在无 `Bak.Dir` 时落到同一位置。改动量小，收益是方法论闭环。

### A-04 【P2】安全守卫清单可以被旁边的 json 清空

脚本明确声明"配置文件走键名白名单，拒绝可劫持脚本自身行为的键"，安全降级"不能被一个放在旁边的 json 悄悄打开"。**方向是对的，但守卫清单本身在白名单里**：

- 第 340 行白名单包含 `NeverDisable`；
- 第 341–343 行无条件用 json 的值覆盖；
- 第 1123–1125 行 `Disable-Svc` 的唯一守卫就是它。

一个 `{"NeverDisable": []}` 就能把 `Spooler / WlanSvc / RpcSs / EventLog / Dnscache / LanmanServer …` 的守卫全部清空。按今天的步骤定义这不会直接造成破坏（内置步骤没禁这些服务），但**"守卫只能加、不能被配置削弱"这条不变量在实现上不存在** —— 与作者自己写下的威胁模型同一个维度。

**行动项（一行）**：`$cfg.NeverDisable` 改为**内置清单 ∪ json 清单**（并集而非覆盖），json 只能在 unions 意义下加码。

### A-05 【P2·待真机验证】`2>&1` + `$ErrorActionPreference='Stop'` 可能封死 `-AllowNonZero` 逃生口

第 178 行全局 `$ErrorActionPreference = 'Stop'`；`Invoke-Native`（第 1281 行）写的是 `$out = & $File @Arguments 2>&1`。

Windows PowerShell 5.1 有一个已知行为：**原生命令的 stderr 被重定向进成功流时，其记录会以 `NativeCommandError` 形式走错误处理管线**，在 `ErrorActionPreference='Stop'` 下成为**终止性错误**。若成立，则：

- `netsh int tcp set global rss=enabled -AllowNonZero`（第 2356 行）在网卡不支持 RSS、netsh 把拒绝写到 stderr 时，**仍会抛错**，`-AllowNonZero` 形同虚设；
- 报错文本会是 `NativeCommandError`，而不是 `Invoke-Native` 精心构造的那句"哪个命令、退出码多少、输出什么"；
- 与头注第 80–82 行的预期恰好相反 —— 那里担心的是 PS7 的 `$PSNativeCommandUseErrorActionPreference`，却漏了 5.1 自己的重定向路径。

**一行验证（Windows 侧，5.1 下跑）**：

```powershell
$ErrorActionPreference = 'Stop'
& cmd /c "echo boom 1>&2" 2>&1      # 抛 NativeCommandError → 假设成立
```

若成立，**最小修法**：`Invoke-Native` 内改为临时局部化偏好（`$ErrorActionPreference='Continue'` 只在函数内），或改用 `Start-Process`/`System.Diagnostics.Process` 直接收 stdout/stderr —— 后者零歧义但代码变长；**优先选前者（一行）**。

### A-06 【P2】交互菜单 `[V]` 的统计会与上一轮执行结果混在一起

`Start-Optimization` 在入口重置 `$script:Results`（第 3691 行），但 `Invoke-VerifyReport` **不重置**（第 3320 行起，只有 `Add`）。而菜单 `[V]` 直接调 `Invoke-VerifyReport; Write-Summary`（第 3823 行）。

于是"先跑 [1] Desktop，再看 [V]"这条最自然的操作路径下，`Write-Summary` 的计数是**两轮混算**：`OK=8 SKIP=3`（执行态）与 `SATISFIED=…/NOT-SET=…`（验证态）同时出现，`$fails`/`$silent`/`$notset` 三个清单也跨轮次混装。

**行动项**：`Invoke-VerifyReport` 开头加 `$script:Results = New-Object System.Collections.ArrayList`（与 `Start-Optimization` 同源），一行。

### A-07 【P2】D14 的存在性判据把"读不出"当成"本机没有"

`Get-SvcStartMode`（第 977–983 行）在**服务不存在**与**CIM 查询失败**两种情况下都返回 `$null`。D14 的 `Probe`（第 1934 行）用 `$null -ne $m` 直接当"服务存在"判据：

- 三个服务都读不到 → `$present.Count -eq 0` → 报 **ABSENT**（"no Themes/Audio services on this build"）；
- 若真相是"服务在、但 WMI 查询失败"，这一格就把**真实缺口**报成了"本机没有这项"，而后者的语义是"不是缺口"。

对比同文件里的正确做法：`Get-SvcProbe`（第 1013 行）先用 `Get-Service` 判存在、再用 CIM 读启动类型；`Get-TaskState`（第 1163–1224 行）更是专门加了"调度器读不到但后备文件在"的第二来源。**P9 那条线修得很彻底，服务这条线留了同一个洞。**

**行动项**：D14 的 `Probe` 改为按 `Get-Service` 判存在（与 `Get-SvcProbe` 同源）；`Get-SvcStartMode` 返回 `$null` 时不得解释为"缺席"，应记 `read-back unavailable` 并给 NOT-SET。

---

### A-08 【P3】N1 标题承诺三项，回读只覆盖两项，且未声明

`N1` 标题是 *"TCP global parameters (autotuning / RSS / heuristics)"*，Action 写三项（第 2352–2357 行），但 `Get-TcpGlobalProbe` 只读 `autotuning` 与 `RSS` —— **`heuristics` 既无回读也无证据行**，报告不会提它。这与 SEC3 当年"有 Test 无证据"是同一族的覆盖缺口，而本脚本对那一族的态度是零容忍（第 3340–3350 行的读侧覆盖报告就是为此造的）。

**行动项**：二选一 —— ① 标题收窄为 autotuning / RSS；② 补一条 `Add-Check` 明说 `heuristics: no language-independent read-back available on this build`。**推荐 ②**（覆盖缺口要留痕，不留痕就永远没人修）。

### A-09 【P3】菜单 `[A]` 手抄了一份阶段清单

第 250 行的注释写得很清楚：「合法阶段名一律从 `$script:StageNames` 派生 —— 同一份清单抄三份，早晚各写各的」。但第 3818 行菜单 `[A]` 是硬编码：

```powershell
$all = @('Desktop', 'Performance', 'Network', 'Services', 'Security', 'Ops', 'Cleanup')
```

这正是 `$script:BaseStages`（第 253 行）的内容。今天两者一致，但**新增阶段时菜单会漏**，而且漏的方式是静默的（`[A]` 少跑一段，报告里看不出来）。

**行动项**：`$all = @($script:BaseStages)`，一行。

### A-10 【P3】N2 / SEC2 在"接口枚举为空"时永久 FAIL，且都没有 Probe

第 2386 行（N2）与第 2498 行（SEC2）都是 `if ($subs.Count -eq 0) { return $false }`，且两步**都没有 `-Probe`**。P2（CPMINCORES）与 P5（HiberbootEnabled）已经因为同类问题获得了三态探针，"枚举为空 → 永久红"这条路在这两步上仍然存在 —— 而长期红灯与长期黄灯一样会训练操作员无视颜色（第 1650–1654 行自己写的规则）。

**行动项**：给两步各加一个最小 `Probe`：`$subs.Count -eq 0` → `NA`（"this build exposes no interface key"）。不到十行。

### A-11 【P3】P9 的证据措辞对"读不到"的任务说了不成立的话

第 2186 行的证据句是：

```
re-disabled N task(s) that were still enabled when this run read them: ...
```

但进入 `$reDone` 的有两种情况：① 读到且不是 Disabled；② **`$st.Found=$false` 但后备文件在**（第 2175–2178 行，即"读不到"）。对第 ② 种，句子里的 `still enabled` 是**未经证实的断言** —— 而这类"证据说了证据支持不了的话"正是本脚本守门人专门要杀的。

**行动项**：措辞按档分开，如 `re-disabled N task(s): X (was Ready), Y (state unreadable, attempted anyway)`。第 2183 行已经算出了 `state unreadable` 这个事实，只差让它进句子。

### A-12 【P3】P7 的 MFT 项是"值达标 ≠ 效果存在"

`NtfsMftZoneReservation=2` 写进去、回读也是 2，报告会判 OK。但按微软文档，**MFT zone 的设置只对"新建卷"生效**，对已有卷不改变现有 MFT 布局 —— 即这一格的绿色与"用户能感知的收益"之间没有因果关系。同类还有 `NtfsDisable8dot3NameCreation`（对已存在文件不追溯，且依赖短名的老安装器可能失败，而 WARNING 段没有提示这条兼容风险）。

这与全脚本最核心的原则相冲突：**判据是"配置值就位"，不是"效果发生"**。这条原则本身没错（不可回读的效果只能如此），但至少要对这一类明说。

**行动项**：给 P7 的 MFT 项加一条 `-Note`（机制已存在于 `Test-RegValue`）：`MFT zone applies to newly formatted volumes only`；WARNING 段补一句 8dot3 的兼容风险。

### A-13 【P3】文档声称三项 PS7 增益，`$PSStyle` 零引用

头注第 73–76 行列出 PS7 增益：`Test-Json`（✅ 第 326 行有用）、`Get-Error`（✅ 第 3898 行有用）、**`$PSStyle`（❌ 全文零引用**，彩色输出一律走 `Write-Host -ForegroundColor`）。

一个"空头承诺"在文档里，正是本脚本反复警惕的那类事（声明与实现不一致）。

**行动项**：从列表里删掉 `$PSStyle`，或真接入。删除更符合"复杂度是负债"。

### A-14 【P3】桌面类步骤"注册表达标"与"用户可感知"之间缺一句提示

D7（任务栏）、D8（资源管理器默认）、D9（开始菜单）、D12（菜单/悬停延迟）、P6（视觉特效）多数需要 `explorer.exe` 重启或注销后才被用户看到。脚本最后只提示重启，不提示注销/重启资源管理器；而报告会全绿。这不是缺陷，是**预期管理缺口**：操作员"跑完全绿但没感觉变快"，第一反应是"脚本没用"。

**行动项（不加机制，只加一句话）**：Desktop 阶段结束后 `Write-Note` 一句 —— `some desktop changes only take effect after signing out / restarting Explorer`。**不要**为此加自动重启 explorer 的机制。

### A-15 【P3·待真机验证】CL1 的递归删除未排除重解析点

第 2919 行 `Remove-Item -LiteralPath $i.FullName -Recurse -Force`。目标目录（`%TEMP%`、`SoftwareDistribution\Download`、`WER\*`、`Logs\CBS`）都是**别的软件可以往里放 junction / symlink 的活体目录**。Windows PowerShell 5.1 的 `Remove-Item -Recurse` 对目录重解析点的行为是"跟随并删除目标内容"（`-FollowSymlink` 是 PS 6+ 才有的显式开关）。

v8.1 的整盘 `del /s` 被删除的理由正是"越界删除"这一类，而这里是**唯一残余的递归删除点**。

**验证（真机，一条）**：在 `%TEMP%` 建 `mklink /J t C:\TempTarget`（目标放一个标记文件），跑 `Remove-Item .\t -Recurse -Force`，看目标标记文件是否消失。

**最小修法**：删除前用 `(Get-Item -LiteralPath $i.FullName).Attributes -band [IO.FileAttributes]::ReparsePoint` 判定，遇重解析点**只删链接自身**（`Remove-Item` 不带 `-Recurse`）或直接跳过并记 `Kept`。三行，成本极低；漏判的代价是不可逆。

### A-16 【P4】两处清洁度问题

1. **第 3288–3302 行 `Invoke-StageByName -Name 'Backup'` 是死分支**：`-Stage Backup` 会被 `Resolve-StageList` 拒（`ValidStages` 不含 Backup），`Start-Optimization` 也只遍历 `BaseStages`，全文没有任何调用点能传进 `'Backup'`。那段为 `-WhatIf` 加固的守卫永远不会被执行（注释说它由"第六层检查器"发现并要求加固 —— 检查器替死代码加固，本身是个信号）。
2. **无"存在 FAIL 则非零退出"的开关**：脚本定位里写了"便于批量部署后汇总"，但 `exit 0` 恒成立（除致命异常），编排器只能靠解析 JSON 判成败。

---

## 3. 需要真机确认的两个假设（唯一无法在主机侧定论的）

| 编号 | 假设 | 验证方式 | 若成立的影响 |
|---|---|---|---|
| A-05 | 5.1 下 `& cmd 2>&1` + `EAP=Stop` 抛 `NativeCommandError` | 见 A-05 的一行命令 | `-AllowNonZero` 失效；N1 在不支持 RSS 的网卡上会抛错而非容忍 |
| A-15 | 5.1 的 `Remove-Item -Recurse` 跟随目录 junction 删目标内容 | 见 A-15 的 junction 实验 | CL1 存在越界删除路径 |

建议：在**同一个快照点**上把这两条一次跑完，把原始输出留档 —— 这两条的结论会直接决定 `Invoke-Native` 与 `Invoke-CleanupTarget` 要不要改。

---

## 4. 行动项汇总（按时点排序）

**第一批（改前必做，安全契约）**
1. A-01：SEC12 加改动前留档；SEC11 的 `Set-MpPreference` 六项登记 + 还原；SEC3 登记 + 还原；头注口径收窄。
2. A-02：第 3738 行回滚命令方向改正。
3. A-15：CL1 加重解析点守卫（先做实验，再决定）。

**第二批（一行级，收益明确）**
4. A-03：`-Verify` 落日志 + `-Json` 可用（方法论闭环）。
5. A-06：`Invoke-VerifyReport` 开头重置 `$script:Results`。
6. A-04：`NeverDisable` 改为并集。
7. A-09：菜单 `[A]` 改用 `$script:BaseStages`。
8. A-13：删掉 `$PSStyle` 空头承诺。

**第三批（覆盖缺口，与既有教条对齐）**
9. A-05：`Invoke-Native` 局部化 `$ErrorActionPreference`（若实验成立）。
10. A-07：D14 `Probe` 改按 `Get-Service` 判存在。
11. A-08：N1 的 heuristics 补 `Add-Check` 或收窄标题。
12. A-10：N2 / SEC2 补最小 `Probe`。
13. A-11：P9 证据措辞按档分开。
14. A-12：P7 MFT 项加 `-Note`；WARNING 补 8dot3 兼容风险。
15. A-14：Desktop 阶段后加一句"需注销/重启资源管理器"的提示。

**第四批（清洁度 / 交付）**
16. A-16：清理死分支；视需要加非零退出开关。
17. 第 0 节：补齐 `Svr2Desktop.cmd`（**这个最影响实际使用**）、`CHANGELOG.md`；确认 `_history/`、`fn_behavior_suite.ps1`、`ps_gate_nesting.ps1` 是"未随本次拷贝带过来"还是"从未存在"。

---

## 5. 一个开放性架构问题（不构成发现，供决策）

3904 行 / 45 步 / 单文件：分发简单（一个文件丢到虚机就能跑），代价是认知负担与注释密度。脚本正文引用的三样东西（行为套件、门控检查器、技能文档）都在文件外，现在又都不在场 —— 也就是说**这套"注释里保存知识"的机制，一旦跨机器拷贝就失效**。

两条路，供你拍板：

| 方案 | 做法 | 优点 | 代价 |
|---|---|---|---|
| **保持单文件** | 只补 `Svr2Desktop.cmd`，注释不动 | 分发零成本；现有结构已验证可用 | 知识仍只活在注释里；跨机器拷贝仍断链 |
| **最小分层** | 步骤定义拆成 `steps/*.ps1` 由主文件 dot-source，注释随之迁移 | 单文件问题解掉；改动点集中 | 分发变成"一个目录"；dot-source 顺序需固定 |

**我倾向保持单文件 + 补 `.cmd`**：这套脚本的价值恰恰在于"一个文件、丢进虚机、双击就跑"，分层换来的只是维护者舒适度，而维护者只有一个。真要减负，把注释里那三处外部引用（技能 §、套件、检查器）删掉或内联，成本比拆文件更低。

---

---

# 附篇（2026-09-22 追加）：从静态审计升级为**本地实测**

前提变了：本机有 `pwsh` 7（`/usr/local/bin/pwsh`），而脚本作者为关键函数留了可测注入点（`-TaskRoot`）。
于是用**真 AST** 从源文件抽出 14 个纯函数，dot-source 后喂夹具实跑 —— **源文件一行未改**。
复跑物留在 `/tmp/svr2probe/`：`run.ps1`（E1–E4）、`scan.ps1`（E6）、`fx_single.txt` / `fx_subgroup.txt`（电源输出夹具）、
`bin/powercfg`（伪造的 powercfg，从环境变量 `SVR2_FIXTURE` 读夹具）。

## 实测结论总览

| 段 | 测什么 | 结果 |
|---|---|---|
| E1 | `Resolve-StageList` 六形态 + 非法项 | ✅ 6/6 形态正确（含 `'Desktop','Ops'` 连引号那种）；`Bogus` / `Backup` / `Backup,Desktop` 均被拒 |
| E2 | `net user` 密码到期专行（zh-CN『帐户到期』在前） | ✅ 取到 `密码到期`、未误取 `帐户到期`；en 同样；只有『帐户到期』时明确说找不到、**不退回泛匹配** |
| E3 | powercfg 取值与判定（伪造 powercfg 喂真机形态输出） | ⚠️ **复现出假绿** —— 见 B-00 |
| E4 | `Get-TaskState` 第二来源 + 聚合分档 + 空清单边界 | ✅ 后备文件在→不判达标；两来源皆无→才当不存在；Unread/Absent 分开计；显式空清单未回落到脚本级 11 项 |
| E5 | 入口：宿主守卫 / 规范化顺序 / 退出码 | ✅ 三项均符合设计 |
| E6 | AST 逐步骤扫"备份登记覆盖" | 机械确认 A-01 的清单一字不差 |

## B-00【P2·新证据】AMBIGUOUS 只写在证据行里，**判据不吃它**

E3 第二个夹具是"前提不成立"的形态：查询 `DISKIDLE`，而输出里还有另一个设置块 `DISKIDLETIMEOUT`，它恰好是 0：

- 真实 `DISKIDLE AC = 0x1e`（30）；脚本读到 `Ac = 0`（串到了 DISKIDLETIMEOUT）；
- `Test-PowerCfgValue -Expected 0` → **True（判绿）**；
- 证据行**确实**印了 `[blocks: DISKIDLE + DISKIDLETIMEOUT  <-- AMBIGUOUS: 2 setting blocks …]`，**而判定照旧通过**。

即 `Get-PowerCfgOutputFacts` 把"前提被破坏"变成了可见的事实，但 `Get-PowerCfgValue` 在 `Suspect` 时**没有任何反应**。
作者 2026-09-18 已用真机证明（P4 四项**零 AMBIGUOUS**）"指定 setting 的查询只输出一个块"，所以**在今天的目标机上这是安全的**；
但代码里没有任何东西**阻止**在前提不成立的 build 上拿别的项的值当本项的值 —— 而 P4 四项的期望值全是 0，
正是最容易被"别人的 0"满足的那一档。这是"**证据说了话、判据不听**"，与 SEC3 那条"属性不存在 ≠ 属性为假"是同一条规矩。

**最小修法（3 行，块数 = 1 时零影响）**：

```powershell
$res.Blocks = Get-PowerCfgOutputFacts -Out $out
if ($res.Blocks.Suspect) {        # 读到多个块 = 取值前提被破坏 → 判负，不冒充绿
    $res.Why = (Get-PowerCfgBlockNote -Facts $res.Blocks)
    $res.Reason = 'ambiguous'
    return $res
}
```

## B-01【P2】`.cmd` 的 pause 会把**无人值守跑挂住**

第 75–77 行是那个经典 idiom，判据是 `%cmdcmdline%` 里有没有脚本名。它区分的是
"新开的 cmd 窗口 vs 已存在的控制台"，**不区分"双击 vs 计划任务 / `cmd /c`"** —— 后两者同样新开 cmd 且 cmdcmdline 带脚本名
→ **一律 pause**。而 `.cmd` 头注第 18 行自己写着：

```
Svr2Desktop.cmd -Stage All -Json   -> unattended full run
```

文档承诺的无人值守用法会卡在 pause 上。**最小修法**（双击场景恒无参数，故安全）：

```bat
if "%ARGS%"=="" ( echo %cmdcmdline% | find /i "%~nx0" >nul && pause )
```

或以脚本的 `-Force` 开关为准。

## B-02【P3】`net session` 作提权探针依赖 LanmanServer 服务

第 56 行用 `net session` 判提权 —— 它同时依赖 Server 服务在跑。该服务被停时
**已提权也会判成未提权** → 触发重入（本脚本把 LanmanServer 列入 `NeverDisable` 守卫，
但别的加固基线会关它）。更稳的探针：`fltmc >nul 2>&1`（只依赖是否提权，不依赖任何服务）。

## B-03【P3】提权重入无循环防护

第 57–65 行的重入没有任何"已尝试过"标记。配上 B-02（或 UAC 被策略拒绝）会形成**重入循环**
（已提权时 UAC 通常不再弹窗，循环是静默的）。**最小修法**：重入前 `set "SVR2D_RUNAS=1"`
（`Start-Process` 默认继承父进程环境块），重入后的实例见到该变量就不再重入，改为明确报错退出。

## B-04【P3】A-13 的空头承诺出现在**用户看得到的地方**

`.cmd` 第 12–13 行向用户复述了"PS7 增益"，而脚本头注列的第三项 `$PSStyle` 是空头承诺（A-13）。
修 A-13 时请连同 `.cmd` 那两行一起看 —— 那是唯一印在用户面前的"能力声明"。

## 与已知"Gemini 二审"清单的关系（CHANGELOG v11.15 第 592–608 行）

CHANGELOG 记载 v11.15 已响应 **F-01**（SEC10 手动回滚提示补 `PromptOnSecureDesktop /d 1` —— 已核实两行确在文件内，属已修）
与 **F-03**（还原脚本补服务运行状态）。**F-02 / F-04 / F-05 明示本轮未动**，时点行动清单在其 Review 文档里。
据此逐条对齐本报告，避免重复计功：

| 本报告编号 | 与 Gemini 清单的关系 |
|---|---|
| A-01（还原覆盖缺口） | **部分重叠 F-02**（`Bak.Misc` 原生命令回放通道）—— netsh / SMBv1 / MpPreference 三项即 F-02 范围。**新的是 SEC12 那一半**：`secedit` 与 `Set-LocalUser` 完全不进任何通道，且**改动前原值从未留档**，连手工回滚都缺依据 |
| A-02（`net accounts /maxpwage:UNLIMITED` 标成回滚） | 新。F-01 修的是 SEC10 那两行 `reg add`；这一行属 SEC12，方向仍反 |
| B-00（AMBIGUOUS 不进判据） | 新，且有可复现证据 |
| B-01 ~ B-04（`.cmd`） | 新（`.cmd` 今日才入目录） |
| A-03 / A-04 / A-06 / A-07 | 新 |
| A-05（`2>&1` + `EAP=Stop`） | 新。**本机已在 pwsh 7 上对照：7 下不抛**（`& sh -c 'echo x 1>&2' 2>&1` 只打印一行）→ 该风险是 **5.1 专有**，仍需 Windows 侧一行定论 |
| A-08 ~ A-16 | 新 |

## E5 实测细节（被确认的设计）

- **宿主守卫生效**：macOS 上 `-Verify` 输出 `FATAL: This script targets Windows only: $env:SystemRoot is empty…`，
  **真实退出码 = 1**（单独核过，非管道假象）。
- **规范化先于守卫**：`-Stage Bogus -Verify` 报的是 `Invalid -Stage value(s): Bogus`，而不是宿主错误 ——
  与头注"非法值必须在任何动作之前被拦下（`-Verify` 同样适用）"一致。
- **A-16 的死分支由实测坐实**：`Backup` 被 `Resolve-StageList` 拒绝（E1），而全文无任何调用点能传 `'Backup'`
  → `Invoke-StageByName` 的那个分支不可达。

## E6 AST 扫描（机械产出，非人工阅读）

```
Add-Step 总数: 45

--- 无任何备份登记原语的步骤 ---
  N1      Network      unregistered-calls: Invoke-Native
  SEC3    Security     unregistered-calls: Set-SmbServerConfiguration
  SEC12   Downgrade    unregistered-calls: Set-Content,Invoke-Native,Remove-Item,Set-LocalUser
  CL1     Cleanup      unregistered-calls:

--- 有备份登记、但仍出现未登记改动的步骤 ---
  P2      Performance  unregistered-calls: Invoke-Native
  P4      Performance  unregistered-calls: Invoke-Native
  SEC11   Downgrade    unregistered-calls: Set-MpPreference
```

与 A-01 的手工清单一字不差。SEC12 行里的 `Set-Content`/`Remove-Item` 是它自己的 `%TEMP%` 自清理（无害），
真正的未登记改动是 `secedit`（经 `Invoke-Native`）与 `Set-LocalUser`。

## 行动项增补

- **第一批（并入 A-01）**：SEC12 的留档 + A-02 的方向修正 **共用一处根因修复** ——
  先让 SEC12 记录改动前的 `MaximumPasswordAge`，那条手动回滚提示才可能写对。
- **第二批（一行级）**：**B-00** 的 3 行守卫（证据已说话，判据必须听）；**B-01** 的 pause 门控。
- **第三批**：B-02 换 `fltmc` 探针；B-03 加重入标记；B-04 随 A-13 一并处理。

---

# 闭环记录（2026-09-22 v11.16 已落地）

按决策人指示修复：**只动 `.ps1`，`.cmd` 退出交付集**（移入 `_local_probe_macos/Svr2Desktop.cmd.retired` 备查，未删）。

| 本报告编号 | 处置 | 落点 |
|---|---|---|
| **B-00** | ✅ 已修：`Get-PowerCfgValue` 在 `Blocks.Suspect` 时短路 → `Found=$false`、`Reason='ambiguous'`，判负不冒充绿 | 新增守卫 |
| 措辞随 Reason 分档（B-00 的连带） | ✅ 已修：`Test-PowerCfgValue` 缺值措辞 / `Set-PowerCfgValue` 写后读回提示 / P2 探针 NOT-SET 措辞，三处都不再把 ambiguous、unreadable 说成"本方案没这一项"或"本 build 没有" | 三处 |
| **A-02** | ✅ 已修：`net accounts /maxpwage:UNLIMITED` → `net accounts /maxpwage:<pre-run days>`，并指明原值留档位置 | 降级风险摘要 |
| **A-01 的 SEC12 那一半** | ✅ 已修：SEC12 的 Action 先 `secedit /export` 导出改动前的 `MaximumPasswordAge`，落进 `Bak.Misc` → `misc_snapshot.txt`（键 `MaximumPasswordAgeBefore`） | SEC12 |
| **A-01 的口径那一半** | ✅ 已修：还原脚本头注从"回滚一切"收窄为"五条通道"，并追加 `NOT replayable here` 段逐条列明 | 生成器头注 |
| **A-13** | ✅ 已修：删掉 `$PSStyle` 空头承诺 | PS7 增益清单 |
| 入口（B-01~B-04 随 `.cmd` 退场失效） | ✅ 已改：USAGE 改为"以管理员身份跑 `.ps1`"，并写明双击默认是「编辑」、`Unblock-File`、`-ExecutionPolicy Bypass` 三条实操 | USAGE |

**未动**（仍在时点行动清单上）：A-03、A-04、A-05（待 Windows 侧一行定论）、A-06、A-07、A-10 ~ A-16，
以及 A-01 与 F-02 重叠的其余部分（SEC11 的 `Set-MpPreference`、SEC3 的 SMBv1、N1 的 netsh）。

**修复后的复验（本机 macOS + pwsh 7，同一套夹具）**

- AST 解析 0 error；UTF-8 with BOM + CRLF 保持；改动 16 个 hunk、净 +103 / −15 行。
- E3 **A 档（单块输出 = 今天的目标机形态）行为与打补丁前逐字节一致** → 目标机零回归。
- E3 **B 档由假绿转为判负**：`Found=False Reason=ambiguous`，`Test-PowerCfgValue -Expected 0` 由 `True` 变 `False`，
  证据行 `<read-back ambiguous>` + MISMATCH。
- E1 / E2 / E4 / E5 全部维持原判（未受影响）。

**已知验证缺口**：行为套件（PASS 169 那套）、门控基线 `-AssertClean`、变异清单、回放夹具**本轮未运行** ——
其宿主目录 `skills/powershell-hardening-rewrite/scripts/` 不在本机。v11.16 的验证结论不继承 v11.15 的任何既有结论。

---

# 闭环记录（二）：v12.0-preview 已收口

决策人指示"全部修完 + 改名 + 标注为发布前最终预览"。本轮把剩余项一次做完，并**扩了夹具**
（新增 E7：生成的还原脚本必须能被 AST 解析；E8：退出码四态）。

| 本报告编号 | v12.0-preview 处置 |
|---|---|
| **A-01（F-02 那一半）** | ✅ 新增 `Backup-NativeCommand` 原生命令回放通道；SEC11（Defender 偏好六项）/ SEC3（SMBv1）/ N1（TCP 全局）/ SEC12（密码策略）四个**生产者**各自登记原值 + 回放语句 |
| **A-03** | ✅ `-Verify` 落日志与 JSON（与备份同根、`verify_` 前缀；不写快照、不生成还原脚本）；汇总处打印两个路径 |
| **A-04** | ✅ `NeverDisable` 改为并集，json 只能加码不能削减 |
| **A-05** | ✅ `Invoke-Native` 函数作用域内降 `$ErrorActionPreference`，5.1/7 行为一致 |
| **A-06** | ✅ `Invoke-VerifyReport` 入口清空 `$script:Results` |
| **A-07** | ✅ D14 存在性判据改用 `Get-Service`；StartMode 读不出记 NOT-SET 而非 ABSENT |
| **A-08** | ✅ heuristics 补证据行明说"写了、回读不到" |
| **A-09** | ✅ 菜单 `[A]` 改用 `$script:BaseStages` |
| **A-10** | ✅ N2 / SEC2 补三态探针，接口枚举为空记 NA |
| **A-11** | ✅ P9 证据按"调度器报启用"/"状态读不出"分档 |
| **A-12** | ✅ MFT 项加 Note；WARNING 补 8dot3 兼容风险 |
| **A-14** | ✅ Desktop 阶段后一句注销/重启 Explorer 提示 |
| **A-15** | ✅ CL1 加重解析点守卫（只登记不递归） |
| **A-16** | ✅ 删死分支；新增 `-ExitOnFail` 退出码契约 |
| **B-01~B-04** | ✅ `.cmd` 重做为 `Svr2Desktop_v12-preview.cmd`：pause 只对无参数生效、探针换 `fltmc`、重入加 `SVR2D_RUNAS` 标记、分支改 goto |

**交付件**：`Svr2Desktop_v12-preview.ps1`（3900+ 行，`$script:VER = '12.0-preview'`）
+ `Svr2Desktop_v12-preview.cmd`（双击入口，ASCII + CRLF）+ `CHANGELOG.md` + 本报告。

**本轮自撞的两个坑（由新夹具 E7 撞出，已修并写进 CHANGELOG）**：生成回放行时用单引号串
使反引号失效；改成单行拼接后，注释又把 `}` 吃掉 —— 都导致生成的还原脚本语法错误。
教训已落成规矩：**生成器必须对回放文本免疫**（回放语句独立成行放在 try 里）。

**发布前待办**（虚机验证通过、转正式 V12 时）：
1. `$script:VER` 改 `'12.0'`；文件名回 `Svr2Desktop.ps1`（脚本内 13 处自引用一并改回）。
2. 在虚机上跑：`-Verify → -WhatIf → 执行 → 重启 → -Verify`，并**实际执行一次生成的还原脚本**
   （回放通道是新增的，只有真机跑过才知道四条回放命令的等价物对不对）。
3. 顺手把 A-05 的一行定论跑掉（5.1 会话里 `& cmd /c "echo x 1>&2" 2>&1` 是否抛错）。
4. 拿到 `skills/powershell-hardening-rewrite/scripts/` 后补跑行为套件与门控基线。

---

# 闭环记录（三）：真机验证（v12.0-preview 首上机）

## 目标机画像（由报告本身推出，非猜测）

| 特征 | 依据 |
|---|---|
| Win11 风格桌面 shell（build ≥ 22000） | D7 写入了 `TaskbarAl` 分支 |
| 活动电源方案 = **OlSoul_P**（第三方方案） | P2/P4 的 `[scheme: OlSoul_P [1577…]]` |
| Defender 组件已被移除 | SEC11 → ABSENT（WinDefend 不存在） |
| 前任优化痕迹 | `autotuning = disabled`（默认应为 normal）、`MenuShowDelay = 50`（默认 400）、`NoDriveTypeAutoRun = 0xDF`（默认 0x91） |
| 8dot3 = 2（按卷）、MFT zone = 0（默认） | P7 的证据行 |

## 三跑结果

| 跑次 | 结果 |
|---|---|
| `-Verify`（PS7，13:56:33） | FAIL 0 / CHECK-ERROR 0 / SATISFIED 10 / NOT-SET 30 / N/A 1 / ABSENT 1 / ONE-SHOT 1 |
| `-Verify`（PS 5.1，14:01:06） | **逐项与上一跑相同**（含每一条证据行的实测值） |
| `-WhatIf`（PS7，全链路预演） | 31 WHATIF / 10 SKIP / 2 N/A，无菜单、不写盘 |

## 双轨一致性：第一次拿到真机背书

脚本声称"语法底线 5.1，宿主是 PS7 时只解锁增益"，此前**只有设计说明、没有真机证据**。
两跑对照后可确认：SATISFIED 10 项同集合、NOT-SET 30、N/A 1（P2 连 Why 与方案 GUID 都相同）、
ABSENT 1、ONE-SHOT 1、探针覆盖 15/43、零证据 3 项（P2 / CL1 / SEC11）全部一致。

**可复验的做法**（去掉每行的时间戳前缀后比对两份日志，预期只有两处不同）：

```powershell
$d='C:\Svr2DesktopBackup'
$p1 = Get-ChildItem "$d\Svr2Desktop_verify_20260922_135633\Svr2Desktop_verify.log"
$p2 = Get-ChildItem "$d\Svr2Desktop_verify_20260922_140106\Svr2Desktop_verify.log"
function M($f){ (Get-Content $f) | ForEach-Object { ($_ -split "`t",3)[2] } }
Compare-Object (M $p1) (M $p2)
# 预期差异仅两行：头部行的 ps= 字段（7.x vs 5.1.x）与 verify dir: 指向各自目录。
```

## v12.0-preview 的改动在真机输出里逐条可见

| 编号 | 真机可见的证据 |
|---|---|
| A-03 | `Log : C:\Svr2DesktopBackup\Svr2Desktop_verify_20260922_135633\…` —— Verify 首次有落点 |
| A-08 | `tcp heuristics = <written, not read back>` |
| A-10 | `nagle: 3 interface key(s); TCPNoDelay ok 0; TcpAckFrequency ok 0`（一行汇总，不再逐接口铺屏） |
| A-12 | `want 2 [applies to newly formatted volumes only - an existing volume keeps its current MFT layout]` |
| A-14 | Desktop 段末 `note: some desktop changes only take effect after signing out or restarting Explorer.exe` |
| A-02 | 降级摘要新文案：`…including the password policy and the Defender preferences (replayed from their pre-run values)` |
| **B-00** | P2 → `[block: <none>]`；P4 → 四个**单块**身份，**零 AMBIGUOUS** ⇒ v11.16 新增的"块数 > 1 则判负"守卫**在目标机上不会误触发** |
| Probe/Test 同源 | `-Verify` 的 10 个 SATISFIED 与 `-WhatIf` 的 10 个 SKIP **完全同一集合** |
| A-07 / A-09 / A-04 / A-15 | 未触发（D14 三服务皆存在且 Auto；菜单未走 [A]；无配置 json；无重解析点） |

## 两条真机数据才看得见的新发现（已在 v12.0-preview2 处理）

**C-01【P4·观察】D12 的 100 是"统一基准值"，不是"越小越好"。** 真机 `MenuShowDelay = 50`，
脚本写 100 —— 标题写的是 *Speed up*，但在这台机器上它是**减速**（Windows 默认是 400，从默认出发才是加速）。
50ms 与 100ms 都在"即时"阈值以内、人不可感，因此**刻意不引入"只快不慢"的不等式判定**：
那要新增判定语义，且 Action 一旦跳过写入就与 Test 脱钩、制造永久 NOT-SET。改为把语义写进 Note。

**C-02【P4·文档】P7 的 Note 例证与真机不符。** 注释举 `0x80000003`，真机报 **`0x80000001`**
（低两位 01 + bit31 系统管理）。**判据正确** —— 那一行没有 MISMATCH，说明 bit0 判定判了达标；
只是例证需扩成"两者都是同一意图的系统编码"。另：真机 `8dot3 = 2`（按卷），脚本将改为全局 1 ——
这是**真实的行为扩大**（对全部卷关闭 8dot3 短名生成），WARNING 里新加的兼容性提示正好覆盖它。

## A-05：部分闭合，另一半需一次一行实验

- **已证**：5.1 会话里整条回读路径跑通、无 `NativeCommandError`。SEC12 的 Test 会经 `Invoke-Native`
  调 `secedit /export`，那一跳在 5.1 下正常。
- **未证**：A-05 假设的触发条件是"原生命令**往 stderr 写**"，而 `-Verify` 不调用那些命令
  （`-AllowNonZero` 的三条 `netsh` 只在执行档里跑）。
- **判定假设真伪的一行实验**（在 5.1 会话里跑）：

```powershell
$ErrorActionPreference = "Stop"
& cmd /c "echo boom 1>&2" 2>&1
# 打印 boom 并继续 = 5.1 不抛（我那个假设不成立，局部化那条改动属纯防御）
# 抛 NativeCommandError = 假设成立（局部化那条改动是必需的，且已堵住脚本自身的路径）
```

  两种结果都不需要再改代码 —— `Invoke-Native` 内部已把错误偏好局部化为 `Continue`，两条路径都安全。
  这条实验的价值是**判定"防御是否必要"**，消除一处未确证的假设。

## 待办（执行阶段）

1. 快照上执行：`-Stage All -Json -Force`（或菜单），重启，再 `-Verify`。
2. **实际执行一次生成的 `Restore_<stamp>.ps1`** —— 原生命令回放段是全新代码，
   四条回放（`net accounts /maxpwage` / `Set-MpPreference` ×6 / `Set-SmbServerConfiguration` /
   `netsh int tcp set global`）只有真机跑过才知道等价物对不对。**这是唯一纸面验证不了的一条。**
3. 执行档里注意 N1 的结局：若网卡不支持 RSS，`netsh … rss=enabled` 会失败，
   `-AllowNonZero` 应让它容忍而不是判 FAIL —— 那也是 A-05 的另一半现场。
4. 拿回两份报告 + `Svr2Desktop_result.json`，做差集审计（哪几项真动了、哪几项是环境限制）。
5. 拿到 `skills/powershell-hardening-rewrite/scripts/` 后补跑行为套件与门控基线（仍是最老的缺口）。

---

# 闭环记录（四）：执行档 + 重启后 Verify + Restore 实测

真机环境：**Windows Server 2025 Datacenter build 26100**（还原脚本头注自报），PS7 执行。

## 三段数据首次完整闭合，数字严丝合缝

| 阶段 | 结果 | 合计 |
|---|---|---|
| 执行前基线（PS7 / 5.1 两跑一致） | SATISFIED 10 · NOT-SET 30 · N/A 1 · ABSENT 1 · ONE-SHOT 1 | 43 ✓ |
| 执行档 `-Stage All -Json -Force` 14:08:29 | **OK 30** · SKIP 10 · N/A 2 · PARTIAL 1 · FAIL 0 · CHECK-ERROR 0 | 43 ✓ |
| 重启后 `-Verify` 14:19:46 | **SATISFIED 39** · **NOT-SET 1** · N/A 1 · ABSENT 1 · ONE-SHOT 1 | 43 ✓ |

差集：`10 + 30 = 40 = 39 + 1` ⇒ **29 项由 NOT-SET 转绿、零回退、零 FAIL**。
执行档的 `OK 30 = 29 转绿 + P9`（P9 执行时成功、重启后被系统还原）—— 三份数据对得上，
这是本项目第一次拿到"基线 → 执行 → 重启"的完整闭环。

## P9 自愈性质第三次被确认，并首次被区分开

执行时 `re-disabled 2 task(s) the scheduler still reported as enabled: PcaPatchDbTask (Ready), QueueReporting (Ready)`；
重启后只剩 `PcaPatchDbTask`。⇒ **QueueReporting 是永久关掉的，PcaPatchDbTask 才是真自愈项**。
A-11 改的那句措辞（"the scheduler still reported as enabled"）与 v11.8 的自愈说明，
共同把"重启后变 NOT-SET"从"脚本疑似失效"变成了**可读的事实**。

## Restore 脚本实测：applied 87 / failed 0

计数分解**精确吻合**，说明没有静默跳过、也没有重复计数：

| 段 | 条数 |
|---|---|
| registry（`Invoke-RestoreReg`） | 73 |
| services | 7（SysMain / CertPropSvc / BthServ / BTAGService / BthAvctpSvc / DiagTrack / dmwappushservice） |
| scheduled tasks | 2（PcaPatchDbTask / QueueReporting） |
| power（4 条 setvalueindex，`/setactive` 不计） | 4 |
| **native commands（新回放通道）** | **1** |
| 合计 | **87** ✓ |

**native 段只登记了 1 条，且这是正确行为**：SEC12（策略已是 -1）与 SEC3（SMBv1 已关）在执行档里是 SKIP、
SEC11 是 N/A（WinDefend 不存在）—— 三者**从未执行 Action**，因此不该登记回放。这条纪律
（"只有真动过的才登记"）在真机上得到确认。

**新回放通道第一次真机执行成功**：输出里那行 `确定。` 就是中文 netsh 的成功回显（`Ok.`），
它证明 `netsh int tcp set global autotuninglevel=disabled rss=enabled` 真的跑了并成功；
没有任何 `[FAIL] native …` 行，`$ok++` 也计入了 87。

## 本轮新发现（还原脚本侧）

### D-01【P2】`Invoke-RestoreReg` 的"删除"分支是**无条件记成功**

```powershell
} else {
    if (Test-Path -LiteralPath $Path) { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue }
}
$script:ok++        # <-- 不管上面删没删掉，都记一次成功
```

`-ErrorAction SilentlyContinue` 吞掉删除失败，紧接着 `$ok++` —— 这与 v8.1「逐行无条件写完成」
是同一形态，只是范围小。本次 73 条 registry 里有相当一部分是"原本不存在 → 删除"（`-Existed $false`），
所以 `applied: 87` 这个数字**不能保证每一项都真的生效**。

- **最小修法**：去掉 `-ErrorAction SilentlyContinue`（让它进 `catch` → `$fail++`），一行。
- **验证方法**：还原 + 重启后跑 `-Verify`，与**原始基线**（135633 / 140106）比对 ——
  若 NOT-SET 集合与基线一致，说明还原真的都生效了；若有项目仍为 SATISFIED，就是漏还原的现场。

### D-02【P3】native 回放段是"执行即成功"，没有回读

`try { <replay>; $ok++ } catch { $fail++ }` 只覆盖"命令退出码"，不覆盖"值是否真的回到目标"——
而 `netsh` 退出 0 不代表设置生效（脚本主体在 P2 上早就撞过同一件事）。
这也让回放段与脚本主体"处处回读"的哲学不一致。

- **验证方法（零代码）**：还原 + 重启后 `-Verify`，看 N1 是否回到 NOT-SET（`autotuning = disabled`）。
- **若要根治**（加机制，需决策）：让 `Backup-NativeCommand` 增加一个可选的"回读语句"字段，
  生成器在回放后追加一次读回与断言。代价是生产者要各写一份读法（`Get-TcpGlobalState` 已有，
  `Get-SmbServerConfiguration` 已有，Defender 偏好用 `Get-MpPreference`）—— 四个生产者里三个现成。
  **未得指示前不动**：按"每加一个机制先论证它不可省"的规矩，这一条应当由决策人拍板。

### D-03【P4】生成的还原脚本里 `$touched = 0` 是死变量

模板从早期版本起就声明它，但从未被读写过（生成物里也确实只出现在开头）。
本项目为同类理由删过 `Set-RegMultiString`、删过 `Invoke-StageByName` 的死分支 —— 这一处应当一并清掉。

### D-04【提示】V1 的四个 VBS 键以"删除"方式还原

四个键执行前均为 `absent`，所以还原脚本删掉它们（而不是置 0）⇒ DeviceGuard 回到"**未配置**"，
而 VBS 是否回升取决于系统默认（Server 2025 在支持硬件上可能自行启用）。
本次 `VBS status before: 0`（本就没在跑），所以观察不到差别；
但**若目标是"还原后 VBS 仍显式关闭"，需要额外确认**，删除不等于显式关闭。

### D-05【P3】失败不留名的两条通道（scheduled tasks / power）

还原脚本的五段里，三段会把失败**点名**（`[FAIL] reg <路径>`、`[FAIL] svc <名字>`、`[FAIL] native <键>`），
但另外两段是静默的：

```powershell
try { Enable-ScheduledTask ... ; $ok++ } catch { $fail++ }                 # 不问是哪一项
try { powercfg /setacvalueindex ... | Out-Null; $ok++ } catch { $fail++ }   # 不问是哪一项
```

一旦它们失败，操作员只看到末行的 `failed: 2`，却不知是哪两项 —— 与本脚本主体"结论要么给理由、
要么声明理由没采集到"的作风相悖。**最小修法**：两处 catch 各补一行 `Write-Host '[FAIL] task/power <键>'`。

## 仍未被真机覆盖的两处（不虚报）

1. **A-05 的 5.1 执行路径**：本次执行走 PS7。A-05 的假设只可能在 5.1 上出现，
   补法：在 5.1 会话里跑 `-Stage Network -Force`（会真正调用 netsh 三条 `-AllowNonZero`）。
2. **行为套件 / 门控基线 / 变异清单**：宿主目录 `skills/powershell-hardening-rewrite/scripts/` 仍不在本机（最老的缺口）。

## 建议的收口动作

1. 还原后重启 → `-Verify` → 与原始基线比对（同时验证 D-01 与 D-02）。
2. 修 D-01（一行）+ 清 D-03（一行）；D-02 待决策。
3. 5.1 执行路径补一次 `-Stage Network -Force`。
4. 以上全绿即可转正式 V12：`$script:VER` 改 `'12.0'`、文件名回 `Svr2Desktop.ps1`（脚本内 13 处自引用同步）。

---

# 闭环记录（五）：V12 封板

## 封板内容

| 项 | 值 |
|---|---|
| 版本 | `$script:VER = '12.0'`（预览版的文件名与内部版本号一并收回） |
| 交付件 | `Svr2Desktop.ps1`（4340 行，UTF-8 with BOM + CRLF）+ `Svr2Desktop.cmd`（96 行，ASCII + CRLF） |
| 与已验 preview2 的差异 | 仅三处，**全部落在生成的还原脚本**：D-01（删除分支不再吞错）、D-03（删死变量 `$touched`）、D-05（task / power 两段失败点名）。判定阈值、写入路径、回放语义零改动 ⇒ preview2 的三段真机闭环证据对 v12.0 成立 |
| 归档 | `_local_probe_macos/Svr2Desktop_v12-preview2.{ps1,cmd}.verified.bak` —— 被真机验收过的确切产物 |

三处修复的生成物已在本地夹具里复验（E7 断言）：生成的还原脚本 AST 0 error，
`-ErrorAction Stop` 到位、`$touched` 消失、`[FAIL] task …` / `[FAIL] power … ` 都点名到项。

## 执行档 JSON 的程序化校验（A-03 的机器可读产物第一次真正被用上）

`Svr2Desktop_result.json`（12.0-preview2，2026-09-22 14:09:22，Server 2025 build 26100）逐项核过：

| 校验 | 结果 |
|---|---|
| 步数 | **43** ✓ |
| 状态分布 | SKIP 10 · OK 30 · N/A 2 · PARTIAL 1 —— 与屏幕输出**逐项一致** ✓ |
| "同时带 before/after 两段"的步骤 | **恰好 30 个**（D3…V1，即真正执行了动作的那些）✓ |
| SKIP / N/A 带 before 段（应为空） | **空** ✓ ⇒ "只有真执行过才有前检"这条性质对全部 43 步成立 |
| 负判定（FAIL / PARTIAL）却零证据 | **空** ✓ ⇒ 零证据闸的前提成立 |
| OK 步骤的 Detail | 全为空串 ✓（无噪音） |
| N/A 的两条 | P2（`CPMINCORES` 本方案不暴露）、SEC11（`WinDefend` 不存在）—— 两条都**指名了理由** ✓ |

这份校验的意义：**报告的性质第一次由机器而非人眼确认**。人眼读屏幕只能确认"看着对"，
而"30 个执行步带两段、12 个早退步不带"这种覆盖率断言必须靠结构化数据。

## 本轮自身引入并已修掉的两个瑕疵（如实记录）

1. **夹具的"陈旧抽取"漏洞**：三个 harness 的源文件路径写死，改名后 AST 抽取落空，
   却**静默复用了上一次的 `ex2.ps1`** —— 于是 E7 测的是旧代码，先报出一串**假红**。
   这个洞的方向更危险的一面是**假绿**（旧产物恰好满足断言）。
   已修：源文件按候选表解析、找不到即 `throw`、抽取缺函数即 `throw`、
   每次打印 `source: <路径> (mtime, 行数)` 自证身份。
   教训与主体同源：**任何"读不到就退回旧值"的静默回退，都是假绿通道**。
2. **行尾混用**：封板补丁里有两个多行字符串带进 LF，文件成了 CRLF/LF 混用（3 处）。
   已归一到纯 CRLF 并复核（`file` 自证），AST 仍 0 error。这类瑕疵不影响 PowerShell 解析，
   但破坏"文件编码单一"这条交付约定。

## 决策记录

- **D-02（native 回放段无回读）→ 不做**（2026-09-22 决策人裁定）。理由充分：还原后的 `-Verify`
  已在**工作流层面**给出值级验证 —— 实测 N1 确已回到 `autotuning = disabled`。
  再给每条回放配一套读法属重复机制，与"复杂度是负债"相悖。
- **A-05（5.1 下 stderr 重定向）**：`Invoke-Native` 内的错误偏好局部化保留（两条路径都安全），
  但"该假设是否成立"仍未定论 —— 需在 5.1 会话里跑一行（见闭环三），或直接看日志首行的 `ps=` 字段。

## 发布件的验证状态（诚实版）

| 验证面 | 状态 |
|---|---|
| 43 步的判定与回读 | ✅ 真机三段闭环（基线 → 执行 → 重启后），零回退、零 FAIL |
| 双轨（PS7 / 5.1）只读路径 | ✅ 逐项一致 |
| 还原完整性 | ✅ 还原 + 重启后与原始基线逐项一致（87/0） |
| 原生命令回放通道 | ⚠️ 四个生产者里**只有 N1 被执行过**（另三个因 Action 未执行而未登记，属正确行为）—— 回放语句的**等价物正确性**只有 N1 拿到真机验证 |
| A-05 的 5.1 执行路径 | ❌ 未覆盖（执行档走 PS7） |
| 行为套件 / 门控基线 / 变异清单 | ❌ 未运行（宿主目录不在本机） |

**结论**：V12 可发布；上表后两项是**已知的、有明确补法的**缺口，不影响本次发布。
建议在拿到 `skills/powershell-hardening-rewrite/scripts/` 后补跑一次套件，作为 V12.1 的入场券。

---

# 附录：V12.1 候选池（"当桌面用"方向）

**筛选标准**（即本项目自身的纪律，四条缺一不可）：
① 能回读（有 Probe / Test，判据与证据同源）；② 能还原（进 Bak 通道，或走原生命令回放）；
③ 零安全代价 —— 有代价的必须进显式降级档，不得进默认路径；④ **效果可感知**。

**先看现状**：这台机器上 43 步里 39 项已达标、仅 1 项是已知自愈项。也就是说，
**"把已有的做全"这条线上的边际收益已经接近零**；真正还大的只剩两类：**输入手感**与**访问方式**。

## A 档 —— 建议做（零代价、可回读、可感知）

| # | 项 | 机制 | 为什么可感知 | 回读点 |
|---|---|---|---|---|
| A1 | **关闭"提高指针精确度"（鼠标加速）** | `HKCU\Control Panel\Mouse` → `MouseSpeed=0`、`MouseThreshold1=0`、`MouseThreshold2=0` | 虚拟机上鼠标本来就"飘"，再叠加系统加速曲线会让精确点击变难。这是**单点收益最大**的一项 | 三个 REG_SZ 回读，`Test-RegValue` 直接用 |
| A2 | **关闭资源管理器缩略图与信息提示** | `HKCU\…\Explorer\Advanced` → `IconsOnly=1`、`ShowInfoTip=0` | 无 GPU 加速的环境里，缩略图生成是资源管理器卡顿的常见源 | 同上 |
| A3 | **关掉 DWM 透明效果** | `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize\EnableTransparency=0` | 透明是纯合成开销，VM 里（软件渲染）代价相对更明显 | 同上 |
| A4 | **抑制"网络发现"弹窗** | `HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff=1` | 每次换网都弹"是否让此 PC 可被发现"——桌面化收尾的经典项 | 同上 |
| A5 | **确认时间源只有一个** | VMware Tools 时间同步 vs Windows `W32Time` 双源冲突（VM 常见坑） | 时钟反复跳会让日志时间戳、TLS、Kerberos 不可信 —— 对**审计型用法**尤其要命 | 只读检查：`w32tm /query /status` 与 `HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters\Type` |

> A5 建议**先做只读探针**（`-Verify` 类型的三态），不急着写死改法 —— 该改哪一侧取决于你的意图（跟主机走 / 跟外部 NTP 走）。

## B 档 —— 值得做，但要你定调

| # | 项 | 机制 | 代价 | 归类 |
|---|---|---|---|---|
| B1 | **自动登录** | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon` → `AutoAdminLogon=1` + `DefaultUserName` + `DefaultPassword` | **口令明文落盘**（`DefaultPassword` 是纯文本）。变体：用 Sysinternals `Autologon` 写 LSA secret（加密、可回读），代价是引入外部工具 | **必须是显式降级档**（与 SEC10-13 同级），绝不进默认路径 |
| B2 | **免按 Ctrl+Alt+Del 登录** | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\DisableCAD=1` | CAD 提供一条"可信路径"，去掉它在**本地物理机**上是弱化；在这台仅你使用的 VM 上风险很小 | 建议同归显式档（`-Stage Downgrade` 或新开一档） |
| B3 | **开启剪贴板历史（Win+V）** | `HKCU\SOFTWARE\Microsoft\Clipboard\EnableClipboardHistory=1` | 无 —— 但它是**"像桌面"的加法**（历史最多 25 条，含敏感串的风险） | 可进默认（视你对剪贴板留痕的取向） |
| B4 | **中文输入法的云候选/自学习开关** | `HKCU\SOFTWARE\Microsoft\InputMethod\Settings\CHS` 下的若干键 | **键名随版本漂移**，需先在真机取一次现值；不同版本语义还可能变 | 先只读探针；确认键名后再动 |
| B5 | **资源管理器右键加"用 PowerShell 7 运行此脚本"** | `HKCU\Software\Classes\Microsoft.PowerShellScript.1\Shell\…` 增一个 verb，指向 `pwsh.exe -NoProfile -File "%1"` | 无（纯增量、只影响当前用户） | 可进默认 —— 见文末"从你的工作流看到的"一句 |

## C 档 —— 我建议**明确不做**（理由比建议更重要）

| # | 项 | 为什么不做 |
|---|---|---|
| C1 | `HKCU\Control Panel\Desktop\UserPreferencesMask`（经典"关菜单淡入/滑动"） | **位域二进制值，位含义随版本漂移，回读无法给出可读语义** —— 违反"能回读"这条底线。P6 已经用一个个具名键达到了同样效果，这才是正确做法 |
| C2 | `Win32PrioritySeparation` / `NetworkThrottlingIndex` / `SystemResponsiveness` | 玄学调优：**没有可信的效果证据**，且它们的"值"与"效果"之间没有可回读的因果关系。与 P7 的 MFT 项同类（值达标 ≠ 效果存在），但连"达标"的意义都说不清 |
| C3 | 关闭/固定页面文件、各种"内存清理" | 与 P8 重叠且方向相反；VM 内存充足不代表能去掉后备存储 |
| C4 | 关闭 `ScheduledDefrag` / 自动维护 | P1-7 已明确**不动**（SSD 的 TRIM 靠它）。这条是既有决策，重申一次以免日后被"优化"回来 |
| C5 | 把 RDP 视觉体验强制降级 | **仅在你确实用 RDP 时才有意义**；若你用 VMware 控制台，它是纯噪声 —— 见下面的"待定分支" |

## D 档 —— 需先答一个问题（它会重排优先级）

**你是怎么"当桌面用"的？** 三条路线的收益分布完全不同：

| 路线 | 该调什么 | 备注 |
|---|---|---|
| **VMware 控制台窗口** | 输入手感（A1）+ VMware Tools 侧（拖放/剪贴板共享、**3D 加速开关**、显示缩放） | Tools 侧与 VM 设置**脚本管不到**，但那是这条路上收益最大的地方 |
| **RDP** | 服务器端一整组：`SelectTransport`（启用 UDP 提升响应）、会话内视觉特效策略、带宽/压缩策略；客户端 `.rdp` 的连接类型与位图缓存 | **收益可能超过前面所有项之和** —— 但只有确认走 RDP 才值得写 |
| **VNC / 其他** | 基本无脚本侧可做（帧缓冲由第三方驱动） | 建议只在客户端侧调 |

## 成本提醒（这才是要慎重的理由）

本项目每一项"合规"的改动 = `Action` + `Test` + 可选 `Probe` + 备份登记 + 证据行 + CHANGELOG 条目，
**约 30 行**。加 5 项就是 150 行代码 + 一轮真机三段验证（`-WhatIf` → 执行 → 重启 → `-Verify` 差集）。
所以应按"**每加一项先论证它不可省**"来筛，而不是按"它有没有用"。

**顺带值得复核的两项存量**（加上面的同时该减的）：

- **D12 在这台机器上是"归一"而非"加速"**（真机 50 → 写 100）：50ms 与 100ms 都在"即时"阈值以内，
  它的价值只剩"统一基准"。要么保留并接受这个定位，要么把期望值改成"≤100 即达标"（那需要新增不等式判定语义 —— 我倾向不做）。
- **P7 的 MFT zone 项对现有卷无任何效果**（只对新建卷生效，已加 Note）：它是"值达标但效果不存在"的典型。
  可考虑在 V12.1 里把它降为**只报告不动作**（`-OneShot` 式说明），或明说"为将来的卷预留"。

## 我的推荐次序

1. **A1（鼠标加速）** —— 单点收益最大、机制最简单、回读最干净。
2. **A2 + A3（缩略图 / 透明）** —— 同为 VM 上可感的合成与磁盘开销，两条一起写。
3. **A4（网络发现弹窗）** —— 一行的事，纯噪音消除。
4. **A5（时间源）先只读探针**，看清现状再定改法。
5. **B3 / B5** —— 若你要"像桌面"，这两条是加法里性价比最高的。
6. **B1 / B2 走显式降级档** —— 只有你自己能决定是否用便利换那点安全。
7. **D 档的答案决定要不要开一整组 RDP 项** —— 建议先回答再动。

每一项都按既有纪律实现：`Probe` + `Test` 同源、证据行带实测值、进备份通道、CHANGELOG 记一条，
然后在这台机器上跑一次 `-WhatIf` → 执行 → 重启 → `-Verify` 三段，用差集确认它真的动了。

---

*以上为候选池草案，V12 已封板；这些项属 V12.1 范围，需逐项勾选后再实现。*

*审计者：特斯拉（Mac64 Buddy） · 2026-09-22 · 初稿（静态）→ 附篇（本地实测）→ 闭环一（v11.16）→ 闭环二（v12.0-preview）→ 闭环三（真机双轨）→ 闭环四（执行 + 重启 + 还原）→ 闭环五（V12 封板）*
