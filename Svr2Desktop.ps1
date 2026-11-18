#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
===============================================================================
 Svr2Desktop.ps1
 Windows Server 2016 / 2019 / 2022 / 2025 —— 桌面化与流畅度优化
===============================================================================
 Version    : 13.3
 Released   : 2026-09-29
 Baseline   : "Windows Server 2016-2025 to desktop.bat" v8.1 (社区版, 无签名)
 Maintainer : Bob / WorkBuddy (Audi · 特斯拉) —— 2026-09-29 两线合并，见 CHANGELOG
 Encoding   : UTF-8 with BOM —— 请保持此编码保存，否则中文注释会乱码
-------------------------------------------------------------------------------
 PURPOSE
   让 Server 具备接近桌面的交互流畅度：消除登录与关机的等待和弹窗、开启桌面
   体验、按服务器场景调优电源与网络、精简无用服务、补齐可运维性。所有改动均
   可回读验证；除"清理阶段删掉的文件"（删除没有撤销）外，均可一键还原 ——
   原生命令类改动（密码策略 / TCP 全局参数 / SMBv1 / Defender 偏好）由还原脚本的
   原生命令回放段重放，见 SECTION 2 的 Backup-NativeCommand。

 SECURITY MODEL —— 与 v8.1 的根本差异，与 v10.0 相比的变化
   v8.1 把"安全降级"和"桌面化"混作一谈，叠加后构成完整杀伤链：
       RDP 弱口令 → UAC 无提示提权 → 无 AV 拦截 → 无安全告警
   ★ v11.0 起按机主要求，把四项安全降级做成【显式选择的独立阶段 Downgrade】：
       SEC10  UAC 管理员静默提权（保留 EnableLUA=1，不彻底关 UAC）
       SEC11  关闭 Defender 实时防护与服务（可逆，不卸载组件）
       SEC12  密码永不过期（长度与复杂度保持默认）
       SEC13  屏蔽安全中心告警与托盘图标
   它们【绝不默认执行】，必须由菜单 [10]、-Stage Downgrade 或 -Stage All 显式
   触发，执行前还会打印风险摘要与回滚命令并要求确认；配置文件的键名白名单里
   也没有它们 —— 安全降级不能被一个放在旁边的 json 悄悄打开。
   仍然【不提供】：彻底关闭 UAC 框架、卸载 Defender 组件、关闭 SEHOP/DEP、
   密码复杂度与最小长度归零。
   ▼ 一条必须记住的耦合：SEC10 把 ConsentPromptBehaviorAdmin 置 0（管理员不再
     弹提示）的同时把 PromptOnSecureDesktop 置 0（不进安全桌面）。后者单独存在
     时是经典的 UAC 绕过口（UACME 类攻击可模拟点击安全桌面之外的提示），只有在
     前者为 0（本就无提示）时风险才不放大。日后若单独把 ConsentPromptBehaviorAdmin
     改回 2 或 5，必须同步把 PromptOnSecureDesktop 改回 1。
   ▼ 本版仍保留的加固项：禁 LLMNR 与 NBT-NS（根治 UNC 投毒面）、关闭 SMBv1、
     关闭 AutoPlay/AutoRun、禁用 WDigest 明文缓存。均为无使用代价项。
   ※ 除 Downgrade 阶段的四项外，另一个安全降级项 = 关闭 VBS/Credential Guard，
     同样须显式选择（菜单 [9] 或 -Stage VBS）。

 CHANGE LOG vs v8.1（对应审计报告 26 项发现 + 本轮增强）
   [P0-1] 全卷递归删除（del /f /s /q %SystemDrive%\*.log 等 6 类）→ 删除，
          改为白名单目录清理；主动排除 System32\LogFiles（IIS 日志面）
   [P0-2] 硬编码 \\network\share\sxs 回退源 → 删除（LLMNR 投毒面）
   [P0-3] Defender 无效键（TamperProtection / DisableAntiSpyware）→ 不再写入
   [P0-4] UAC 静默提权 / 密码策略归零 / 隐藏安全告警 → v10.0 整段移除；
          v11.0 按机主要求改为显式选择的 Downgrade 阶段（见 SEC10-13）
   [P1-1] WMIC → CIM（Server 2025 起 WMIC 为 FoD，默认不安装）
   [P1-2] 休眠 与 快速启动 互斥 → 只保留休眠，关闭快速启动
   [P1-3] 备份前置到任何修改之前；覆盖注册表 / 服务 / 功能 / 计划任务
   [P1-4] 生成可执行还原脚本 Restore_<stamp>.ps1（含逐项回放）
   [P1-5] 逐项回读断言，杜绝"假绿"（v8.1 逐行无条件写"完成"）
   [P1-6] 配置文件走键名白名单，拒绝可劫持脚本自身行为的键
   [P1-7] 计划碎片整理任务在 SSD 上承担 TRIM 维护 → 明确【不动】
   [NEW ] VBS/Credential Guard 状态检测（Server 2025 默认启用）
   [NEW ] Core Parking / Nagle / IPv6 隧道 / NTFS / 长路径等新增项
   [NEW ] 支持 -WhatIf 全链路预演、-Verify 只回读、-Stage 分阶段
   [NEW ] 结果可输出 JSON，便于批量部署后汇总
-------------------------------------------------------------------------------
 CHANGE HISTORY
   v11.0 → v11.11 的逐版变更记录（[DEL]/[FIX]/[ADD]/[ROOT]/[RULE]…）已整体移出，
   见同目录 CHANGELOG.md（2026-09-21 由 v11.12 移出；逐字节版本快照见 _history/）。
   此后新版本的变更记录续写在 CHANGELOG.md 末尾。

 语言兼容性（2026-09-18 起为双轨）：
   语法底线仍是 Windows PowerShell 5.1（目标机内置版本），因此任何一台
   Server 2016-2025 即使没装 PS7 也能直接运行；同时脚本会探测宿主版本，
   在 PowerShell 7 下解锁几项实质增益（见下节 POWERSHELL 7 ENHANCEMENTS）。
   刻意不使用的 PS7 专有语法：三元运算符、?? 、管道链 && ||。

 POWERSHELL 7 ENHANCEMENTS（仅在 pwsh 7.x 下生效，5.1 下自动降级）
   · Test-Json  —— 反序列化之前先严格校验配置文件，5.1 只能靠 ConvertFrom-Json 抛错
   · Get-Error  —— 致命错误时输出完整的错误诊断对象（5.1 无此命令）
   （原列在这里的第三项 $PSStyle 于 v11.16 删除：全脚本零引用，属文档空头承诺）
   刻意【不做】-Parallel 并行回读：每个步骤的 Test 脚本块都引用 $script: 作用域
   （配置、备份会话、结果集），ForEach-Object -Parallel 会把脚本块隔离到独立
   运行空间，回读断言将全部失效 —— 那是用"更快"换"更不可信"，与整套设计原则
   相悖。同样刻意不启用 $PSNativeCommandUseErrorActionPreference：Invoke-Native
   已经逐条检查 $LASTEXITCODE 并给出比异常更有信息量的报错，启用后反而会把它的
   -AllowNonZero 逃生口封死。
   另有一处跨版本编码陷阱已在本版修掉：Set-Content -Encoding UTF8 在 5.1 下写
   BOM、在 PS7 下不写，行为相反。生成的还原脚本可能被任一版本的 PowerShell
   打开，因此改由 Write-TextFileUtf8Bom 显式决定编码。
-------------------------------------------------------------------------------
 USAGE
   # 入口：两种，任选
   #   ① 双击随行的 Svr2Desktop_v12-preview.cmd —— 自动提权一次，窗口留在原地；
   #      它按自己的文件名去找 .ps1，两个文件一起改名也不会断。
   #   ② 在**管理员** PowerShell 窗口里直接跑本脚本：
   .\Svr2Desktop.ps1                                        # 交互菜单
   #   三条与入口有关的 Windows 默认行为要知道：
   #     · 双击 .ps1 的默认动作是「编辑」不是运行 —— 所以双击走那条 .cmd；
   #       直接跑 .ps1 时先"以管理员身份运行 PowerShell"。未提权时
   #       #Requires -RunAsAdministrator 会明确拒绝，不会静默半途失败。
   #     · .cmd 把退出码原样带出来（0 / 1 / 2），无人值守可直接判成败。
   #     · 文件若来自网络 / 共享，先 Unblock-File（去掉 Zone.Identifier）；
   #       执行策略受限时：powershell -ExecutionPolicy Bypass -File .\Svr2Desktop.ps1
   powershell -File Svr2Desktop.ps1 -WhatIf                 # 预演全链路（跳过菜单，
                                                            #  直接按 All 空跑所有步骤）
   powershell -File Svr2Desktop.ps1 -Verify                 # 只回读：摘要视图（SATISFIED 证据折叠；-Full 展开）
   powershell -File Svr2Desktop.ps1 -Stage Desktop,Ops -Force
   powershell -File Svr2Desktop.ps1 -Stage All -Json        # 全量 + JSON 结果
   powershell -File Svr2Desktop.ps1 -Verify -Json           # 只回读 + JSON（基线可留档）
   powershell -File Svr2Desktop.ps1 -Stage All -Json -Force -ExitOnFail
                                                            # 无人值守：有 FAIL 则退出码 2
   #   -Verify 现在也落日志与 JSON：与备份同根、目录名带 verify_ 前缀（v12.0）。
   #   -ExitOnFail：0 = 无失败，2 = 有 FAIL / CHECK-ERROR，1 = 致命错误。仅命令行模式生效。
   powershell -File Svr2Desktop.ps1 -Stage Downgrade,VBS    # 只做安全降级档
   pwsh -File Svr2Desktop.ps1 -Stage All                    # PS7 增强模式（可选）
   -Stage 可一次给多个：逗号 / 分号 / 空格分隔均可（-File 模式不支持真正的数组，
   所以逗号是标准写法；脚本内调用 -Stage @('Desktop','Ops') 同样可用）。
   ※ 实测记录：在 -File 模式下，命令行**没有任何写法**能把多个元素送进数组参数
     —— 逗号、分号、空格、甚至 -Stage 'Desktop','Ops' 都会作为**单个字符串**到达
     （最后一种还把字面单引号一起带进来）。所以"拆分"只能在脚本内做，这正是
     Resolve-StageList 存在的原因；它也顺带剥掉两端引号，让上面那种写法同样可用。
   不给 -Stage 默认 Interactive，即进入交互菜单。

   推荐的收口流程 —— 两次 -Verify 的差集，就是"本次运行改了什么"的证明：
     1) -Verify                      存基线（未被本脚本改动的项会显示实测值）
     2) 执行非降级批 → 重启 → 如需再执行降级批
     3) -Verify                      与基线对照：有变化 = 本脚本所为，
                                     仍为 NOT-SET = 真没生效（附实测值）
   执行与 -Verify 都会逐项打印"实测值 vs 期望值"（判定依据链）：非 OK 的步骤
   -Verify 与执行档默认摘要视图（-Verify 折叠 SATISFIED、执行档折叠 SKIP 的证据
   行，其余状态照印），加 -Full 逐项展开实测值（做基线 / 交审计用）。用
   -NoEvidence 可整体关闭屏幕输出 —— 视图折叠的只是屏幕，证据行仍完整落日志。
   真正执行了动作的步骤，其证据分两段并带标头（其余步骤只有一段，因为没动过）：
     -- before the action --     动作前的回读，回答"为什么判定需要动作"
     -- after  the action --     动作后的回读，判定的依据就在这一段
   两段对照能直接读出一件事：**值有没有移动**。一字未变 = 动作没触达这个值
   （写失败、或写到了别处）；变了但没到目标 = 动作生效了、只是没到位。
   两者的排查方向完全不同 —— 曾经的"post-check returned false"什么都答不了。

 WARNING
   1) 首次使用请在虚机快照或系统还原点上运行；
   2) 脚本会修改注册表、服务启动类型、电源方案、可选功能与计划任务；
   3) 还原方式：以管理员运行备份目录下的 Restore_<stamp>.ps1（它含原生命令回放段）；
   4) P7 会关闭 8.3 短名生成（NtfsDisable8dot3NameCreation=1）：对已存在文件不追溯，
      但此后依赖短名的老安装器 / 工具可能失败。这是本脚本少见的**兼容性代价项**，
      关掉它请自行把该键改回 0（0 = 按卷设置，1 = 全局禁用）。
===============================================================================
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    # 要执行的阶段；Interactive 表示进入菜单。多个阶段用逗号分隔：-Stage Desktop,Ops
    #
    # 这里**刻意不用 [ValidateSet]** —— -File 的参数绑定模型不支持数组：
    #   powershell -File Svr2Desktop.ps1 -Stage Desktop,Ops
    # 整个 "Desktop,Ops" 会作为**单个字符串**绑定到 [string[]] 上，ValidateSet
    # 随即抛 ParameterArgumentValidationError，脚本体一行都跑不到（真机实测）。
    # 改为在脚本内规范化：见 SECTION 6 的 Resolve-StageList。
    [string[]]$Stage = @('Interactive'),

    # 可选：配置文件路径（默认取脚本同目录 Svr2Desktop.config.json）
    [string]$ConfigPath,

    # 可选：备份根目录（默认 SystemDrive\Svr2DesktopBackup）
    [string]$BackupRoot,

    # 只回读、不改动：输出"当前状态 vs 期望状态"差异表
    [switch]$Verify,

    # 逐项展开全部证据行：-Verify 摘要视图折叠 SATISFIED 的证据、执行模式折叠
    # SKIP 的证据（其余状态证据照印 —— 非 OK 的证据绝不能被视图折叠）
    [switch]$Full,

    # 额外输出 JSON 结果文件
    [switch]$Json,

    # 跳过所有交互确认（供远程 / 批量部署）
    [switch]$Force,

    # 显式排除 VBS 阶段（即便 -Stage All）
    [switch]$SkipVBS,

    # 显式排除 Downgrade 阶段（即便 -Stage All）
    [switch]$SkipDowngrade,

    # 额外禁用打印后台处理程序（默认保留）
    [switch]$DisableSpooler,

    # 额外禁用无线 LAN 服务（默认保留）
    [switch]$DisableWLAN,

    # 结束后不提示重启
    [switch]$NoRestartPrompt,

    # 批量部署用退出码（v12.0，审计 A-16）：跑完若存在 FAIL / CHECK-ERROR 则
    # 返回 2（0 = 无失败，1 = 致命错误）。交互菜单模式不适用 —— 那时退出码属于操作员
    # 的 [Q]，不该被一次失败带走。
    [switch]$ExitOnFail,

    # 关闭"判定依据链"（evidence）的屏幕输出。默认：非 OK 的步骤逐项打印实测值，
    # OK 的步骤只落日志，-Verify 视图下全部打印。证据行始终完整写进日志文件 ——
    # 静音屏幕不等于放弃留痕。
    [switch]$NoEvidence
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
#  -WhatIf 的控制权回收
# -----------------------------------------------------------------------------
# [CmdletBinding(SupportsShouldProcess)] 会把 $WhatIfPreference 设成**全局偏好**。
# 它影响的不只是本脚本的写操作 —— 任何 cmdlet 的 ShouldProcess 都会被拦下并打印：
#   1) PowerShell 自动加载模块时，模块 psd1 里的别名声明也被算作"待预演操作"。
#      真机实测刷出 20 行 "WhatIf: ...设置别名"，来自 CimCmdlets / ServerManager /
#      SmbShare，把真正的步骤输出冲散；
#   2) 本脚本**自己**产生的临时文件的清理动作同样被拦 —— SEC12 用 secedit 导出的
#      %TEMP%\svr2desk_pwread_<pid>.inf 会因此留在磁盘上。这是真机实测到的写盘残留。
# 因此：把本意存进 $script:WantWhatIf，然后把全局偏好交还给 PowerShell。预演与否
# 由 Invoke-StepOne 显式判断（步骤级拦截），而不是依赖对一切 cmdlet 的隐式拦截。
# 副作用是脚本自身的清理动作恢复执行 —— 这正是我们要的。
$script:WantWhatIf = [bool]$WhatIfPreference
$WhatIfPreference  = $false

# -----------------------------------------------------------------------------
#  进度条静音（v11.8）
# -----------------------------------------------------------------------------
# 真机 v11.7 执行会话里，"Environment snapshot" 那一块之后多出一行残影：
#        ]                         0s]
# （v11.6 是 `   ]    ]` —— 长度可变，这次还带上了 `0s`）。它出现在
# Write-Note 'services / features / power plans / environment captured' **之后**，
# 并且**吃掉了 Write-Sub 本应留下的那一行空行** —— 说明它是在同一行上被反复覆盖的
# 进度条碎片，而不是某条正常输出。
# 快照区只有四条命令（Get-ComputerInfo / Get-Service / Get-WindowsFeature / powercfg），
# 其中前两者都可能驱动进度条。静音它既清掉这股噪音，也能给这几条命令提速 ——
# 而它们本来只是"存个快照"，进度对操作员没有任何信息量。
# 本条是脚本作用域内的偏好：不泄漏到调用方会话，也不拦任何写操作
# （与 $WhatIfPreference 那种"全局偏好"性质完全不同，因此不需要像它那样交还）。
$ProgressPreference = 'SilentlyContinue'

$script:VER     = '13.3'
$script:REL     = '2026-09-29'
$script:Results = New-Object System.Collections.ArrayList
$script:LogFile = $null
# -Verify 模式的日志落点（v12.0）：该模式下不建备份会话，而报告同样需要
# 留痕 —— 否则"两次 -Verify 的差集"这条方法论只活在屏幕上。
$script:VerifyDir = ''
$script:JsonFile  = ''
$script:HInfo   = $null
$script:Config  = $null

# 证据链 / 部分达成 / 活动电源方案缓存 —— 见 SECTION 3 的"判定依据采集"。
# $script:StepPartial 由采用 PARTIAL 语义的步骤（目前只有 CL1）在动作里赋值，
# 引擎在回读通过后据此把状态从 OK 降为 PARTIAL。
$script:Evidence     = New-Object System.Collections.ArrayList
$script:StepPartial  = ""
$script:ActiveScheme = ""
$script:NoEvidence   = [bool]$NoEvidence

# PS7 双轨探测：语法底线是 5.1，宿主是 PowerShell 7 时解锁几项增益。
$script:IsPS7  = ($PSVersionTable.PSVersion.Major -ge 7)
$script:PSMode = 'compatibility (Windows PowerShell 5.1)'
$script:PSMode = if ($script:IsPS7) { 'enhanced (PowerShell 7)' } else { $script:PSMode }

$script:Bak = [PSCustomObject]@{
    Stamp = ''
    Dir   = ''
    Reg   = New-Object System.Collections.ArrayList
    Svc   = New-Object System.Collections.ArrayList
    Feat  = New-Object System.Collections.ArrayList
    Task  = New-Object System.Collections.ArrayList
    Misc  = New-Object System.Collections.ArrayList
    Power = New-Object System.Collections.ArrayList
    Cmd   = New-Object System.Collections.ArrayList   # 原生命令回放通道（v12.0）
}

# 步骤注册表：每个优化项都是一个 { Id, Title, Action, Test } 结构，
# 由 Invoke-StageByName 统一执行，由 -Verify 统一只回读。这样"执行"与"验证"
# 共用同一份定义，不存在两套逻辑走偏的可能。
$script:StageNames = @('Desktop', 'Performance', 'Network', 'Services', 'Security', 'Ops', 'Cleanup', 'Downgrade', 'VBS', 'Backup')
$script:Steps = @{}
foreach ($s in $script:StageNames) { $script:Steps[$s] = New-Object System.Collections.ArrayList }

# 合法阶段名一律从 $script:StageNames 派生 —— 同一份清单抄三份，早晚各写各的。
# Backup 是引擎内部阶段（只快照不优化），不作为 -Stage 取值对操作员暴露。
$script:UserStages  = @($script:StageNames | Where-Object { $_ -ne 'Backup' })
$script:BaseStages  = @($script:UserStages | Where-Object { ($_ -ne 'Downgrade') -and ($_ -ne 'VBS') })
$script:ValidStages = @('Interactive') + @($script:UserStages) + @('All')

# =============================================================================
#  SECTION 1 — 日志与结果
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    if (-not $script:LogFile) { return }
    # 预演模式不落日志。当前 $script:LogFile 因为备份会话被跳过而本就是 $null，
    # 这一行是把它**显式化**：从"依赖 LogFile 恰好为空"的隐式保证，改成显式约束，
    # 以免日后有人把日志改成独立于备份会话时，-WhatIf 下会悄悄写出文件。
    if ($script:WantWhatIf) { return }
    $line = "{0}`t{1}`t{2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
}

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkGray
    Write-Host ("  $Text") -ForegroundColor White
    Write-Host ('=' * 78) -ForegroundColor DarkGray
    Write-Log "=== $Text ==="
}

function Write-Sub {
    param([string]$Text)
    Write-Host ''
    Write-Host ("-- $Text " + ('-' * [Math]::Max(0, 70 - $Text.Length))) -ForegroundColor DarkCyan
    Write-Log "--- $Text"
}

function Write-Note {
    param([string]$Text, [string]$Color = 'Gray')
    Write-Host "   $Text" -ForegroundColor $Color
    Write-Log "NOTE`t$Text"
}

# =============================================================================
#  SECTION 2 — 备份与还原
# =============================================================================

function Read-Config {
    param([string]$Path)

    # 注意：这里刻意不提供"关闭 VBS"之类的配置项 —— 安全降级只能由命令行参数
    # 或菜单的显式选择触发，不允许被一个放在旁边的 json 悄悄打开。
    $cfg = [PSCustomObject]@{
        BackupRoot        = ''
        DisableNagle      = $true
        DisableIPv6Tunnel = $true
        KeepFontSmoothing = $true
        CleanupEnabled    = $true
        NeverDisable      = @('Spooler', 'WlanSvc', 'dot3svc', 'Dnscache', 'LanmanServer', 'LanmanWorkstation', 'RpcSs', 'EventLog')
    }

    if (-not $Path) {
        $cand = Join-Path -Path $PSScriptRoot -ChildPath 'Svr2Desktop.config.json'
        if (Test-Path -LiteralPath $cand) { $Path = $cand }
    }
    if (-not $Path) { return $cfg }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Note "config not found: $Path (using built-in defaults)" 'DarkYellow'
        return $cfg
    }

    try {
        $cfgText = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

        # PS7 有 Test-Json，可以在反序列化之前先校验结构；5.1 没有这个命令，
        # 只能依赖 ConvertFrom-Json 抛错后走 catch。两条路径最终都落到默认值。
        if ($script:IsPS7 -and (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
            if (-not ($cfgText | Test-Json -ErrorAction Stop)) {
                throw 'not a valid JSON document'
            }
        }
        $raw = $cfgText | ConvertFrom-Json
        Write-Note "config loaded: $Path" 'DarkGray'
    } catch {
        Write-Note "config parse failed, defaults used: $($_.Exception.Message)" 'DarkYellow'
        return $cfg
    }

    # 键名白名单 —— 绝不接受 BACKUP_DIR / LOG_FILE / TEMP / PATH 这类可以
    # 劫持脚本自身行为的键（v8.1 的 :LOAD_CONFIG 正是栽在这里）。
    # ★ NeverDisable 是**守卫**，不是普通配置项（v12.0，审计 A-04）：
    # 内置清单是**地板**，json 只能往上加。此前它是普通白名单键、被 json 无条件覆盖，
    # 一个 {"NeverDisable": []} 就能把 Spooler / RpcSs / EventLog 这些守卫全部清空 ——
    # 这与本文件"安全降级不能被一个放在旁边的 json 悄悄打开"是同一条规矩的另一面：
    # 降级不能被打开，守卫也不能被削掉。
    $allow = @('BackupRoot', 'DisableNagle', 'DisableIPv6Tunnel', 'KeepFontSmoothing', 'CleanupEnabled')
    foreach ($k in $allow) {
        if ($raw.PSObject.Properties.Name -contains $k) { $cfg.$k = $raw.$k }
    }
    if ($raw.PSObject.Properties.Name -contains 'NeverDisable') {
        $cfg.NeverDisable = @(@($cfg.NeverDisable) + @($raw.NeverDisable) | Select-Object -Unique)
    }
    return $cfg
}

function Get-BackupRoot {
    <#
      备份根的**唯一**解析处（v13.1 收敛）。

      此前这段逻辑抄在 New-BackupSession 与 New-VerifySession 两处；v13.1 的备份保留
      （CL2）要用第三遍 —— 那就是"同一份清单抄三份，早晚各写各的"。
      优先级：命令行 -BackupRoot > 配置文件 BackupRoot > 默认 SystemDrive\Svr2DesktopBackup。

      $env:SystemDrive 为空（非 Windows / 被裁剪的服务上下文）时 Join-Path 会抛异常，
      这里**不吞**：调用方各自决定怎么降级（New-VerifySession 记 NOTE 退回屏幕、
      CL2 记 SKIP 不删东西）—— 删东西这条线上，静默降级是不可接受的。
    #>
    $root = $BackupRoot
    if (-not $root) { $root = $script:Config.BackupRoot }
    if (-not $root) { $root = Join-Path -Path $env:SystemDrive -ChildPath 'Svr2DesktopBackup' }
    return $root
}

function New-BackupSession {
    param([string]$Root)

    # v13.1：根解析走 Get-BackupRoot（同一份逻辑不再抄第二遍）
    if (-not $Root) { $Root = Get-BackupRoot }

    $script:Bak.Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:Bak.Dir   = Join-Path -Path $Root -ChildPath ("Svr2Desktop_{0}" -f $script:Bak.Stamp)

    if (-not (Test-Path -LiteralPath $script:Bak.Dir)) {
        New-Item -ItemType Directory -Path $script:Bak.Dir -Force | Out-Null
    }
    $script:LogFile = Join-Path -Path $script:Bak.Dir -ChildPath 'Svr2Desktop.log'
    # 先以带 BOM 的方式建出日志文件：PS7 的 Add-Content -Encoding UTF8 不带 BOM，
    # 而 5.1 带；若首建发生在 PS7 下，之后用 5.1 读日志会看到乱码中文。
    try { Write-TextFileUtf8Bom -Path $script:LogFile -Lines @() } catch { }

    Write-Log ("Svr2Desktop v{0} start | host={1} build={2} install={3} ps={4}" -f `
        $script:VER, $script:HInfo.Caption, $script:HInfo.Build, $script:HInfo.Install, $script:HInfo.PSVersion)
    Write-Log "backup dir: $($script:Bak.Dir)"
}

function New-VerifySession {
    <#
      给 -Verify 一个**日志落点**（v12.0，审计 A-03）。

      病在哪：-Verify 不创建备份会话（那会写快照并生成还原脚本，与只读语义相悖），
      而 $script:LogFile 只在 New-BackupSession 里被赋值 → 该模式下 Write-Log 直接
      return，**整份报告只活在屏幕上**；-Json 也不是有效产物（入口提前 return，
      且 Save-JsonResult 要求 Bak.Dir 非空 —— 双重失效）。
      而本脚本推荐的核心方法论恰恰是"两次 -Verify 的差集就是本次改动的证明"，
      差集要靠留档才存在。靠人肉抄屏，基线是不可靠的。

      所以只开一个落点：与备份同根、名字自带 verify_ 前缀（不与任何备份会话混淆），
      **不写快照、不生成还原脚本**。目录建不出来时明说并退回旧行为 —— 静默失败
      会让操作员以为有日志。
      预演（-WhatIf）下不建：预演承诺"什么都不写"，日志也不例外。
    #>

    if ($script:WantWhatIf) { return }
    if ($script:VerifyDir) { return }   # 菜单里反复按 [V] 不重复建目录

    $root = ''
    $dir  = ''
    try {
        # 根目录解析也放进 try：$env:SystemDrive 为空（非 Windows / 被裁剪的服务上下文）
        # 时 Join-Path 会抛 null 路径异常 —— 那正是入口守卫要挡的处境，这里只需如实降级。
        $root = Get-BackupRoot
        $dir = Join-Path -Path $root -ChildPath ('Svr2Desktop_verify_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $script:LogFile = Join-Path -Path $dir -ChildPath 'Svr2Desktop_verify.log'
        Write-TextFileUtf8Bom -Path $script:LogFile -Lines @()
        $script:VerifyDir = $dir
    } catch {
        $script:VerifyDir = ''
        $script:LogFile   = $null
        Write-Note ("verify log could not be created under {0} ({1}) - this report lives on screen only" -f $dir, $_.Exception.Message) 'DarkYellow'
        return
    }
    Write-Log (("Svr2Desktop v{0} VERIFY (read-back only) | host={1} build={2} install={3} ps={4}") -f `
        $script:VER, $script:HInfo.Caption, $script:HInfo.Build, $script:HInfo.Install, $script:HInfo.PSVersion)
    Write-Log "verify dir: $dir"
}

function Get-BakLeaf {
    param([string]$Leaf)
    return (Join-Path -Path $script:Bak.Dir -ChildPath $Leaf)
}

function Save-EnvironmentSnapshot {
    Write-Sub 'Environment snapshot'

    try {
        Get-ComputerInfo | Select-Object CsName, OsName, OsVersion, OsBuildNumber, CsManufacturer, CsModel |
            Format-List | Out-File -LiteralPath (Get-BakLeaf 'environment.txt') -Encoding UTF8
    } catch { }

    try {
        Get-Service | Select-Object Name, DisplayName, Status, StartType |
            Sort-Object Name | Export-Csv -LiteralPath (Get-BakLeaf 'services.csv') -NoTypeInformation -Encoding UTF8
    } catch { }

    try {
        Get-WindowsFeature | Select-Object Name, DisplayName, Installed |
            Sort-Object Name | Export-Csv -LiteralPath (Get-BakLeaf 'features.csv') -NoTypeInformation -Encoding UTF8
    } catch { }

    try {
        (powercfg /list) | Out-File -LiteralPath (Get-BakLeaf 'powerplans.txt') -Encoding UTF8
        (powercfg /getactivescheme) | Out-File -LiteralPath (Get-BakLeaf 'powerplan-active.txt') -Append -Encoding UTF8
    } catch { }

    Write-Note 'services / features / power plans / environment captured' 'DarkGray'
    Write-Log 'environment snapshot saved'
}

function Backup-RegValue {
    param([string]$Path, [string]$Name)

    $key = "$Path|$Name"
    foreach ($b in $script:Bak.Reg) { if ($b.Key -eq $key) { return } }

    $existed = $false
    $val     = $null
    $kind    = 'String'

    if (Test-Path -LiteralPath $Path) {
        try {
            $k = Get-Item -LiteralPath $Path -ErrorAction Stop
            if ($k.GetValueNames() -contains $Name) {
                $existed = $true
                $val     = $k.GetValue($Name)
                $kind    = $k.GetValueKind($Name).ToString()
            }
        } catch { }
    }

    [void]$script:Bak.Reg.Add([PSCustomObject]@{
        Key = $key; Path = $Path; Name = $Name
        Existed = $existed; Value = $val; Kind = $kind
    })
}

function Backup-Service {
    param([string]$Name)

    foreach ($b in $script:Bak.Svc) { if ($b.Name -eq $Name) { return } }

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        [void]$script:Bak.Svc.Add([PSCustomObject]@{ Name = $Name; Existed = $false; StartMode = $null; State = $null })
        return
    }
    $mode = $null
    try {
        $w = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction Stop
        $mode = $w.StartMode
    } catch { }

    [void]$script:Bak.Svc.Add([PSCustomObject]@{
        Name = $Name; Existed = $true; StartMode = $mode; State = [string]$svc.Status
    })
}

function Backup-Feature {
    param([string]$Name)

    foreach ($b in $script:Bak.Feat) { if ($b.Name -eq $Name) { return } }

    $f = Get-WindowsFeature -Name $Name -ErrorAction SilentlyContinue
    if (-not $f) {
        [void]$script:Bak.Feat.Add([PSCustomObject]@{ Name = $Name; Existed = $false; Installed = $false })
        return
    }
    [void]$script:Bak.Feat.Add([PSCustomObject]@{ Name = $Name; Existed = $true; Installed = [bool]$f.Installed })
}

function Backup-Task {
    param([string]$TaskPath, [string]$TaskName)

    $key = "$TaskPath|$TaskName"
    foreach ($b in $script:Bak.Task) { if ($b.Key -eq $key) { return } }

    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) {
        [void]$script:Bak.Task.Add([PSCustomObject]@{ Key = $key; Path = $TaskPath; Name = $TaskName; Existed = $false; State = $null })
        return
    }
    [void]$script:Bak.Task.Add([PSCustomObject]@{
        Key = $key; Path = $TaskPath; Name = $TaskName; Existed = $true; State = [string]$t.State
    })
}

function Backup-NativeCommand {
    <#
      原生命令改动的登记口 —— 闭合审计 A-01 里与 F-02 同源的那一半。

      病在哪：有些改动没有任何 Reg / Svc / Feat / Task / Power 通道能表达 ——
      secedit 写的密码策略、netsh 改的 TCP 全局参数、Set-SmbServerConfiguration
      改的 SMBv1、Set-MpPreference 改的 Defender 偏好。它们此前**只被写入**，
      既无原值、也无回放路径，于是"所有改动均可一键还原"这句承诺对它们不成立；
      更糟的是 SEC11：策略键与服务都还原了，实时防护却还是关的，而报告会说已还原。

      怎么做：每个条目是一条**可回放的 PowerShell 源码行**，由调用方自己给出
      （读原值 → 拼回放语句）。本函数只登记，不做任何解释与推测 —— 生成器
      负责把它原样排进还原脚本的"native commands"段。职责边界与 Dispose 一样清楚：
      **谁改的谁负责给出回放语句**，因为只有它知道那条命令的正确等价物是什么。

      PreState 是给人看的原值快照，会以注释形式落在还原脚本里；read 失败时调用方
      传一个诚实说明（而不是一个猜的值），回放语句则退化为一句"需人工处理"的注释 ——
      宁可留白，也不回放一个我们没读准的值。
    #>
    param([string]$Key, [string]$PreState, [string]$Replay)

    foreach ($b in $script:Bak.Cmd) { if ($b.Key -eq $Key) { return } }
    [void]$script:Bak.Cmd.Add([PSCustomObject]@{ Key = $Key; PreState = $PreState; Replay = $Replay })
}

function ConvertTo-PSValueLiteral {
    param([object]$Value, [string]$Kind)

    switch ($Kind) {
        'DWord' { return ([string][int]$Value).Trim() }
        'QWord' { return ([string][long]$Value).Trim() }
        'MultiString' {
            $parts = New-Object System.Collections.ArrayList
            foreach ($v in @($Value)) { [void]$parts.Add(("'{0}'" -f ([string]$v).Replace("'", "''"))) }
            return ('@({0})' -f ($parts -join ', '))
        }
        'Binary' {
            $bytes = New-Object System.Collections.ArrayList
            foreach ($x in @($Value)) { [void]$bytes.Add([string][int]$x) }
            return ('([byte[]]@({0}))' -f ($bytes -join ','))
        }
        default { return ("'{0}'" -f ([string]$Value).Replace("'", "''")) }
    }
}

function ConvertTo-PSSvcStartup {
    param([string]$WmiMode)
    switch ($WmiMode) {
        'Auto'     { return 'Automatic' }
        'Manual'   { return 'Manual' }
        'Disabled' { return 'Disabled' }
        default    { return 'Manual' }
    }
}

function New-RestoreScript {
    $out = Get-BakLeaf ("Restore_{0}.ps1" -f $script:Bak.Stamp)
    $L   = New-Object System.Collections.Generic.List[string]

    $L.Add('#Requires -Version 5.1')
    $L.Add('#Requires -RunAsAdministrator')
    $L.Add('# =============================================================================')
    $L.Add(('#  Restore script - generated by Svr2Desktop v{0}' -f $script:VER))
    $L.Add(('#  Generated : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $L.Add(('#  Target    : {0} (build {1}, {2})' -f $script:HInfo.Caption, $script:HInfo.Build, $script:HInfo.Install))
    $L.Add(('#  Backup    : {0}' -f $script:Bak.Dir))
    $L.Add('#')
    $L.Add('#  Rolls back the registry / service / feature / scheduled-task / power values')
    $L.Add('#  captured immediately BEFORE the run.')
    $L.Add('#  Registry values that did not exist before are removed; existing ones are')
    $L.Add('#  re-written with their original kind and data. Services return to their')
    $L.Add('#  original start mode (and are started again if they were running),')
    $L.Add('#  scheduled tasks to their original state.')
    $L.Add('#')
    $L.Add('#  NOT replayable here: the temp files deleted by the cleanup stage (there is')
    $L.Add('#  no undo for a deletion), and the TCP heuristics switch on builds that offer')
    $L.Add('#  no language-independent way to read it back.')
    $L.Add('#  Everything else - including the password policy, the TCP globals, SMBv1 and')
    $L.Add('#  the Defender preferences - is replayed by the native-command section below.')
    $L.Add('#')
    $L.Add('#  NOTE: a reboot may be required for every change to take effect.')
    $L.Add('# =============================================================================')

    # v13.1 起：本次到底有没有**可回放的值**？没有的话这份脚本是空壳，必须由它自己在
    # 顶部说清。E11 夹具实测过空壳的形态：五段各自都写了 "(no ... were changed)"，
    # 逐段读是自明的，但**顶部没有一句总声明**，操作员得连读五段才能确认；而且 power
    # 段末尾那句无条件的 `powercfg /setactive` 看起来像"干过活"。这不是假绿，是阅读成本。
    #
    # ★ v13.2 更正措辞（由真机逼出）：13.1 那句话写的是 "NOTHING WAS CHANGED IN THIS RUN"，
    #   而真机 `-Stage Cleanup` 那一跑里 CL1 删了 14 个文件、CL2 也动了备份根 —— 只是这些
    #   动作不进备份通道，脚本仍是空壳。**判据（备份通道是否为空）是对的，话说过头了**：
    #   该说的是"没有可回放的值"，不是"什么都没改"。报告说出证据支持不了的话，正是本文件
    #   要杀的那类毛病 —— 哪怕方向是"往坏处说"也不行，因为它会掩盖真实发生过的事。
    # 判据取"六个备份通道是否有任何条目"：任一非空即视为有过动作。这是**保守方向** ——
    # 宁可不说"没改"，也不谎报"没改"（Power 通道里值为 $null 的条目仍算"有动作"，
    # 于是这种情况下不会打这句声明，属可接受的不精确）。
    $anyReplay = (@($script:Bak.Reg).Count + @($script:Bak.Svc).Count + @($script:Bak.Feat).Count +
                  @($script:Bak.Task).Count + @($script:Bak.Power).Count + @($script:Bak.Cmd).Count) -gt 0
    if (-not $anyReplay) {
        $L.Add('#  ★ THIS SCRIPT HAS NOTHING TO REPLAY: no registry / service / feature /')
        $L.Add('#    scheduled-task / power / native-command value was captured in this run, so')
        $L.Add('#    every section below is a placeholder and running it reports 0 applied items.')
        $L.Add('#    ★ NOTE this is about REPLAYABLE values, not about "nothing happened": the')
        $L.Add('#      cleanup stage may well have deleted files in this run. Deletions are not')
        $L.Add('#      restorable in any case (a deletion has no undo) and they never go through')
        $L.Add('#      the backup channels - which is exactly why this script cannot replay them.')
    }
    $L.Add('')
    $L.Add('$ErrorActionPreference = ''Continue''')
    $L.Add('$ok = 0')
    $L.Add('$fail = 0')
    # v12.0（审计 D-03）：$touched = 0 从早期模板沿袭至今，生成物里从未读写过一次。
    # 本项目为同类理由删过 Set-RegMultiString 与 Invoke-StageByName 的死分支，此处一并清掉。
    $L.Add('')
    $L.Add('function Invoke-RestoreReg {')
    $L.Add('    param([string]$Path, [string]$Name, [bool]$Existed, [object]$Value, [string]$Kind)')
    $L.Add('    try {')
    $L.Add('        if ($Existed) {')
    $L.Add('            if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }')
    $L.Add('            New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null')
    $L.Add('        } else {')
    # v12.0（审计 D-01）：删除分支此前是 `-ErrorAction SilentlyContinue` 紧跟一句无条件的
    # $script:ok++ —— 删没删掉都记成功，与 v8.1「逐行无条件写完成」同形，只是范围小。
    # 真机上那次 applied: 87 恰好每项都生效，但那是运气而不是保证。这里让失败真的抛出来，
    # catch 会打 [FAIL] reg <路径> :: <原因> 并计 $fail —— 有名字的失败才修得动。
    $L.Add('            if (Test-Path -LiteralPath $Path) { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop }')
    $L.Add('        }')
    $L.Add('        $script:ok++')
    $L.Add('    } catch {')
    $L.Add('        $script:fail++')
    $L.Add('        Write-Host ("  [FAIL] reg {0} :: {1}" -f $Path, $_.Exception.Message) -ForegroundColor Red')
    $L.Add('    }')
    $L.Add('}')
    $L.Add('')
    $L.Add('Write-Host ''Svr2Desktop restore - starting'' -ForegroundColor Cyan')
    $L.Add('')

    $L.Add('# ---- registry ----')
    if ($script:Bak.Reg.Count -eq 0) {
        $L.Add('# (no registry values were changed)')
    } else {
        foreach ($r in $script:Bak.Reg) {
            $psPath = ([string]$r.Path).Replace("'", "''")
            $name   = ([string]$r.Name).Replace("'", "''")
            $kind   = [string]$r.Kind
            $existed = if ($r.Existed) { '$true' } else { '$false' }
            $lit = '0'
            if ($r.Existed) { $lit = ConvertTo-PSValueLiteral -Value $r.Value -Kind $kind }
            if (-not $r.Existed) { $kind = 'String' }
            $L.Add(("Invoke-RestoreReg -Path '{0}' -Name '{1}' -Existed {2} -Value {3} -Kind '{4}'" -f `
                $psPath, $name, $existed, $lit, $kind))
        }
    }
    $L.Add('')

    $L.Add('# ---- services ----')
    $anySvc = $false
    foreach ($s in $script:Bak.Svc) {
        if (-not $s.Existed) { continue }
        $anySvc = $true
        $st = ConvertTo-PSSvcStartup -WmiMode ([string]$s.StartMode)
        # 注意：`$ok++ 的反引号不可省 —— 这里是要生成代码文本，不是当场自增
        $L.Add(("try {{ Set-Service -Name '{0}' -StartupType {1} -ErrorAction Stop; if ('{2}' -eq 'Running') {{ Start-Service -Name '{0}' -ErrorAction SilentlyContinue }}; `$ok++ }} catch {{ `$fail++; Write-Host '  [FAIL] svc {0}' -ForegroundColor Red }}" -f $s.Name, $st, $s.State))
    }
    if (-not $anySvc) { $L.Add('# (no services were changed)') }
    $L.Add('')

    $L.Add('# ---- scheduled tasks ----')
    $anyTask = $false
    foreach ($t in $script:Bak.Task) {
        if (-not $t.Existed) { continue }
        if ($t.State -eq 'Disabled') { continue }
        $anyTask = $true
        $tp = ([string]$t.Path).Replace("'", "''")
        $tn = ([string]$t.Name).Replace("'", "''")
        # v12.0（审计 D-05）：失败必须点名 —— 这一段此前只计 $fail，操作员看到末行
        # "failed: 1" 却不知是哪一项，与 reg / svc / native 三段的 [FAIL] 行不一致。
        $L.Add(("try {{ Enable-ScheduledTask -TaskPath '{0}' -TaskName '{1}' -ErrorAction Stop | Out-Null; `$ok++ }} catch {{ `$fail++; Write-Host ('  [FAIL] task {0}{1}: ' + `$_.Exception.Message) -ForegroundColor Red }}" -f $tp, $tn))
    }
    if (-not $anyTask) { $L.Add('# (no scheduled tasks were disabled)') }
    $L.Add('')

    $L.Add('# ---- windows features ----')
    $anyFeat = $false
    foreach ($f in $script:Bak.Feat) {
        if (-not $f.Existed) { continue }
        $anyFeat = $true
        if ($f.Installed) {
            $L.Add(("try {{ if (-not (Get-WindowsFeature -Name '{0}').Installed) {{ Install-WindowsFeature -Name '{0}' -ErrorAction Stop | Out-Null }}; `$ok++ }} catch {{ `$fail++ }}" -f $f.Name))
        } else {
            $L.Add(("try {{ if ((Get-WindowsFeature -Name '{0}').Installed) {{ Uninstall-WindowsFeature -Name '{0}' -ErrorAction Stop | Out-Null }}; `$ok++ }} catch {{ `$fail++ }}" -f $f.Name))
        }
    }
    if (-not $anyFeat) { $L.Add('# (no windows features were changed)') }
    $L.Add('')

    $L.Add('# ---- power settings ----')
    $anyPwr = $false
    foreach ($pw in $script:Bak.Power) {
        if ($null -eq $pw.Value) { continue }
        $anyPwr = $true
        $pf = '/setacvalueindex'
        if ($pw.IsDc) { $pf = '/setdcvalueindex' }
        # 注意：`$ok++ 的反引号不可省 —— 这里是要生成代码文本，不是当场自增
        # v12.0（审计 D-05）：同上 —— 点出是哪一项、回放到哪个值。
        $L.Add(("try {{ powercfg {0} SCHEME_CURRENT {1} {2} {3} | Out-Null; `$ok++ }} catch {{ `$fail++; Write-Host ('  [FAIL] power {1} {2} -> {3}: ' + `$_.Exception.Message) -ForegroundColor Red }}" -f $pf, $pw.SubGroup, $pw.Setting, $pw.Value))
    }
    if (-not $anyPwr) { $L.Add('# (no power settings were changed)') }
    $L.Add('try { powercfg /setactive SCHEME_CURRENT | Out-Null } catch { }')
    $L.Add('')

    $L.Add('# ---- native commands (no registry / service channel could express these) ----')
    $anyCmd = $false
    foreach ($c in $script:Bak.Cmd) {
        $anyCmd = $true
        # 不用 -f 拼这两行：Key / PreState 里出现花括号就会破坏格式串。
        $L.Add('# pre-run state (' + $c.Key + '): ' + $c.PreState)
        # 回放语句**独立成行**放在 try 里，不拼成一行。理由：Replay 文本由调用方自由
        # 给出，"原值读不出"那一档给的是一句说明性语句 —— 一旦把它拼进单行，
        # 语句里的 `#` 会把后面的 `}` 一起吃掉，生成的脚本直接语法错误。
        # 这不是假想：本地夹具用"原值读不出"这一档就把它撞出来了
        # （生成的还原脚本 AST 报 Missing closing }）。生成器必须对回放文本免疫。
        # 计数行用单引号串写，$ok++ 自然就是字面量，不需要反引号。
        $L.Add('try {')
        $L.Add('    ' + $c.Replay)
        $L.Add('    ' + '$ok++')
        $L.Add('} catch {')
        $L.Add('    ' + '$fail++')
        $L.Add(("    Write-Host ('  [FAIL] native {0}: ' + `$_.Exception.Message) -ForegroundColor Red" -f $c.Key))
        $L.Add('}')
    }
    if (-not $anyCmd) { $L.Add('# (no native-command changes were recorded)') }
    $L.Add('')

    $L.Add('Write-Host ""')
    $L.Add('Write-Host ("Restore finished - applied: {0}  failed: {1}" -f $ok, $fail) -ForegroundColor Cyan')
    $L.Add('Write-Host "NOTE: reboot the server to make every restored value active." -ForegroundColor Yellow')

    Write-TextFileUtf8Bom -Path $out -Lines $L

    # 额外留一份可直接给 powercfg 用的电源方案原始输出，便于人工核对
    try {
        (powercfg /list) | Out-File -LiteralPath (Get-BakLeaf 'powerplans_after.txt') -Encoding UTF8
    } catch { }

    # Misc 通道在 v10.0 里只写不落盘 —— 等于黑洞。这里补一份文本留档。
    try {
        $ml = New-Object System.Collections.Generic.List[string]
        foreach ($m in $script:Bak.Misc) {
            $ml.Add(('{0} = {1}' -f $m.Key, (($m.Value | Out-String).Trim())))
        }
        if ($ml.Count -gt 0) { Write-TextFileUtf8Bom -Path (Get-BakLeaf 'misc_snapshot.txt') -Lines $ml }
    } catch { }

    Write-Note "restore script: $out" 'DarkGray'
    if (-not $anyReplay) {
        Write-Note 'no replayable values were captured in this run - the restore script is a placeholder (it says so at the top); note that cleanup deletions are NOT restorable and are therefore not replayed either' 'DarkGray'
    }
    Write-Log "restore script generated: $out"
    return $out
}

# =============================================================================
#  SECTION 3 — 原子操作（全部自带备份登记）
# =============================================================================

# -----------------------------------------------------------------------------
#  判定依据采集（Evidence Trail）—— v11.4
# -----------------------------------------------------------------------------
# 病在哪：v11.3 的真机日志里 34 个步骤报 SKIP，而报告只给出一个结论词。操作员
# 无法从输出判断"SKIP 是真达标，还是探针判错了"—— 这不是可确认的结论。它与
# v8.1「逐行无条件写完成」是同一类病的两种表现：那边是无条件假绿，这边是无法
# 证伪。同理，4 个 FAIL 的 Detail 只写 "post-check returned false"，没有实测值，
# 定因只能靠猜。
#
# 怎么做：把观察钩子挂在**读值原语**层。任何用这些原语搭建的步骤都自动获得
# 证据链，不必逐个去改步骤定义。开销是一行字符串，收益是每次结论都可复核。
#
# 硬约束：Add-Evidence 必须用 [void] 吞掉返回值 —— 探针脚本块内多出一个管道
# 输出，$pr.State 就会取空（v11.1 已踩过这个坑）。
#
# v11.6 追加：凡是"电源设置项的实测值"，后面都跟一段 [block: ...]，回答
# "这个值是**从哪一项**读来的"。起因是取值逻辑（取输出里含 0x 的行的倒数第 2 /
# 第 1 个）隐含了一个从未在真机上确认过的前提 —— "指定了 setting 的查询只会输出
# 一个设置块"。而 P4 那四项的期望值**全是 0**：真要是串了块，报告照样是绿的。
#   [block: DISKIDLE]                     读的就是这一项
#   [block: <none>]                       这份输出里没有设置块（与 N/A 互相印证）
#   [blocks: A + B <-- AMBIGUOUS ...]     读到多个块 → 取的值可能属于别的项
# 三种措辞对应三种事实，读报告的人不必去猜。
#
# v11.7 追加：证据**分期**。真正执行了动作的步骤，其证据分 before / after 两段
# （见 Invoke-StepOne 的封存点）。前检与后检原先共用一个缓冲，同一行会重复出现
# 两遍 —— 不止难看，它把"值有没有移动"埋掉了，而那正是判"到底写没写进去"的
# 唯一依据。硬约束：自洽性守门人只吃 after 段。before 段必然带着"动作前不达标"
# 的 MISMATCH，一起喂进去守门人会为这个必然出现的标记而永久静音。
$script:Evidence = New-Object System.Collections.ArrayList

function Reset-Evidence {
    $script:Evidence = New-Object System.Collections.ArrayList
}

function Add-Evidence {
    param([string]$Text)
    if ($null -eq $script:Evidence) { return }
    if (-not $Text) { return }
    $n = $script:Evidence.Count
    if ($n -gt 0) {
        if ([string]$script:Evidence[$n - 1] -eq $Text) { return }
    }
    [void]$script:Evidence.Add($Text)
}

function Get-EvidenceText {
    if ($null -eq $script:Evidence) { return '' }
    if ($script:Evidence.Count -eq 0) { return '' }
    return ($script:Evidence -join "`r`n")
}

function Get-EvidenceMark {
    param([bool]$Ok)
    # 只给不匹配的行加记号：满屏 "OK" 会让人不再读这一列。
    if ($Ok) { return '' }
    return '   <-- MISMATCH'
}

function Shorten-RegPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    # 只留末两段：HKLM 全路径有 70+ 字符，铺满一屏反而看不清值；末两段足以区分
    # Explorer\Advanced 与 Control Panel\Desktop 这类同根键。
    #
    # ★ 但 hive **必须保留**。v11.4 真机报告里 D1 的三条证据行有一对字面完全相同：
    #   HKLM:\SOFTWARE\Microsoft\ServerManager      -> Microsoft\ServerManager
    #   HKCU:\SOFTWARE\Microsoft\ServerManager      -> Microsoft\ServerManager
    # 全是 OK 时只像"重复打印"；一旦其中一个失败，操作员会看到两行一模一样的标签、
    # 一行带 MISMATCH 一行不带，根本无从判断该去改哪一个。hive 是"同一个键名落在
    # 两个位置"的唯一区分手段，不能省。中间用 \...\ 表示被省略的层级。
    $parts = @($Path -split '\\' | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return $Path }
    $hive = ([string]$parts[0]).TrimEnd(':')
    if ($parts.Count -eq 1) { return $hive }
    if ($parts.Count -le 3) { return (($hive + '\') + (@($parts[1..($parts.Count - 1)]) -join '\')) }
    return ("{0}\...\{1}" -f $hive, ($parts[($parts.Count - 2)..($parts.Count - 1)] -join '\'))
}

function Get-EvidenceConflict {
    <#
      「结论必须与证据自洽」的守门人。返回空串 = 自洽；返回一句人话 = 报告在自相矛盾。

      起因（v11.4 真机报告）：D15 / P9 / SEC12 三个步骤被判 NOT-SET，而屏幕上印出的
      证据行**每一条都是 OK**。原因是它们的 -Test 里各有一段手写条件没有挂钩子
      （D15/SEC13 用 Test-Path + GetValueNames 查 Run 键；P9 走未挂钩子的
      Test-TaskDisabled；SEC12 整段手写 secedit 解析）。

      这比"没有证据"更坏：没有证据时操作员知道自己不知道；证据主动说"三项都对"，
      他只会以为报告坏了 —— 更糟的是去改本来正确的东西。所以这里必须开口：
      **要么给出理由，要么明确声明"这个理由我没采集到"。报告永不沉默。**
    #>
    param([string]$Verdict, [string]$Evidence, [string]$Why)

    if (($Verdict -ne 'NOT-SET') -and ($Verdict -ne 'FAIL')) { return '' }
    if ($Why) { return '' }   # 自带原因（探针的 Why / 异常文本）已经够了
    if (-not $Evidence) {
        return 'no evidence was recorded at all: this step reads back through no instrumented primitive (see its -Test block)'
    }
    if ($Evidence -notmatch 'MISMATCH') {
        return 'every recorded check reads OK, yet the step is not satisfied: the deciding condition is NOT instrumented (see its -Test block)'
    }
    return ''
}

function Write-EvidenceLines {
    param([string]$Evidence)
    # 是否调用由调用方决定：执行模式下 SKIP 默认折叠（-Full 展开），其余状态调用；
    # -Verify 摘要视图下仅非 SATISFIED 的步骤调用，-Full 全量。$script:NoEvidence
    # 一票否决屏幕输出。
    if ($script:NoEvidence) { return }
    if (-not $Evidence) { return }
    foreach ($l in @($Evidence -split "\r?\n")) {
        if ([string]$l.Trim() -eq '') { continue }
        Write-Host ("               . {0}" -f $l) -ForegroundColor DarkGray
    }
}

function Get-ActivePowerScheme {
    # 只作证据用：报告里写明改动落在哪个方案上。"活动方案变了"是电源类步骤
    # 反复失败的一个常见根因（写到 A 方案、读到 B 方案），值得每次都印出来。
    # 取 GUID 的写法与语言无关（中文版是"电源方案 GUID:"），括号里是友好名。
    if ($script:ActiveScheme) { return $script:ActiveScheme }
    $guid = ''
    $name = ''
    try {
        $t = (powercfg /getactivescheme) | Out-String
        $m1 = [regex]::Match($t, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
        if ($m1.Success) { $guid = $m1.Groups[1].Value }
        $m2 = [regex]::Match($t, '\(([^)]+)\)')
        if ($m2.Success) { $name = $m2.Groups[1].Value.Trim() }
    } catch { }
    if ($name) {
        $script:ActiveScheme = ("{0} [{1}]" -f $name, $guid)
    } else {
        $script:ActiveScheme = $guid
    }
    return $script:ActiveScheme
}

function Test-KeyExists {
    param([string]$Path)
    return (Test-Path -LiteralPath $Path)
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($k.GetValueNames() -notcontains $Name) { return $null }
        return $k.GetValue($Name)
    } catch { return $null }
}

function Format-RegValue {
    # 位域值用十进制看毫无意义：-2147483645 是个"怪数字"，0x80000003 才是事实。
    # 只对**不常见**的值附十六进制（负数或 >= 10），免得 `= 1 (0x1)` 这种噪音
    # 把真正需要看的那一行淹掉。
    param([object]$Value)
    $s = [string]$Value
    $n = 0
    if (-not [int]::TryParse($s, [ref]$n)) { return $s }
    if ($n -lt 0) {
        # 纯算术转无符号，避开 [uint32] 转换在 5.1/7 上的差异
        $u = [int64]$n + 4294967296
        return ("{0} (0x{1:X8})" -f $s, $u)
    }
    if ($n -ge 10) { return ("{0} (0x{1:X})" -f $s, $n) }
    return $s
}

function Test-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Expected,
        # 位域判定：给出掩码，掩码内**所有位**都置位才算达标。与 -Expected 互斥，优先。
        # 用于系统会自行改写编码的值 —— 典型是 NtfsDisableLastAccessUpdate：脚本写 1
        # （用户管理 + 已禁用），NTFS 把它规范成 0x80000003（系统管理 + 已禁用），
        # 语义完全一致，但字面量比较会判失败。真机 P7 就是这么被判 NOT-SET 的。
        [int]$BitSet = -1,
        # 附在证据行末尾的解释，给"为什么这个怪值算达标"一个可读的出口，
        # 免得操作员去猜我们的判据。
        [string]$Note
    )

    $wantTxt = [string]$Expected
    if ($BitSet -ge 0) {
        $wantTxt = ("bit 0x{0:X} set" -f $BitSet)
        # 位域判定下 -Expected 不参与比较，但它记录了"动作写的是哪个值"——
        # 这份信息对读报告的人有用（"写了 1，读回 0x80000003，为什么算达标"），
        # 印出来比丢掉好，也免得源码里两个参数看起来互相矛盾。
        if ($null -ne $Expected) { $wantTxt = ("{0} (script writes {1})" -f $wantTxt, $Expected) }
    }
    $noteTxt = ''
    if ($Note) { $noteTxt = (" [{0}]" -f $Note) }

    $v = Get-RegValue -Path $Path -Name $Name
    if ($null -eq $v) {
        # 值缺席**也是**一种"不达标"，必须带标记 —— 否则自洽性守门人会对着一条
        # 已经写明理由的报告喊"你没给理由"。规则：凡代表"观察结果不达标"的证据行
        # 都必须带标记，这样守门人那句"every recorded check reads OK"才是准确的。
        Add-Evidence (("reg {0}\{1} = <absent> (want {2}{3})" -f (Shorten-RegPath -Path $Path), $Name, $wantTxt, $noteTxt) + (Get-EvidenceMark -Ok $false))
        return $false
    }
    # $null 一律判假，与 Test-SvcDisabled 对"服务不存在"返回真正好相反 ——
    # 差别在动作侧：Set-RegDword 自带 New-Item，键缺失时会把键建出来，
    # 所以"读不到"在注册表这条线上不存在"无法判定"的中间态。
    $ok = $false
    if ($BitSet -ge 0) {
        $n = 0
        if ([int]::TryParse([string]$v, [ref]$n)) { $ok = (($n -band $BitSet) -eq $BitSet) }
    } else {
        $ok = ([string]$v -eq [string]$Expected)
    }
    Add-Evidence (("reg {0}\{1} = {2} (want {3}{4})" -f (Shorten-RegPath -Path $Path), $Name, (Format-RegValue -Value $v), $wantTxt, $noteTxt) + (Get-EvidenceMark -Ok $ok))
    return $ok
}

function Test-RegValueAbsent {
    <#
      「某个键值不应存在」的**带证据**写法。

      原先这类条件在两处是手写的：
        $x = $true
        if (Test-Path -LiteralPath $rk) {
            $x = ((Get-Item -LiteralPath $rk).GetValueNames() -notcontains 'OneDrive')
        }
      它参与判定却不产证据行 —— 于是真机报告里 D15 呈现为"三条 reg 证据行全 OK
      加一个 NOT-SET"，操作员无从知道其实是这第五个条件没过（见 Get-EvidenceConflict）。
      凡参与判定的条件都必须留痕，这是把"报告可证伪"落实到最后一公里的地方。
    #>
    param([string]$Path, [string]$Name)

    $val = '<absent>'
    if (Test-Path -LiteralPath $Path) {
        $k = Get-Item -LiteralPath $Path
        if ($k.GetValueNames() -contains $Name) { $val = (Format-RegValue -Value $k.GetValue($Name)) }
    }
    $ok = ($val -eq '<absent>')
    Add-Evidence (("reg {0}\{1} = {2} (want <absent>)" -f (Shorten-RegPath -Path $Path), $Name, $val) + (Get-EvidenceMark -Ok $ok))
    return $ok
}

function Add-Check {
    <#
      把任意"手工条件"记成一条证据行，并把它原样返回（便于 $x = Add-Check ...）。

      给那些无法用读值原语表达的回读一个留痕出口：secedit 导出的策略文本、
      Get-LocalUser 的对象属性、外部命令的输出。没有它，SEC12 那种整段手写的 Test
      在报告里只剩一个结论词 —— 那就是"不可证伪"，与 v8.1 的无条件假绿是同一类病的两面。

      调用方负责把**实测值**放进 -Text，形如：
        '[void](Add-Check -Ok $ageOk -Text ("secedit SECURITYPOLICY MaximumPasswordAge = {0} (want -1)" -f $ageTxt))'
    #>
    param([bool]$Ok, [string]$Text)
    Add-Evidence ($Text + (Get-EvidenceMark -Ok $Ok))
    return $Ok
}

function Get-NetUserPasswordExpiryLine {
    <#
      从 `net user` 的**全文**里取出「密码到期」那一行（原样，含标签）。

      为什么必须有它（v11.8）：v11.7 用的是**泛匹配**
          @($nu -split "\r?\n" | Where-Object { $_ -match '(?i)expir|过期|到期' })[0]
      而中文 `net user` 的输出里 **「帐户到期」(Account expires) 排在「密码到期」
      (Password expires) 之前** —— 取到的永远是**帐号**到期。它对几乎所有账户都是
      「从不」，于是这一行看着像佐证、答的却是另一个问题。真机实证（v11.7 会话
      20260921_092704）：那一行印出来正是 `帐户到期               从不`。
      也就是说，当时那条"第二条独立路径"**从来没有回答过它要回答的问题** ——
      与 P9 疑案同族：拿一条**看起来同义**的证据冒充第二条路径。

      所以这里**只认专名**；专名找不到就明说找不到，**绝不退回泛匹配**
      （退回就是重犯同一个错）。抽成独立函数，是为了让"给定一份真实输出、
      取到的是哪一行"这件事能在行为层被断言（见 fn_behavior_suite.ps1 的 I 段，
      夹具直接取自真机输出原文）。
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [PSCustomObject]@{ Found = $false; Line = ''; Why = 'no net user output handed in' }
    }
    # 标签是本地化的，所以按"专名集合"匹配，而不是按语言去推断结构。
    #   zh-CN / zh-TW: 密码到期 / 密碼到期        en: Password expires
    # 刻意不用 \b 收尾：它在非 ASCII 词尾的行为不稳定，而这里标签后面恒是空白或冒号。
    $spec = @($Text -split "\r?\n" | Where-Object { $_ -match '(?i)^\s*(密码到期|密碼到期|password\s+expires)(\s|:|$)' })
    if ($spec.Count -gt 0) {
        return [PSCustomObject]@{ Found = $true; Line = ([string]$spec[0]).Trim(); Why = '' }
    }
    # 专名找不到时，把"泛匹配到几行"当作**可诊断的线索**附上，但仍然不复用它们 ——
    # 目标是让人一眼看出"这一行不是密码到期"，而不是再猜一次。
    $loose = @($Text -split "\r?\n" | Where-Object { $_ -match '(?i)expir|过期|到期' })
    return [PSCustomObject]@{
        Found = $false
        Line  = ''
        Why   = ("no password-expiry line found in net user output (the label is localised); {0} other line(s) merely mention expiry" -f $loose.Count)
    }
}

function Set-RegDword {
    param([string]$Path, [string]$Name, [int]$Value)
    Backup-RegValue -Path $Path -Name $Name
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-RegString {
    param([string]$Path, [string]$Name, [string]$Value, [switch]$Expand)
    Backup-RegValue -Path $Path -Name $Name
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    $t = 'String'
    if ($Expand) { $t = 'ExpandString' }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $t -Force | Out-Null
}

function Remove-RegValueSafe {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ((Get-Item -LiteralPath $Path).GetValueNames() -notcontains $Name) { return }
    Backup-RegValue -Path $Path -Name $Name
    Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
}

function Get-SvcStartMode {
    param([string]$Name)
    try {
        $w = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction Stop
        return $w.StartMode
    } catch { return $null }
}

function Test-SvcDisabled {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        # 本机不存在该服务 → 视为无需处理。这是二态 Test 的妥协：执行侧不刷 FAIL，
        # 代价是"本机没这项"会被报成已达标。凡定义了 Probe 的步骤都不走这条路
        # （S1/S3/S4/S5/S6/S7 都有 Probe）；证据行把这次妥协写出来，避免它再次隐身。
        Add-Evidence ("svc {0} = <not present> -> counted as satisfied (two-state fallback)" -f $Name)
        return $true
    }
    $mode = Get-SvcStartMode -Name $Name
    $ok = ($mode -eq 'Disabled')
    Add-Evidence ("svc {0} start mode = {1} (want Disabled){2}" -f $Name, $mode, (Get-EvidenceMark -Ok $ok))
    return $ok
}

# -----------------------------------------------------------------------------
#  三态探针 —— 供 -Verify 报告与执行前的适用性判断使用
# -----------------------------------------------------------------------------
# 注意：探针脚本块内**不得**产生多余的管道输出（Write-Host 不受影响），否则
# Invoke-StepOne / Invoke-VerifyReport 读 $pr.State 会取空。
function New-ProbeResult {
    param([string]$State, [string]$Why = '')
    return [PSCustomObject]@{ State = $State; Why = $Why }
}

function Get-SvcProbe {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Add-Evidence ("svc {0} = <not present> -> ABSENT (not the same as satisfied)" -f $Name)
        return (New-ProbeResult -State 'ABSENT' -Why ("{0} not present on this build" -f $Name))
    }
    $mode = Get-SvcStartMode -Name $Name
    $ok = ($mode -eq 'Disabled')
    Add-Evidence ("svc {0} start mode = {1} (want Disabled){2}" -f $Name, $mode, (Get-EvidenceMark -Ok $ok))
    if ($ok) { return (New-ProbeResult -State 'OK') }
    return (New-ProbeResult -State 'NOT-SET' -Why ("{0} startup = {1}" -f $Name, $mode))
}

function Get-SvcGroupProbe {
    param([string[]]$Names)
    $present = New-Object System.Collections.ArrayList
    $ok = 0
    foreach ($n in $Names) {
        if (Get-Service -Name $n -ErrorAction SilentlyContinue) {
            [void]$present.Add($n)
            if ((Get-SvcStartMode -Name $n) -eq 'Disabled') { $ok++ }
        }
    }
    Add-Evidence ("svc group [{0}]: present {1}, disabled {2}" -f ($Names -join ', '), $present.Count, $ok)
    if ($present.Count -eq 0) {
        return (New-ProbeResult -State 'ABSENT' -Why ("none of [{0}] present on this build" -f ($Names -join ', ')))
    }
    if ($ok -eq $present.Count) { return (New-ProbeResult -State 'OK') }
    return (New-ProbeResult -State 'NOT-SET' -Why ("{0} of {1} disabled (present: {2})" -f $ok, $present.Count, ($present -join ', ')))
}

function Test-DesktopShell {
    # 本机是否为"带桌面体验"的安装。
    # 以 InstallationType 这一**手来源**为准，刻意不依赖 ServerManager 目录里
    # 有没有某个特性名 —— 真机上这个差异确实存在（Server 2025 build 26200 的
    # 目录里已无 Desktop-Experience，若拿目录当判据就会把图形界面的机器误报成
    # "无此项"）。取值：Server / Server Core / Client。
    $it = [string](Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'InstallationType')
    return ($it -eq 'Server')
}

function Get-GuiProbe {
    # GUI 组件状态。判定顺序刻意是"一手来源优先"：
    #   1) InstallationType 已是 Server（图形界面）→ OK，根本不查特性目录；
    #   2) 否则（Server Core）才去目录里看能否转换，并把三种处境分开报：
    #      Available（可装，可能需联网） / Removed（载荷已移除，必须给 -Source 介质）
    #      / 目录里一个 GUI 特性名都没有（该 build 已取消转换能力）。
    # 这样"查不了"永远不会被当成"没有"，也不会因为查不到名字就谎报已达标。
    # 读值留痕（v11.9）：v11.8 的读侧覆盖报告点出 D13/D14 是"零证据行"的最后两处
    # （真机 v11.7 的 43 步里只有 D13/D14/SEC3），SEC3 已补，这两处一并补上 ——
    # 达标也要能看见"凭什么达标"。
    # 判据与 Test-DesktopShell 同源（同一个 InstallationType 键），这里只是把值印出来。
    $it = [string](Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'InstallationType')
    if ($it -eq 'Server') {
        Add-Evidence (("reg {0}\{1} = {2} (want Server: this install already carries the desktop shell)" -f (Shorten-RegPath -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'), 'InstallationType', (Format-RegValue $it)) + (Get-EvidenceMark -Ok $true))
        return (New-ProbeResult -State 'OK')
    }
    Add-Evidence (("reg {0}\{1} = {2} (want Server; this build is not a desktop-capable install)" -f (Shorten-RegPath -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'), 'InstallationType', (Format-RegValue $it)))

    $names   = @('Server-Gui-Shell', 'Server-Gui-Mgmt-Infra', 'Desktop-Experience')
    $present = New-Object System.Collections.ArrayList
    $canAdd  = $false
    $featEv  = New-Object System.Collections.ArrayList
    foreach ($n in $names) {
        $f = Get-WindowsFeature -Name $n -ErrorAction SilentlyContinue
        if (-not $f) { continue }
        [void]$present.Add($n)
        [void]$featEv.Add(("feature {0}: Installed = {1}, InstallState = {2} (want Installed = True)" -f $n, [bool]$f.Installed, [string]$f.InstallState))
        if ($f.Installed) {
            foreach ($l in $featEv) { Add-Evidence ($l + (Get-EvidenceMark -Ok $true)) }
            return (New-ProbeResult -State 'OK')
        }
        if ([string]$f.InstallState -eq 'Available') { $canAdd = $true }
    }
    if ($present.Count -eq 0) {
        # NA：不是缺口 —— 这个 build 的目录里一个 GUI 特性名都没有。值照印，不打不达标标记。
        Add-Evidence ("feature catalog carries none of: {0} (this build dropped the client-GUI conversion)" -f ($names -join ', '))
        return (New-ProbeResult -State 'NA' -Why 'this host has no desktop shell and this build carries no GUI feature in its catalog')
    }
    if ($canAdd) {
        foreach ($l in $featEv) { Add-Evidence ($l + (Get-EvidenceMark -Ok $false)) }
        return (New-ProbeResult -State 'NOT-SET' -Why ("GUI feature available but not installed: {0}" -f ($present -join ', ')))
    }
    foreach ($l in $featEv) { Add-Evidence $l }
    return (New-ProbeResult -State 'NA' -Why ("GUI payload removed in this build ({0}); re-adding needs matching installation media - not done by this script" -f ($present -join ', ')))
}

function Set-SvcStartup {
    param([string]$Name, [ValidateSet('Automatic', 'Manual', 'Disabled')][string]$Type)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue

    # 本版本 Windows 没有这个服务（例如 2016/2019 上的蓝牙组件）→ 静默跳过。
    # 对应的 Test 返回 $true，最终记 SKIP。若在这里 throw，老系统上会刷出一片
    # FAIL，把真正的问题淹掉。
    if (-not $svc) {
        Write-Log ("SKIP`tservice-not-present`t{0}" -f $Name)
        return
    }

    Backup-Service -Name $Name
    Set-Service -Name $Name -StartupType $Type -ErrorAction Stop
}

function Disable-Svc {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log ("SKIP`tservice-not-present`t{0}" -f $Name)
        return
    }

    foreach ($guard in $script:Config.NeverDisable) {
        if ($guard -eq $Name) { throw "service '$Name' is on the never-disable guard list" }
    }

    Backup-Service -Name $Name
    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    }
    Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
}

function Set-FeatureState {
    param([string]$Name, [ValidateSet('Enable', 'Disable')][string]$State)
    $f = Get-WindowsFeature -Name $Name -ErrorAction SilentlyContinue
    if (-not $f) { throw "windows feature '$Name' not available on this OS" }

    Backup-Feature -Name $Name
    if ($State -eq 'Enable') {
        if (-not $f.Installed) { Install-WindowsFeature -Name $Name -ErrorAction Stop | Out-Null }
    } else {
        if ($f.Installed) { Uninstall-WindowsFeature -Name $Name -ErrorAction Stop | Out-Null }
    }
}

function Test-FeatureInstalled {
    param([string]$Name)
    $f = Get-WindowsFeature -Name $Name -ErrorAction SilentlyContinue
    if (-not $f) { return $false }
    return [bool]$f.Installed
}

function Disable-TaskSafe {
    param([string]$TaskPath, [string]$TaskName)
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return $false }   # 该任务在本版本 Windows 上不存在 → 静默跳过，不算失败
    Backup-Task -TaskPath $TaskPath -TaskName $TaskName
    Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
    return $true
}

function Get-TaskState {
    <#
      计划任务读值的**唯一实现**。返回 @{ Found; State; Backing; Why }。

      为什么需要它（v11.7）：Test-TaskDisabled 原先直接写
          $t = Get-ScheduledTask … -ErrorAction SilentlyContinue
          if (-not $t) { Add-Evidence '… <not present> -> counted as satisfied'; return $true }
      于是"调度器没报出这个任务"被直接当成"本机确实没有这个任务"，进而当成**达标**。
      这两件事必须分开。真机实证：P9 在 v11.6 的执行会话里报 [ OK ]，重启后的
      -Verify 却又是 NOT-SET（PcaPatchDbTask = Ready）—— 究竟是"禁用生效后被系统
      还原"还是"我们没读到却算了达标"，当时的证据分不出来。而全脚本扫过一遍，
      这是唯一一个"读不到即判达标、且没有 Probe 兜底"的位置。

      第二条独立路径：调度器把每个任务存成 System32\Tasks 下的 XML 文件，文件名与
      TaskPath/TaskName 一一对应。"调度器读不到、后备文件却在"这种自相矛盾的组合，
      只可能是我们读值失败 —— 那时绝不判达标，单列 read-back unavailable。
      两个来源都说没有，才算"确实不存在"。与 P2 用子组全清单交叉验证同一手法。
    #>
    param([string]$TaskPath, [string]$TaskName, [switch]$Evidence, [string]$TaskRoot)

    $rel = (@($TaskPath -split '\\' | Where-Object { $_ -ne '' }) -join '\')
    if ($rel) { $rel = $rel + '\' }
    # -TaskRoot 是**注入点，只为可测性**：生产调用一律走默认值（本机的
    # System32\Tasks）。开发机（macOS）没有这个目录，不开放注入点的话，
    # "后备文件在、调度器却读不到"这一档就永远无法在本地被断言 ——
    # 而它恰恰是本版新增的最关键行为（见行为套件 H 段）。
    if (-not $TaskRoot) {
        if ($env:SystemRoot) { $TaskRoot = Join-Path $env:SystemRoot 'System32\Tasks' }
    }
    $bf = ''
    if ($TaskRoot) { $bf = Join-Path $TaskRoot ($rel + $TaskName) }

    $backing = $false
    if ($bf) {
        try { $backing = [bool](Test-Path -LiteralPath $bf) } catch { $backing = $false }
    }

    $t = $null
    try { $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop } catch { $t = $null }

    if (-not $t) {
        if ($backing) {
            $why = ("the scheduler did not report it, but its backing file exists ({0})" -f $bf)
            # 自相矛盾：后备文件在、调度器却读不到 → 这是「我们读不出来」，不是「本机没有」。
            if ($Evidence) {
                Add-Evidence (("task {0}{1} = <read-back unavailable> - {2} -> NOT counted as satisfied" -f $TaskPath, $TaskName, $why) + (Get-EvidenceMark -Ok $false))
            }
            return [PSCustomObject]@{ Found = $false; State = ''; Backing = $true; Why = $why }
        }
        $why = 'not present on this build (no backing file under System32\Tasks)'
        # 两个独立来源都说没有 → 确实不存在，与 Disable-TaskSafe 的静默跳过同源。
        if ($Evidence) {
            Add-Evidence ("task {0}{1} = <not present> ({2}) -> counted as satisfied" -f $TaskPath, $TaskName, $why)
        }
        return [PSCustomObject]@{ Found = $false; State = ''; Backing = $false; Why = $why }
    }
    $st = [string](@($t)[0].State)
    if ($Evidence) {
        Add-Evidence (("task {0}{1} state = {2} (want Disabled)" -f $TaskPath, $TaskName, $st) + (Get-EvidenceMark -Ok ($st -eq 'Disabled')))
    }
    return [PSCustomObject]@{ Found = $true; State = $st; Backing = $backing; Why = '' }
}

function Test-TaskDisabled {
    # 单任务版本，供一般场景使用。P9 的聚合走 Get-TelemetryTaskReport
    # （Probe 与 Test 共用同一套判据，见该函数注释）。
    # -TaskRoot 只为可测性注入，生产调用不传即可。
    param([string]$TaskPath, [string]$TaskName, [string]$TaskRoot)
    $r = Get-TaskState -TaskPath $TaskPath -TaskName $TaskName -Evidence -TaskRoot $TaskRoot
    if (-not $r.Found) { return (-not $r.Backing) }   # 存在却读不到 → 绝不判达标
    return ($r.State -eq 'Disabled')
}

function Get-TelemetryTaskReport {
    <#
      把遥测任务清单读**一遍**并分类，返回 @{ Total; Enabled; Unread; Absent; Ok }。

      P9 的 -Probe（执行前判适用性）与 -Test（动作后回读）都调用它 —— 判据只有一份，
      杜绝"两套读法错位"。这与 Get-PowerCfgValue 替换 Test-PowerCfgValue 的读逻辑是
      同一条理由：同源。差异只留在 Why 的措辞里，不留在"成立与否"的判据里。

      -Tasks 可传入（默认 $script:TelemetryTasks），因而能在行为套件里独立测。
      Enabled / Unread 收的是**任务名**（带状态），不是布尔 —— 读报告的人需要知道是哪个。

      Ok 的语义：没有任何任务处于"未禁用"，也没有任何任务处于"读不出来"。
      「本机不存在」计为达标（与 Disable-TaskSafe 的静默跳过同源），但数量会印出来 ——
      "11 个任务里 5 个本机就没有"和"11 个全部被我关掉"不是同一件事。
    #>
    param($Tasks, [string]$TaskRoot)

    # ★ 判据必须是"未指定"，不能是"不成立"：PowerShell 里空数组是**假**，
    #   写成 if (-not $Tasks) 会把"显式传了一份空清单"偷偷换成脚本级清单 ——
    #   报告于是回一个 Total=11 的结论，而调用方要的是"没有任务"。
    #   生产路径（P9 的 -Probe / -Test）从不传 -Tasks，走的是 $null 分支，行为不变。
    if ($null -eq $Tasks) { $Tasks = $script:TelemetryTasks }
    $all     = @($Tasks)
    $enabled = New-Object System.Collections.ArrayList
    $unread  = New-Object System.Collections.ArrayList
    $absent  = 0
    foreach ($t in $all) {
        $r = Get-TaskState -TaskPath $t.P -TaskName $t.N -Evidence -TaskRoot $TaskRoot
        if (-not $r.Found) {
            if ($r.Backing) { [void]$unread.Add($t.N) } else { $absent++ }
            continue
        }
        if ($r.State -ne 'Disabled') { [void]$enabled.Add(("{0} ({1})" -f $t.N, $r.State)) }
    }
    return [PSCustomObject]@{
        Total   = $all.Count
        Enabled = $enabled
        Unread  = $unread
        Absent  = $absent
        Ok      = (($enabled.Count -eq 0) -and ($unread.Count -eq 0))
    }
}

function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [switch]$AllowNonZero)
    # ★ v12.0（审计 A-05）：把错误偏好在**函数作用域内**降为 Continue，
    # 再重定向 stderr。原因：Windows PowerShell 5.1 有一个已知行为 —— 原生命令的
    # stderr 被 2>&1 重定向进成功流时，那些记录会以 NativeCommandError 走错误管线，
    # 在 $ErrorActionPreference = 'Stop' 下成为终止性错误。真若如此，-AllowNonZero
    # 的逃生口（网卡不支持 RSS 时容忍 netsh 拒绝）就被静默封死，且报错文本会变成
    # NativeCommandError，而不是本函数精心构造的那句"哪个命令、退出码多少、输出什么"。
    # 本函数本来就把 stdout + stderr 一并收下、再逐条检查 $LASTEXITCODE —— 那才是它
    # 的判错方式，不需要错误管线代劳。改后 5.1 与 7 的行为一致。
    # （真机仍建议核一次 5.1 下的行为，见审计 A-05 的一行命令。）
    $ErrorActionPreference = 'Continue'
    $out  = & $File @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowNonZero) {
        throw ("{0} {1} exited {2}: {3}" -f $File, ($Arguments -join ' '), $code, (($out | Out-String).Trim()))
    }
    return (($out | Out-String).Trim())
}

function Clear-StaleScriptTemp {
    # 清掉此前运行遗留的 %TEMP%\svr2desk_*（目前只有 SEC12 的 secedit 导出）。
    #
    # 为什么需要它：SEC12 的 Test 用 secedit /export 落一个临时 inf，靠 finally 删除。
    # 但 finally 只覆盖"正常/异常退出"—— Ctrl+C、直接关窗口、进程被杀都不会走到它。
    # 真机上确实观察到过残留。与其指望每次都能收干净，不如让残留**自愈**：
    # 每次真实执行开跑前先扫一遍。
    #
    # 安全约束：文件名里带 PID 的，先看那个进程还在不在；还在跑就绝不碰 ——
    # 避免误删同时运行的另一个实例正在用的文件。
    $removed = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -Path $env:TEMP -Filter 'svr2desk_*' -File -ErrorAction SilentlyContinue)) {
        $keep = $false
        $m = [regex]::Match($f.Name, '_(\d+)\.')
        if ($m.Success) {
            $owner = 0
            if ([int]::TryParse($m.Groups[1].Value, [ref]$owner)) {
                if (Get-Process -Id $owner -ErrorAction SilentlyContinue) { $keep = $true }
            }
        }
        if (-not $keep) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop -WhatIf:$false
                [void]$removed.Add($f.Name)
            } catch {
                Write-Log ("stale temp remove failed`t{0}`t{1}" -f $f.Name, $_.Exception.Message)
            }
        }
    }
    if ($removed.Count -gt 0) { Write-Log ("stale temp removed`t{0}" -f ($removed -join ', ')) }
}

function Write-TextFileUtf8Bom {
    param([string]$Path, [string[]]$Lines)

    # 显式写 UTF-8 with BOM，不用 Set-Content -Encoding UTF8 ——
    # 这个参数在 PowerShell 5.1 与 7 上行为相反：5.1 写 BOM，7 不写。
    # 生成的还原脚本会被任意版本的 PowerShell 打开，编码必须由脚本自己决定，
    # 不能交给宿主默认。用 .NET API 写，两侧行为完全一致。
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, $enc)
}

function Backup-PowerValue {
    param([string]$SubGroup, [string]$Setting, [switch]$Dc)

    $key = '{0}|{1}|{2}' -f $SubGroup, $Setting, ([bool]$Dc)
    foreach ($b in $script:Bak.Power) { if ($b.Key -eq $key) { return } }

    # 读回当前值：与 Test-PowerCfgValue 共用同一套语言无关解析（Get-PowerCfgValue）。
    # 两个解析器各写一份，迟早出现"测试认为改了、还原按另一个值回放"的错位 ——
    # v10.0 到 v11.0 之间这类错位已经出过一次（方案名粒度 vs 方案内值粒度）。
    # Found=$false（本方案里没有这一项，虚机常见）时登记 $null；还原脚本对 $null
    # 早已是"跳过该行"，不会回放一个空值。
    $r = Get-PowerCfgValue -SubGroup $SubGroup -Setting $Setting
    $cur = $null
    if ($r.Found) {
        $cur = $r.Ac
        if ($Dc) { $cur = $r.Dc }
    }

    [void]$script:Bak.Power.Add([PSCustomObject]@{
        Key = $key; SubGroup = $SubGroup; Setting = $Setting; IsDc = [bool]$Dc; Value = $cur
    })
}

function Set-PowerCfgValue {
    param([string]$SubGroup, [string]$Setting, [int]$Value, [switch]$Dc)
    # 写前登记原值 —— 否则还原脚本无从回放（v10.0 只备份了「当前方案名」，
    # 而 P2/P4 改的是方案内的具体值，粒度对不上）。
    Backup-PowerValue -SubGroup $SubGroup -Setting $Setting -Dc:$Dc

    $flag = '/setacvalueindex'
    if ($Dc) { $flag = '/setdcvalueindex' }
    Invoke-Native -File 'powercfg' -Arguments @($flag, 'SCHEME_CURRENT', $SubGroup, $Setting, ([string]$Value)) | Out-Null

    # 写命令返回 0 不等于写进去了：方案里没有这一项时 powercfg 会静默接受、什么
    # 都不做（真机上 P2 就是这样：exit 0 但回读永远是原值）。这里补一句事实说明，
    # 让"写了等于没写"在证据链里现形，而不是等到 post-check 才变成一个没有信息
    # 量的 "returned false"。
    $chk = Get-PowerCfgValue -SubGroup $SubGroup -Setting $Setting
    if (-not $chk.Found) {
        # v11.16：Reason 三档就要三句不同的话。原文只有一句"本方案没有这一项"，在
        # ambiguous / unreadable 两档上都是**假话**（那一项在，只是我们读不准），
        # 而"结论与事实自洽"正是本文件反复要求的那条规矩。
        $stuck = 'the active scheme exposes no such setting - the write cannot stick'
        if ($chk.Reason -eq 'ambiguous') { $stuck = 'the read-back is ambiguous (more than one setting block) - this write cannot be confirmed' }
        elseif ($chk.Reason -ne 'absent') { $stuck = 'the value could not be read back - this write cannot be confirmed' }
        Add-Evidence ("powercfg set {0} {1}: {2} [{3}] ({4})" -f $SubGroup, $Setting, $stuck, (Get-PowerCfgBlockNote -Facts $chk.Blocks), $chk.Why)
    }
}

function Get-PowerCfgOutputFacts {
    <#
      数一份 powercfg 输出里到底有几个"设置块"、各是哪个设置项的 —— 用来回答一个
      以前没人问过的问题：**我刚才取到的那个 AC/DC 值，属于哪一项？**

      动因（2026-09-18 目标机判决性实验）：取值逻辑是"取输出里含 0x 的行的倒数第 2 /
      倒数第 1 个 = AC / DC"，这在**指定了 setting** 的查询上是对的 —— 那时输出里只有
      1 个设置块。但它建立在一个从未在真机上确认过的假设上：powercfg 确实会按 setting
      名裁剪输出。而 P4 那四项的期望值**全是 0**，万一它没有裁剪、串到了别的项的 0，
      报告照样是绿的，谁也看不出来。

      所以这里不碰取值、不碰判定，只把"这份输出里有几个块、各叫什么"算出来：

          块数 = 1  → 证据行印出块身份（如 [block: DISKIDLE]），操作员可与调用点对照
          块数 > 1  → 标 AMBIGUOUS，明说"这一次读回取的值可能不是你要的那一项"
          块数 = 0  → 印证"本方案没有这一项"，与 absent 判定**互相独立地**对上

      块切分的两条规矩，都是在真机数据上撞出来的（夹具见技能 §6.1）：
        · 块起点用**结构特征**（含 GUID 的行），不用"跳过前 N 块" —— 单 setting 查询
          只有"方案"一段，子组全清单有"方案 + 子组 + 各设置项"段，层级数不一样。
        · 块的身份用"**块内有没有数据行**"判（方案段 / 子组段只有标识行与别名行，
          没有 0x 行）。阈值取 >= 1 而**不是** >= 2：取 >= 2 会把"只暴露一个索引的设置项"
          挤出清单，于是"存在但读法不对"伪装成"不存在" → 假灰，而假灰比假红更危险 ——
          它把缺陷藏进"环境限制"这个看起来完全合理的解释里。
    #>
    param([string]$Out)

    $blocks = New-Object System.Collections.ArrayList
    $cur = $null
    foreach ($ln in @($Out -split "\r?\n")) {
        $m = [regex]::Match($ln, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
        if ($m.Success) {
            if ($null -ne $cur) { [void]$blocks.Add($cur) }
            $cur = [PSCustomObject]@{ Id = $m.Groups[1].Value.ToLower(); Alias = ''; Data = 0 }
            continue
        }
        if ($null -eq $cur) { continue }
        # 别名 = 块内第一次出现"冒号后是一个标识符"的行。要求以字母 / 下划线开头是硬条件：
        # 否则 `当前交流电源设置索引: 0x00000064` 会把 0x00000064 认成别名（被这条挡住）。
        if (($cur.Alias -eq '') -and ($ln -match '[:：]')) {
            $tail = ((($ln -split '[:：]', 2)[1]).Trim() -replace '\(.*$', '').Trim()
            if ($tail -match '^[A-Za-z_][A-Za-z0-9_]{2,}$') { $cur.Alias = $tail }
        }
        if ($ln -match '0x[0-9a-fA-F]+') { $cur.Data = [int]$cur.Data + 1 }
    }
    if ($null -ne $cur) { [void]$blocks.Add($cur) }

    $settings = @($blocks | Where-Object { $_.Data -ge 1 })
    $ids = @($settings | ForEach-Object { $(if ($_.Alias) { $_.Alias } else { $_.Id }) })

    return [PSCustomObject]@{
        Ids     = $ids
        Count   = $settings.Count
        Label   = $(if ($settings.Count -eq 0) { '<none>' } else { $ids -join ' + ' })
        Suspect = ($settings.Count -gt 1)
    }
}

function Get-PowerCfgBlockNote {
    # 证据行里那一段"我读的是哪一块"。三种情形措辞必须分开，别让操作员去猜：
    #   block: <none>              = 这份输出里没有任何设置块（与"本方案没有这一项"互相印证）
    #   block: DISKIDLE            = 读的就是 DISKIDLE
    #   blocks: A + B <-- AMBIGUOUS = 读到了多个块，取的值可能不是想要的那一项
    param($Facts)

    if ($null -eq $Facts) { return 'block: <unknown>' }
    if ($Facts.Count -eq 0) { return 'block: <none>' }
    if ($Facts.Suspect) {
        return ("blocks: {0}  <-- AMBIGUOUS: {1} setting blocks in one read-back, the value taken may belong to another setting" -f $Facts.Label, $Facts.Count)
    }
    return ("block: {0}" -f $Facts.Label)
}

function Get-PowerCfgValue {
    <#
      读一个电源设置项在**当前活动方案**里的 AC / DC 值。
      返回 @{ Found; Ac; Dc; Why }，Found=$false 的语义是
      "本方案里没有这一项"，与"值不等于期望"是两件不同的事：

        不存在 → 探针记 N/A，不动作（写了也写不进去）
        值不对 → 探针记 NOT-SET，动作 + 回读

      v11.3 把两者合并成同一个 $false。虚机的活动方案里没有 CPMINCORES 这一项，
      于是 P2 写不进、也读不到，每次运行都以 FAIL 收场，而失败原因只写
      "post-check returned false" —— 报了个结论，没报事实。

      v11.16 起 Reason 是三档（absent / unreadable / ambiguous）。第三档的含义是
      "这份输出里有多个设置块，倒数两个 0x 可能不属于本项"—— 此时返回 Found=$false，
      宁可判负也不冒充绿（见下方短路处的完整论证）。

      解析语言无关：不匹配 'Current AC Power Setting Index' 这类英文字面标签
      （中文版 Windows 会把字段名一并本地化），而是取含 0x 的行 —— 只有
      Current AC / Current DC 两行带 0x，顺序固定（倒数第 2 = AC，倒数第 1 = DC）。
    #>
    param([string]$SubGroup, [string]$Setting)

    $res = [PSCustomObject]@{
        Found  = $false; Ac = $null; Dc = $null
        Why    = '';     Reason = 'unreadable'
        Blocks = $null
    }

    $out = ''
    $code = $null
    try {
        $out = (powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>&1) | Out-String
        $code = $LASTEXITCODE
    } catch {
        $res.Why = $_.Exception.Message
        return $res
    }

    # 先算"这份输出里有几个设置块、各叫什么"。它与下面的取值**互不依赖**：取值仍然是
    # 原来那套"倒数两个 0x 行"（在单块输出上正确），块报告只是把它的前提**变可见** ——
    # 块数 > 1 就说明 powercfg 没有按 setting 名裁剪，取到的值可能属于别的设置项。
    # v11.6 的处置是"只报告、不据此改判"：判据还没在真机上见过 > 1 的情形，先上机把
    # 事实印出来再决定。**该阶段已经结束** —— v11.7 在 P4 四项上零 AMBIGUOUS，
    # "指定 setting 的查询只输出一个块"这条前提在该 build 上被真机确认。
    # v11.16 据此改成**短路**。理由：前提一旦不成立，那"倒数两个 0x"就可能属于别的
    # 设置项，而判据此前对此毫无反应 —— 本地夹具已复现出假绿（查 DISKIDLE 却串到
    # DISKIDLETIMEOUT 的 0，Test-PowerCfgValue -Expected 0 判 True）。
    # 证据既然已经说了话，判据就必须听。
    # 代价：块数 > 1 时不再返回任何值 → Backup-PowerValue 登记 $null → 还原脚本跳过
    # 该行。"少还原一项"优于"回放一个我们都没读准的值"。
    $res.Blocks = Get-PowerCfgOutputFacts -Out $out
    if ($res.Blocks.Suspect) {
        $flat = (($out -replace '\s*\r?\n\s*', ' / ')).Trim()
        # Why 里刻意**不再复述块注** —— 调用方（Test-PowerCfgValue / 探针）本就会把块注
        # 印在同一行的 [ ] 里，这里再说一遍就是同一件事讲两遍，而重复的措辞只会训练
        # 操作员跳过这一行。此处只带系统原文。
        $res.Why    = ("the read-back was ambiguous; full output: {0}" -f $flat)
        $res.Reason = 'ambiguous'
        return $res
    }

    $hexLines = @($out -split "\r?\n" | Where-Object { $_ -match '0x[0-9a-fA-F]+' })
    if (($code -ne 0) -or ($hexLines.Count -lt 2)) {
        # 把系统自己的原话**整段**带出去（换行压成 / 保持单行）。只摘第一行是不够的：
        # 操作员没法据此判断"powercfg 是明确回答'本方案没有这一项'，还是我们没解析出来"
        # —— 这两种情形的处置完全不同，前者记 N/A，后者是我们自己的缺陷。
        $flat = (($out -replace '\s*\r?\n\s*', ' / ')).Trim()
        $res.Why = ("powercfg exit {0}, {1} line(s) with 0x; output: {2}" -f $code, $hexLines.Count, $flat)

        # 分档判据（语言无关，不看本地化的报错文字）：
        #   命令成功返回（exit 0）且有输出、却没有索引行 → 它是在**回答**"没有这一项" → absent
        #   命令失败 / 无输出                              → 我们可能只是没读懂      → unreadable
        if (($code -eq 0) -and ($flat -ne '')) { $res.Reason = 'absent' } else { $res.Reason = 'unreadable' }
        return $res
    }

    $mAc = [regex]::Match($hexLines[$hexLines.Count - 2], '0x([0-9a-fA-F]+)')
    if (-not $mAc.Success) {
        $res.Why = 'no AC index line in powercfg output'
        return $res
    }
    $res.Found = $true
    $res.Ac = [Convert]::ToInt32($mAc.Groups[1].Value, 16)

    $mDc = [regex]::Match($hexLines[$hexLines.Count - 1], '0x([0-9a-fA-F]+)')
    if ($mDc.Success) { $res.Dc = [Convert]::ToInt32($mDc.Groups[1].Value, 16) }

    return $res
}

function Test-PowerCfgValue {
    param([string]$SubGroup, [string]$Setting, [int]$Expected, [switch]$Dc)

    $r = Get-PowerCfgValue -SubGroup $SubGroup -Setting $Setting
    $which = 'AC'
    if ($Dc) { $which = 'DC' }

    # 每一条证据行都带上"我读的是哪一块"。这个值以前是隐式的：操作员看到
    # `powercfg DISKIDLE AC = 0 (want 0)` 时，无从判断那个 0 究竟来自 DISKIDLE，
    # 还是来自同一份输出里排在后面的另一项 —— 而 P4 四项的期望值**全是 0**，
    # 串了块也照样是绿的。印出块身份，等于把"结论"与"结论的依据"钉在一起。
    $note = Get-PowerCfgBlockNote -Facts $r.Blocks

    if (-not $r.Found) {
        # v11.16：三种"没读到"必须分开说 —— 本方案没有这一项 / 读到多个块、值无法归属 /
        # 我们没解析出来。三者处置方向完全不同（记 N/A / 换个读法 / 修解析器），
        # 合成一句就等于没说，而那句话正是当年 P2 每次刷 FAIL 的形态。
        $missTxt = '<not in active scheme>'
        if ($r.Reason -eq 'ambiguous') { $missTxt = '<read-back ambiguous>' }
        elseif ($r.Reason -ne 'absent') { $missTxt = '<unreadable>' }
        Add-Evidence (("powercfg {0} {1} = {2} [{3}] ({4})" -f $Setting, $which, $missTxt, $note, $r.Why) + (Get-EvidenceMark -Ok $false))
        return $false
    }

    $cur = $r.Ac
    if ($Dc) { $cur = $r.Dc }
    if ($null -eq $cur) {
        Add-Evidence (("powercfg {0} {1} = <unreadable> [{2}] ({3})" -f $Setting, $which, $note, $r.Why) + (Get-EvidenceMark -Ok $false))
        return $false
    }

    $ok = ($cur -eq $Expected)
    Add-Evidence ("powercfg {0} {1} = {2} (want {3}) [{4}]{5}" -f $Setting, $which, $cur, $Expected, $note, (Get-EvidenceMark -Ok $ok))
    return $ok
}

# =============================================================================
#  SECTION 4 — 环境探测
# =============================================================================

function Get-HostProfile {
    $info = [PSCustomObject]@{
        Caption   = 'Unknown'
        Build     = 0
        Version   = '0.0'
        Install   = 'Server'
        IsCore    = $false
        CPUName   = ''
        CPUCores  = 0
        RAMGB     = 0
        IsWin11UI = $false
        PSVersion = $PSVersionTable.PSVersion.ToString()
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $info.Caption = [string]$os.Caption
        $info.Build   = [int]$os.BuildNumber
        $info.Version = [string]$os.Version
    } catch { }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $info.RAMGB = [Math]::Round(($cs.TotalPhysicalMemory / 1GB), 1)
    } catch { }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $info.CPUName  = ([string]$cpu.Name).Trim()
        $info.CPUCores = [int]$cpu.NumberOfCores
    } catch { }

    $it = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'InstallationType'
    if ($it) { $info.Install = [string]$it }
    $info.IsCore = ($info.Install -notmatch '^Server$')

    # Server 2025 (build >= 22000) 使用 Win11 风格桌面 shell
    if ($info.Build -ge 22000) { $info.IsWin11UI = $true }

    return $info
}

function Get-VbsStatus {
    $r = [PSCustomObject]@{
        Query      = 'unavailable'
        VbsStatus  = -1
        Running    = @()
        CgRunning  = $false
        HvciRunning = $false
        LsaCfgFlags = -1
        DeviceGuardEnable = -1
    }

    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction Stop
        $r.Query     = 'ok'
        $r.VbsStatus = [int]$dg.VirtualizationBasedSecurityStatus
        $r.Running   = @($dg.SecurityServicesRunning)
        foreach ($s in $r.Running) {
            if ([int]$s -eq 1) { $r.CgRunning = $true }
            if ([int]$s -eq 2) { $r.HvciRunning = $true }
        }
    } catch {
        $r.Query = "unavailable: $($_.Exception.Message)"
    }

    $v = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags'
    if ($null -ne $v) { $r.LsaCfgFlags = [int]$v }

    $v = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity'
    if ($null -ne $v) { $r.DeviceGuardEnable = [int]$v }

    return $r
}

# =============================================================================
#  SECTION 5 — 步骤注册框架
# =============================================================================

function Add-Step {
    param(
        [Parameter(Mandatory)][string]$StageName,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Action,
        [scriptblock]$Test,
        # 可选：三态探针，返回 New-ProbeResult 生成的对象 { State; Why }。
        #   OK      —— 期望状态已满足（真达标）
        #   ABSENT  —— 本机不存在该服务/功能/硬件，本项不适用（≠ 已优化）
        #   NA      —— 存在，但本机场景下无意义（如单核主机上的核心停泊）
        #   NOT-SET —— 存在且未达标（需要动作）
        # 未提供 Probe 时回退到 Test 的二态。补 Probe 是为了让 -Verify 的
        # SATISFIED 不再与"服务根本不存在"混为一谈：Test-SvcDisabled 对不存在的
        # 服务返回 $true（老系统不刷 FAIL 的代价），执行语义保留，报告必须说实话。
        # 有了 Probe 的步骤，执行判断与报告判断都**只用 Probe**，避免两套逻辑并存。
        [scriptblock]$Probe,

        # 可选：本步骤是"动作型"而非"状态型"—— 执行之后没有可回读的稳态（清理是
        # 典型：临时目录随时会被系统重新填满）。-Verify 会把它标成 [ONE-SHOT] 并
        # 附上这段话，而不是每轮都报 NOT-SET。长期黄灯与长期红灯一样会训练操作员
        # 无视颜色 —— 那比漏报更坏。
        [string]$OneShot = ''
    )
    [void]$script:Steps[$StageName].Add([PSCustomObject]@{
        Id = $Id; Title = $Title; Action = $Action; Test = $Test; Probe = $Probe; OneShot = $OneShot
    })
}

# =============================================================================
#  SECTION 6 — 阶段定义
# =============================================================================

# -----------------------------------------------------------------------------
#  Resolve-StageList —— -Stage 的规范化与校验
# -----------------------------------------------------------------------------
function Resolve-StageList {
    <#
      把 -Stage 的输入规范化成规范的阶段名数组。

      为什么不能靠 [ValidateSet]：-File 的参数绑定不支持数组，逗号写法会作为
      单个字符串送进来，见 param 块内注释与 v11.3 变更记录。

      容忍的写法（大小写无关）：
        -Stage Desktop,Ops        -File 模式下的标准写法
        -Stage "Desktop; Ops"     分号 / 空格同样拆开
        -Stage @('Desktop','Ops')  脚本内调用
        -Stage desktop            归一成 'Desktop'
      非法项一次性列全后 throw，而不是"改一个报一个"。
    #>
    param([string[]]$Names)

    # 拆：逗号 / 分号 / 空白 全是分隔符，空段丢弃。
    # 顺带剥掉两端包裹的引号：从 PowerShell 控制台调用
    #   powershell -File Svr2Desktop.ps1 -Stage 'Desktop','Ops'
    # 时，PowerShell 会把两个字符串**连引号一起**拼成单个参数值
    # 「'Desktop','Ops'」传进来（实测，见 v11.4 变更记录）。不剥的话拆出来的是
    # 'Desktop' 与 'Ops'（带字面单引号），正规化必然判非法 —— 操作员会看到
    # 一个"语法明明没错却被拒绝"的报错，而真正的原因（-File 的绑定模型）不可见。
    $tokens = New-Object System.Collections.ArrayList
    foreach ($item in @($Names)) {
        foreach ($tok in ([string]$item -split '[,;\s]+')) {
            $t = $tok.Trim()
            $t = $t.Trim([char[]]@("'", '"'))
            if ($t) { [void]$tokens.Add($t) }
        }
    }
    if ($tokens.Count -eq 0) { return [string[]]@('Interactive') }

    # 归一 + 挑错：字符串 -eq 默认大小写无关，故 'desktop' 能命中 'Desktop'。
    $good = New-Object System.Collections.ArrayList
    $bad  = New-Object System.Collections.ArrayList
    foreach ($t in $tokens) {
        $hit = @($script:ValidStages | Where-Object { $_ -eq $t })
        if ($hit.Count -gt 0) {
            if (-not ($good -contains $hit[0])) { [void]$good.Add($hit[0]) }
        } elseif (-not ($bad -contains $t)) {
            [void]$bad.Add($t)
        }
    }

    if ($bad.Count -gt 0) {
        throw ("Invalid -Stage value(s): {0}. Valid: {1}. Comma-separated lists are accepted: -Stage Desktop,Ops" -f ($bad -join ', '), ($script:ValidStages -join ', '))
    }
    return [string[]]$good
}

# -----------------------------------------------------------------------------
#  Desktop —— 交互流畅度（登录、关机、桌面、资源管理器、任务栏）
# -----------------------------------------------------------------------------
function Register-DesktopSteps {

    Add-Step -StageName 'Desktop' -Id 'D1' -Title 'Disable Server Manager auto-start at logon' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
        Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Oobe' -Name 'DoNotOpenInitialConfigurationTasksAtLogon' -Value 1
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Expected 1
        $b = Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Oobe' -Name 'DoNotOpenInitialConfigurationTasksAtLogon' -Expected 1
        $c = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Expected 1
        return ($a -and $b -and $c)
    }

    Add-Step -StageName 'Desktop' -Id 'D2' -Title 'Disable Shutdown Event Tracker (no reason prompt)' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name 'ShutdownReasonOn' -Value 0
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name 'ShutdownReasonUI' -Value 0
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name 'ShutdownReasonOn' -Expected 0
        $b = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name 'ShutdownReasonUI' -Expected 0
        return ($a -and $b)
    }

    Add-Step -StageName 'Desktop' -Id 'D3' -Title 'Turn off IE Enhanced Security Configuration' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}' -Name 'IsInstalled' -Value 0
        Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}' -Name 'IsInstalled' -Value 0
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}' -Name 'IsInstalled' -Expected 0
        $b = Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}' -Name 'IsInstalled' -Expected 0
        return ($a -and $b)
    }

    Add-Step -StageName 'Desktop' -Id 'D4' -Title 'Disable lock screen' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Value 1
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Expected 1)
    }

    Add-Step -StageName 'Desktop' -Id 'D5' -Title 'Remove post-logon desktop switch delay' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'DelayedDesktopSwitchTimeout' -Value 0
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'DelayedDesktopSwitchTimeout' -Expected 0)
    }

    Add-Step -StageName 'Desktop' -Id 'D6' -Title 'Turn off suggestions, tips and silent app promotion' -Action {
        $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        Set-RegDword -Path $cc -Name 'DisableWindowsConsumerFeatures' -Value 1
        Set-RegDword -Path $cc -Name 'DisableSoftLanding' -Value 1

        $cdm = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        $names = @(
            'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
            'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
            'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled',
            'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled',
            'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'OemPreinstalledAppsEnabled'
        )
        foreach ($n in $names) { Set-RegDword -Path $cdm -Name $n -Value 0 }
    } -Test {
        $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        $a = Test-RegValue -Path $cc -Name 'DisableWindowsConsumerFeatures' -Expected 1
        $b = Test-RegValue -Path $cc -Name 'DisableSoftLanding' -Expected 1
        # 与 Action 同源：Action 用 foreach 写 11 个键，Test 就逐个回读。
        # 只抽查一个代表的话，「其余某个没写进去」是不可见的。
        $cdm = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        $c = $true
        foreach ($n in @(
            'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
            'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
            'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled',
            'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled',
            'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'OemPreinstalledAppsEnabled'
        )) {
            if (-not (Test-RegValue -Path $cdm -Name $n -Expected 0)) { $c = $false }
        }
        return ($a -and $b -and $c)
    }

    Add-Step -StageName 'Desktop' -Id 'D7' -Title 'Slim down taskbar (search / widgets / news / chat)' -Action {
        $adv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 1
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0
        Set-RegDword -Path $adv -Name 'TaskbarDa' -Value 0
        Set-RegDword -Path $adv -Name 'TaskbarMn' -Value 0
        if ($script:HInfo.IsWin11UI) {
            Set-RegDword -Path $adv -Name 'TaskbarAl' -Value 0   # 任务栏左对齐
        }
    } -Test {
        $a = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Expected 1
        $b = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Expected 0
        $adv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        $c = Test-RegValue -Path $adv -Name 'TaskbarDa' -Expected 0
        $d = Test-RegValue -Path $adv -Name 'TaskbarMn' -Expected 0
        # TaskbarAl 是 Win11 分支才写的键，断言必须同源条件化
        if ($script:HInfo.IsWin11UI) {
            $e = Test-RegValue -Path $adv -Name 'TaskbarAl' -Expected 0
            return ($a -and $b -and $c -and $d -and $e)
        }
        return ($a -and $b -and $c -and $d)
    }

    # ▼ FullPath 的配置单元（来自宝马线的 v11.16 根因修复，2026-09-29 合并）：
    #   标题栏完整路径由 Explorer 从 HKCU\...\Explorer\CabinetState\FullPath 读取；
    #   HKLM 同名键**不被 Explorer 读取**，写了就是死键。真机实证（Server 2025
    #   build 26100）：v11.15 执行档写入 HKLM=1、-Verify 报 SATISFIED，标题栏却始终
    #   无变化，直到机主 2026-09-28 追问"打开标题栏完整路径"才暴露 —— 同一时刻 HKCU
    #   的 FullPath 由系统自己维护着 0（资源管理器把文件夹选项状态物化在 HKCU）。
    #   这是 v8.1 [P0-3]「Defender 无效键」的同族错误：写入与回读完全自洽，唯独读这个
    #   值的不是 Explorer —— **判据链对，判据对象错**。
    #   ★ 特斯拉侧的一处审计遗漏：2026-09-22 的真机执行档里，这一项 before=<absent>、
    #     after=1、报 OK；当时只看"值有没有移动"，没有追问"谁读这个值"。
    #   HKLM 遗留值无害：不再写、也不必清理（Test 已改指 HKCU，不会去追它）。
    Add-Step -StageName 'Desktop' -Id 'D8' -Title 'Explorer defaults (extensions / hidden files / open to This PC)' -Action {
        $adv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Set-RegDword -Path $adv -Name 'HideFileExt'      -Value 0
        Set-RegDword -Path $adv -Name 'Hidden'           -Value 1
        Set-RegDword -Path $adv -Name 'ShowSuperHidden'  -Value 0
        Set-RegDword -Path $adv -Name 'LaunchTo'         -Value 1
        Set-RegDword -Path $adv -Name 'ShowRecent'       -Value 0
        Set-RegDword -Path $adv -Name 'ShowFrequent'     -Value 0
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CabinetState' -Name 'FullPath' -Value 1
    } -Test {
        $adv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        $a = Test-RegValue -Path $adv -Name 'HideFileExt'     -Expected 0
        $b = Test-RegValue -Path $adv -Name 'LaunchTo'        -Expected 1
        $c = Test-RegValue -Path $adv -Name 'Hidden'          -Expected 1
        $d = Test-RegValue -Path $adv -Name 'ShowSuperHidden' -Expected 0
        $e = Test-RegValue -Path $adv -Name 'ShowRecent'      -Expected 0
        $f = Test-RegValue -Path $adv -Name 'ShowFrequent'    -Expected 0
        $g = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CabinetState' -Name 'FullPath' -Expected 1
        return ($a -and $b -and $c -and $d -and $e -and $f -and $g)
    }

    Add-Step -StageName 'Desktop' -Id 'D9' -Title 'Turn off Start menu recommendations and recent history' -Action {
        $adv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'HideRecommendedSection' -Value 1
        Set-RegDword -Path $adv -Name 'Start_TrackProgs' -Value 0
        Set-RegDword -Path $adv -Name 'Start_TrackDocs'  -Value 0
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'HideRecommendedSection' -Expected 1
        $b = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Expected 0
        $c = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackDocs' -Expected 0
        return ($a -and $b -and $c)
    }


    # 原 D10「恢复 Windows 10 风格经典右键菜单」已按机主 2026-09-18 决策删除：
    # Server 2025 的 Win11 风格右键菜单是机主的偏好选择，明确保留。
    # 原实现（在 CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32
    # 写空默认值）见 git 历史或 _history 目录中的 v10.0 副本。

    Add-Step -StageName 'Desktop' -Id 'D11' -Title 'Show This PC icon on desktop' -Action {
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' `
            -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Value 0
    } -Test {
        return (Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' `
            -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Expected 0)
    }

    Add-Step -StageName 'Desktop' -Id 'D12' -Title 'Speed up menu and mouse-hover response' -Action {
        Set-RegString -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay'  -Value '100'
        Set-RegString -Path 'HKCU:\Control Panel\Mouse'   -Name 'MouseHoverTime' -Value '100'
        Set-RegString -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '1'
    } -Test {
        # ★ v12.0（真机数据 C-01）：100 是**统一基准值**，不是"越小越好"。
        # Windows 默认 MenuShowDelay / MouseHoverTime 都是 400，从默认出发这两项是加速；
        # 但真机上那台机器已被前任优化到 50 —— 对它而言这一项是**减速**。
        # 50ms 与 100ms 都在"即时"阈值以内、人不可感，所以刻意**不**为此引入"只快不慢"的
        # 不等式判定：那需要新增判定语义，且 Action 一旦跳过写入就会与 Test 脱钩、
        # 制造一条永久 NOT-SET。语义写进 Note 即可，读者不必猜这一格为什么是"往慢里改"。
        $a = Test-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay'  -Expected '100' -Note '100 is the uniform baseline: the Windows default is 400, and a hand-tuned value below 100 is moved up to it'
        $b = Test-RegValue -Path 'HKCU:\Control Panel\Mouse'   -Name 'MouseHoverTime' -Expected '100' -Note '100 is the uniform baseline (the Windows default here is 400)'
        $c = Test-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Expected '1'
        return ($a -and $b -and $c)
    }

    # D13 —— 保证图形界面组件在位。
    # ⚠ v11.2 修正（由真机体检数据驱动）：现代 Server（2016+）的 GUI 特性名是
    #   Server-Gui-Shell + Server-Gui-Mgmt-Infra；Desktop-Experience 是更早的
    #   别名，在 Windows Server 2025（build 26200）的目录里已不存在 ——
    #   真机上 Get-WindowsFeature 全表 263 项，唯一含 "Desktop" 的是
    #   Remote-Desktop-Services。原写法只认 Desktop-Experience，在这类 build 上
    #   必然永远落空。
    Add-Step -StageName 'Desktop' -Id 'D13' -Title 'Ensure GUI shell feature is installed' -Action {
        # 逐个候选：目录里存在哪个就启用哪个（同一 build 上通常只有一个存在）。
        # 先做存在性判断再调用 —— 对目录里没有的名字调 Install-WindowsFeature 会抛错。
        if (Get-WindowsFeature -Name 'Server-Gui-Shell'     -ErrorAction SilentlyContinue) { Set-FeatureState -Name 'Server-Gui-Shell'     -State Enable }
        if (Get-WindowsFeature -Name 'Server-Gui-Mgmt-Infra' -ErrorAction SilentlyContinue) { Set-FeatureState -Name 'Server-Gui-Mgmt-Infra' -State Enable }
        if (Get-WindowsFeature -Name 'Desktop-Experience'   -ErrorAction SilentlyContinue) { Set-FeatureState -Name 'Desktop-Experience'   -State Enable }
    } -Test {
        # 与 Probe 同源：主判据是 InstallationType 这一手来源，不依赖特性目录列了谁。
        if (Test-DesktopShell) { return $true }
        $a = Test-FeatureInstalled -Name 'Server-Gui-Shell'
        $b = Test-FeatureInstalled -Name 'Server-Gui-Mgmt-Infra'
        $c = Test-FeatureInstalled -Name 'Desktop-Experience'
        return ($a -or $b -or $c)
    } -Probe {
        return (Get-GuiProbe)
    }

    Add-Step -StageName 'Desktop' -Id 'D14' -Title 'Enable Themes and Windows Audio services' -Action {
        Set-SvcStartup -Name 'Themes'                -Type Automatic
        Set-SvcStartup -Name 'AudioEndpointBuilder'  -Type Automatic
        Set-SvcStartup -Name 'Audiosrv'              -Type Automatic
    } -Test {
        # 三个服务中任一本版本不存在（如 Server 2016/2019 无音频栈）→ 视为满足，
        # 与 Action 中 Set-SvcStartup 的 service-not-present 静默跳过保持同源；
        # 否则会出现「Action 跳过、Test 判假」的假红死循环。
        $t = Get-SvcStartMode -Name 'Themes'
        $a = Get-SvcStartMode -Name 'Audiosrv'
        $e = Get-SvcStartMode -Name 'AudioEndpointBuilder'
        if ($null -eq $t) { return $true }
        if ($null -eq $a) { return $true }
        if ($null -eq $e) { return $true }
        return (($t -eq 'Auto') -and ($a -eq 'Auto') -and ($e -eq 'Auto'))
    } -Probe {
        # Test 的判据是"任一本版本不存在即视为满足"（为了不出现"Action 跳过、
        # Test 判假"的假红死循环），但它在「部分服务存在且未配置」时会误判成 SKIP。
        # Probe 用精确语义替代它：
        #   全部不存在 → ABSENT（本机无主题/音频栈，通常是没装 Desktop Experience）
        #   都存在且都是 Auto → OK
        #   其余 → NOT-SET
        $names = @('Themes', 'Audiosrv', 'AudioEndpointBuilder')
        $present = New-Object System.Collections.ArrayList
        $auto = 0
        # 读值一并留痕（v11.9）。标记**分路给**：OK 档全标 Ok；NOT-SET 档逐条按真值标；
        # ABSENT 档照印值但不打不达标标记 —— 本机没有主题/音频栈**不是缺口**，
        # 给不是缺口的东西打不达标标记，只会训练操作员无视标记。
        $svcEv = New-Object System.Collections.ArrayList
        foreach ($n in $names) {
            # ★ v12.0（审计 A-07）：存在性判据换成 Get-Service，不再拿
            # "StartMode 是否为空"当存在性。Get-SvcStartMode 在"服务不存在"与
            # "CIM 查询失败"两种情况下都返回 $null —— 用它判存在，会让"我们读不出来"
            # 伪装成"本机没有这一项"（→ ABSENT，语义是"不是缺口"）。
            # P9 当年正是用第二条独立来源解决同一类问题（Get-TaskState），服务这条线漏了。
            if (-not (Get-Service -Name $n -ErrorAction SilentlyContinue)) {
                # Test 也把"服务不存在"当满足（否则会出现"Action 跳过、Test 判假"的假红回路），
                # 所以这一行的 Ok 与 Test 同源：不存在 = 不算缺口。
                [void]$svcEv.Add([PSCustomObject]@{ Text = ("svc {0} = <not present on this build>" -f $n); Ok = $true })
                continue
            }
            [void]$present.Add($n)
            $m = Get-SvcStartMode -Name $n
            if ($null -eq $m) {
                # 服务在、启动类型却读不出 → 这是**我们的读值问题**，不是环境限制。
                # 记不达标，让探针落到 NOT-SET，而不是被当成 ABSENT 静音（假灰更危险）。
                [void]$svcEv.Add([PSCustomObject]@{ Text = ("svc {0} start mode = <read-back unavailable>" -f $n); Ok = $false })
                continue
            }
            if ($m -eq 'Auto') { $auto++ }
            [void]$svcEv.Add([PSCustomObject]@{ Text = ("svc {0} start mode = {1} (want Auto)" -f $n, $m); Ok = ($m -eq 'Auto') })
        }
        if ($present.Count -eq 0) {
            foreach ($e in $svcEv) { Add-Evidence $e.Text }
            return (New-ProbeResult -State 'ABSENT' -Why 'no Themes/Audio services on this build (Desktop Experience not installed)')
        }
        if ($auto -eq $present.Count) {
            foreach ($e in $svcEv) { Add-Evidence ($e.Text + (Get-EvidenceMark -Ok $true)) }
            return (New-ProbeResult -State 'OK')
        }
        foreach ($e in $svcEv) { Add-Evidence ($e.Text + (Get-EvidenceMark -Ok $e.Ok)) }
        return (New-ProbeResult -State 'NOT-SET' -Why ("{0} of {1} set to Automatic (present: {2})" -f $auto, $present.Count, ($present -join ', ')))
    }
    # ---- A11：抑制 OneDrive 与 Windows 备份推广 ----
    # 每个键都有出处，不写来路不明的值：
    #   DisableFileSyncNGSC           —— 组策略「阻止使用 OneDrive 存储文件」
    #   ShowSyncProviderNotifications —— 资源管理器「同步提供程序通知」开关
    #   DisableMonitoring             —— 微软官方文档（路径是 HKLM，不是 HKCU）
    #     learn.microsoft.com/windows/win32/backup/registry-keys-for-backup-and-restore
    #     官方说明：置 1 后，未配置备份的机器不再出现操作中心提示与外接硬盘提示
    # Server 上通常并无 OneDrive 组件，策略键写入后被系统忽略、无副作用，因此不做
    # 存在性判断 —— 保证 Action 与 Test 两侧的前置条件完全一致。
    Add-Step -StageName 'Desktop' -Id 'D15' -Title 'Suppress OneDrive sync and Windows Backup promotion' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -Name 'DisableFileSyncNGSC' -Value 1
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Value 0
        Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup' -Name 'DisableMonitoring' -Value 1
        Remove-RegValueSafe -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive'
        Remove-RegValueSafe -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSetup'
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -Name 'DisableFileSyncNGSC' -Expected 1
        $b = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Expected 0
        $c = Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup' -Name 'DisableMonitoring' -Expected 1
        # OneDrive 自启项：不存在即视为已达标，与 Remove-RegValueSafe 的静默跳过同源。
        # ★ 必须走 Test-RegValueAbsent 而不是手写 Test-Path + GetValueNames ——
        # 手写版参与判定却不产证据行，真机上这一条让 D15 呈现为"三条证据全 OK、
        # 结论却是 NOT-SET"，操作员完全无从下手（见 Get-EvidenceConflict）。
        $d = Test-RegValueAbsent -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive'
        $e = Test-RegValueAbsent -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSetup'
        return ($a -and $b -and $c -and $d -and $e)
    }

    # ---- D16：任务栏右键「结束任务」（宝马线 v11.16 新增，2026-09-29 合并）----
    # 机主 2026-09-28 点单。Win11 风格任务栏的开发者设置（TaskbarDeveloperSettings）
    # 仅在 build >= 22000 的桌面 shell 上存在（Server 2025 即此类）。经典 Server 任务栏
    # （2016/2019/2022）没有这个开关，键写了也不被读 —— 与 D8 的 FullPath 教训同族：
    # **对不存在的目标写值 = 死键**。因此 Action 条件化（同 D7 的 TaskbarAl 先例），
    # Probe 给三态：非 Win11UI → ABSENT（本项不适用），不假绿、也不制造永久红灯。
    # 注册表写入本身即达成；可见效果需重启 explorer.exe（故 Test 只断言值，不追效果）。
    Add-Step -StageName 'Desktop' -Id 'D16' -Title 'Enable Taskbar End Task (right-click kill for hung apps)' -Action {
        if ($script:HInfo.IsWin11UI) {
            Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' -Value 1
        }
    } -Test {
        # 与 Action 同源条件化：经典任务栏分支什么都没写，断言不得恒假
        # （否则会出现"Action 跳过、Test 判假"的假红死循环 —— D14 踩过同一个坑）。
        if (-not $script:HInfo.IsWin11UI) { return $true }
        return (Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' -Expected 1)
    } -Probe {
        if (-not $script:HInfo.IsWin11UI) {
            Add-Evidence ("host build {0}: classic Server taskbar, no TaskbarEndTask setting on this OS" -f $script:HInfo.Build)
            return (New-ProbeResult -State 'ABSENT' -Why 'this build carries the classic Server taskbar (no End Task entry to enable)')
        }
        $ok = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' -Expected 1
        if ($ok) { return (New-ProbeResult -State 'OK') }
        return (New-ProbeResult -State 'NOT-SET' -Why 'TaskbarEndTask is not set to 1 (takes effect after explorer.exe restart)')
    }
}

# -----------------------------------------------------------------------------
#  Performance —— 电源、处理器、视觉、文件系统、遥测
# -----------------------------------------------------------------------------
function Register-PerformanceSteps {

    # 遥测相关的计划任务清单（Server 上普遍无实际用途，关闭可减少后台唤醒）
    $script:TelemetryTasks = @(
        [PSCustomObject]@{ P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Application Experience\'; N = 'ProgramDataUpdater' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Application Experience\'; N = 'StartupAppTask' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Application Experience\'; N = 'PcaPatchDbTask' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'KernelCeipTask' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClient' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClientOnScenarioDownload' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\DiskDiagnostic\'; N = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        [PSCustomObject]@{ P = '\Microsoft\Windows\Windows Error Reporting\'; N = 'QueueReporting' }
    )


    # 原 P1「电源方案切到高性能」与 P3「处理器状态锁定 100%」已按机主 2026-09-18
    # 决策删除：目标机以电池供电时，这两项直接抬高 CPU 频率与状态档位，是续航的
    # 最大杀手。保留 P2（关核心停泊）与 P4（关设备省电）—— 它们改善的是核心唤醒
    # 与设备链路延迟，耗电增量小。P2/P4 改的是「当前方案」内的具体值，还原由
    # Backup-PowerValue 逐项登记并回放。

    Add-Step -StageName 'Performance' -Id 'P2' -Title 'Disable CPU core parking (low latency)' -Action {
        Set-PowerCfgValue -SubGroup 'SUB_PROCESSOR' -Setting 'CPMINCORES' -Value 100
        Set-PowerCfgValue -SubGroup 'SUB_PROCESSOR' -Setting 'CPMINCORES' -Value 100 -Dc
        Invoke-Native -File 'powercfg' -Arguments @('/setactive', 'SCHEME_CURRENT') | Out-Null
    } -Test {
        $a = Test-PowerCfgValue -SubGroup 'SUB_PROCESSOR' -Setting 'CPMINCORES' -Expected 100
        $b = Test-PowerCfgValue -SubGroup 'SUB_PROCESSOR' -Setting 'CPMINCORES' -Expected 100 -Dc
        return ($a -and $b)
    } -Probe {
        # 核心停泊是"把空闲核停泊以省电"的机制：单核主机没有第二个核可停泊，设
        # CPMINCORES=100 等于声明"保持那唯一的核常开"——本来就是事实。故记 N/A。
        $c = [int]$env:NUMBER_OF_PROCESSORS
        if ($c -lt 2) {
            return (New-ProbeResult -State 'NA' -Why ("single-core host ({0} logical processor): core parking not applicable" -f $c))
        }

        # 先判"这一项在当前方案里到底存不存在"。不存在就不动作（写了也写不进去），
        # 更不能报 FAIL —— 那是把虚拟化平台的限制记在脚本账上。真机实证：v11.3 在
        # 这台虚机上 P2 每次都 FAIL，而原因写成 "post-check returned false"，
        # 看不出任何可用信息。
        $r = Get-PowerCfgValue -SubGroup 'SUB_PROCESSOR' -Setting 'CPMINCORES'
        if (-not $r.Found) {
            # ★ 这里必须再分一层：系统明确回答"没有这一项" ≠ 我们读不出来。
            # 合并成同一个 N/A 的话，"我们的解析器坏了"会伪装成"环境限制"，
            # 于是永远没人去修 —— 与 P2 当年把三态压成两态是同一个错误，只是升了一层。
            if ($r.Reason -eq 'absent') {
                return (New-ProbeResult -State 'NA' -Why ("active power scheme exposes no CPMINCORES - not present on this build [{0}]; {1} [scheme: {2}]" -f (Get-PowerCfgBlockNote -Facts $r.Blocks), $r.Why, (Get-ActivePowerScheme)))
            }
            # v11.16：措辞不能预设原因 —— absent 档已在上面分出去，剩下的两档是
            # "我们没解析出来"（unreadable）与"读到多个块、值无法归属"（ambiguous）。
            # 都写成 "read-back unavailable on this build" 会让"我们的读法有问题"
            # 伪装成"环境限制"，而假灰比假红更危险 —— 它把缺陷藏进一个看起来
            # 完全合理的解释里，于是永远没人去修。
            $reasonTxt = 'read-back unavailable'
            if ($r.Reason -eq 'ambiguous') { $reasonTxt = 'read-back ambiguous (more than one setting block in the output)' }
            return (New-ProbeResult -State 'NOT-SET' -Why ("CPMINCORES {0} on this build [{1}] - {2} [scheme: {3}]" -f $reasonTxt, (Get-PowerCfgBlockNote -Facts $r.Blocks), $r.Why, (Get-ActivePowerScheme)))
        }

        if (($r.Ac -eq 100) -and ($r.Dc -eq 100)) { return (New-ProbeResult -State 'OK') }
        $acTxt = 'n/a'
        $dcTxt = 'n/a'
        if ($null -ne $r.Ac) { $acTxt = [string]$r.Ac }
        if ($null -ne $r.Dc) { $dcTxt = [string]$r.Dc }
        return (New-ProbeResult -State 'NOT-SET' -Why ("CPMINCORES AC={0} DC={1}, want 100/100 [scheme: {2}]" -f $acTxt, $dcTxt, (Get-ActivePowerScheme)))
    }


    Add-Step -StageName 'Performance' -Id 'P4' -Title 'Disable disk / PCIe / USB idle power saving' -Action {
        Set-PowerCfgValue -SubGroup 'SUB_DISK'        -Setting 'DISKIDLE' -Value 0
        Set-PowerCfgValue -SubGroup 'SUB_DISK'        -Setting 'DISKIDLE' -Value 0 -Dc
        Set-PowerCfgValue -SubGroup 'SUB_PCIEXPRESS'  -Setting 'ASPM'     -Value 0
        Set-PowerCfgValue -SubGroup '2a737441-1930-4402-8d77-b2bebba308a3' -Setting '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' -Value 0
        Invoke-Native -File 'powercfg' -Arguments @('/setactive', 'SCHEME_CURRENT') | Out-Null
    } -Test {
        $a = Test-PowerCfgValue -SubGroup 'SUB_DISK'       -Setting 'DISKIDLE' -Expected 0
        $b = Test-PowerCfgValue -SubGroup 'SUB_PCIEXPRESS' -Setting 'ASPM'     -Expected 0
        # USB 选择性挂起用的是裸 GUID（SUB_USB / 设置项），原 Test 完全没覆盖这一项
        $c = Test-PowerCfgValue -SubGroup '2a737441-1930-4402-8d77-b2bebba308a3' -Setting '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' -Expected 0
        $d = Test-PowerCfgValue -SubGroup 'SUB_DISK'       -Setting 'DISKIDLE' -Expected 0 -Dc
        return ($a -and $b -and $c -and $d)
    }

    # P5 —— 快速启动。本版把承诺收敛到可验证的那一半（见 v11.4 变更记录）：
    #   承诺 = 关闭快速启动；休眠状态不由本脚本改变。
    #   旧版无条件下 `powercfg /hibernate on`。虚机上该调用返回"不支持该请求"
    #   （虚拟化平台不提供 S4），异常把后面那半项一起带走 —— 于是真机上"关快速
    #   启动"这件与手感直接相关的事一次都没做成，还每次刷一条红。而"保留休眠"
    #   的正确含义本来就是不去动它（v8.1 才是关掉休眠的那一方）。
    #   改法：只写 HiberbootEnabled=0；检测到休眠处于关闭时给一条可复制的提示，
    #   由操作员按需自行 powercfg /hibernate on（它会在系统盘生成 RAM 大小的
    #   hiberfil.sys，是否值得由机主决定，不该由脚本替他决定）。
    Add-Step -StageName 'Performance' -Id 'P5' -Title 'Disable Fast Startup (hibernation left as-is)' -Action {
        $hib = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled'
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0
        $hibOff = $false
        if ($null -eq $hib) { $hibOff = $true }
        if ([string]$hib -eq '0') { $hibOff = $true }
        if ($hibOff) {
            Write-Note 'hibernation is off on this host - not changed by this script (to enable it yourself: powercfg /hibernate on)' 'DarkGray'
        }
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Expected 0)
    } -Probe {
        $r = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled'
        if ($null -eq $r) {
            # 值不存在 = 本机没有快速启动这个概念（Server 上常见）→ 无此项可关。
            # 注意这不是"读不到"：HiberbootEnabled 缺席就是快速启动从未启用过，
            # 与普通注册表回读失败（Test-RegValue 判假）是两回事。
            Add-Evidence 'reg ...\Session Manager\Power\HiberbootEnabled = <absent> -> this build exposes no Fast Startup switch'
            return (New-ProbeResult -State 'NA' -Why 'HiberbootEnabled absent: this build exposes no Fast Startup switch, nothing to disable')
        }
        $ok = ([string]$r -eq '0')
        Add-Evidence ("reg ...\Session Manager\Power\HiberbootEnabled = {0} (want 0){1}" -f $r, (Get-EvidenceMark -Ok $ok))
        if ($ok) { return (New-ProbeResult -State 'OK') }
        return (New-ProbeResult -State 'NOT-SET' -Why ("HiberbootEnabled = {0}, want 0" -f $r))
    }

    Add-Step -StageName 'Performance' -Id 'P6' -Title 'Trim visual effects but keep font smoothing' -Action {
        $adv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 3
        Set-RegString -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0'
        Set-RegDword -Path $adv -Name 'TaskbarAnimations'    -Value 0
        Set-RegDword -Path $adv -Name 'ListviewShadow'       -Value 0
        Set-RegDword -Path $adv -Name 'ListviewAlphaSelect'  -Value 0
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' -Name 'EnableAeroPeek' -Value 0

        # 字体平滑保持开启 —— 原 bat 一律套"最佳性能"把 ClearType 一起关掉，字会发毛
        if ($script:Config.KeepFontSmoothing) {
            Set-RegString -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothing' -Value '2'
            Set-RegDword  -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothingType' -Value 2
        }
    } -Test {
        $adv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        $a = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Expected 3
        $b = Test-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Expected '0'
        $c = Test-RegValue -Path $adv -Name 'TaskbarAnimations'   -Expected 0
        $d = Test-RegValue -Path $adv -Name 'ListviewShadow'      -Expected 0
        $e = Test-RegValue -Path $adv -Name 'ListviewAlphaSelect' -Expected 0
        $f = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' -Name 'EnableAeroPeek' -Expected 0

        # 字体平滑是这一步对用户的明确承诺（标题即 'keep font smoothing'），必须回读。
        # 但它受配置开关 KeepFontSmoothing 支配：开则写、关则不写。Test 必须与
        # Action 同源，否则关掉该开关后本步会永远判 NOT-SET。
        if ($script:Config.KeepFontSmoothing) {
            $g = Test-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothing'     -Expected '2'
            $h = Test-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothingType' -Expected 2
            return ($a -and $b -and $c -and $d -and $e -and $f -and $g -and $h)
        }
        return ($a -and $b -and $c -and $d -and $e -and $f)
    }

    Add-Step -StageName 'Performance' -Id 'P7' -Title 'NTFS tuning (last access off, 8dot3 off)' -Action {
        $fs = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
        Set-RegDword -Path $fs -Name 'NtfsDisableLastAccessUpdate'   -Value 1
        Set-RegDword -Path $fs -Name 'NtfsDisable8dot3NameCreation'  -Value 1
        # ★ v13.1（机主 2026-09-29 决定）：**不再写 NtfsMftZoneReservation**。
        #   该值只在**格式化 / 首次以该参数挂载**时被读取并固化进卷结构 —— 对已存在的卷
        #   改注册表不会重排 MFT，真机上"值就位、收益为 0"（P7 原来把它写成 2，即把预留
        #   区从 12.5% 抬到 25%，报告判 OK 而磁盘行为一字未变）。
        #   而"保留写入"的期望收益（对未来新建卷）**同样不可证伪** —— 收益取决于负载形态，
        #   没有普适结论。两个方向都无法用效果论证时，就选动作更少的那个：**不写**。
        #   值停在系统默认（0 = 系统自行选择），这是保守且合理的选择；真需要给新卷调预留，
        #   那种场景本来就该显式设置。
    } -Test {
        $fs = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
        # NtfsDisableLastAccessUpdate 是**位域**：bit31 = 系统管理该设置，bit0 = 禁用
        # 最后访问更新。脚本写 1（用户管理 + 已禁用），NTFS 随后把它规范成
        # 0x80000003 = -2147483645（系统管理 + 已禁用）—— 语义一致，甚至更"正式"。
        # 真机上 P7 因此被判 NOT-SET，而 MISMATCH 指向一个看起来完全正确的值。
        # 故这里不看字面量，只看 bit0：置位即"已禁用"，与 Expected 无关。
        $a = Test-RegValue -Path $fs -Name 'NtfsDisableLastAccessUpdate' -Expected 1 -BitSet 1 -Note 'bit0 set = last access updates disabled; 0x80000001 and 0x80000003 are both system-managed encodings of the same intent (the second is the Win10/11 default, the first is what the audited host reports)'
        $b = Test-RegValue -Path $fs -Name 'NtfsDisable8dot3NameCreation' -Expected 1
        # v13.1：第三项改为**只报告、不判定、不动作**（原先是 -Expected 2 的断言）。
        #   为什么不再用 Test-RegValue：本脚本既然不再写这个值，就不该再拿一个期望值去
        #   卡它 —— 那会变成一条等不到 2 的**永久假红**（"长期红灯会训练操作员无视颜色"
        #   是本文件自己写下的教训）。但也不能不留痕：把现状印出来，并说明"本脚本不动它、
        #   消费者在何时读它"。消费方是谁这件事，正是 D8 那条死键教训的落点。
        $mftNow = Get-RegValue -Path $fs -Name 'NtfsMftZoneReservation'
        $mftTxt = '<absent>'
        if ($null -ne $mftNow) { $mftTxt = [string]$mftNow }
        $c = Add-Check -Ok $true -Text ("reg {0}\NtfsMftZoneReservation = {1}  [not written by this script: the reservation matters only when a volume is formatted - an existing volume keeps its current MFT layout, so writing it here would be a no-op with no measurable gain]" -f (Shorten-RegPath -Path $fs), $mftTxt)
        return ($a -and $b -and $c)
    }

    Add-Step -StageName 'Performance' -Id 'P8' -Title 'Stop clearing the page file at shutdown' -Action {
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'ClearPageFileAtShutdown' -Value 0
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'ClearPageFileAtShutdown' -Expected 0)
    }

    Add-Step -StageName 'Performance' -Id 'P9' -Title 'Disable telemetry policy and CEIP scheduled tasks' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0
        # ★ 自愈项，不是一次性项（v11.8）。
        # 真机实证：v11.6 执行会话报 [ OK ] → 重启后的 -Verify 又是 NOT-SET
        # （PcaPatchDbTask = Ready）；v11.7 会话再次印证（执行前 Ready → 执行后 Disabled）。
        # 说明它**跨重启会被 Windows 维护栈重新启用**。
        # 而"重施"这件事**早已是现状**：本步骤是幂等的，每次运行都会把这 11 个任务
        # 重新禁用一遍，所以它每次都能自愈。缺的从来不是重施，而是**报告里说清
        # 它是一个会被系统还原的自愈项** —— 否则操作员把"重启后又变 NOT-SET"
        # 误读成脚本失效，再花一轮去查一个不存在的问题。
        # 因此这里只做两件事：① 只在"确实还没禁用"时才动它（省掉无谓写）；
        # ② 把本次实际重施了哪些、以及它的自愈性质写进证据。
        $reEnabled = @()
        $reUnread  = @()
        foreach ($t in $script:TelemetryTasks) {
            $st = Get-TaskState -TaskPath $t.P -TaskName $t.N
            if (-not $st.Found) {
                # 本版本没有这个任务（后备文件也不在）→ 与 Disable-TaskSafe 同一取舍：静默跳过
                if (-not $st.Backing) { continue }
                # 存在但调度器读不到 → **仍然尝试**禁用：读不到不等于写不进
            } elseif ($st.State -eq 'Disabled') {
                continue
            }
            [void](Disable-TaskSafe -TaskPath $t.P -TaskName $t.N)
            # ★ v12.0（审计 A-11）：两档分开记。原文案说这些任务是
            # "still enabled when this run read them"，可"读不到"那一档根本没读到
            # 启用状态 —— 证据说了它支持不了的话，正是守门人专门要杀的形态。
            if ($st.Found) { $reEnabled += ("{0} ({1})" -f $t.N, $st.State) }
            else           { $reUnread  += ("{0} (state unreadable - attempted anyway)" -f $t.N) }
        }
        if ($reEnabled.Count -gt 0) {
            Add-Evidence ("re-disabled {0} task(s) the scheduler still reported as enabled: {1}" -f $reEnabled.Count, ($reEnabled -join ', '))
        }
        if ($reUnread.Count -gt 0) {
            Add-Evidence ("re-disabled {0} task(s) whose state could not be read, but whose backing file exists: {1}" -f $reUnread.Count, ($reUnread -join ', '))
        }
        if (($reEnabled.Count + $reUnread.Count) -gt 0) {
            Add-Evidence ("  (self-healing item, not one-shot: Windows servicing can re-enable these across a reboot; every run of this script re-applies them - re-run -Verify after a reboot to watch it flip)")
        }
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Expected 0
        # ★ 不提前 return：原先写成"第一个没禁用的任务就 return $false"，后果有两个 ——
        #   ① 其余任务是否达标无从得知（v11.2 那个"改一个报一个"的接口同病）；
        #   ② 由于 Test-TaskDisabled 当时还没有证据钩子，整条失败路径**不留任何痕迹**，
        #      于是报告呈现为"AllowTelemetry 那一行 OK，结论却是 NOT-SET"。
        # 现在全读一遍、全部留痕，末尾再合结论。判据由 Get-TelemetryTaskReport 给出，
        # 与下面的 -Probe 共用同一份 —— 两套读法各判一次，就会出现
        # "Probe 说达标、Test 说不达标"的自相矛盾，那正是上一轮 D15/P9/SEC12 的病根。
        $rep = Get-TelemetryTaskReport
        return ($a -and $rep.Ok)
    } -Probe {
        # v11.7 新增。此前 P9 是全脚本唯一一个"读不到即判达标、且没有 Probe 兜底"
        # 的位置，因而也是唯一一条能产生假绿的通道（真机实证：执行会话报 [ OK ]，
        # 重启后的 -Verify 却又是 NOT-SET）。给它一个三态探针，让"适用性判断"
        # 与"回读"落在同一套事实上。
        $dcPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        $policyOk = Test-RegValue -Path $dcPath -Name 'AllowTelemetry' -Expected 0
        if (-not $policyOk) {
            # 只在失败分支多读一次，仅为把**实测值**写进 Why（判据仍来自上面那次调用）
            $tv = Get-RegValue -Path $dcPath -Name 'AllowTelemetry'
            if ($null -eq $tv) {
                return (New-ProbeResult -State 'NOT-SET' -Why ('AllowTelemetry policy is not present ({0})' -f (Shorten-RegPath -Path $dcPath)))
            }
            return (New-ProbeResult -State 'NOT-SET' -Why ('AllowTelemetry = {0}, want 0' -f $tv))
        }
        $rep = Get-TelemetryTaskReport
        # 顺序有意：先说"确实没达标"，再说"我没读出来" —— 前者是事实，后者是我们自己的问题。
        if ($rep.Enabled.Count -gt 0) {
            # v11.8：把"这是自愈项"写进 Why —— 真机实证（v11.6 执行 [OK] → 重启后 Not-Set；
            # v11.7 执行前 Ready → 执行后 Disabled）说明它跨重启会被 Windows 维护栈重新启用。
            # 不说这一句，操作员会把"重启后又变 NOT-SET"误读成脚本失效。
            return (New-ProbeResult -State 'NOT-SET' -Why ("{0} of {1} telemetry task(s) still enabled: {2} (self-healing item: Windows servicing can re-enable these across a reboot; every run of this script re-disables them)" -f $rep.Enabled.Count, $rep.Total, ($rep.Enabled -join ', ')))
        }
        if ($rep.Unread.Count -gt 0) {
            return (New-ProbeResult -State 'NOT-SET' -Why ("read-back unavailable for {0} of {1} telemetry task(s): {2}" -f $rep.Unread.Count, $rep.Total, ($rep.Unread -join ', ')))
        }
        return (New-ProbeResult -State 'OK')
    }

    Add-Step -StageName 'Performance' -Id 'P10' -Title 'Disable SysMain (Superfetch) if present' -Action {
        Disable-Svc -Name 'SysMain'
    } -Test {
        return (Test-SvcDisabled -Name 'SysMain')
    } -Probe {
        return (Get-SvcProbe -Name 'SysMain')
    }
}

# -----------------------------------------------------------------------------
#  Network —— TCP 全局参数、Nagle、IPv6 隧道
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
#  TCP 全局参数 —— 语言无关读法
# -----------------------------------------------------------------------------
function Get-TcpGlobalState {
    <#
      v11.3 的 N1 用英文标签正则去匹配 netsh 的输出：
          $out -match '(?i)Receive-Side Scaling State\s*:\s*enabled'
      中文版 Windows 会把标签一并本地化（"接收方缩放状态 / 自动调整级别"），
      英文正则恒不匹配 → Test 恒假 → 步骤**每次运行都判 FAIL**，而设置每次都被
      白写一遍。真机日志里 N1 的失败原因正是 "post-check returned false"。
      这与 Test-PowerCfgValue 注释里记的坑是同一类缺陷 —— 当时只修了那一处，
      同类缺陷没有一次扫全，代价就在 N1 上重演了一遍。

      主路：Get-NetOffloadGlobalSetting + Get-NetTCPSetting，属性名不受语言影响。
      属性一律按名字取、不做具名展开：这些属性在各 Windows 版本间有过增删，
      取不到就当"读不到"，不能让它悄悄变成"值不对"。
      退路：netsh，标签中英双写匹配。
      返回 @{ Source; Rss; AutoTune }，读不到的值为 $null。
    #>
    $st = [PSCustomObject]@{
        Source   = 'none'
        Rss      = $null
        AutoTune = $null
    }

    try {
        $off = Get-NetOffloadGlobalSetting -ErrorAction Stop
        $tcp = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop
        $p1 = $off.PSObject.Properties['ReceiveSideScaling']
        $p2 = $tcp.PSObject.Properties['AutoTuningLevelLocal']
        if ($p1 -and $p2) {
            $st.Source   = 'Get-NetOffloadGlobalSetting/Get-NetTCPSetting'
            $st.Rss      = ([string]$p1.Value).ToLower()
            $st.AutoTune = ([string]$p2.Value).ToLower()
            return $st
        }
    } catch { }

    try {
        $out = (netsh int tcp show global 2>&1) | Out-String
        $mRss = [regex]::Match($out, '(?i)(Receive-Side Scaling|接收方缩放|接收端缩放|RSS)[^\r\n:：]*[:：]\s*([^\r\n]+)')
        $mAut = [regex]::Match($out, '(?i)(Auto-?Tuning|自动调整|自动调优)[^\r\n:：]*[:：]\s*([^\r\n]+)')
        if ($mRss.Success -or $mAut.Success) {
            $st.Source = 'netsh int tcp show global'
            if ($mRss.Success) { $st.Rss      = $mRss.Groups[2].Value.Trim().ToLower() }
            if ($mAut.Success) { $st.AutoTune = $mAut.Groups[2].Value.Trim().ToLower() }
        }
    } catch { }

    return $st
}

function Get-RssCapability {
    # 有没有具备 RSS 能力的网卡。返回 yes / no / unknown。
    # 没有硬件基础时把全局开关置 Enabled 也不会生效 —— 那不是"优化没做成"，
    # 而是本机没有这项能力。用于把 N1 里 RSS 这半项在无能力主机（部分虚机网卡
    # 就是这样）上降为"不作为失败项"，而不是每次刷 FAIL。
    try {
        $a = @(Get-NetAdapterRss -ErrorAction Stop)
        if ($a.Count -gt 0) { return 'yes' }
        return 'no'
    } catch { }
    return 'unknown'
}

function Get-TcpGlobalProbe {
    # Test 与 Probe 共用这一份判定 —— 执行与验证同源，不存两套走偏的可能。
    #
    # 判定口径（关键取舍）：
    #   自动调整级别 = normal  → 必须成立，这是与交互延迟真正相关的那一项。
    #   RSS           → 只有在"有 RSS 能力的网卡"且"全局 RSS 关着"时才判失败。
    #                   无能力 / 无法判定时，**不判失败，但把实测事实印出来**。
    #   结论可以从宽，事实必须印全 —— 这样既没有假绿（值都摆着），也不制造
    #   永远摘不掉的红灯。
    $s = Get-TcpGlobalState

    if (($null -eq $s.Rss) -and ($null -eq $s.AutoTune)) {
        Add-Evidence ("tcp global read-back unavailable (source: {0})" -f $s.Source)
        return (New-ProbeResult -State 'NA' -Why ("TCP global read-back unavailable on this build (source: {0}): settings can be written but not verified here" -f $s.Source))
    }

    $autoOk = ($s.AutoTune -eq 'normal')
    Add-Evidence ("tcp autotuning = {0} (want normal){1}  [via {2}]" -f $s.AutoTune, (Get-EvidenceMark -Ok $autoOk), $s.Source)

    $rssCap = Get-RssCapability
    $rssOk  = $true
    $rssNote = 'not required: no RSS-capable NIC reported'
    if ($s.Rss -eq 'enabled') {
        $rssNote = 'ok'
    } elseif ($rssCap -eq 'yes') {
        $rssOk = $false
        $rssNote = 'RSS-capable NIC present but global RSS is off'
    } elseif ($rssCap -eq 'unknown') {
        $rssNote = 'not required: RSS capability could not be determined on this build'
    }
    Add-Evidence ("tcp rss = {0} (want enabled){1}  [{2}]" -f $s.Rss, (Get-EvidenceMark -Ok $rssOk), $rssNote)
    # ★ v12.0（审计 A-08）：N1 的标题承诺三项，回读只覆盖两项 —— heuristics
    # 在 Get-NetOffloadGlobalSetting / Get-NetTCPSetting 上都没有对应属性，而 netsh 的
    # 本地化文本刻意不解析（v11.4 的教训）。覆盖缺口必须留痕：不留痕的缺口永远没人修
    # —— SEC3 就这样混过了 v11.4 ~ v11.7 四轮。
    Add-Evidence 'tcp heuristics = <written, not read back>  [the read path used here exposes autotuning and RSS only; the netsh label is localised and deliberately not parsed]'

    if ($autoOk -and $rssOk) { return (New-ProbeResult -State 'OK') }

    $why = ''
    if (-not $autoOk) { $why = ("autotuning = {0}, want normal" -f $s.AutoTune) }
    if (-not $rssOk) {
        if ($why) { $why = $why + '; ' }
        $why = $why + 'global RSS off on an RSS-capable NIC'
    }
    return (New-ProbeResult -State 'NOT-SET' -Why $why)
}

function Register-NetworkSteps {

    Add-Step -StageName 'Network' -Id 'N1' -Title 'TCP global parameters (autotuning / RSS / heuristics)' -Action {
        # ★ v12.0（审计 A-01，即 Gemini F-02 那一半）：netsh 改的全局参数没有
        # 注册表通道可登记。可读的两项（autotuning / RSS）先读原值并登记回放语句；
        # heuristics 在本 build 上读不出（见 Get-TcpGlobalProbe 的证据行），只能如实
        # 标成需人工处理 —— 宁可留白，也不回放一个我们没读准的值。
        $tg = Get-TcpGlobalState
        $tgPre    = ('autotuninglevel={0}, rss={1}, heuristics=<not readable on this build>' -f $tg.AutoTune, $tg.Rss)
        $tgReplay = "Write-Host '  [SKIP] TCP globals: neither the pre-run nor the target state could be read - set them by hand if needed' -ForegroundColor DarkYellow"
        $tgAt = [string]$tg.AutoTune
        $tgRs = [string]$tg.Rss
        if ($tgAt -and $tgRs) {
            $tgReplay = ('netsh int tcp set global autotuninglevel={0} rss={1}' -f $tgAt, $tgRs)
        } elseif ($tgAt) {
            $tgReplay = ('netsh int tcp set global autotuninglevel={0}' -f $tgAt)
        }
        Backup-NativeCommand -Key 'N1 TCP globals' -PreState $tgPre -Replay $tgReplay

        Invoke-Native -File 'netsh' -Arguments @('int', 'tcp', 'set', 'global', 'autotuninglevel=normal') | Out-Null
        # rss= 用 -AllowNonZero：网卡不支持 RSS 时 netsh 可能拒绝，但该子项已由
        # 能力探针判定为"不作为失败项"，这里再抛异常只会把整步连坐（见
        # Get-TcpGlobalProbe 的口径）。
        Invoke-Native -File 'netsh' -Arguments @('int', 'tcp', 'set', 'global', 'rss=enabled') -AllowNonZero | Out-Null
        Invoke-Native -File 'netsh' -Arguments @('int', 'tcp', 'set', 'heuristics', 'disabled') -AllowNonZero | Out-Null
    } -Test {
        # 读回走语言无关的一手来源，不再解析 netsh 的本地化文本。
        return ((Get-TcpGlobalProbe).State -eq 'OK')
    } -Probe {
        return (Get-TcpGlobalProbe)
    }

    if ($script:Config.DisableNagle) {
        Add-Step -StageName 'Network' -Id 'N2' -Title 'Disable Nagle algorithm on all interfaces (interactive latency)' -Action {
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $subs = Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue
            foreach ($s in $subs) {
                $p = $base + '\' + $s.PSChildName
                Set-RegDword -Path $p -Name 'TcpAckFrequency' -Value 1
                Set-RegDword -Path $p -Name 'TCPNoDelay'      -Value 1
            }
        } -Test {
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $subs = Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue
            # Action 写的是两个键（TcpAckFrequency + TCPNoDelay），这里就两个都回读：
            # 只验 TCPNoDelay 的话，TcpAckFrequency 写失败不会暴露。
            $seen  = 0
            $seen2 = 0
            foreach ($s in $subs) {
                $p = $base + '\' + $s.PSChildName
                if (Test-RegValue -Path $p -Name 'TCPNoDelay'      -Expected 1) { $seen++ }
                if (Test-RegValue -Path $p -Name 'TcpAckFrequency' -Expected 1) { $seen2++ }
            }
            if ($subs.Count -eq 0) { return $false }
            return (($seen -eq $subs.Count) -and ($seen2 -eq $subs.Count))
        } -Probe {
            # ★ v12.0（审计 A-10）：此前没有 Probe，而 Test 在"接口枚举为空"时
            # 返回 $false → 动作照做、回读照假 → **永久 FAIL**，而长期红灯与长期黄灯
            # 一样会让操作员无视颜色。三态化：本机没有接口键 → NA（既不是缺口，也不是失败）。
            # 证据只印一行汇总（逐接口逐键会铺满屏，与 Get-SvcGroupProbe 同一取舍）。
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $subs = @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)
            if ($subs.Count -eq 0) {
                Add-Evidence ("no interface key under {0} -> NA (nothing to tune on this build)" -f (Shorten-RegPath -Path $base))
                return (New-ProbeResult -State 'NA' -Why 'no interface key under Tcpip\Parameters\Interfaces on this build')
            }
            $ok1 = 0
            $ok2 = 0
            foreach ($s in $subs) {
                $p = $base + '\' + $s.PSChildName
                $v1 = Get-RegValue -Path $p -Name 'TCPNoDelay'
                $v2 = Get-RegValue -Path $p -Name 'TcpAckFrequency'
                if ($v1 -eq 1) { $ok1++ }
                if ($v2 -eq 1) { $ok2++ }
            }
            $ok = (($ok1 -eq $subs.Count) -and ($ok2 -eq $subs.Count))
            Add-Evidence ("nagle: {0} interface key(s); TCPNoDelay ok {1}; TcpAckFrequency ok {2}{3}" -f $subs.Count, $ok1, $ok2, (Get-EvidenceMark -Ok $ok))
            if ($ok) { return (New-ProbeResult -State 'OK') }
            return (New-ProbeResult -State 'NOT-SET' -Why ("TCPNoDelay {0}/{1} interface(s), TcpAckFrequency {2}/{1}" -f $ok1, $subs.Count, $ok2))
        }
    }

    if ($script:Config.DisableIPv6Tunnel) {
        Add-Step -StageName 'Network' -Id 'N3' -Title 'Disable IPv6 transition tunnels only (6to4 / ISATAP / Teredo)' -Action {
            # 0x01 = 仅禁用隧道接口；不触碰 IPv6 本体
            Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -Value 1
        } -Test {
            return (Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -Expected 1)
        }
    }
}

# -----------------------------------------------------------------------------
#  补充工具
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
#  Services —— 服务精简（CertPropSvc + 蓝牙；Spooler / WLAN 仅 opt-in）
# -----------------------------------------------------------------------------
function Register-ServicesSteps {

    # CertPropSvc —— 证书传播服务。禁用后智能卡/UKey 上的证书不再自动传播到
    # 用户证书存储，依赖智能卡登录或签名的场景会失效。服务器侧不做 UKey 客户端
    # 操作，故禁用（减小攻击面、少一层空闲轮询）。
    # 还原：Set-Service CertPropSvc -StartupType Manual ; Start-Service CertPropSvc
    Add-Step -StageName 'Services' -Id 'S1' -Title 'Disable Certificate Propagation (CertPropSvc)' -Action {
        Disable-Svc -Name 'CertPropSvc'
    } -Test {
        return (Test-SvcDisabled -Name 'CertPropSvc')
    } -Probe {
        return (Get-SvcProbe -Name 'CertPropSvc')
    }


    # 原 S2「禁用 Windows Search 索引」已按机主 2026-09-18 决策删除
    # （C2 = 不禁用）：开始菜单与资源管理器的搜索响应依赖索引服务。

    Add-Step -StageName 'Services' -Id 'S3' -Title 'Disable Bluetooth services' -Action {
        Disable-Svc -Name 'BthServ'
        Disable-Svc -Name 'BTAGService'
        Disable-Svc -Name 'BthAvctpSvc'
    } -Test {
        $a = Test-SvcDisabled -Name 'BthServ'
        $b = Test-SvcDisabled -Name 'BTAGService'
        $c = Test-SvcDisabled -Name 'BthAvctpSvc'
        return ($a -and $b -and $c)
    } -Probe {
        return (Get-SvcGroupProbe -Names @('BthServ', 'BTAGService', 'BthAvctpSvc'))
    }

    Add-Step -StageName 'Services' -Id 'S4' -Title 'Disable Connected User Experiences and Telemetry (DiagTrack)' -Action {
        Disable-Svc -Name 'DiagTrack'
    } -Test {
        return (Test-SvcDisabled -Name 'DiagTrack')
    } -Probe {
        return (Get-SvcProbe -Name 'DiagTrack')
    }

    Add-Step -StageName 'Services' -Id 'S5' -Title 'Disable dmwappushservice' -Action {
        Disable-Svc -Name 'dmwappushservice'
    } -Test {
        return (Test-SvcDisabled -Name 'dmwappushservice')
    } -Probe {
        return (Get-SvcProbe -Name 'dmwappushservice')
    }

    if ($DisableSpooler) {
        Add-Step -StageName 'Services' -Id 'S6' -Title 'Disable Print Spooler (opt-in via -DisableSpooler)' -Action {
            Disable-Svc -Name 'Spooler'
        } -Test {
            return (Test-SvcDisabled -Name 'Spooler')
        } -Probe {
            return (Get-SvcProbe -Name 'Spooler')
        }
    }

    if ($DisableWLAN) {
        Add-Step -StageName 'Services' -Id 'S7' -Title 'Disable WLAN AutoConfig (opt-in via -DisableWLAN)' -Action {
            Disable-Svc -Name 'WlanSvc'
        } -Test {
            return (Test-SvcDisabled -Name 'WlanSvc')
        } -Probe {
            return (Get-SvcProbe -Name 'WlanSvc')
        }
    }
}

# -----------------------------------------------------------------------------
#  Security —— 加固（与 v8.1 的降级方向完全相反）
# -----------------------------------------------------------------------------
function Register-SecuritySteps {

    Add-Step -StageName 'Security' -Id 'SEC1' -Title 'Disable LLMNR (kills UNC/host spoofing vector)' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Value 0
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Expected 0)
    }

    Add-Step -StageName 'Security' -Id 'SEC2' -Title 'Disable NetBIOS over TCP/IP on all interfaces' -Action {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
        $subs = Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue
        foreach ($s in $subs) {
            $p = $base + '\' + $s.PSChildName
            Set-RegDword -Path $p -Name 'NetbiosOptions' -Value 2
        }
    } -Test {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
        $subs = Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue
        if ($subs.Count -eq 0) { return $false }
        $seen = 0
        foreach ($s in $subs) {
            $p = $base + '\' + $s.PSChildName
            if (Test-RegValue -Path $p -Name 'NetbiosOptions' -Expected 2) { $seen++ }
        }
        return ($seen -eq $subs.Count)
    } -Probe {
        # ★ v12.0（审计 A-10）：同 N2 —— "接口枚举为空"此前落到永久 FAIL，
        # 而那是环境事实（本机没有 NetBT 接口键），不是缺口。
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
        $subs = @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)
        if ($subs.Count -eq 0) {
            Add-Evidence ("no NetBT interface key under {0} -> NA (no interface to harden on this build)" -f (Shorten-RegPath -Path $base))
            return (New-ProbeResult -State 'NA' -Why 'no NetBT interface key on this build (NetBIOS over TCP/IP is not exposed here)')
        }
        $okNbt = 0
        foreach ($s in $subs) {
            $p = $base + '\' + $s.PSChildName
            $v = Get-RegValue -Path $p -Name 'NetbiosOptions'
            if ($v -eq 2) { $okNbt++ }
        }
        Add-Evidence ("netbios over tcp/ip: {0} interface key(s), {1} set to 2{2}" -f $subs.Count, $okNbt, (Get-EvidenceMark -Ok ($okNbt -eq $subs.Count)))
        if ($okNbt -eq $subs.Count) { return (New-ProbeResult -State 'OK') }
        return (New-ProbeResult -State 'NOT-SET' -Why ("{0} of {1} interface key(s) still have NetbiosOptions != 2" -f ($subs.Count - $okNbt), $subs.Count))
    }

    Add-Step -StageName 'Security' -Id 'SEC3' -Title 'Disable SMBv1 on the server' -Action {
        # ★ v12.0（审计 A-01，即 Gemini F-02 那一半）：SMBv1 的服务端状态同样没有
        # 注册表通道可登记 —— 先读原值，再登记一条可回放语句（写侧的同一条命令）。
        $smbPre    = '<could not be read before the change>'
        $smbReplay = "Write-Host '  [SKIP] SMBv1 server: the pre-run state could not be read - set it by hand if needed' -ForegroundColor DarkYellow"
        if (Get-Command Get-SmbServerConfiguration -ErrorAction SilentlyContinue) {
            try {
                $bs = Get-SmbServerConfiguration -ErrorAction Stop
                if ($bs.PSObject.Properties['EnableSMB1Protocol']) {
                    $smbPre = ('EnableSMB1Protocol={0}' -f [bool]$bs.EnableSMB1Protocol)
                    if ([bool]$bs.EnableSMB1Protocol) { $smbReplay = 'Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force' }
                    else { $smbReplay = 'Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force' }
                }
            } catch { }
        }
        Backup-NativeCommand -Key 'SEC3 SMBv1 server' -PreState $smbPre -Replay $smbReplay
        if (Get-Command Set-SmbServerConfiguration -ErrorAction SilentlyContinue) {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
        } else {
            throw 'Set-SmbServerConfiguration is not available on this system'
        }
    } -Test {
        # ★ 读侧留痕（v11.8）。本步此前是**全脚本唯一**"有 Test、无 Probe、Test 又一条
        # 证据行都不产"的位置 —— 一旦判负，报告里只剩一个结论词，操作员不知道读到的是
        # 什么。真机审计（v11.7 会话 20260921_092704 的 -Verify，逐条数过 43 步）显示
        # 零证据行的只有 D13 / D14 / SEC3 三项，而前两项的 Probe 至少会用 Why 说明处境，
        # 只有 SEC3 连理由都没有 —— v11.3 那个"只给结论词"的老毛病最后残留的位置。
        if (-not (Get-Command Get-SmbServerConfiguration -ErrorAction SilentlyContinue)) {
            [void](Add-Check -Ok $false -Text 'Get-SmbServerConfiguration is not available on this system (the SMBv1 state cannot be read back)')
            return $false
        }
        $smb = $null
        try { $smb = Get-SmbServerConfiguration -ErrorAction Stop }
        catch {
            [void](Add-Check -Ok $false -Text ("Get-SmbServerConfiguration failed: {0}" -f $_.Exception.Message))
            return $false
        }
        # 属性不存在与属性为假是两件事：拿"读不到"当"已关闭"就是一条假绿通道。
        if ($null -eq $smb.PSObject.Properties['EnableSMB1Protocol']) {
            [void](Add-Check -Ok $false -Text 'Get-SmbServerConfiguration returned no EnableSMB1Protocol property on this build (the SMBv1 state cannot be read back)')
            return $false
        }
        $v1 = [bool]$smb.EnableSMB1Protocol
        [void](Add-Check -Ok (-not $v1) -Text ("SMB server EnableSMB1Protocol = {0} (want False)" -f $v1))
        return (-not $v1)
    }

    Add-Step -StageName 'Security' -Id 'SEC4' -Title 'Disable AutoPlay and AutoRun for all drive types' -Action {
        $ex = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        Set-RegDword -Path $ex -Name 'NoDriveTypeAutoRun' -Value 255
        Set-RegDword -Path $ex -Name 'NoAutorun'          -Value 1
        Set-RegDword -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Value 1
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveTypeAutoRun' -Expected 255
        $b = Test-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoAutorun' -Expected 1
        $c = Test-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Expected 1
        return ($a -and $b -and $c)
    }

    Add-Step -StageName 'Security' -Id 'SEC5' -Title 'Disable WDigest plaintext credential caching' -Action {
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Value 0
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Expected 0)
    }


    # 原 SEC6 / SEC7 / SEC8（审计留痕三项）与 SEC9（Defender 加固开启）已按机主
    # 2026-09-18 决策删除：目标机是私人家庭虚机、非工作用途，不启用审计；安全防护
    # 交由火绒承担，故不再朝「开启 Defender」的方向加固。
    # 本阶段保留的加固项：SEC1 LLMNR / SEC2 NBT-NS / SEC3 SMBv1 / SEC4 AutoPlay /
    # SEC5 WDigest —— 全部是无使用代价项。

}

# -----------------------------------------------------------------------------
#  Downgrade —— 安全降级档（默认不执行，必须显式选择）
#
#  这一档的每一项都是「拿一个安全控制换一点便利」，因此：
#    · 不在任何默认路径里：菜单需选 [10]，命令行需 -Stage Downgrade 或 All
#    · 配置文件的键名白名单不含它们 —— 不允许被旁边的 json 悄悄打开
#    · 执行前由 Start-Optimization 打印风险摘要与回滚命令并要求确认
#    · 每一项都带完整回读断言，且都有对应可逆手段
# -----------------------------------------------------------------------------
function Register-DowngradeSteps {

    # SEC10 —— UAC 管理员静默提权。
    # 沿用 v8.1 的温和写法：EnableLUA 保持 1（UAC 框架、完整性级别与文件虚拟化
    # 机制全部保留），只是管理员提权不再弹提示、不再切到安全桌面。
    # ⚠ 耦合警告：PromptOnSecureDesktop=0 单独存在时是经典 UAC 绕过口（UACME 类
    #   攻击可模拟点击安全桌面之外的提示）。只有在 ConsentPromptBehaviorAdmin=0
    #   （本就无提示）的前提下风险才不放大。日后若把 ConsentPromptBehaviorAdmin
    #   改回 2 或 5，必须同步把 PromptOnSecureDesktop 改回 1。
    # 还原：ConsentPromptBehaviorAdmin 置 5、PromptOnSecureDesktop 置 1。
    Add-Step -StageName 'Downgrade' -Id 'SEC10' -Title '[DOWNGRADE] Suppress UAC elevation prompts for administrators' -Action {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        Set-RegDword -Path $p -Name 'EnableLUA'                  -Value 1
        Set-RegDword -Path $p -Name 'ConsentPromptBehaviorAdmin' -Value 0
        Set-RegDword -Path $p -Name 'PromptOnSecureDesktop'      -Value 0
    } -Test {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        $a = Test-RegValue -Path $p -Name 'EnableLUA'                  -Expected 1
        $b = Test-RegValue -Path $p -Name 'ConsentPromptBehaviorAdmin' -Expected 0
        $c = Test-RegValue -Path $p -Name 'PromptOnSecureDesktop'      -Expected 0
        return ($a -and $b -and $c)
    }

    # SEC11 —— 关闭 Defender（可逆）。刻意不做组件卸载：
    #   Uninstall-WindowsFeature Windows-Defender 需要安装介质才能恢复（不可逆），
    #   而关服务随时可以一行命令还原。机主要装火绒，关服务完全够用。
    # ⚠ 若目标机开启了防篡改保护（Tamper Protection），Set-Service WinDefend 会被
    #   拒绝 —— 此时本步会如实记 FAIL，不会假绿。处置：先在 Windows 安全中心 →
    #   病毒和威胁防护 → 设置 → 关闭「篡改防护」，再重跑本步。
    # 还原：Set-Service WinDefend -StartupType Automatic ; Set-Service WdNisSvc -StartupType Manual
    Add-Step -StageName 'Downgrade' -Id 'SEC11' -Title '[DOWNGRADE] Disable Defender real-time protection and services' -Action {
        # ★ v12.0（审计 A-01，即 Gemini F-02 那一半）：先登记 Defender 偏好的原值。
        # Set-MpPreference 改的东西不在任何注册表备份通道里（策略键才是），还原脚本此前
        # 只还原策略键与服务 —— 于是"还原完之后实时防护还是关的"，而报告会说已还原。
        # 读原值用 Get-MpPreference 的同名属性，回放语句本身就是写侧的那条命令。
        $mpPre    = '<could not be read before the change>'
        $mpReplay = "Write-Host '  [SKIP] Defender preferences: the pre-run state could not be read - set them by hand if needed' -ForegroundColor DarkYellow"
        if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
            try {
                $mp = Get-MpPreference -ErrorAction Stop
                $mpSeen = New-Object System.Collections.ArrayList
                $mpBack = New-Object System.Collections.ArrayList
                foreach ($p in @('DisableRealtimeMonitoring', 'DisableBehaviorMonitoring', 'DisableScriptScanning',
                                 'DisableIOAVProtection', 'DisableArchiveScanning', 'DisableScanningNetworkFiles')) {
                    $pv = $mp.PSObject.Properties[$p]
                    if (-not $pv) { continue }
                    [void]$mpSeen.Add(('{0}={1}' -f $p, [bool]$pv.Value))
                    if ([bool]$pv.Value) { [void]$mpBack.Add(('Set-MpPreference -{0} $true' -f $p)) }
                    else                 { [void]$mpBack.Add(('Set-MpPreference -{0} $false' -f $p)) }
                }
                if ($mpBack.Count -gt 0) {
                    $mpPre    = ($mpSeen -join ', ')
                    $mpReplay = ($mpBack -join '; ')
                }
            } catch { }
        }
        Backup-NativeCommand -Key 'SEC11 Defender preferences' -PreState $mpPre -Replay $mpReplay

        # 1) Defender 自己的 cmdlet（对未开篡改保护的机器有效）。逐项 try/catch：
        #    某一项不被支持就跳过，但不吞掉整步 —— 真伪由下面的 Test 说话。
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            $prefs = @(
                'DisableRealtimeMonitoring', 'DisableBehaviorMonitoring', 'DisableScriptScanning',
                'DisableIOAVProtection', 'DisableArchiveScanning', 'DisableScanningNetworkFiles'
            )
            foreach ($p in $prefs) {
                try {
                    $h = @{}
                    $h[$p] = $true
                    Set-MpPreference @h -ErrorAction Stop
                } catch {
                    Write-Log ("defender-pref skipped`t{0}`t{1}" -f $p, $_.Exception.Message)
                }
            }
        }
        # 2) 策略层（优先级高于 Set-MpPreference）
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -Name 'DisableRealtimeMonitoring' -Value 1
        # 刻意不写 DisableAntiSpyware / DisableAntiVirus：自 Server 2016 起已被微软
        # 忽略，写它只是制造「已关闭」的错觉（v8.1 审计 F-04 的同类假绿）。
        # 3) 关服务 —— 真正起决定作用的一步。失败会抛错并如实记 FAIL。
        Disable-Svc -Name 'WinDefend'
        Disable-Svc -Name 'WdNisSvc'
    } -Test {
        # 策略键也要回读 —— 只验服务状态会漏掉「服务停了但策略没写」的半吊子状态。
        $r = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -Name 'DisableRealtimeMonitoring' -Expected 1
        if (-not $r) { return $false }
        if (-not (Test-SvcDisabled -Name 'WinDefend')) { return $false }
        if (-not (Test-SvcDisabled -Name 'WdNisSvc'))  { return $false }
        # 实时防护若仍报「已启用」则不算成功；若 Get-MpComputerStatus 因服务已停而
        # 报错，恰恰是期望状态，视为通过。
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            try {
                if ([bool](Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled) { return $false }
            } catch { }
        }
        return $true
    } -Probe {
        # 这一条回答一个具体问题：这台机的 Defender 到底在不在、开不开。
        #   ABSENT —— WinDefend 服务不存在：组件缺失或已被卸载，脚本无可禁用之物。
        #             注意这**不等于**"有 AV 在保护"——它只说明 Defender 这条路径
        #             已经不在，机器当前是否有第三方防护，由机主自行掌握。
        #   OK     —— 策略键已写 且 服务已禁用
        #   NOT-SET—— 组件还在，但没关干净
        $pp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
        if (-not (Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue)) {
            return (New-ProbeResult -State 'ABSENT' -Why 'WinDefend not present (Defender component absent or removed) - no AV registered by this script')
        }
        if (-not (Test-RegValue -Path $pp -Name 'DisableRealtimeMonitoring' -Expected 1)) {
            return (New-ProbeResult -State 'NOT-SET' -Why 'policy DisableRealtimeMonitoring != 1')
        }
        $wm = Get-SvcStartMode -Name 'WinDefend'
        if ($wm -ne 'Disabled') {
            return (New-ProbeResult -State 'NOT-SET' -Why ("WinDefend startup = {0}" -f $wm))
        }
        return (New-ProbeResult -State 'OK')
    }

    # SEC12 —— 密码永不过期。
    # 只取消「过期」，长度与复杂度保持默认：这两项只在设置密码那一刻生效，不产生
    # 任何日常打扰，因此没有理由一并放开。
    # 用 secedit 的 inf 模板写入：段名与键名是固定的英文，不随系统语言变化，写入
    # 与回读用同一套键名，避免中文系统上的假红。
    # 当前用户账户侧用 Set-LocalUser，取代 v8.1 已废弃的 wmic 路径。
    # 还原：本步骤走 secedit 与 Set-LocalUser，两条都不经过 Reg / Svc / Task / Feat /
    # Power 通道 —— 所以由**原生命令回放通道**承担（v12.0，见 Backup-NativeCommand）：
    # Action 先导出改动前的 MaximumPasswordAge，登成一条可回放语句
    # （net accounts /maxpwage:<原值>），生成的还原脚本会逐条重放。手工等价：
    #   net accounts /maxpwage:<原值>
    #   Set-LocalUser -Name <user> -PasswordNeverExpires $false
    Add-Step -StageName 'Downgrade' -Id 'SEC12' -Title '[DOWNGRADE] Password never expires (length and complexity kept)' -Action {
        # ★ v11.16：改动前先留档密码策略原值。
        # 起因：本步骤的改动既不在 $script:Bak.Reg，也不在 Svc / Task / Feat / Power
        # 任何通道，还原脚本对它**零覆盖**；而"降级风险摘要"此前给的手动回滚命令
        # 方向还是反的（把降级后的 UNLIMITED 当成回滚目标）。没有原值，那个提示
        # 无论怎么写都不可能正确 —— 所以先把原值记下来。
        # 用 secedit 导出而不是 net accounts：段名/键名是固定英文，不随系统语言变化
        # （与下面的写入用同一套键名），不必去猜中文标签。留档通道选 Bak.Misc ——
        # 登记走原生命令回放通道（Backup-NativeCommand）—— 它本来就是为"注册表通道
        # 表达不了的改动"准备的。临时文件名带 PID，Clear-StaleScriptTemp 能收残。
        $pre = Join-Path $env:TEMP ('svr2desk_pwpre_{0}.inf' -f $PID)
        $preTxt = '<export produced no file>'
        try {
            Invoke-Native -File 'secedit' -Arguments @('/export', '/cfg', $pre, '/areas', 'SECURITYPOLICY') | Out-Null
            if (Test-Path -LiteralPath $pre) {
                $ptxt = Get-Content -LiteralPath $pre -Raw -ErrorAction Stop
                $pm = [regex]::Match($ptxt, '(?m)^\s*MaximumPasswordAge\s*=\s*(-?\d+)\s*$')
                if ($pm.Success) { $preTxt = $pm.Groups[1].Value } else { $preTxt = '<absent from exported policy>' }
            }
        } catch { $preTxt = ("<export failed: {0}>" -f $_.Exception.Message) }
        finally { Remove-Item -LiteralPath $pre -Force -ErrorAction SilentlyContinue -WhatIf:$false }
        # ★ v12.0（审计 A-01）：原值既留档（人可读的那一行）也登记**可回放语句**
        # （机器可回放）—— net accounts /maxpwage 正是 secedit 那个策略的手工等价命令。
        # v11.16 只做到留档（Bak.Misc → misc_snapshot.txt），回放仍靠人；现在并成一条产线，
        # 不再为同一件事记两处。
        $ageNum    = 0
        $ageReplay = "Write-Host '  [SKIP] password policy: the pre-run value could not be read - restore it by hand' -ForegroundColor DarkYellow"
        if ([int]::TryParse($preTxt, [ref]$ageNum)) {
            $ageReplay = ('net accounts /maxpwage:{0}' -f $preTxt)
        }
        Backup-NativeCommand -Key 'SEC12 password policy' -PreState ("MaximumPasswordAge={0}" -f $preTxt) -Replay $ageReplay
        Write-Note ("password policy MaximumPasswordAge before this run: {0}" -f $preTxt) 'DarkYellow'
        Write-Log ("pre-run MaximumPasswordAge`t{0}" -f $preTxt)

        $inf = Join-Path $env:TEMP 'svr2desk_pwsec.inf'
        $sdb = Join-Path $env:TEMP 'svr2desk_pwsec.sdb'
        $log = Join-Path $env:TEMP 'svr2desk_pwsec.log'
        $body = @(
            '[Unicode]'
            'Unicode=yes'
            '[Version]'
            'signature="$CHICAGO$"'
            '[System Access]'
            'MaximumPasswordAge = -1'
        )
        try {
            # -Encoding Unicode 与 inf 里的 [Unicode] Unicode=yes 声明保持一致
            Set-Content -LiteralPath $inf -Value $body -Encoding Unicode
            Invoke-Native -File 'secedit' -Arguments @(
                '/configure', '/db', $sdb, '/cfg', $inf, '/areas', 'SECURITYPOLICY', '/log', $log
            ) | Out-Null
        } finally {
            # 显式 -WhatIf:$false：这三个文件是**本脚本刚刚产生的**，属于自清理，
            # 不是"对系统的改动"，因此不受预演保护。全局偏好已在本版开头交还给
            # PowerShell，这里再标一次，防止日后有人把偏好改回去导致临时文件残留
            # （真机实测过：残留 %TEMP%\svr2desk_pwread_<pid>.inf）。
            Remove-Item -LiteralPath $inf, $sdb, $log -Force -ErrorAction SilentlyContinue -WhatIf:$false
        }
        if (-not (Get-Command Set-LocalUser -ErrorAction SilentlyContinue)) {
            throw 'Set-LocalUser unavailable (LocalAccounts module missing)'
        }
        Set-LocalUser -Name $env:USERNAME -PasswordNeverExpires $true -ErrorAction Stop
    } -Test {
        # 本步是唯一"整段手写回读"的步骤：secedit 导出的策略文本 + Get-LocalUser 的
        # 对象属性，两者都用不上读值原语。原先因此**一条证据行都不产** —— 报告里
        # 只剩一个 NOT-SET，操作员既不知道是策略没写进去、还是用户标志没置上、
        # 还是导出压根失败了。这正是 v11.3 那个"只给结论词"的老毛病在这条线路上复发。
        # 现在两半各自经 Add-Check 留痕，且**不互相掩盖**：任一半失败也照样读另一半。
        $exp   = Join-Path $env:TEMP ('svr2desk_pwread_{0}.inf' -f $PID)
        $ageOk = $false
        try {
            Invoke-Native -File 'secedit' -Arguments @('/export', '/cfg', $exp, '/areas', 'SECURITYPOLICY') | Out-Null
            $ageTxt = '<export produced no file>'
            if (Test-Path -LiteralPath $exp) {
                $txt = Get-Content -LiteralPath $exp -Raw -ErrorAction Stop
                $m = [regex]::Match($txt, '(?m)^\s*MaximumPasswordAge\s*=\s*(-?\d+)\s*$')
                if ($m.Success) { $ageTxt = $m.Groups[1].Value } else { $ageTxt = '<absent from exported policy>' }
            }
            $ageOk = ($ageTxt -eq '-1')
            [void](Add-Check -Ok $ageOk -Text ("secedit SECURITYPOLICY MaximumPasswordAge = {0} (want -1)" -f $ageTxt))
        } catch {
            [void](Add-Check -Ok $false -Text ("secedit /export failed: {0}" -f $_.Exception.Message))
        } finally {
            # 同上：这是本脚本导出的临时文件，必须保证一定删掉。
            Remove-Item -LiteralPath $exp -Force -ErrorAction SilentlyContinue -WhatIf:$false
        }

        # 账户侧的"密码永不过期"标志。三条来源并列印出，**判据只认真正回答本问题的那条**。
        #
        # ★ v11.9 判据换源（根因修复）。v11.6~v11.8 的判据写的是
        #       $u = Get-LocalUser -Name $env:USERNAME ; $pneOk = ($u.PasswordNeverExpires …)
        #   而真机（PowerShell 7.6.6 / build 26200）的
        #       Get-LocalUser -Name X | Format-List * -Force
        #   属性清单里**根本没有 PasswordNeverExpires** —— LocalUser 类只暴露
        #   AccountExpires / PasswordExpires / PasswordLastSet / PasswordRequired /
        #   UserMayChangePassword / PrincipalSource / ObjectClass 等 14 项。
        #   于是那次读取**恒为 $null**、$pneOk **恒为 $false**，而 $null 永远变不成 True
        #   —— SEC12 从 v11.6 起就是一条**永不满足的假红**。
        #   （v11.6 印 False 是 [bool]$null 的强制转换把它藏住了；v11.7 改印原始值才让
        #     它现形 —— 定案证据就是那条 <null> 加一份 -Force 属性清单。）
        #   两侧不对称是根因指纹：写入侧从不抛异常（三次 FAIL 都走"通用措辞"分支而非
        #   异常分支 → Set-LocalUser -PasswordNeverExpires 参数存在且执行过），读取侧
        #   却读不到值。
        #
        #   换上来的这一条**就是写侧操作的那个标志**（同一件事的两个门）：
        #   Win32_UserAccount.PasswordExpires —— 微软官方口径 False = 密码过期被禁用，
        #   且 wmic useraccount set PasswordExpires=FALSE 正是 lusrmgr 里"密码永不过期"
        #   复选框的等价命令；结构化字段，不依赖系统语言。
        #   判据结构不变，仍是"两半都要"（大师 2026-09-21 决策）：
        #       策略 MaximumPasswordAge = -1    且    账户标志 = False
        $cimTxt = '<unread>'
        $cimOk  = $false
        $cimWhy = ''
        try {
            # LocalAccount=True：本脚本管的是本地账户。域账户的 SAM 标志无意义 ——
            # 与其读一个域对象的标志，不如明说"这条查的不是它"。
            $cim = @(Get-CimInstance -ClassName Win32_UserAccount -Filter ("Name='{0}' And LocalAccount=True" -f $env:USERNAME) -ErrorAction Stop)
            if ($cim.Count -eq 0) {
                $cimTxt = '<no local account by that name>'
                $cimWhy = ('CIM returned no local account named {0} (a domain account has no local SAM flag)' -f $env:USERNAME)
            } else {
                $cv = $cim[0].PasswordExpires
                if ($null -eq $cv) { $cimTxt = '<null>' } else { $cimTxt = [string]([bool]$cv) }
                $cimOk = ($cimTxt -eq 'False')
            }
        } catch { $cimTxt = ("<read failed: {0}>" -f $_.Exception.Message) }
        # 读不到就明文写 <cannot determine>，**绝不静默压成 False** —— 后者正是这条缺陷的
        # 形态（$null 被印成 False，混过了 v11.4~v11.8 四轮）。判据上它仍算不达标
        # （读不到不能当达标，见 §3.2 那条规矩），但报告里"读过、是 True"与"根本没读出来"
        # 必须是两句话。
        if ((-not $cimOk) -and ($cimTxt -ne 'True')) { $cimTxt = ('<cannot determine> ' + $cimTxt) }
        [void](Add-Check -Ok $cimOk -Text ("local user {0} Win32_UserAccount.PasswordExpires = {1} (want False = password never expires) [source 1/3: the verdict is this line - the same flag Set-LocalUser -PasswordNeverExpires writes]" -f $env:USERNAME, $cimTxt))
        if ($cimWhy) { Add-Evidence ('  ' + $cimWhy) }

        # 来源 2/3：net user 的「密码到期」专行（取值逻辑见 Get-NetUserPasswordExpiryLine）。
        # v11.7 用的是泛匹配取第一条，真机上取到的是「帐户到期」—— 另一个字段，
        # 且恒为「从不」，看着像佐证、答的却不是这个问题。
        $nuLine = ''
        $nuWhy  = ''
        try {
            $nu     = (net user $env:USERNAME 2>&1 | Out-String)
            $got    = Get-NetUserPasswordExpiryLine -Text $nu
            $nuLine = [string]$got.Line
            $nuWhy  = [string]$got.Why
        } catch { $nuWhy = ("net user failed: {0}" -f $_.Exception.Message) }
        if ($nuLine) {
            Add-Evidence ("  source 2/3 (net user, password-expiry line): {0}" -f $nuLine)
        } else {
            Add-Evidence ("  source 2/3 (net user, password-expiry line): <not found> - {0}" -f $nuWhy)
        }

        # 来源 3/3：Get-LocalUser 的 PasswordExpires —— 这是 LocalUser 类**确实存在**的
        # 属性（真机 Format-List 清单里有它，取回为空）。**只作佐证**：本机策略已是
        # Unlimited 时它对所有账户都为空，分辨不出账户级标志 —— 这恰好实证了"三条
        # 独立路径必须真的独立"：三条都在读同一个策略时，它们不是互相印证。
        $lueTxt = '<unread>'
        try {
            $lu = Get-LocalUser -Name $env:USERNAME -ErrorAction Stop
            $lv = $lu.PasswordExpires
            if ($null -eq $lv) { $lueTxt = '<empty: no expiry date set>' } else { $lueTxt = [string]$lv }
        } catch { $lueTxt = ("<read failed: {0}>" -f $_.Exception.Message) }
        Add-Evidence ("  source 3/3 (Get-LocalUser.PasswordExpires; empty = no expiry date set): {0}" -f $lueTxt)

        # 交叉证据与结论相左时必须点出来。判断"永不过期"的佐证各有口径，都**不依赖
        # 标签文字**：net user 那一行的值里没有数字（"从不" / "Never" 都不是日期），
        # 或者 Get-LocalUser.PasswordExpires 取回为空（没有到期日）。
        # 这一行**刻意不带 MISMATCH** —— 它不是"观察结果不达标"，而是"两条路在打架"；
        # 混为一谈会让守门人（要求判负必须有 MISMATCH）失去判据。
        # 判据换源（v11.9）之后，这一行才真正只在"来源与判据打架"时出现 —— 此前它挂在
        # 一个恒假的判据上，等于每次运行都无条件出现一次。
        $forever = @()
        if ($nuLine -and ($nuLine -notmatch '\d'))           { $forever += 'net user' }
        if ($lueTxt -eq '<empty: no expiry date set>')          { $forever += 'Get-LocalUser' }
        if (($forever.Count -gt 0) -and (-not $cimOk)) {
            Add-Evidence (("  cross-check conflict: {0} independent source(s) say the password never expires ({1}), while the verdict line (source 1/3) does not read False - settle this before trusting the verdict" -f $forever.Count, ($forever -join ', ')))
        }

        return ($ageOk -and $cimOk)
    }

    # SEC13 —— 屏蔽安全中心告警与托盘图标。
    # 这一项与「关 SEHOP」性质相反：SEHOP 对使用者零打扰，关了纯属白送一道缓解；
    # 而关掉 Defender 之后安全中心会持续报红叉与通知，屏蔽它才是真正减少打扰。
    # 刻意不写 v8.1 的 HKLM\Software\Microsoft\Security Center\Notifications_Disable
    # —— 那是 Windows 7 时代的遗留键，在 Server 2016+ 上已被微软废弃、实际无效。
    # 还原：两个策略值置 0 或删除，并恢复 Run 下的 SecurityHealth 项。
    Add-Step -StageName 'Downgrade' -Id 'SEC13' -Title '[DOWNGRADE] Hide Security Center alerts and tray icon' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' -Name 'DisableNotifications' -Value 1
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray'       -Name 'HideSystray'         -Value 1
        Remove-RegValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurityHealth'
    } -Test {
        $a = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' -Name 'DisableNotifications' -Expected 1
        $b = Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray'       -Name 'HideSystray'         -Expected 1
        # 同 D15：原先手写 Test-Path + GetValueNames，参与判定却不产证据。
        # 本步今天恰好全绿所以没暴露，属潜伏缺陷，一并修掉。
        $c = Test-RegValueAbsent -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurityHealth'
        return ($a -and $b -and $c)
    }
}

# -----------------------------------------------------------------------------
#  Ops —— 可运维性
# -----------------------------------------------------------------------------
function Register-OpsSteps {


    # 原 OPS1（安装 OpenSSH Server）与 OPS2（启用 PSRemoting）已按机主 2026-09-18
    # 决策删除：两者都在监听端口（22 / 5985），与「避免被远程操控」的意图相反。
    # 本阶段只保留无暴露面的可运维项：长路径支持、时区稳定、Windows Update 行为。

    Add-Step -StageName 'Ops' -Id 'OPS3' -Title 'Enable long path support (260+ characters)' -Action {
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Expected 1)
    }

    Add-Step -StageName 'Ops' -Id 'OPS4' -Title 'Disable automatic time zone updates (keep clock stable)' -Action {
        Disable-Svc -Name 'tzautoupdate'
    } -Test {
        return (Test-SvcDisabled -Name 'tzautoupdate')
    } -Probe {
        return (Get-SvcProbe -Name 'tzautoupdate')
    }

    Add-Step -StageName 'Ops' -Id 'OPS5' -Title 'Never auto-reboot while a user is logged on (Windows Update)' -Action {
        Set-RegDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1
    } -Test {
        return (Test-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoRebootWithLoggedOnUsers' -Expected 1)
    }
}

# -----------------------------------------------------------------------------
#  Cleanup —— 白名单目录清理
# -----------------------------------------------------------------------------
function Get-CleanupBytes {
    $total = 0
    foreach ($p in $script:CleanupTargets) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
            if ($s) { $total += [long]$s }
        } catch { }
    }
    return [long]$total
}

function Invoke-CleanupTarget {
    <#
      清理一个白名单目录，并**逐条记录**每个顶层条目的去留。

      为什么不能拿"总字节数变小"当 post-check：临时目录是活体 —— Windows 每秒
      都在往里写。真机实测（v11.3）before 6.5 MB / after 6.5→6.6 MB，缓存反而
      "变大"，于是每次运行都判 FAIL。总字节数与"我们删掉了什么"之间没有因果
      关系，它是环境噪音，不是判据。

      现在：删除前记录条目 → 逐条删 → 成功的进 Deletable、失败的进 Kept（含系统
      给出的原因）。判定只看 Deletable 里的条目是否真的消失；被占用的条目不算
      脚本的失败，它们由 PARTIAL 与证据行如实呈现。
    #>
    param([string]$Path)

    $rec = [PSCustomObject]@{
        Dir       = $Path
        Items     = 0
        Deletable = (New-Object System.Collections.ArrayList)
        Kept      = (New-Object System.Collections.ArrayList)
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Note "skip (absent): $Path" 'DarkGray'
        return $rec
    }

    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    $rec.Items = $items.Count
    foreach ($i in $items) {
        # ★ v12.0（审计 A-15）：重解析点（junction / symlink）**绝不递归删除**。
        # Windows PowerShell 5.1 的 Remove-Item -Recurse 会跟随目录链接删掉**目标**里的
        # 内容 —— 那是越界删除，而 v8.1 的整盘 del /s 被删除正是为这一类。
        # 这里是全脚本唯一残余的递归删除点（其余都是注册表/服务值）。
        # 删链本身在"目标非空"时同样会失败，所以交给操作员判断比脚本猜更安全；
        # 只登记进 Kept，并让原因写明是"结构"而不是"被占用" —— 读的人分得清。
        $isLink = $false
        try {
            $itself = Get-Item -LiteralPath $i.FullName -Force -ErrorAction Stop
            $isLink = [bool]($itself.Attributes -band [IO.FileAttributes]::ReparsePoint)
        } catch { $isLink = $false }
        if ($isLink) {
            [void]$rec.Kept.Add([PSCustomObject]@{ Path = $i.FullName; Why = 'reparse point (junction / symlink): left alone - a recursive removal can follow the link and delete the target' })
            continue
        }

        # -ErrorAction Stop 是刻意的：旧版用 SilentlyContinue，把"删不掉"和
        # "已经删掉"混成同一件事，于是既无法判定也没有留痕。
        try {
            Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction Stop
            [void]$rec.Deletable.Add($i.FullName)
        } catch {
            [void]$rec.Kept.Add([PSCustomObject]@{ Path = $i.FullName; Why = $_.Exception.Message })
        }
    }

    Write-Note ("cleaned: {0}  (removed {1} of {2})" -f $Path, $rec.Deletable.Count, $rec.Items) 'DarkGray'
    return $rec
}

function Register-CleanupSteps {

    # v13.1：让配置键 `CleanupEnabled` 真正生效。它此前只是被读进 $cfg 却从未被使用 ——
    # 一个"承诺了行为却不兑现"的死键，与 v8.1 那个无效的 Defender 键同族（本文件反复
    # 强调：写了不生效的值就是假绿）。关掉时 CL1/CL2 都不注册，报告里也就不出现 ——
    # 与 S6/S7 的 opt-in 同一做法。注意副作用：备份保留（CL2）也一并停掉，
    # 于是备份目录会一直累积；这是"一个开关管住所有删除动作"的必然取舍，方向是安全的。
    if (-not $script:Config.CleanupEnabled) { return }

    # 白名单式清理。绝不递归扫描整盘扩展名 —— v8.1 的 del /f /s /q C:\*.log
    # 会连带删掉中间件日志、软件升级保留的 .old 回滚副本和许可证校验文件。
    # 明确排除 System32\LogFiles（IIS 与系统诊断日志，金融场景需留痕）。
    $script:CleanupTargets = @(
        (Join-Path $env:SystemRoot 'Temp'),
        (Join-Path $env:SystemRoot 'SoftwareDistribution\Download'),
        (Join-Path $env:LOCALAPPDATA 'Temp'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:SystemRoot 'Logs\CBS')
    )
    $script:CleanupBeforeBytes = -1
    # 本次执行记录。$null = 本次会话还没跑过动作（Test 据此要求执行）。
    $script:CleanupPlan = $null
    # CL2 的本轮执行记录。$null = 本次会话还没跑过（Test 据此要求执行）。
    $script:PrunePlan = $null

    Add-Step -StageName 'Cleanup' -Id 'CL1' -Title 'Clean whitelisted temp and cache directories' -Action {
        $script:CleanupBeforeBytes = Get-CleanupBytes
        Write-Note ("before: {0:N1} MB" -f ($script:CleanupBeforeBytes / 1MB)) 'DarkGray'

        $plan = New-Object System.Collections.ArrayList
        foreach ($p in $script:CleanupTargets) {
            [void]$plan.Add((Invoke-CleanupTarget -Path $p))
        }
        $script:CleanupPlan = $plan

        $removed = 0
        $keptCnt = 0
        foreach ($r in $plan) {
            $removed = $removed + $r.Deletable.Count
            $keptCnt = $keptCnt + $r.Kept.Count
        }

        # 字节数只作参考印出来，不参与判定（它会因为系统边删边写而反向变化）
        $after = Get-CleanupBytes
        Write-Note ("after : {0:N1} MB   (removed {1} item(s), kept {2})" -f ($after / 1MB), $removed, $keptCnt) 'DarkGray'
        Add-Evidence ("cleanup: removed {0} item(s), kept {1} item(s) held by running processes" -f $removed, $keptCnt)

        foreach ($r in $plan) {
            foreach ($k in $r.Kept) {
                Add-Evidence ("kept (in use): {0}" -f $k.Path)
                if ($k.Path -match '\\Logs\\CBS\\') {
                    Add-Evidence '  ^ expected: CBS.log is held open by TrustedInstaller while the service runs'
                }
            }
        }

        # 有未尽项 → 提交 PARTIAL：动作做到了能做的，剩下的不是脚本能消除的。
        # 既不算达标（不冒充），也不算失败（不制造红字疲劳）。
        if ($keptCnt -gt 0) {
            $script:StepPartial = ("{0} item(s) could not be removed (held by running processes; see evidence)" -f $keptCnt)
        }
    } -Test {
        # 条目级核对：凡报告为"已删除"的条目，必须真的不存在。
        if ($null -eq $script:CleanupPlan) { return $false }   # 本次会话还没执行过 → 需要动作

        $deletable = 0
        $hadItems  = 0
        foreach ($r in $script:CleanupPlan) {
            $deletable = $deletable + $r.Deletable.Count
            $hadItems  = $hadItems + $r.Items
            foreach ($f in $r.Deletable) {
                if (Test-Path -LiteralPath $f) {
                    Add-Evidence ("still present after a successful removal: {0}" -f $f)
                    return $false
                }
            }
        }
        if (($deletable -eq 0) -and ($hadItems -gt 0)) {
            Add-Evidence ("nothing could be removed although {0} item(s) were present" -f $hadItems)
            return $false
        }
        Add-Evidence ("cleanup verified: {0} item(s) removed out of {1} present" -f $deletable, $hadItems)
        return $true
    } -OneShot 'cleanup is a one-shot action: there is no steady state to read back later' 

    # ---- CL2：备份保留 —— 只留当天的备份（机主 2026-09-29 决定）----
    # 背景：备份根会持续累积（每跑一次一个 Svr2Desktop_<stamp>，-Verify 也各一个
    # Svr2Desktop_verify_<stamp>）。机主的决定是**只保留当天**，其余全部清除 ——
    # 注意这不是"把当天之前的清掉"：同一天更早那几次也留（一天多跑是常态，且它们
    # 各自带着一份还原脚本）。
    #
    # ★ 代价写在明处：**删掉旧备份 = 失去回滚到更早状态的能力**。每次运行生成的
    #   还原脚本只回到"本次运行之前"，所以清掉旧的之后，能回滚的最远点就是今天最早
    #   那次运行之前。若哪天要撤销整场调优，只能手工删/卸 —— 别让操作员以为任何
    #   时刻都能一键回到出厂态。
    #
    # 安全约束（删除是破坏性的，一条都不省）：
    #   · 只动备份根的**直接子目录**，绝不递归到别处；
    #   · 目录名必须匹配 ^Svr2Desktop_\d{8}_\d{6}$ 或 ^Svr2Desktop_verify_\d{8}_\d{6}$
    #     —— 认不出的名字一律跳过并列出，绝不"看着像就删"；
    #   · 只删目录，不碰文件；
    #   · 预演（-WhatIf）下 Action 不执行（引擎的步骤级拦截），所以预演里看不到删除清单，
    #     只看到该步骤被标 WHATIF —— 这一点是有意为之：宁可少看，不可误删。
    Add-Step -StageName 'Cleanup' -Id 'CL2' -Title 'Prune the backup root: keep today only' -Action {
        $root = ''
        try { $root = Get-BackupRoot } catch { }
        if (-not $root -or -not (Test-Path -LiteralPath $root)) {
            Write-Note ("backup root not found ({0}) - nothing to prune" -f $root) 'DarkGray'
            return
        }

        $today = Get-Date -Format 'yyyyMMdd'
        $plan  = New-Object System.Collections.ArrayList
        $bytes = [long]0
        $items = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue |
                   Where-Object { $_.PSIsContainer })

        foreach ($d in $items) {
            $stampDate = ''
            if     ($d.Name -match '^Svr2Desktop_(\d{8})_\d{6}$')        { $stampDate = $Matches[1] }
            elseif ($d.Name -match '^Svr2Desktop_verify_(\d{8})_\d{6}$') { $stampDate = $Matches[1] }

            if (-not $stampDate) {
                [void]$plan.Add([PSCustomObject]@{ Path = $d.FullName; Name = $d.Name; Action = 'skipped'; Size = 0; Why = 'name matches neither of the two known session patterns' })
                continue
            }
            if ($stampDate -eq $today) {
                [void]$plan.Add([PSCustomObject]@{ Path = $d.FullName; Name = $d.Name; Action = 'kept'; Size = 0; Why = 'from today' })
                continue
            }

            $size = [long]0
            try {
                $sum = (Get-ChildItem -LiteralPath $d.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                if ($sum) { $size = [long]$sum }
            } catch { }

            try {
                Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop
                $bytes += $size
                [void]$plan.Add([PSCustomObject]@{ Path = $d.FullName; Name = $d.Name; Action = 'removed'; Size = $size; Why = '' })
            } catch {
                [void]$plan.Add([PSCustomObject]@{ Path = $d.FullName; Name = $d.Name; Action = 'failed'; Size = $size; Why = $_.Exception.Message })
            }
        }

        $script:PrunePlan = $plan
        $nRemoved = @($plan | Where-Object { $_.Action -eq 'removed' }).Count
        $nKept    = @($plan | Where-Object { $_.Action -eq 'kept' }).Count
        $nSkip    = @($plan | Where-Object { $_.Action -eq 'skipped' }).Count
        $nFail    = @($plan | Where-Object { $_.Action -eq 'failed' }).Count

        Write-Note ("backup root: {0}" -f $root) 'DarkGray'
        Write-Note ("pruned {0} older session(s), freed {1:N1} MB; kept {2} from today; skipped {3} unrecognised" -f $nRemoved, ($bytes / 1MB), $nKept, $nSkip) 'DarkGray'
        Add-Evidence ("backup prune: removed {0} directory(ies) ({1:N1} MB), kept {2} from today, skipped {3} unrecognised" -f $nRemoved, ($bytes / 1MB), $nKept, $nSkip)
        foreach ($p in $plan) {
            if ($p.Action -eq 'removed') { Add-Evidence ("  removed : {0} ({1:N1} MB)" -f $p.Name, ($p.Size / 1MB)) }
            if ($p.Action -eq 'failed')  { Add-Evidence ("  FAILED  : {0} - {1}" -f $p.Name, $p.Why) }
            if ($p.Action -eq 'skipped') { Add-Evidence ("  skipped : {0} - {1}" -f $p.Name, $p.Why) }
        }
        if ($nFail -gt 0) {
            $script:StepPartial = ("{0} older backup(s) could not be removed (in use or access denied; see evidence)" -f $nFail)
        }
    } -Test {
        # 条目级核对：凡报告"已删除"的，必须真的不存在（与 CL1 同一手法）。
        if ($null -eq $script:PrunePlan) { return $false }   # 本次会话还没执行过 → 需要动作
        $n = 0
        foreach ($p in $script:PrunePlan) {
            if ($p.Action -ne 'removed') { continue }
            $n++
            if (Test-Path -LiteralPath $p.Path) {
                Add-Evidence ("still present after a successful removal: {0}" -f $p.Path)
                return $false
            }
        }
        $kept = @($script:PrunePlan | Where-Object { $_.Action -eq 'kept' })
        Add-Evidence ("backup prune verified: {0} directory(ies) removed; {1} kept from today" -f $n, $kept.Count)
        return $true
    } -OneShot 'backup pruning is a one-shot action: the steady state is "nothing left to prune"'
}

# -----------------------------------------------------------------------------
#  VBS —— 全脚本唯一的安全降级项（默认不执行，需显式选择）
# -----------------------------------------------------------------------------
function Register-VBSSteps {

    Add-Step -StageName 'VBS' -Id 'V1' -Title '[SECURITY DOWNGRADE] Disable VBS / Credential Guard / HVCI' -Action {
        $before = Get-VbsStatus
        [void]$script:Bak.Misc.Add([PSCustomObject]@{ Key = 'VbsStatusBefore'; Value = ($before | Out-String) })

        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -Value 0
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags' -Value 0
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard' -Name 'Enabled' -Value 0
        Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -Value 0

        $after = Get-VbsStatus
        Write-Note ("VBS status before: {0} | after(write): {1}" -f $before.VbsStatus, $after.VbsStatus) 'Yellow'
        Write-Note 'A REBOOT is required before VBS actually stops running.' 'Yellow'
    } -Test {
        # 只校验注册表落盘（VBS 的运行时状态要重启后才会变化）
        $a = Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -Expected 0
        $b = Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LsaCfgFlags' -Expected 0
        $c = Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard' -Name 'Enabled' -Expected 0
        $d = Test-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -Expected 0
        return ($a -and $b -and $c -and $d)
    }
}

function Register-AllSteps {
    Register-DesktopSteps
    Register-PerformanceSteps
    Register-NetworkSteps
    Register-ServicesSteps
    Register-SecuritySteps
    Register-OpsSteps
    Register-DowngradeSteps
    Register-CleanupSteps
    Register-VBSSteps
}

# =============================================================================
#  SECTION 7 — 执行引擎
# =============================================================================

function Write-StepEvidenceLog {
    param([string]$Id, [string]$Evidence)
    # 屏幕可以静音，日志不能：-NoEvidence 只关掉屏幕上的证据行，文件里必须留全。
    # 排障时唯一能回溯"当时到底读到什么"的地方就是这份日志。
    if (-not $Evidence) { return }
    # 证据文本里是**真实**的 CRLF（Get-EvidenceText 用 `r`n 连接），
    # 所以这里用反斜杠正则形式匹配，与全文其余位置保持同一种写法。
    $flat = ($Evidence -replace "\r?\n", ' | ')
    Write-Log ("EVID`t{0}`t{1}" -f $Id, $flat)
}

function Invoke-StepOne {
    param(
        [Parameter(Mandatory)]$StepInfo,
        [Parameter(Mandatory)][string]$StageLabel
    )

    $rec = [PSCustomObject]@{
        Stage = $StageLabel; Id = $StepInfo.Id; Title = $StepInfo.Title
        Status = 'PENDING'; Detail = ''; Evidence = ''
    }

    # 证据链从清空开始：所有读值原语在本步内写下的观察行都属于本步。
    Reset-Evidence
    $script:StepPartial = ''

    # 幂等：先回读。已是期望状态 → 记 SKIP，不重复执行。
    # 有 Probe 的步骤只用 Probe 判断（执行与报告同源），否则回退到 Test 二态。
    if ($StepInfo.Probe) {
        $pr = $null
        try { $pr = & $StepInfo.Probe } catch { $pr = $null }
        if ($pr -and $pr.PSObject.Properties['State']) {
            $st  = [string]$pr.State
            $why = [string]$pr.Why
            if ($st -eq 'OK') {
                $rec.Status = 'SKIP'
                $rec.Detail = 'already in desired state (probe)'
                $rec.Evidence = Get-EvidenceText
                [void]$script:Results.Add($rec)
                Write-Host ("   [ SKIP ] {0,-7} {1}" -f $StepInfo.Id, $StepInfo.Title) -ForegroundColor DarkGray
                # v11.14 摘要视图：SKIP = 已满足、未动手、无变化 —— 屏幕只留判定行，
                # 证据折叠（与 -Verify 折叠 SATISFIED 对偶）。折叠判据**只认 SKIP**：
                # OK / PARTIAL / FAIL / N/A / WHATIF 的证据照印（红线，套件 N 段与
                # 变异 M18/M19/M20 看守）。日志 Write-StepEvidenceLog 不受视图影响。
                if ($Full) { Write-EvidenceLines -Evidence $rec.Evidence }
                Write-Log ("SKIP`t{0}`t{1}" -f $StepInfo.Id, $StepInfo.Title)
                Write-StepEvidenceLog -Id $StepInfo.Id -Evidence $rec.Evidence
                return
            }
            if ($st -eq 'ABSENT' -or $st -eq 'NA') {
                # 本机没有这一项 / 本机场景下无意义 → 不执行动作，也不计进"已优化"。
                $rec.Status = 'N/A'
                $rec.Detail = $why
                $rec.Evidence = Get-EvidenceText
                [void]$script:Results.Add($rec)
                Write-Host ("   [ N/A  ] {0,-7} {1}" -f $StepInfo.Id, $StepInfo.Title) -ForegroundColor DarkCyan
                if ($why) { Write-Host ("            ^ {0}" -f $why) -ForegroundColor DarkCyan }
                Write-EvidenceLines -Evidence $rec.Evidence
                Write-Log ("N/A`t{0}`t{1}`t{2}" -f $StepInfo.Id, $StepInfo.Title, $why)
                Write-StepEvidenceLog -Id $StepInfo.Id -Evidence $rec.Evidence
                return
            }
        }
    } elseif ($StepInfo.Test) {
        $pre = $false
        try { $pre = [bool](& $StepInfo.Test) } catch { $pre = $false }
        if ($pre) {
            $rec.Status = 'SKIP'
            $rec.Detail = 'already in desired state'
            $rec.Evidence = Get-EvidenceText
            [void]$script:Results.Add($rec)
            Write-Host ("   [ SKIP ] {0,-7} {1}" -f $StepInfo.Id, $StepInfo.Title) -ForegroundColor DarkGray
            # v11.14 摘要视图（Test 早退路径）：折叠判据只认 SKIP，-Full 展开。
            if ($Full) { Write-EvidenceLines -Evidence $rec.Evidence }
            Write-Log ("SKIP`t{0}`t{1}" -f $StepInfo.Id, $StepInfo.Title)
            Write-StepEvidenceLog -Id $StepInfo.Id -Evidence $rec.Evidence
            return
        }
    }

    if ($script:WantWhatIf) {
        $rec.Status = 'WHATIF'
        $rec.Detail = 'not applied (-WhatIf)'
        $rec.Evidence = Get-EvidenceText
        [void]$script:Results.Add($rec)
        Write-Host ("   [WHATIF] {0,-7} {1}" -f $StepInfo.Id, $StepInfo.Title) -ForegroundColor DarkCyan
        Write-EvidenceLines -Evidence $rec.Evidence
        Write-Log ("WHATIF`t{0}`t{1}" -f $StepInfo.Id, $StepInfo.Title)
        Write-StepEvidenceLog -Id $StepInfo.Id -Evidence $rec.Evidence
        return
    }

    # ★ 证据分期（v11.7）：能走到这里，说明上面三条"早退"路径（SKIP / N/A / WHATIF）
    # 都没命中 —— 也就是**即将真的执行动作**。前检写下的证据到此封存，缓冲区清空，
    # 动作与后检重新采集。
    # 不封存会怎样：两者首尾相接，真机 SEC12 的 FAIL 块里每行出现两遍，读报告的人
    # 分不出哪一份是动作前的、哪一份是动作后的。而"值有没有移动"恰恰是判
    # "到底写没写进去"的唯一依据 —— 把它埋进重复行里，等于白采集。
    $evBefore = Get-EvidenceText
    Reset-Evidence

    $failReason = ''   # 非空 = 这次 FAIL 自带真实原因（异常文本）；空则交由自洽性守门人裁决
    try {
        & $StepInfo.Action | Out-Null
        if ($StepInfo.Test) {
            $post = [bool](& $StepInfo.Test)
            if ($post) {
                # 动作做到了，但存在无法由本脚本消除的未尽项（如临时目录里被运行中
                # 进程占用的文件）→ PARTIAL。由动作自己通过 $script:StepPartial 提交，
                # 引擎不替它猜。
                if ($script:StepPartial) {
                    $rec.Status = 'PARTIAL'
                    $rec.Detail = $script:StepPartial
                } else {
                    $rec.Status = 'OK'
                }
            } else {
                $rec.Status = 'FAIL'
                # 不再只写一句 "post-check returned false"：证据链已经给出了实测值，
                # 把话说到"哪一项、实测多少、期望多少"为止（见下方两段证据）。
                # 具体措辞由下方按"值有没有移动"再分档。
                $rec.Detail = 'read-back did not reach the expected state (see the two evidence blocks above)'
            }
        } else {
            $rec.Status = 'OK'
            $rec.Detail = 'no read-back defined'
        }
    } catch {
        $rec.Status = 'FAIL'
        $rec.Detail = $_.Exception.Message
        $failReason = [string]$_.Exception.Message
    }

    $evAfter = Get-EvidenceText

    # 证据分期装配：只有真正执行过动作的步骤才有 before 段（见上方封存点）。
    if ($evBefore) {
        $rec.Evidence = "-- before the action --`r`n" + $evBefore
        if ($evAfter) {
            $rec.Evidence += ("`r`n-- after the action --`r`n" + $evAfter)
        } else {
            $rec.Evidence += "`r`n-- after the action -- (no instrumented read-back ran)"
        }
    } else {
        # ★ v11.9：前检一个值都没留痕时，证据块**只有 after 内容、连标头都没有** ——
        # "这一行到底来自哪一侧"于是不可辨（上方那句 "不许凭空造 before 标头" 的规矩
        # 不能破）。反方向上前检有留痕、后检空时，脚本却主动写了
        # "-- after the action -- (no instrumented read-back ran)"。
        # **一侧说了、另一侧没说** —— 而"前检没插桩"正是覆盖缺口最直接的表现，
        # 它得由证据块自己讲出来，读报告的人不该靠"少了哪个标头"去推算。
        # 两条硬约束：
        #   ① 只在 $evAfter 非空时加 —— 两侧都空时 Evidence 必须保持**空**：
        #      那是"零回读"这个事实的表示，摘要里的零证据闸按它触发（塞占位会让闸失灵）。
        #   ② 只在 FAIL 时加 —— 达标/无判据的步骤说这句只是噪音。
        # 措辞刻意**不**叫 "-- before the action --"：那会破坏 H1d 那条
        # "没有前检留痕时不得凭空造 before 标头"的回归红线。
        $rec.Evidence = $evAfter
        if ($evAfter -and ($rec.Status -eq 'FAIL')) {
            $rec.Evidence += "`r`n-- (no pre-action read-back: this step's pre-check is not instrumented) --"
        }
    }

    # FAIL 的措辞按"**值有没有移动**"分档 —— 那是判"写没写进去"的唯一依据，
    # 各档的下一步排查方向完全不同，混成一句等于没说：
    #   两侧一字未变     → 动作没触达这个值（写失败、或写到了别处）
    #   两侧都有且变了   → 动作生效了，只是没到位
    #   只有一侧有证据   → 缺的那一侧根本没插桩（那是**工具覆盖的缺口**，不是动作失败）
    # 异常路径（$failReason 非空）自带真实原因，不覆盖它。
    #
    # ★ v11.9 更正 —— "两侧都空"这一档此处**故意不写措辞**：
    #   本块首次落盘时把它当成独立一档，写了 "nothing was read back: …needs an
    #   instrumented read-back"。与 v11.8 基线对读后确认**那整句是死代码**：
    #   进入本块的条件就是 $failReason 为空，而紧随其后的自洽性守门人
    #   （Get-EvidenceConflict）拿到的 -Why 正是 $failReason，于是它必然命中
    #   "no evidence was recorded at all" 规则、返回非空、覆盖 $rec.Detail，
    #   屏幕前缀也换成 '!!'。
    #   一句话：**有上游覆盖者的档位，写多长的解释都不会有人看见**。
    #   教训：定因时先看清"这句话要经过谁的手"，再决定写到哪一层（技能 §8-45）。
    #   这里只留中性占位 —— 万一日后守门人被改动或移除，留下的也不是假话：
    #   一个值都没读到，谈不上"移动"，旧措辞那句 'the read-back moved' 正是在说假话。
    if (($rec.Status -eq 'FAIL') -and (-not $failReason)) {
        if ((-not $evBefore) -and (-not $evAfter)) {
            $rec.Detail = 'the read-back produced no values at all (the conflict notice that follows explains why)'
        } elseif ($evBefore -and ($evBefore -eq $evAfter)) {
            $rec.Detail = 'nothing changed: the read-back before and after the action is identical (see the two evidence blocks above)'
        } elseif ($evBefore -and $evAfter) {
            $rec.Detail = 'the read-back moved, but not to the expected state (compare the two evidence blocks above)'
        } else {
            $rec.Detail = 'the read-back did not reach the expected state, and only one side produced evidence: the empty side ran no instrumented read-back (this is a coverage gap, not an action failure)'
        }
    }

    # 结论与证据必须自洽（判据与 -Verify 完全同源，见 Get-EvidenceConflict）。两点必须注意：
    #   ① 传入 $failReason 而不是 $rec.Detail —— 上方那句通用措辞不是原因本身，
    #      拿它当原因，守门人会被静音，矛盾就会继续存在；
    #   ② **只喂 after 段** —— before 段里必然带着"动作前不达标"的 MISMATCH，
    #      一起喂进去守门人会被永久静音，而它的全部价值就在于抓
    #      "判负却拿不出 MISMATCH"（见技能 §3.2 (e) 报告自洽性守门）。
    if ($rec.Status -eq 'FAIL') {
        $conflict = Get-EvidenceConflict -Verdict 'FAIL' -Evidence $evAfter -Why $failReason
        if ($conflict) { $rec.Detail = $conflict }
    }

    [void]$script:Results.Add($rec)
    Write-StepEvidenceLog -Id $StepInfo.Id -Evidence $rec.Evidence

    if ($rec.Status -eq 'OK') {
        Write-Host ("   [  OK  ] {0,-7} {1}" -f $StepInfo.Id, $StepInfo.Title) -ForegroundColor Green
        # ★ v11.8：OK 的步骤**也要把证据铺到屏幕上**。
        # 原注释写的是"动作本身已经是证据" —— 那句话正是 v11.5 自洽性守门人被造出来
        # 要杀掉的推理（动作执行成功 <> 达到目标状态）。
        # 真机实证（v11.7 会话 20260921_092704）：P9 是那次运行里**唯一真正执行了动作**
        # 的步骤，屏幕上却一行证据都没有；同时 38 个 SKIP 步骤铺了 100+ 行。
        # 分布是反的 —— SKIP 给的是"我为什么不动手"，而只有走到这里的 OK 才带
        # before/after 两段，那正是"值有没有移动"的唯一现场凭据。
        # 噪音顾虑 v11.14 起由摘要视图接管（SKIP 证据折叠，判据只认 SKIP）；
        # -NoEvidence 仍是整体静音开关（屏幕静音，日志仍完整留痕）。
        Write-EvidenceLines -Evidence $rec.Evidence
    } elseif ($rec.Status -eq 'PARTIAL') {
        Write-Host ("   [PARTIAL] {0,-7} {1}" -f $StepInfo.Id, $StepInfo.Title) -ForegroundColor DarkYellow
        Write-EvidenceLines -Evidence $rec.Evidence
        Write-Host ("               -> {0}" -f $rec.Detail) -ForegroundColor DarkYellow
    } else {
        Write-Host ("   [ FAIL ] {0,-7} {1}" -f $StepInfo.Id, $StepInfo.Title) -ForegroundColor Red
        Write-EvidenceLines -Evidence $rec.Evidence
        if ($conflict) {
            Write-Host ("               !! {0}" -f $rec.Detail) -ForegroundColor Red
        } else {
            Write-Host ("               -> {0}" -f $rec.Detail) -ForegroundColor DarkRed
        }
    }
    Write-Log ("{0}`t{1}`t{2}`t{3}" -f $rec.Status, $StepInfo.Id, $StepInfo.Title, $rec.Detail)
}

function Invoke-StageByName {
    param([Parameter(Mandatory)][string]$Name)

    # 原 'Backup' 分支（snapshot only + WantWhatIf 守卫）于 v12.0 删除：
    # 'Backup' 不是合法 -Stage 取值（Resolve-StageList 会拒 —— 见审计附篇 E1 实测），
    # Start-Optimization 也从不以 'Backup' 调本函数，那段守卫**永远不可达**。
    # 备份仍由 Start-Optimization 在任何改动之前完成（那里有 WantWhatIf 守卫）。
    # 为死代码加固本身是"检查器替不可达路径背书"的信号 —— 删掉比留着更诚实。

    if ($Name -eq 'Desktop' -and $script:HInfo.IsCore) {
        Write-Sub 'Desktop - skipped (Server Core has no desktop shell)'
        Write-Log 'Desktop stage skipped: Server Core'
        return
    }

    $list = $script:Steps[$Name]
    if ($null -eq $list -or $list.Count -eq 0) {
        Write-Sub ("{0} - no steps registered" -f $Name)
        return
    }

    Write-Sub ("{0}  -  {1} step(s)" -f $Name, $list.Count)
    foreach ($s in $list) { Invoke-StepOne -StepInfo $s -StageLabel $Name }

    # v12.0（审计 A-14）：一句话预期管理，不加任何机制。桌面类改动里有一批
    # 要等注销或 Explorer 重启才被看见（任务栏 / 资源管理器默认 / 开始菜单 / 菜单延迟），
    # 而报告会全绿 —— "跑完全绿却没感觉变快"的第一反应是"脚本没用"。
    if ($Name -eq 'Desktop') {
        Write-Note 'note: some desktop changes only take effect after signing out or restarting Explorer.exe (taskbar, Explorer defaults, Start menu, menu delays)' 'DarkGray'
    }
}

function Invoke-VerifyReport {
    # 每轮独立统计（v12.0，审计 A-06）：此前不清 $script:Results，而菜单 [V]
    # 通常是在执行档之后被按下的 —— 于是计数表把"上一轮执行的结果"与"本轮验证的
    # 结果"混算，$fails / $notset / $silent 三个清单同样跨轮混装。与 Start-Optimization
    # 同源修复：入口处清空。
    $script:Results = New-Object System.Collections.ArrayList

    Write-Head 'VERIFY - read-back only, nothing will be modified'
    # ★ 报告必须自证版本（v11.11）：-Verify 由本函数出报告，而它**不经 Show-Banner**
    #   —— Show-Banner 是印版本号的唯一位置。于是这份报告此前完全不携带版本信息：
    #   判定“这是哪一版跑出来的”只能靠**内容特征反推**（例如“脚注出现 且 NOT-SET = 0
    #   则必为 v11.10 之后”）。报告一旦被单独保存、转发，或几周后翻看日志，归因即失效。
    #   对照物就在同一文件里：Start-Optimization 的入口头印 `Svr2Desktop v{VER}`，
    #   本函数是唯一一个不印的入口头 —— 同类不同待遇。
    #   版本号是操作员分辨“手上这版”的唯一标识（v11.9 → v11.10 升版即为此因），
    #   报告里没有它，这个标识就断了。
    #   走 Write-Note 而不是 Write-Host，是为了**同时落日志**（跨会话可查）。
    Write-Note ("script   : Svr2Desktop v{0}" -f $script:VER) 'Gray'
    # 视图自声明（v11.13）：报告必须当场说清读者看到的是摘要还是全量，而不是靠
    # 行数去猜。两路都印（与 evidence coverage 段同一写法），走 Write-Note 同落日志。
    $modeLine = if ($Full) { 'mode     : full (every step prints its read-back evidence)' }
                else       { 'mode     : summary (SATISFIED shows the verdict only; add -Full to expand)' }
    Write-Note $modeLine 'Gray'
    $probedTotal = 0
    $probedSteps = 0
    # ★ 读侧留痕覆盖（v11.8）：探针覆盖率回答的是"多少结论有一手来源"，但没有回答
    # 另一个问题 —— "有没有哪一项**一条实测值都没印**"。真机审计（v11.7 会话
    # 20260921_092704 的 -Verify，逐条数过 43 步）发现 D13 / D14 / SEC3 三项零证据行，
    # 而 -Verify 本该每项都印。其中 SEC3 连 Probe 都没有，一旦判负只剩一个结论词 ——
    # 正是 v11.3 那个"只给结论词"的老毛病最后残留的位置。
    # 这两张表把缺口变成**每轮都可见的事实**，不再靠人肉逐条数。
    $evEmpty = New-Object System.Collections.ArrayList   # 一条证据行都没有的步骤（信息）
    # ★ 真正该报警的是这一个，而不是"有没有证据行"：**未达标、却一个实测值都没印**，
    # 那样的结论不可证伪。D13/D14 恒为零证据行（其探针在该版本上不产证据），
    # 若按"零证据即报警"来标色，就会得到一条永远黄的灯 —— 而"长期黄灯只会训练
    # 操作员无视黄灯"正是本脚本 CL1 当初从 NOT-SET 改成 ONE-SHOT 的理由。
    $evRisk  = New-Object System.Collections.ArrayList   # 未达标且零证据（报警）

    foreach ($name in $script:StageNames) {
        if ($name -eq 'Backup') { continue }
        if ($name -eq 'Desktop' -and $script:HInfo.IsCore) { continue }

        $list = $script:Steps[$name]
        if ($null -eq $list -or $list.Count -eq 0) { continue }

        Write-Sub $name
        foreach ($s in $list) {
            $state = 'UNKNOWN'
            $why   = ''
            $probedTotal = $probedTotal + 1
            if ($s.Probe) { $probedSteps = $probedSteps + 1 }

            Reset-Evidence
            if ($s.Probe) {
                try {
                    $pr = & $s.Probe
                    if ($pr -and $pr.PSObject.Properties['State']) {
                        $raw = [string]$pr.State
                        $why = [string]$pr.Why
                        if     ($raw -eq 'OK')      { $state = 'SATISFIED' }
                        elseif ($raw -eq 'ABSENT')  { $state = 'ABSENT' }
                        elseif ($raw -eq 'NA')      { $state = 'N/A' }
                        elseif ($raw -eq 'NOT-SET') { $state = 'NOT-SET' }
                        else                        { $state = 'UNKNOWN' }
                    } else {
                        $state = 'CHECK-ERROR'
                        $why   = 'probe returned no State property'
                    }
                } catch {
                    $state = 'CHECK-ERROR'
                    $why   = $_.Exception.Message
                }
            } elseif ($s.Test) {
                try {
                    if ([bool](& $s.Test)) { $state = 'SATISFIED' } else { $state = 'NOT-SET' }
                } catch {
                    $state = 'CHECK-ERROR'
                    $why   = $_.Exception.Message
                }
            }
            $ev = Get-EvidenceText

            # 动作型步骤：执行过就没有稳态可回读（清理是典型）。此前它每轮 -Verify
            # 都报 NOT-SET，长期黄灯只会训练操作员无视黄灯，而这条黄灯永不消失、
            # 也不代表任何可行动的事实。改标 [ONE-SHOT] 并说明白。
            if (($state -eq 'NOT-SET') -and (-not $why) -and $s.OneShot) {
                $state = 'ONE-SHOT'
                $why   = [string]$s.OneShot
            }

            # 结论与证据必须自洽：判负却拿不出任何 MISMATCH，说明决定本步的条件没挂钩子。
            # 真机实证（v11.4）：D15 / P9 / SEC12 三例都是"证据全 OK + 结论 NOT-SET"，
            # 操作员看到只会以为报告坏了。守门人在这时候必须开口 —— 见 Get-EvidenceConflict。
            $conflict = Get-EvidenceConflict -Verdict $state -Evidence $ev -Why $why
            if ($conflict) { $why = $conflict }

            # 读侧留痕覆盖（v11.8）：判负可以只给理由，但**一条实测值都不给**
            # 就是不可证伪 —— 那才是要报的。放在这里而不是取值处，是为了让 $state
            # 与 $why 都已被守门人订正过，分类才准。
            if ([string]::IsNullOrWhiteSpace($ev)) {
                [void]$evEmpty.Add($s.Id)
                if (($state -eq 'NOT-SET') -or ($state -eq 'CHECK-ERROR') -or ($state -eq 'UNKNOWN')) {
                    [void]$evRisk.Add($s.Id)
                }
            }

            $tag = '[UNKNOWN  ]'
            $col = 'Yellow'
            if     ($state -eq 'SATISFIED')   { $tag = '[SATISFIED]'; $col = 'Green' }
            elseif ($state -eq 'ABSENT')      { $tag = '[ABSENT   ]'; $col = 'DarkGray' }
            elseif ($state -eq 'N/A')         { $tag = '[N/A      ]'; $col = 'DarkCyan' }
            elseif ($state -eq 'NOT-SET')     { $tag = '[NOT-SET  ]'; $col = 'Yellow' }
            elseif ($state -eq 'ONE-SHOT')    { $tag = '[ONE-SHOT ]'; $col = 'DarkGray' }
            elseif ($state -eq 'CHECK-ERROR') { $tag = '[CHECK-ERR]'; $col = 'Red' }

            Write-Host ("   {0} {1,-7} {2}" -f $tag, $s.Id, $s.Title) -ForegroundColor $col
            if ($why) {
                if ($conflict) { Write-Host ("               !! {0}" -f $why) -ForegroundColor Red }
                else           { Write-Host ("               {0}" -f $why) -ForegroundColor DarkGray }
            }
            # 摘要视图（v11.13）：SATISFIED 的证据行折叠 —— 全绿报告里逐项实测值没人读，
            # 折叠判据**只认状态**：非 SATISFIED（含 FAIL / PARTIAL / NOT-SET /
            # CHECK-ERROR / ABSENT / N-A / ONE-SHOT）证据照印 —— 非 OK 的证据就是
            # 修机的依据，绝不能被视图藏掉（红线，变异 M16/M17 与套件 M 段看守）。
            # 日志（Write-StepEvidenceLog）与 $script:Results 不受视图影响：屏幕减的
            # 是信息出口，不是信息本身。
            if ($Full -or ($state -ne 'SATISFIED')) { Write-EvidenceLines -Evidence $ev }
            Write-Log ("VERIFY`t{0}`t{1}`t{2}`t{3}" -f $state, $s.Id, $s.Title, $why)
            Write-StepEvidenceLog -Id $s.Id -Evidence $ev
            [void]$script:Results.Add([PSCustomObject]@{
                Stage = $name; Id = $s.Id; Title = $s.Title; Status = $state; Detail = $why; Evidence = $ev
            })
        }
    }

    # opt-in 项未启用时，它们在注册表里根本不存在，报告里也就看不到 —— 容易被
    # 误读成"脚本没有这两个能力"。补一段显式说明。
    $optIn = @()
    if (-not $DisableSpooler) { $optIn += 'S6  Disable Print Spooler        - not enabled (add -DisableSpooler)' }
    if (-not $DisableWLAN)    { $optIn += 'S7  Disable WLAN AutoConfig      - not enabled (add -DisableWLAN)' }
    if ($optIn.Count -gt 0) {
        Write-Sub 'opt-in (not enabled)'
        foreach ($o in $optIn) { Write-Host ("   [SKIPPED  ] {0}" -f $o) -ForegroundColor DarkGray }
    }

    # 探针覆盖率：只说"多少项达标"而不说"这些结论有多少是一手读出来的"，
    # 等于让操作员自己去猜报告的可信度。覆盖率是可以被检查的事实，就该印出来。
    Write-Sub 'probe coverage'
    Write-Host ("   {0} of {1} step(s) carry a three-state probe (verdict: OK / ABSENT / NA / NOT-SET)." -f $probedSteps, $probedTotal)
    Write-Host ("   The remaining {0} report through the two-state test fallback; what they read is shown per step (summary view folds SATISFIED evidence; -Full expands it; the log always carries it)." -f ($probedTotal - $probedSteps))
    # ★ 读侧留痕覆盖（v11.8）：与上一行同族的事实 —— 只报"多少结论有一手来源"，
    # 不报"哪些结论一条实测值都没印"，缺口就会长期存在而没人负责（SEC3 就是这样
    # 混过 v11.4 ~ v11.7 四轮的）。
    $evZeroN = $evEmpty.Count
    if ($evZeroN -gt 0) {
        Write-Host ("   evidence coverage: {0} of {1} step(s) recorded at least one evidence line; {2} recorded none: {3}" -f ($probedTotal - $evZeroN), $probedTotal, $evZeroN, ($evEmpty -join ', '))
        Write-Host '   A step can still be covered without an evidence line - its reason may carry the reading (N/A and one-shot steps do this on purpose).'
    } else {
        Write-Host ("   evidence coverage: all {0} step(s) recorded at least one evidence line." -f $probedTotal)
    }
    # 报警条件刻意收窄到"未达标 + 零证据"：正常情况下这一行**不出现**。
    # 它出现就是真问题 —— 那种判负拿不出任何实测值，读者无法证伪（SEC3 在
    # v11.4 ~ v11.7 四轮里就是这个样子，却没有任何一版报告指出过）。
    if ($evRisk.Count -gt 0) {
        Write-Host ("   !! not at target yet, and no read-back values at all - the verdict below cannot be falsified: {0}" -f ($evRisk -join ', ')) -ForegroundColor Yellow
    }
    # 计数口径要说清：这里的总数是**本次注册**的步骤数，而脚本里 Add-Step 出现的
    # 次数会更多 —— opt-in 项（S6/S7）只在传 -DisableSpooler / -DisableWLAN 时才注册。
    # 两个数字都对，但不说明就会被人当成缺陷去查。
    Write-Host '   Count note: opt-in steps (S6/S7) register only when their switch is given,'
    Write-Host '   so this total is smaller than the number of step definitions in the script.'
    Write-Host ''
    Write-Host '   Baseline tip: run -Verify BEFORE applying and keep the output. The delta' -ForegroundColor DarkGray
    Write-Host '   between the two reports is the proof of what this script actually changed.' -ForegroundColor DarkGray

    # 覆盖率的两种口径都落日志，便于跨机器比较"这台机器的报告有多可信"
    Write-Log ("VERIFY-COVERAGE`tprobe={0}`tfallback={1}`ttotal={2}" -f $probedSteps, ($probedTotal - $probedSteps), $probedTotal)
    Write-Log ("VERIFY-EVIDENCE`tzero={0}`trisk={1}`tzero_ids={2}`trisk_ids={3}" -f $evZeroN, $evRisk.Count, ($evEmpty -join '|'), ($evRisk -join '|'))
}

function Save-JsonResult {
    # -Verify 没有备份会话（$script:Bak.Dir 为空），但它同样需要机器可读产物 ——
    # 基线与差集是这套方法论的全部依据（v12.0，审计 A-03）。
    $dir = ''
    if ($script:Bak.Dir) { $dir = $script:Bak.Dir }
    elseif ($script:VerifyDir) { $dir = $script:VerifyDir }
    if (-not $dir) { return }
    $obj = [PSCustomObject]@{
        Version   = $script:VER
        Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Host      = $script:HInfo.Caption
        Build     = $script:HInfo.Build
        Install   = $script:HInfo.Install
        WhatIf    = [bool]$script:WantWhatIf
        Results   = $script:Results
    }
    $p = Join-Path -Path $dir -ChildPath 'Svr2Desktop_result.json'
    try {
        $jsonLines = @($obj | ConvertTo-Json -Depth 5)
        Write-TextFileUtf8Bom -Path $p -Lines $jsonLines
        $script:JsonFile = $p
        Write-Note "json result: $p" 'DarkGray'
    } catch {
        Write-Note "json write failed: $($_.Exception.Message)" 'DarkYellow'
    }
}

function Assert-NoBadResults {
    # 只报"有失败"，不替调用方决定怎么办 —— 2 的意义由 -ExitOnFail 的文档给出。
    $n = Get-BadResultCount
    if ($n -gt 0) {
        Write-Host ''
        Write-Host ("   exit 2: {0} step(s) FAILed or could not be checked (see the summary above)" -f $n) -ForegroundColor Red
        exit 2
    }
}

function Get-BadResultCount {
    # 退出码契约的判据（v12.0）：只算 FAIL 与 CHECK-ERROR。
    # NOT-SET / ABSENT / N-A / ONE-SHOT 都**不是**失败 —— 前者是"还没做"，
    # 后三者是"本机没这一项 / 不适用 / 无稳态"。把它们算成失败，会让无人值守
    # 部署在完全正常的机器上返回 2。
    return @($script:Results | Where-Object { ($_.Status -eq 'FAIL') -or ($_.Status -eq 'CHECK-ERROR') }).Count
}

function Write-Summary {
    Write-Head 'SUMMARY'

    $order = @('OK', 'FAIL', 'PARTIAL', 'SKIP', 'N/A', 'WHATIF', 'SATISFIED', 'ABSENT', 'NOT-SET', 'ONE-SHOT', 'CHECK-ERROR', 'UNKNOWN')

    # 预先把每个状态置 0：FAIL / CHECK-ERROR 即使为 0 也会被印出来。
    # 理由：干净运行此前只印 SKIP/N/A/WHATIF，操作员得靠"没看到红字"去推断没问题 ——
    # 那是缺席的证据，不是可确认的结论。干净应当能被一眼确认。
    # PARTIAL 同理：它是新引入的通道，必须让人看到"这个通道存在且现在是空的"。
    $tally = @{}
    foreach ($k in $order) { $tally[$k] = 0 }
    foreach ($r in $script:Results) {
        $k = [string]$r.Status
        if ($tally.ContainsKey($k)) { $tally[$k] = $tally[$k] + 1 }
        else { $tally[$k] = 1 }
    }

    Write-Host ''
    foreach ($k in $order) {
        $n    = [int]$tally[$k]
        $bad  = (($k -eq 'FAIL') -or ($k -eq 'CHECK-ERROR'))
        $warn = ($k -eq 'PARTIAL')
        if (($n -eq 0) -and (-not $bad) -and (-not $warn)) { continue }
        if ($bad) {
            if ($n -gt 0) { Write-Host ("   {0,-12} {1}" -f $k, $n) -ForegroundColor Red }
            else          { Write-Host ("   {0,-12} {1}" -f $k, $n) -ForegroundColor DarkGreen }
        } elseif ($warn) {
            if ($n -gt 0) { Write-Host ("   {0,-12} {1}" -f $k, $n) -ForegroundColor DarkYellow }
            else          { Write-Host ("   {0,-12} {1}" -f $k, $n) -ForegroundColor DarkGreen }
        } else {
            Write-Host ("   {0,-12} {1}" -f $k, $n)
        }
    }

    $fails = @($script:Results | Where-Object { $_.Status -eq 'FAIL' -or $_.Status -eq 'CHECK-ERROR' })
    if ($fails.Count -gt 0) {
        Write-Host ''
        Write-Host '   Failed items (review before trusting the run):' -ForegroundColor Red
        foreach ($f in $fails) {
            Write-Host ("     - {0,-7} {1}" -f $f.Id, $f.Title) -ForegroundColor Red
            if ($f.Detail) { Write-Host ("               {0}" -f $f.Detail) -ForegroundColor DarkRed }
        }
    }

    # PARTIAL 独立成区：它不是失败（不刷红），也绝不是达标（不冒充绿）。放在
    # "该看什么"的位置上，让操作员一眼看到"这几项没完全做到，原因如下"。
    $partials = @($script:Results | Where-Object { $_.Status -eq 'PARTIAL' })
    if ($partials.Count -gt 0) {
        Write-Host ''
        Write-Host '   Partial (done, with items this script cannot clear):' -ForegroundColor DarkYellow
        foreach ($p in $partials) {
            Write-Host ("     - {0,-7} {1}" -f $p.Id, $p.Title) -ForegroundColor DarkYellow
            if ($p.Detail) { Write-Host ("               {0}" -f $p.Detail) -ForegroundColor DarkYellow }
        }
    }

    # ★ 零证据闸（v11.9）：此前"判负却一条实测值都没印"只在 -Verify 的读侧覆盖
    # 报告里有人看守（Invoke-VerifyReport），**执行模式没有这道闸** —— 而执行模式
    # 恰恰是判负最多的地方。守门人（Get-EvidenceConflict）只能保证"没证据时给一句
    # 声明"，保证不了这句声明被看见。
    $silent = @($script:Results | Where-Object {
        (($_.Status -eq 'FAIL') -or ($_.Status -eq 'PARTIAL')) -and [string]::IsNullOrWhiteSpace([string]$_.Evidence)
    })
    if ($silent.Count -gt 0) {
        Write-Host ''
        Write-Host ("   !! not at target yet and no read-back values at all - these verdicts cannot be falsified: {0}" -f (($silent | ForEach-Object { $_.Id }) -join ', ')) -ForegroundColor Yellow
        Write-Host '      (the step needs an instrumented read-back; the per-step lines above say what it tried to read)'
    }

    # NOT-SET 独立成区（v11.9）：FAIL / PARTIAL 早有逐项列表，唯独"未达标"里最常见的
    # 那一档没有 —— 于是在这台机器上，"重启后必然出现的 P9 + 曾被误判的 SEC12"只能在
    # 一百多行里滚动去找。把它和原因并排放到"该看什么"的位置上。
    $notset = @($script:Results | Where-Object { $_.Status -eq 'NOT-SET' })
    if ($notset.Count -gt 0) {
        Write-Host ''
        Write-Host '   Not at target (target state not held yet - each line says why):' -ForegroundColor Yellow
        foreach ($n in $notset) {
            Write-Host ("     - {0,-7} {1}" -f $n.Id, $n.Title) -ForegroundColor Yellow
            if ($n.Detail) { Write-Host ("               {0}" -f $n.Detail) -ForegroundColor DarkYellow }
        }
    }

    # ★ 脚注独立成块（v11.9 同族扫描发现）：这句话解释的是**上方计数表**里那三个数字
    # 为什么不在缺口清单里 —— 它与“本次有没有 NOT-SET”毫无关系。原先它嵌在
    # `if ($notset.Count -gt 0)` 里面，于是外层条件**不蕴含**内层条件：真机
    # 20260921_102804 实证 N/A = 2 而 NOT-SET = 0 —— 数字印出来了、解释被吞掉，读
    # 报告的人只能上翻两百行去找那两项是什么。
    # 这不是孤例，是 v11.9 修过的“摘要两块被嵌进 if ($partials)”的同一病根：
    # 局部修复时只搬走了点名的那两块，没有扫同族。这一次扫了（107 处门控逐条过一遍）。
    # ★ 刻意**不写**“全脚本只有这一处违反”（v11.11 改写）：那是扫描当时的时点结论，
    #   一旦有人新增一处同型门控，这句话就变成假话，而没有任何检查器会去复查注释。
    #   这类“关于全脚本的量化断言”是可验证的事实，就该交给检查器 —— 见
    #   ps_gate_nesting.ps1 的 -AssertClean：它与一份经人工审查的基线逐条比对，
    #   任何新增 / 消失的门控都被点名待审查。注释只留规则，不留结论。
    # 规则：输出语句的**外层门控条件必须蕴含它自身的适用条件**。凡“覆盖声明 / 脚注 /
    # 证据”这类东西，它描述的是一个**关于数据的事实**，不是数据的一部分 —— 该在
    # 事实成立时印，而不是在某个无关分支被走到时印。
    # 同一文件里的正确写法就在旁边，可以直接对照（同样不写行号，理由见上）：
    #   Invoke-VerifyReport 的 evidence coverage 段：一条印“N printed none”、
    #     另一条印“all N ...” —— 两路都印；
    #   SEC12 的 source 2/3：一条印读到的空值、一条印读到的值 —— 两路都印；
    #   Get-GuiProbe 与 D14 的探针各有兜底出口 —— 终值不是“什么都没说”。
    if (($tally['ABSENT'] -gt 0) -or ($tally['N/A'] -gt 0) -or ($tally['ONE-SHOT'] -gt 0)) {
        Write-Host ''
        Write-Host '   (ABSENT / N/A / ONE-SHOT are not listed as gaps: this build carries no such item / exposes no such knob / has no steady state to read.)' -ForegroundColor DarkGray
    }

    if ($script:Bak.Dir) {
        Write-Host ''
        Write-Host ("   Backup  : {0}" -f $script:Bak.Dir) -ForegroundColor Gray
        Write-Host ("   Log     : {0}" -f $script:LogFile) -ForegroundColor Gray
        $restore = Join-Path -Path $script:Bak.Dir -ChildPath ("Restore_{0}.ps1" -f $script:Bak.Stamp)
        if (Test-Path -LiteralPath $restore) {
            Write-Host ("   Restore : {0}" -f $restore) -ForegroundColor Gray
        } else {
            Write-Host '   Restore : (none - WhatIf run, nothing was changed)' -ForegroundColor Gray
        }
        if ($script:JsonFile) { Write-Host ("   JSON    : {0}" -f $script:JsonFile) -ForegroundColor Gray }
    } elseif ($script:VerifyDir) {
        # -Verify 会话同样留痕（v12.0，审计 A-03）：报告不再只活在屏幕上。
        Write-Host ''
        Write-Host ("   Log     : {0}" -f $script:LogFile) -ForegroundColor Gray
        if ($script:JsonFile) { Write-Host ("   JSON    : {0}" -f $script:JsonFile) -ForegroundColor Gray }
    }

    $line = ("SUMMARY OK={0} FAIL={1} PARTIAL={2} CHECK-ERROR={3} SKIP={4} N/A={5} WHATIF={6} SATISFIED={7} ABSENT={8} NOT-SET={9} ONE-SHOT={10}" -f $tally['OK'], $tally['FAIL'], $tally['PARTIAL'], $tally['CHECK-ERROR'], $tally['SKIP'], $tally['N/A'], $tally['WHATIF'], $tally['SATISFIED'], $tally['ABSENT'], $tally['NOT-SET'], $tally['ONE-SHOT'])
    Write-Log $line
}

# =============================================================================
#  SECTION 8 — 交互界面与主流程
# =============================================================================

function Show-Banner {
    Write-Host ''
    Write-Host ("   Engine  : {0}" -f $script:PSMode) -ForegroundColor DarkGray
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host ("  Svr2Desktop v{0}   Windows Server desktop & responsiveness tuning" -f $script:VER) -ForegroundColor White
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host ("   Host    : {0}" -f $script:HInfo.Caption)
    Write-Host ("   Build   : {0}    Install: {1}" -f $script:HInfo.Build, $script:HInfo.Install)
    Write-Host ("   CPU     : {0} core(s), {1} GB RAM" -f $script:HInfo.CPUCores, $script:HInfo.RAMGB)
    Write-Host ("   PS      : {0}" -f $script:HInfo.PSVersion)

    $vbs = Get-VbsStatus
    $vbsText = 'unknown'
    if ($vbs.VbsStatus -eq 2) { $vbsText = 'RUNNING' }
    elseif ($vbs.VbsStatus -eq 1) { $vbsText = 'enabled, not running' }
    elseif ($vbs.VbsStatus -eq 0) { $vbsText = 'not running' }
    $cg = 'not running'
    if ($vbs.CgRunning) { $cg = 'ON' }
    # 这一行说的是【运行时事实】：VBS 此刻有没有在跑。V1 的断言判的是另一件事 ——
    # "是否已被显式配置为关闭"（要求四个注册表键都等于 0）。在从没配过 VBS 的机器上
    # 本行会显示 not running，而 V1 报 NOT-SET：两者都对，层级不同。为免被读成
    # 自相矛盾，把配置态单独标出来。
    $cfgNote = 'no explicit policy keys'
    if ($vbs.DeviceGuardEnable -eq 0) { $cfgNote = 'explicitly configured off' }
    elseif ($vbs.DeviceGuardEnable -eq 1) { $cfgNote = 'explicitly configured on' }
    Write-Host ("   VBS/CG  : {0}   Credential Guard: {1}" -f $vbsText, $cg)
    Write-Host ("             registry policy : {0}   (V1 needs explicit 0 on 4 keys)" -f $cfgNote) -ForegroundColor DarkGray

    try {
        $pp = Invoke-Native -File 'powercfg' -Arguments @('/getactivescheme')
        Write-Host ("   Power   : {0}" -f (($pp -replace '\s+', ' ').Trim()))
    } catch { }
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
}

function Confirm-Yes {
    param([string]$Prompt)
    if ($Force) { return $true }
    $a = Read-Host ("   {0} [Y/N]" -f $Prompt)
    return ($a -match '^(Y|y)')
}

function Confirm-Reboot {
    <#
      重启的**两步确认**（机主 2026-09-29 定）。

      为什么：重启是本脚本能做出的最打断人的动作，而它偏偏在**写操作全部完成之后**
      才问 —— 一次 Y/N 太容易误触（前面已经按过好几轮确认，手感上很容易一路 Y 下去），
      误触的代价是工作现场直接消失。

      做法：第一次仍是 Y/N（与全脚本其余确认同一手感），通过之后再要求**打出 OK**
      —— 按 Y 会被肌肉记忆带走，打字不会。两次回答都落日志，事后能看清
      这台机器为什么重启过。
      ★ 词从 REBOOT 改成 OK（机主 2026-09-29）：**目的本就是击穿"一次误触 Y"**，
        不需要长词承担更多 —— OK 两下按键，摩擦刚好，也不必让人为一个确认打七个字母。

      -Force 时整个重启提示块根本不会进来（远程/批量部署的既定语义：跳过一切交互），
      所以这里**不需要**额外的跳过开关 —— 加一个只会是多一个没人用的机制。
    #>
    if (-not (Confirm-Yes -Prompt 'Reboot now to apply the changes? (shutdown /a aborts)')) {
        Write-Log 'reboot: declined at the first prompt'
        return $false
    }
    Write-Host '   ★ Second confirmation - the machine restarts immediately and anything unsaved is lost.' -ForegroundColor Yellow
    Write-Host '     Type OK to confirm (any case). Anything else cancels.' -ForegroundColor Yellow
    $a = Read-Host '   Confirm reboot'
    Write-Log ("reboot: first answer Y, second answer '{0}'" -f $a)
    # -eq 对字符串是**大小写无关**的（与 Resolve-StageList 同一个用法），
    # 所以 ok / OK / Ok 都算确认，别的一律取消；空回车也取消（那是最容易被误触的情形）。
    if ($a -and ($a.Trim() -eq 'ok')) { return $true }
    Write-Note 'reboot cancelled at the second confirmation' 'DarkYellow'
    return $false
}

function Start-Optimization {
    param(
        [string[]]$StageList,
        [switch]$BackupOnly
    )

    # 菜单可以连续执行多轮；每轮的结果单独统计，避免上一轮的 FAIL/SKIP 混进来
    $script:Results = New-Object System.Collections.ArrayList

    if (-not $script:Bak.Dir) {
        if (-not $script:WantWhatIf) {
            New-BackupSession -Root $BackupRoot
            # 残留自愈只放在真实执行模式：预演承诺"什么都不改"，包括不删文件。
            Clear-StaleScriptTemp
        }
    }

    Write-Head ("Svr2Desktop v{0}" -f $script:VER)
    if ($script:Bak.Dir) {
        Write-Note ("session  : {0}" -f $script:Bak.Stamp) 'Gray'
        Write-Note ("backup   : {0}" -f $script:Bak.Dir) 'Gray'
    }
    if ($script:WantWhatIf) {
        Write-Note 'MODE     : WHATIF - nothing will be changed' 'DarkCyan'
    }
    # 视图自声明（v11.14）：执行档同样有摘要/全量两档（折叠判据只认 SKIP），
    # 与 -Verify 的 mode 行同一原则 —— 报告当场说清读者看到的是哪一档。
    $execModeLine = if ($Full) { 'mode     : full evidence (every step prints its read-back lines)' }
                    else       { 'mode     : summary (SKIP steps fold their read-back; add -Full to expand)' }
    Write-Note $execModeLine 'Gray'

    # 备份永远排在所有改动之前
    if (-not $script:WantWhatIf) {
        Save-EnvironmentSnapshot
    }

    if (-not $BackupOnly) {
        $ordered = $script:BaseStages
        foreach ($s in $ordered) {
            if ($StageList -contains $s) { Invoke-StageByName -Name $s }
        }

        if (($StageList -contains 'Downgrade') -and (-not $SkipDowngrade)) {
            Write-Head 'SECURITY DOWNGRADE - UAC / Defender / password expiry / alerts'
            Write-Host '   These four swap a security control for convenience. They are never' -ForegroundColor Yellow
            Write-Host '   applied by default and exist in no config file:' -ForegroundColor Yellow
            Write-Host '' -ForegroundColor Yellow
            Write-Host '     SEC10  UAC elevation prompts suppressed (EnableLUA stays 1)' -ForegroundColor Yellow
            Write-Host '     SEC11  Defender real-time protection and services disabled' -ForegroundColor Yellow
            Write-Host '     SEC12  Password never expires (length/complexity untouched)' -ForegroundColor Yellow
            Write-Host '     SEC13  Security Center alerts and tray icon hidden' -ForegroundColor Yellow
            Write-Host '' -ForegroundColor Yellow
            # ★ v11.16：原文案把"降级后的状态"（maxpwage:UNLIMITED）当成 SEC12 的回滚
            # 命令 —— 方向反了，照做等于把降级又执行一遍。密码策略不在还原脚本的
            # 覆盖范围内（见 SEC12 头注与生成脚本自己的 NOT replayable 段），所以
            # 这里只能给"按原值写回"，而原值由 SEC12 的 Action 留档。
            Write-Host '   Rollback: Restore_<stamp>.ps1 rewrites the registry / service values it' -ForegroundColor DarkYellow
            Write-Host '   captured before the run, including the password policy and the Defender' -ForegroundColor DarkYellow
            Write-Host '   preferences (replayed from their pre-run values). Manual equivalents:' -ForegroundColor DarkYellow
            Write-Host '     Set-Service WinDefend -StartupType Automatic' -ForegroundColor DarkYellow
            Write-Host '     net accounts /maxpwage:<the pre-run days>   (recorded in the run log)' -ForegroundColor DarkYellow
            Write-Host '     reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 5 /f' -ForegroundColor DarkYellow
            Write-Host '     reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v PromptOnSecureDesktop /t REG_DWORD /d 1 /f' -ForegroundColor DarkYellow
            Write-Host ''
            if ($script:WantWhatIf -or (Confirm-Yes -Prompt 'Proceed with the security downgrade set?')) {
                Invoke-StageByName -Name 'Downgrade'
            } else {
                Write-Note 'Downgrade stage skipped by operator' 'DarkYellow'
            }
        }

        if (($StageList -contains 'VBS') -and (-not $SkipVBS)) {
            Write-Head 'SECURITY DOWNGRADE - VBS / Credential Guard'
            Write-Host '   Turning VBS off removes hypervisor-based protection of credential' -ForegroundColor Yellow
            Write-Host '   material (NTLM hashes / Kerberos TGT). It buys responsiveness, it' -ForegroundColor Yellow
            Write-Host '   costs a real security control. A reboot is required to take effect.' -ForegroundColor Yellow
            Write-Host ''
            if ($script:WantWhatIf -or (Confirm-Yes -Prompt 'Proceed with disabling VBS / Credential Guard?')) {
                Invoke-StageByName -Name 'VBS'
            } else {
                Write-Note 'VBS stage skipped by operator' 'DarkYellow'
            }
        }
    }

    if (-not $script:WantWhatIf) {
        [void](New-RestoreScript)
    }
    if ($Json) { Save-JsonResult }

    Write-Summary

    if (-not $NoRestartPrompt -and -not $Force -and -not $script:WantWhatIf) {
        $tally = @($script:Results | Where-Object { $_.Status -eq 'OK' })
        if ($tally.Count -gt 0) {
            Write-Host ''
            if (Confirm-Reboot) {
                Restart-Computer -Force
                Write-Log 'reboot: Restart-Computer -Force was issued'
            } else {
                Write-Note 'Reboot postponed. Some changes stay inactive until the next boot.' 'DarkYellow'
            }
        }
    }
}

function Show-Menu {
    Show-Banner
    while ($true) {
        Write-Host ''
        Write-Host '   [1] Desktop experience and responsiveness'
        Write-Host '   [2] Performance, power and visual effects'
        Write-Host '   [3] Network stack'
        Write-Host '   [4] Services (CertPropSvc / Bluetooth; Spooler+WLAN opt-in)'
        Write-Host '   [5] Security hardening (LLMNR, NBT-NS, SMBv1, AutoPlay, WDigest)'
        Write-Host '   [6] Operability (long paths / timezone / Windows Update)'
        Write-Host '   [7] Cleanup whitelisted temp and cache directories'
        Write-Host '   [8] Backup only (snapshot + restore script)'
        Write-Host '   [9] Disable VBS / Credential Guard   <-- SECURITY DOWNGRADE' -ForegroundColor Yellow
        Write-Host '   [10] UAC / Defender / password / alerts  <-- SECURITY DOWNGRADE' -ForegroundColor Yellow
        Write-Host '   [A] All of the above'
        Write-Host '   [V] Verify only (read-back, change nothing)'
        Write-Host '   [Q] Quit'
        Write-Host ''

        $sel = Read-Host '   Choice'
        if ($null -eq $sel) { continue }
        $sel = $sel.Trim().ToUpper()

        switch ($sel) {
            '1' { Start-Optimization -StageList @('Desktop') }
            '2' { Start-Optimization -StageList @('Performance') }
            '3' { Start-Optimization -StageList @('Network') }
            '4' { Start-Optimization -StageList @('Services') }
            '5' { Start-Optimization -StageList @('Security') }
            '6' { Start-Optimization -StageList @('Ops') }
            '7' { Start-Optimization -StageList @('Cleanup') }
            '8' { Start-Optimization -BackupOnly }
            '9' { Start-Optimization -StageList @('VBS') }
            '10' { Start-Optimization -StageList @('Downgrade') }
            'A' {
                # 清单从 $script:BaseStages 派生（v12.0，审计 A-09）：此前是手抄的
                # 七项，新增阶段时会静默漏跑 —— 而漏跑在报告里看不出来。
                $all = @($script:BaseStages)
                if (-not $SkipDowngrade) { $all += 'Downgrade' }
                if (-not $SkipVBS) { $all += 'VBS' }
                Start-Optimization -StageList $all
            }
            'V' {
                New-VerifySession
                Invoke-VerifyReport
                Write-Summary
                if ($Json) { Save-JsonResult }
            }
            'Q' { return }
            default { Write-Note "unknown choice: $sel" 'DarkYellow' }
        }
    }
}

# -----------------------------------------------------------------------------
#  入口
# -----------------------------------------------------------------------------

try {
    # 最先做 -Stage 规范化：非法值必须在任何动作之前被拦下（-Verify 同样适用），
    # 且不能依赖调用方写出正确的数组 —— -File 模式写不出数组。
    $Stage = @(Resolve-StageList -Names $Stage)

    # 宿主前置检查：本脚本只对 Windows 有意义。若 $env:SystemRoot 为空
    # （macOS / Linux，或被裁剪的容器与服务上下文），后续 Join-Path 会在很深的
    # 位置抛一个 null 路径异常，报错完全指不到真正原因。宁可在门口明说。
    if ([string]::IsNullOrEmpty($env:SystemRoot)) {
        throw 'This script targets Windows only: $env:SystemRoot is empty, so the host is not Windows (or is a stripped context). Nothing was changed.'
    }

    $script:HInfo  = Get-HostProfile
    $script:Config = Read-Config -Path $ConfigPath

    if ($DisableSpooler) {
        $script:Config.NeverDisable = @($script:Config.NeverDisable | Where-Object { $_ -ne 'Spooler' })
    }
    if ($DisableWLAN) {
        $script:Config.NeverDisable = @($script:Config.NeverDisable | Where-Object { $_ -ne 'WlanSvc' })
    }

    Register-AllSteps

    if ($Verify) {
        New-VerifySession
        Invoke-VerifyReport
        Write-Summary
        if ($Json) { Save-JsonResult }
        if ($ExitOnFail) { Assert-NoBadResults }
        # v13.3：正常收尾显式给 0。**不要依赖 PowerShell 的默认行为** —— `$LASTEXITCODE`
        # 是**粘的**：脚本里任何一次直接调用的原生命令（读值路径里的 powercfg /query、
        # netsh show global）若返回非零，而之后又没有别的原生命令把它刷成 0，那个非零值
        # 就会成为**整个进程的退出码** —— 于是启动器会喊 "Script exited with code 1"，
        # 而报告里 FAIL = 0。退出码契约（0/1/2）必须与报告一致，且**不受外部命令影响**。
        exit 0
    }

    # -WhatIf 是"全链路预演"，不是"先弹菜单再预演"：既然什么都不写，就没有理由
    # 让操作员再选一遍。此前这里会照常弹菜单，操作员多半顺手选 [V]，于是走的是
    # Verify 分支 —— 一个步骤都不会被预演，"全链路预演"的承诺形同虚设。
    if ($script:WantWhatIf -and ($Stage -contains 'Interactive')) {
        Write-Note '-WhatIf without -Stage: running the full preflight (All), no menu.' 'DarkCyan'
        $Stage = @('All')
    }

    if ($Stage -contains 'Interactive') {
        Show-Menu
        # v13.3：退出菜单即"正常收尾"，显式给 0（理由同上：不能把进程退出码交给
        # $LASTEXITCODE 决定）。菜单模式本就不走 -ExitOnFail —— 成败由操作员的 [Q] 决定。
        exit 0
    }

    $resolved = New-Object System.Collections.ArrayList
    foreach ($s in $Stage) {
        if ($s -eq 'All') {
            # All = 全部用户可见阶段，顺序即 $script:UserStages 顺序；
            # Downgrade / VBS 属安全降级，可用 -SkipDowngrade / -SkipVBS 排除。
            foreach ($x in $script:UserStages) {
                if (($x -eq 'Downgrade') -and $SkipDowngrade) { continue }
                if (($x -eq 'VBS') -and $SkipVBS) { continue }
                [void]$resolved.Add($x)
            }
        } else {
            [void]$resolved.Add($s)
        }
    }

    Start-Optimization -StageList ([string[]]$resolved)

    # 无人值守的退出码契约（v12.0，审计 A-16）。放在 try 内：exit 不是异常，
    # 不会被下面的 catch 接走。
    if ($ExitOnFail) { Assert-NoBadResults }
    # v13.3：走到这里说明"没有 FAIL、或没打开 -ExitOnFail"⇒ 正常收尾 ⇒ 显式 0
    # （同上：不让 $LASTEXITCODE 里残留的原生命令退出码冒充本脚本的结论）。
    exit 0
} catch {
    Write-Host ''
    Write-Host ("   FATAL: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("   At   : {0}" -f $_.InvocationInfo.PositionMessage) -ForegroundColor DarkRed
    Write-Log ("FATAL`t{0}`t{1}" -f $_.Exception.Message, $_.InvocationInfo.PositionMessage) 'ERROR'
    if ($script:IsPS7 -and (Get-Command Get-Error -ErrorAction SilentlyContinue)) {
        Write-Host ''
        Write-Host '   Full error record:' -ForegroundColor DarkRed
        try { Get-Error | Out-String | Write-Host } catch { }
    }
    exit 1
}
