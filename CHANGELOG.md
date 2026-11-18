# Svr2Desktop.ps1 — CHANGELOG

> 本文件由 Svr2Desktop v11.12 精简工程（2026-09-21）从脚本头注释区**原样平移**而来，内容未作任何改写。
> 逐字节版本快照见 `_history/`。v11.12 起的新变更记录续写在本文件末尾。

---
   ── v11.0（2026-09-18，按机主 A/B/C/D/E 编号清单改造）────────────
   [DEL ] D10 经典右键菜单 —— 机主保留 Server 2025 的 Win11 新菜单
   [DEL ] P1 高性能电源方案 + P3 处理器状态 100% —— 电池续航考量
   [DEL ] S2 Windows Search 索引禁用 —— C2 = 不禁用
   [DEL ] SEC6/7/8 审计留痕三项 —— 私人家庭虚机，非工作用途
   [DEL ] SEC9 Defender 加固开启 —— 安全防护交由火绒承担
   [DEL ] OPS1 OpenSSH + OPS2 PSRemoting —— 关闭远程入口
   [ADD ] D15 抑制 OneDrive 同步与 Windows 备份推广（补 v10.0 漏实现项）
   [ADD ] Downgrade 阶段：SEC10 UAC 静默 / SEC11 关 Defender /
          SEC12 密码永不过期 / SEC13 屏蔽安全中心告警
   [FIX ] 跨版本编码陷阱：还原脚本 / 日志 / JSON 改由 Write-TextFileUtf8Bom
          显式写 BOM —— Set-Content -Encoding UTF8 在 5.1 写 BOM、在 PS7 不写
   [FIX ] 电源项改由 Backup-PowerValue 逐项登记，还原脚本可逐项回放
   [FIX ] Bak.Misc 通道此前只写不落盘（等于黑洞），现落 misc_snapshot.txt
   [FIX ] 还原脚本新增长路径说明；Build/PowerPlans 快照保持原样
   ── v11.1（2026-09-18，真机首跑 -WhatIf 暴露的问题）────────────────
   [FIX ] -WhatIf 此前仍会弹出交互菜单，操作员被迫手选，结果是走 Verify
          分支而**从未**真正预演过任何步骤（设计承诺"全链路预演"未兑现）。
          现在 -WhatIf 且未指定 -Stage 时直接按 All 预演，不进菜单。
   [FIX ] $WhatIfPreference 是全局偏好，会连带拦截一切 cmdlet 的
          ShouldProcess：既刷出 20 行模块别名噪音（CimCmdlets /
          ServerManager / SmbShare 加载时），也拦掉脚本**自己**的临时文件
          清理 —— SEC12 的 %TEMP%\svr2desk_pwread_<pid>.inf 会实打实留在
          磁盘上。现在本意存进 $script:WantWhatIf，全局偏好交还 PowerShell，
          预演与否由 Invoke-StepOne 显式判断（步骤级拦截）。
   [ADD ] Verify 四态：SATISFIED / ABSENT（本机无此项，≠ 已优化）/ N/A
          （本机场景下无意义）/ NOT-SET；并附原因行。此前 Test-SvcDisabled
          对不存在的服务返回 $true，会让"本机没这项"显示成 SATISFIED。
   [ADD ] 服务/功能/电源类步骤补 Probe 探针；P2 在单核主机上记 N/A
          （核心停泊无第二个核可停泊，写了也是空写）。
   [FIX ] 头部 VBS/CG 行改报"运行时事实 + 注册表配置态"两层，消除与 V1
          断言（要求四个键显式等于 0）读起来自相矛盾的观感。
   [ADD ] Verify 末尾列出未启用的 opt-in 项（S6 Spooler / S7 WLAN）。
   [FIX ] 新增第六层检查器 ps_whatif_safety.ps1 后，它立刻抓出 Invoke-StageByName
          的 Backup 分支缺 WantWhatIf 守卫 —— 从"Backup 阶段"这条路进来会绕过
          预演、直接写备份文件。已补齐（与 Start-Optimization 的调用点同源）。
   [FIX ] 删除死代码 Set-RegMultiString（定义后从未被调用）。
   [FIX ] Write-Log 的"预演不落日志"由隐式（依赖 $script:LogFile 恰为 $null）
          改为显式（if ($script:WantWhatIf) { return }）。

   ── v11.2（2026-09-18，真机体检数据带回的修正）──────────────────────
   [FIX ] D13 一直在检查 Desktop-Experience —— 这个特性名在 Windows Server 2025
          (build 26200) 的目录里根本不存在（真机实测：Get-WindowsFeature 全表
          263 项，唯一含 "Desktop" 的是 Remote-Desktop-Services）。现代 Server
          (2016+) 的图形界面特性名是 Server-Gui-Shell + Server-Gui-Mgmt-Infra。
          原写法在这类 build 上永远不会命中，探针只能报"本机无此特性"。
          现改为三个候选名逐个检测，主判据换成 InstallationType（一手来源，
          不依赖特性目录），并把"载荷已移除、需安装介质"与"可装未装"分开报。
   [ADD ] Clear-StaleScriptTemp()：启动时扫掉此前遗留的 %TEMP%\svr2desk_*
          —— 步骤内的 finally 覆盖不了 Ctrl+C / 进程被杀，真机上确实观察到过
          残留的 svr2desk_pwread_<pid>.inf。文件名含 PID 的，进程还活着就不碰。
          仅在真实执行模式下清理；预演承诺"什么都不改"，包括不删文件。
   [ADD ] 摘要显式打印 FAIL / CHECK-ERROR（哪怕为 0）—— 此前干净运行只印
          SKIP/N/A/WHATIF，"没看到红字"要靠推断，那不是可确认的结论。
   [DEL ] Get-FeatureProbe 随 D13 改写一并移除（已被 Get-GuiProbe 取代）。

   ── v11.3（2026-09-18，真机执行时暴露的 -Stage 参数绑定缺陷）────────────
   [FIX ] -Stage 的 [ValidateSet] 让"逗号写法"在真机上直接失败。powershell /
          pwsh 的 **-File 参数绑定模型不支持数组**：
            powershell -File Svr2Desktop.ps1 -Stage Desktop,Ops
          整个 "Desktop,Ops" 被当作**单个字符串**绑定到 [string[]] 上（数组只有
          1 个元素），ValidateSet 拿它跟合法名逐个比较 → 抛
          ParameterArgumentValidationError，**脚本体一行都没跑到**。
          讽刺的是文件头 USAGE 里一直写着 `-Stage Desktop,Ops` —— 文档在教一个
          跑不通的写法；而脚本内调用 -Stage @('Desktop','Ops') 一直是好的，
          即"哪种写法能跑"取决于调用者，这不是可接受的接口。
          现移除 ValidateSet，改由 Resolve-StageList 在脚本内规范化：
          逗号 / 分号 / 空格统一拆开、大小写无关匹配、归一成规范写法，
          非法项一次性列全再 throw（避免"改一个报一个"）。
   [FIX ] "合法阶段名"此前在 ValidateSet / All 展开 / 执行顺序三处各写一份，
          新增阶段极易漏改其一。现集中为由 $script:StageNames 派生的三个变量
          （UserStages / BaseStages / ValidStages），其余位置一律引用。
   [ADD ] 入口增加宿主前置检查：$env:SystemRoot 为空（非 Windows / 被裁剪的
           容器或服务上下文）时明确拒绝并说明，而不是在后续 Join-Path 上抛一个
           指不到原因的 null 路径异常。

   ── v11.4（2026-09-18，真机执行日志：四项 FAIL + 报告的可证伪性）────────
   [ADD ] 判定依据链（Evidence Trail）。读值原语在回读时顺手记一行"实测值 vs
          期望值"，执行与 -Verify 都逐步骤打印。起因：v11.3 真机日志里 34 个
          步骤报 SKIP，而报告只给一个结论词 —— 操作员既无法确认"真达标"，
          也无法证伪"探针判错"。这与 v8.1「逐行无条件写完成」是同一类病的
          两种表现：那边是无条件假绿，这边是无法证伪。钩子挂在原语层，因此
          全部步骤一次性获得证据，不必逐个改定义。
   [FIX ] N1（TCP 全局参数）的回读用英文标签正则匹配 netsh 输出。中文版
          Windows 会把标签本地化（"接收方缩放状态 / 自动调整级别"），正则恒
          不匹配 → Test 恒假 → 步骤每次运行都判 FAIL，而设置每次都被白写一遍。
          现改用语言无关的一手来源 Get-NetOffloadGlobalSetting /
          Get-NetTCPSetting，netsh 中英双标签仅作退路。
          ※ 同类缺陷在 powercfg 上早已修过（见 Test-PowerCfgValue 注释），
            当时只修了一处 —— 教训是同类缺陷要一次扫全，不能逐个撞。
   [FIX ] P2（关核心停泊）把"电源设置项在本方案中不存在"与"值不等于 100"
          合并成同一个 $false。虚机的活动方案里没有 CPMINCORES 这一项，于是
          写不进去、也读不到，每次运行都以 FAIL 收场。现由 Get-PowerCfgValue
          把两者分开：不存在 → 探针记 N/A 并附 powercfg 原文；值不对 →
          NOT-SET 并附实测 AC/DC 值与方案名。
   [FIX ] P5 无条件执行 powercfg /hibernate on，失败即抛异常。虚机上该系统
          调用返回"不支持该请求"（虚拟化平台不提供 S4），于是"关快速启动"
          —— 唯一与手感直接相关的半项 —— 每次都被前面那半项连坐。现改为
          不主动改变休眠状态（v8.1 才是关休眠的那一方），只写 HiberbootEnabled=0；
          休眠处于关闭时给出一条可复制的提示，由操作员自行决定。
   [FIX ] CL1（白名单清理）的 post-check 比"目录总字节数是否变小"。临时目录
          是活体：Windows 每秒都在往里写，真机实测 before 6.5 MB / after 6.6 MB
          —— 缓存反而"变大" → 判 FAIL。这个指标与"我们删掉了什么"没有因果
          关系，它是环境噪音。现改为条目级：记录执行前的条目 → 逐条核对是否
          消失；被运行中进程占用而未删除的条目单列并计 PARTIAL。
          ※ C:\WINDOWS\Logs\CBS 的 CBS.log 长期被 TrustedInstaller 持有，
            落在 kept 里属预期行为，输出里会明确标注。
   [ADD ] 执行结果新增 PARTIAL 态（黄）：动作已执行，但存在无法由本脚本消除
          的未尽项。它不冒充达标，也不制造红字疲劳。
   [ADD ] -Verify 对 CL1 这类**不是稳态**的动作型步骤标 [ONE-SHOT]，不再报
          NOT-SET —— 清理没有可回读的稳定状态，长期黄灯只会训练操作员无视黄灯。
   [ADD ] -Verify 末尾报告探针覆盖率（多少步骤有三态探针、多少只靠二态 Test
          回退），并把"先 -Verify 存基线 → 执行 → 重启 → 再 -Verify"写进 USAGE：
          两次报告的差集，就是"这次运行到底改了什么"的证明。
   [FIX ] Resolve-StageList 增加一项容错：剥掉词元两端的引号。起因是把 v11.3
          的绑定修复拿去做冒烟复验时，实测发现 **-File 下没有任何命令行写法能
          传递真正的数组** —— 用独立探针逐个试过：Desktop,Ops / "Desktop, Ops"
          / Desktop;Ops / Desktop / desktop / 'Desktop','Ops' 六种，全部以
          **1 个元素**的 [string[]] 到达；其中 -Stage 'Desktop','Ops'（在
          PowerShell 控制台里写，会被解析成二元素数组）拼成单个字符串时**连字面
          单引号一起**送进来，拆出来是 'Desktop' 与 'Ops' → 必然判非法。这是一次
          响亮但误导的失败（报错说名字非法，真实原因在绑定模型），故直接容错。
          至此"多阶段怎么写"有了确定答案：-File 下只能靠逗号在脚本内拆。

   ── v11.5（2026-09-18，v11.4 真机重启后 -Verify：报告的可证伪性补完）───────
   承接 v11.4 的判定依据链。四项修复全部按预期生效（P2 FAIL→N/A、P5 FAIL→
   SATISFIED、N1 FAIL→SATISFIED、CL1 FAIL→ONE-SHOT；SATISFIED 35→36，
   NOT-SET 7→4），但这一版报告暴露出三类**可信度层面**的新问题：

   【一】报告自相矛盾：证据行全 OK，结论却是 NOT-SET。
         起因是 -Test 里存在**未挂钩子**的手工条件，它们参与判定却不留痕：
           · D15/SEC13 —— Test-Path + GetValueNames 查 Run 键（各一段）
           · P9        —— 走未挂钩子的 Test-TaskDisabled，且失败即提前 return
           · SEC12     —— 整段手写（secedit 导出解析 + Get-LocalUser），
                          一条证据都不产。它是降级档里唯一动密码策略的步骤，
                          失败原因完全不可见，等于 v11.3"只给结论词"复发。
         这比"没有证据"更坏：没有证据时操作员知道自己不知道；证据主动说
         "三项都对"，他只会以为报告坏了 —— 更糟的是去改本来正确的东西。
   [ADD ] Get-EvidenceConflict()：判负（NOT-SET / FAIL）却没给原因、且证据里
          没有任何 MISMATCH（或压根无证据）时，打印一行醒目的
          "!! ... the deciding condition is NOT instrumented"。
          执行引擎与 -Verify 共用同一判据。原则：**报告要么给出理由，要么明确
          声明"这个理由我没采集到"，永不沉默。**
   [ADD ] Test-RegValueAbsent()：给"某键值不应存在"一个带证据的写法（D15 的
          OneDrive / OneDriveSetup、SEC13 的 SecurityHealth 三处改用）。
   [ADD ] Add-Check()：把任意手工条件记成证据行并原样返回，给 secedit /
          Get-LocalUser 这类用不上读值原语的回读一个留痕出口。
   [ADD ] Test-TaskDisabled() 挂上证据钩子（含"任务不存在→视为达标"的妥协）。
   [FIX ] P9 的 -Test 去掉提前 return：全读一遍、全部留痕再合结论（原先第一个
          未禁用任务就退出，其余任务是否达标无从得知 —— 与 v11.2"改一个报一个"
          的接口同病）；SEC12 的两半也改成互不掩盖，任一半失败仍读另一半。

   【二】同一个标签指两个不同的位置。/ Verify 里 D1 的三条证据行有一对字面完全
         相同，实为两个不同位置被渲染成同一个标签：
           HKLM:\SOFTWARE\Microsoft\ServerManager -> Microsoft\ServerManager
           HKCU:\SOFTWARE\Microsoft\ServerManager -> Microsoft\ServerManager
         全是 OK 时只像重复；一旦其中一个失败，操作员会看到两行同标签、一行带
         MISMATCH 一行不带，根本无从判断该改哪一个。
   [FIX ] Shorten-RegPath() 保留 hive 前缀（HKLM\...\Explorer\Advanced 形式）。
          hive 是"同一个键名落在两个位置"的唯一区分手段，不能为省宽度省掉。

   【三】值与字面量不同，但语义达标 —— 三态表缺的第四栏。
         真机 P7 报 NOT-SET，MISMATCH 指向 NtfsDisableLastAccessUpdate =
         -2147483645。那是 0x80000003：bit31 = 系统管理，bit0 = 已禁用。脚本写 1
         （用户管理 + 已禁用），NTFS 把它**规范成**系统管理编码，意图完全一致、
         甚至更正式。字面量比较把一次成功的改动判成了失败。
   [FIX ] Test-RegValue() 新增 -BitSet（掩码内所有位都置位才算达标）与 -Note
          （附注）。P7 改用 -BitSet 1。新增 Format-RegValue()：不常见的数值
          （负数 / >=10）一律附十六进制，"这个怪数字是什么"从此一眼可读。
          位域判定下 -Expected 不参与比较，但仍印在证据行里作为"动作写了什么"
          的参照。

   【四】P2 的 N/A 判对了，但证据不足以让操作员复核。原先 Get-PowerCfgValue
         把"系统明确回答没有这一项"与"我们没解析出来"合并成同一个 Found=$false
         —— 与当年 P2 的三态压成两态是同一个错误，只是升了一层。Why 还只带了
         powercfg 输出的第一行。
   [FIX ] Get-PowerCfgValue() 增 Reason 字段（absent / unreadable）并带出**完整**
          powercfg 输出。P2 探针对应分成两档：absent → N/A（not present on this
          build）；unreadable → NOT-SET（read-back unavailable on this build）。
          两种"不适用"的措辞必须分开，否则"我们的解析器坏了"会伪装成"环境限制"，
          永远没人去修。
   [ADD ] 探针覆盖率段落补一句计数口径说明：报告里的总数是**本次注册**的步骤数，
          比脚本里 Add-Step 的字面出现次数少（opt-in 的 S6/S7 只在传开关时注册）。
          两个数字都对，不说明就会被当成缺陷去查。

   ※ 上机待办：跑一次
       powercfg /query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES
       powercfg /q SCHEME_CURRENT SUB_PROCESSOR
     以定案 P2 属于 absent（环境限制，N/A 正确）还是 unreadable（我们的解析器
     错了，应改判 NOT-SET 并去写）。本节的分档只是让这个结论第一次变得**看得见**。
     ★ 2026-09-18 已定案，见下。

   ── v11.6（2026-09-18，P2 判决性实验：让"读的是哪一块"可见）─────────────
   P2 定案。目标机上跑：
       powercfg /query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES -> 只回 2 行方案头，exit 0
       powercfg /q SCHEME_CURRENT SUB_PROCESSOR                -> 该子组只暴露两项：
                                                                 PROCTHROTTLEMIN / PROCTHROTTLEMAX
   两条**独立路径**（指定 setting 查询 / 列举子组全部设置项）结论一致：这台虚机的
   处理器电源子组不暴露核心停泊。v11.5 的 absent 分档判对了，N/A 成立 —— 是环境
   限制，不是我们的解析器坏了。P2 就此结案：不改判、也不去写。

   但把真机输出固化成夹具做回放时，撞出一个**改进的隐藏代价**（不是 v11.5 的缺陷）：
   取值逻辑"取输出里含 0x 的行的倒数第 2 / 倒数第 1 个 = AC / DC"在**指定了 setting**
   的查询上是对的（那时输出里只有 1 个设置块），却依赖一个从未在真机上确认过的假设
   —— powercfg 确实会按 setting 名裁剪输出。夹具实测：把同一段逻辑用在子组全清单
   输出上，查该机并不存在的 CPMINCORES 会得到 Found=True, AC=100, DC=100（那是
   PROCTHROTTLEMAX 的值）—— **一个 N/A 变成了假绿的 OK**。而 P4 那四项的期望值
   全是 0，真要串了块，报告照样是绿的，看不出来。

   [ADD ] Get-PowerCfgOutputFacts() + Get-PowerCfgBlockNote()：读回时数一数"这份
          输出里有几个设置块、各叫什么"，并把它印进每一条电源证据行：
            [block: DISKIDLE]                   读的就是这一项
            [block: <none>]                     输出里没有设置块（与 N/A 互相印证）
            [blocks: A + B <-- AMBIGUOUS ...]   读到多个块 → 取的值可能属于别的项
          块起点用**结构特征**（含 GUID 的行），不用"跳过前 N 块" —— 单 setting 查询
          只有"方案"一段，子组全清单有"方案 + 子组 + 各设置项"段，层级数不一样。
          块身份用"**块内有没有数据行**"判，阈值取 >=1 而不是 >=2：取 >=2 会把
          "只暴露一个索引的设置项"挤出清单，于是"存在但读法不对"伪装成"不存在"
          —— 假灰比假红更危险，它把缺陷藏进"环境限制"这个看起来完全合理的解释里。
   [KEEP] **取值与判定一字未动。** 本版只做"让前提可见"：这条判据还没在真机上见过
          块数 > 1 的情形，先上机把事实印出来，再决定要不要把取值改成"命中块内取
          位置"。一次上机同时验证 v11.5 的 Fix1-6 与本版的块报告。

   ── v11.7（2026-09-18，v11.6 真机三段闭环：基线 → 执行 → 重启后）──────────
   第一次拿到完整闭环数据。v11.5/11.6 的八项修复**全部通过真机验收**：
   · D15 的第五个条件（HKCU Run\OneDrive）第一次现形，并被动作清除；
   · P7 位域判定生效，SATISFIED（上一版这里还是 NOT-SET）；
   · SEC12 的两半分别可见，失败点精确落到 PasswordNeverExpires；
   · D1 那对"看似重复"的行分得开了（HKLM\… vs HKCU\…）；
   · P2 的 Why 带 [block: <none>] + 系统原文；
   · P4 四行块身份，**零 AMBIGUOUS** —— 上一版设计 C 的判据是"只有出现
     AMBIGUOUS 才说明取值前提不成立"，真机零命中，于是"指定了 setting 的查询
     只输出一个设置块"这个前提**已被真机确认**，候选方案 A/B 正式作废
     （取值逻辑不必改，也就没有回归风险可谈）。
   · 自洽性守门人**全程沉默，且沉默得正确**：所有负判定都带 MISMATCH，
     没有一处"证据全 OK 却判负"。
   净成果：基线 37 达标 → 重启后 38，唯一跨过重启的是 D15。43 步里 37 步本来就
   达标 —— 幂等预检是对的，但这个脚本在这台机器上的边际价值已接近零。

   本轮同时暴露两处新缺陷与一条可疑通道：

   【一】执行视图里证据行成对重复。
         SEC12 的 FAIL 块每行出现两遍（同一份 -Verify 视图只有一遍）。根因：
         Invoke-StepOne 只在入口 Reset-Evidence，前检（Test）与动作后的后检
         （又是 Test）共用同一个缓冲，末尾一次性取走。SKIP 只调一次、-Verify
         每步只调一次 → 都不重复；CL1 是 PARTIAL 也不重复（它的 Test 不产证据
         行）—— 三份日志与这个预测完全吻合。
         代价不止是难看：它把"动作前 vs 动作后"的区分埋掉了，而"值有没有移动"
         恰恰是判"到底写没写进去"的唯一依据（P9 疑案正需要它）。
   [FIX ] Invoke-StepOne 证据分期：即将执行动作时把前检证据封存（$evBefore）并
          Reset-Evidence，动作与后检重新采集（$evAfter）；报告与日志里分带
          "-- before the action --" / "-- after the action --" 标头。
          FAIL 的措辞再按"值有没有移动"分档：一字未变 = 动作没触达这个值
          （写失败 / 写到了别处）；变了但没到目标 = 动作生效了、只是没到位。
          两者排查方向完全不同，混成一句等于没说。
          ★ 自洽性守门人改为**只喂 after 段** —— before 段必然带着"动作前不
          达标"的 MISMATCH，一起喂进去它会为了这个必然出现的标记而永久静音，
          而它的全部价值就在于抓"判负却拿不出 MISMATCH"。

   【二】"调度器读不到"被当成"本机没有"，进而当成**达标**。
         Test-TaskDisabled 原先：Get-ScheduledTask 读空 → 印
         "<not present> -> counted as satisfied" → return $true。
         把全脚本扫过一遍后确认：这是**唯一**一个"读不到即判达标、且没有 Probe
         兜底"的位置 —— 也就是唯一一条能产生假绿的通道（其余同类都有兜底：
         Test-SvcDisabled 由 Probe 接管、Get-SvcProbe 已是 ABSENT 分档、
         D14 有 Probe；Test-RegValue / Test-FeatureInstalled 都往**假红**方向
         倒，是安全方向）。
         而事情恰好就出在它身上：P9 在 v11.6 执行会话报 [ OK ]，重启后的 -Verify
         却又是 NOT-SET（PcaPatchDbTask = Ready）。是"禁用生效后被系统还原"，
         还是"没读到却算了达标"？当时的证据分不出来 —— 因为这两种结局在报告里
         长得一模一样。
   [ADD ] Get-TaskState()：计划任务读值的唯一实现，返回 @{Found;State;Backing;Why}，
          并可用 -Evidence 留痕。**第二条独立路径**：调度器把每个任务存成
          System32\Tasks 下的 XML 文件，文件名与 TaskPath/TaskName 一一对应。
          "调度器读不到、后备文件却在"这种自相矛盾的组合，只可能是我们读值失败
          —— 那时记 read-back unavailable 且**不达标**；两个来源都说没有，才算
          确实不存在。与 P2 用"子组全清单"交叉验证是同一手法。
          Test-TaskDisabled 收薄为单任务包装；P9 的聚合改走
          Get-TelemetryTaskReport（-Tasks 可注入，便于在行为套件里独立测）。
   [ADD ] P9 补三态探针：策略值 + 11 个任务逐一判定，NOT-SET 的 Why **指名**是
          哪个任务、处于什么状态（此前必须先扫 11 行证据去找那一处 MISMATCH）。
          探针覆盖率 12/43 → 13/43。
   [ADD ] Get-TelemetryTaskReport() 由 -Probe 与 -Test **共用**，判据只有一份 ——
          两套读法各判一次就会出现"Probe 说达标、Test 说不达标"的自相矛盾，
          那正是上一轮 D15/P9/SEC12 的病根。
   [FIX ] Get-TelemetryTaskReport 判"没传任务清单"用的是 $null -eq，不是 -not。
          PowerShell 里**空数组是假**，写成 -not $Tasks 时，调用方显式传一份空
          清单会被静默换成脚本级清单 —— 报告于是回一份"别的清单"的结论，而调用方
          要的是"没有任务"。这是"空 vs 未指定"压成同一个分支，与 SEC12 把三态压成
          两态同族。生产路径（P9 的 -Probe / -Test）从不传 -Tasks，走 $null 分支，
          行为不变；本项只修这个新函数自己的边界。

   【三】SEC12 的证据行把三态压成了两态。
         $pneOk = [bool]$u.PasswordNeverExpires —— 属性若取回 $null，
         [bool]$null 同样是 False，于是"读值失败"与"真的是 False"在报告里长得
         一模一样。真机实证：Set-LocalUser -ErrorAction Stop **没有抛异常**
         （否则 Detail 会是异常原文），读回却是 False。是写侧没生效，还是读侧
         把 $null 印成了 False？当时的证据分不出来。
   [FIX ] 读侧改三态：印**原始值**（True / False / <null> / <read failed: …>），
          并引入 net user 做第二条独立来源交叉验证（**不靠标签取值** —— 标签随
          系统语言变化，那正是 N1 当年恒 FAIL 的根因；只把那一行原文摘出来并列
          印，判据仍以 Get-LocalUser 那条为准，免得为了一行说明又引入一处本地化
          依赖）。**写入路径一字未动**：等定案再决定要不要换写入方式。
   [KEEP] SEC12 的写入路径、P4/P2 的取值逻辑、以及所有步骤的判定阈值一字未动。
   ── v11.8（2026-09-21，v11.7 真机三段闭环：基线 → 执行 → 未重启的收口）──────
   v11.7 的三项 Fix **全部通过真机验收**，其中最有价值的一条是"证据分期"：
   · SEC12 的 FAIL 块第一次出现 "-- before the action --" / "-- after the action --"
     两段标头，MISMATCH 每段各一次（v11.6 那种"同一行印两遍"消失）；FAIL 措辞也
     自动落到正确档位："nothing changed: the read-back before and after the action
     is identical"。
   · 同一次运行里 38 个 SKIP 步骤**无一例**带 before 段，只有真正执行了动作的两步
     （P9 / SEC12）才有 —— "只有真执行过才有前检"不是靠注释自证，而是靠 38 个
     反例一起证明的。
   · P9 的 11 个任务逐条留痕，且两类"没有"分得开：<not present> 后面明确写出
     "(no backing file under System32\Tasks)" —— 后备文件也不在，才敢算达标。
   · P9 探针给出精确 Why（"1 of 11 telemetry task(s) still enabled: PcaPatchDbTask
     (Ready)"）：A 档没达标与"我们没读出来"不再混成一句。
   · 净成果 1 项：基线 38 达标 → 执行后 39，唯一跨过的是 P9（PcaPatchDbTask
     Ready → Disabled）。到这一步，本脚本在这台机器上的边际价值只剩两条：
     P9 的重启稳定性、SEC12 判据的真伪。
   本轮又暴露三处新缺陷（都在"报告 / 取证"层，步骤判定阈值仍未动）：

   【四】SEC12 的**第二条独立路径读错了字段**。
         v11.7 用泛匹配 '(?i)expir|过期|到期' 取第一条，而中文 net user 的输出里
         「帐户到期」(Account expires) 排在「密码到期」(Password expires) **之前**
         —— 取到的永远是**帐号**到期，它对几乎所有账户都是「从不」。于是这一行看着
         像佐证、答的却是另一个问题。真机原样：`帐户到期               从不`。
         也就是说，那条"第二条独立路径"**从来没有回答过它要回答的问题** ——
         与 P9 疑案同族：拿一条**看起来同义**的证据冒充第二条路径。
   [ADD ] Get-NetUserPasswordExpiryLine()：只认专名（密码到期 / 密碼到期 /
          "Password expires"），**专名找不到就明说找不到、绝不退回泛匹配**
          （退回就是重犯同一个错）。抽成独立函数，是为了让"给定一份真实输出、
          取到的是哪一行"能在行为层被断言（夹具直接取自真机输出原文）。
   [ADD ] SEC12 补齐三条来源并列取证：① 账户标志（**判据仍在这一条**）
          ② net user 的密码到期专行 ③ Win32_UserAccount.PasswordExpires
          （CIM 结构化字段，完全不依赖语言）。并且：当两条独立来源都指向"永不过期"
          而账户标志读不出 True 时，追加一条 **cross-check conflict** 证据行 ——
          那一行刻意**不带 MISMATCH**（它不是"观察结果不达标"，而是"两条路在打架"；
          混为一谈会让守门人失去判据）。
   [KEEP] SEC12 的**判据一字未动**（2026-09-21 决策：本版只修取证、不换判据）——
          在弄清楚 <null> 的语义之前换判据，等于用一个未知去换另一个未知。
          写入路径同样一字未动。

   【五】执行视图里 **OK 步骤的证据不上屏**，与 Fix A 直接相冲。
         真机实证：P9 是那次运行里**唯一真正执行了动作**的步骤，屏幕上却一行证据都
         没有；同时 38 个 SKIP 步骤铺了 100+ 行。分布是反的 —— SKIP 给的是
         "我为什么不动手"，而只有走到这里的 OK 才带 before / after 两段，那正是
         "值有没有移动"的唯一现场凭据。
         原注释写的理由是"动作本身已经是证据" —— 那句话正是 v11.5 自洽性守门人
         被造出来要杀掉的推理（动作执行成功 ≠ 达到目标状态）。这是一条**显示层的
         假绿通道**，与第四层那个"任务模式整体空转却照样印 100%"同类：藏在
         "看起来合理"的设计意图里。
   [FIX ] OK 分支改为照常调用 Write-EvidenceLines。噪音顾虑交给已有的 -NoEvidence
          开关（屏幕静音，日志仍完整留痕）。

   【六】D13 / D14 / SEC3 在审计视图里**零证据行**。
         逐条数过真机 -Verify 的 43 步，一条证据行都没有的只有这三项；D13/D14
         至少还有 Probe 的 Why 说明处境，**SEC3 是唯一"有 Test、无 Probe、Test 又
         不留痕"的位置** —— 一旦判负只剩一个结论词。这正是 v11.3 那个"只给结论词"
         的老毛病最后残留的地方（它就这样混过了 v11.4 ~ v11.7 四轮）。
   [FIX ] SEC3 的 Test 补读侧留痕：读到什么、期望什么、为什么读不到。同时把
          "属性不存在"与"属性为假"分开 —— 拿"读不到"当"已关闭"就是一条假绿通道。
   [ADD ] -Verify 新增**读侧留痕覆盖**报告行（紧邻既有的"探针覆盖率"）：多少步
          印出了证据行、零证据的是谁，并落日志 VERIFY-EVIDENCE。
          两档刻意分开：零证据只是**事实陈述**（D13/D14 恒为零证据行，若一律标黄
          就是一条永远黄的灯 —— 而"长期黄灯只会训练操作员无视黄灯"是本脚本自己
          写下的教训）；真正**标黄报警**的是"未达标却一个实测值都没印"，
          正常情况下这一行不出现。与既有指标同族：只报"多少结论有一手来源"、
          不报"哪些结论一条实测值都没印"，缺口就会长期存在而没人负责。

   【七】"Environment snapshot" 之后那行进度条残影（v11.6 是 `]    ]`，v11.7 是
         `]                         0s]` —— 长度可变、这次还带上了计时）。
         它出现在 Write-Note 之后、并**吃掉了 Write-Sub 本应留下的那一行空行**，
         说明它是在同一行上被反复覆盖的进度条碎片，而不是某条正常输出。
         快照区只有四条命令（Get-ComputerInfo / Get-Service / Get-WindowsFeature /
         powercfg），其中前两者都可能驱动进度条。
   [FIX ] 脚本开头 $ProgressPreference = 'SilentlyContinue'：既清掉噪音，也给这几条
          只用于"存快照"的命令提速。它是脚本作用域内的偏好，不泄漏到调用方会话，
          也不拦任何写操作（与 $WhatIfPreference 那种全局偏好性质不同，无需交还）。

   【八】P9 的处境需要写清楚：它是**自愈项，不是一次性项**。
         真机两次实证（v11.6 执行 [OK] → 重启后 Not-Set；v11.7 执行前 Ready →
         执行后 Disabled）说明这些任务**跨重启会被 Windows 维护栈重新启用**。
         而"重施"这件事**早已是现状**：本步骤幂等，每次运行都会重新禁用一遍。
         缺的从来不是重施，而是报告里说清它是会被系统还原的自愈项。
   [FIX ] P9 的 Action 只在"确实还没禁用"时才动它（省掉无谓写），并把本次实际
          重施了哪些写进证据；探针的 Why 里也写明自愈性质 —— 否则操作员会把
          "重启后又变 NOT-SET"误读成脚本失效，再花一轮去查一个不存在的问题。

   ── v11.9（2026-09-21，v11.8 真机两份数据：-Stage Desktop 执行 + **重启后** -Verify）─
   ★ 一句话：两个悬案同时定案 —— SEC12 是**永不满足的假红**，P9 是**系统还原**。

   【九】SEC12 的判据读的是一个**不存在的属性**。
         真机 Get-LocalUser -Name Administrator | Format-List * -Force 的属性清单里
         **根本没有 PasswordNeverExpires**（LocalUser 类只暴露 AccountExpires /
         PasswordExpires / PasswordLastSet / PasswordRequired / UserMayChangePassword /
         PrincipalSource / ObjectClass 等 14 项）。于是 v11.6~v11.8 的判据
         "$pneOk = ($u.PasswordNeverExpires …)" **恒为 $false**，而 $null 永远变不成
         True —— SEC12 从 v11.6 起就是一条**永不满足的假红**。
         v11.6 印 False 是 [bool]$null 的强制转换把它藏住了；**v11.7 改印原始值，它才
         现形** —— 定案证据就是那条 <null> 加一份 -Force 属性清单。
         两侧不对称是根因指纹：写入侧从不抛异常（三次 FAIL 都走"通用措辞"分支而非
         异常分支 → Set-LocalUser -PasswordNeverExpires 参数存在且执行过），读取侧
         却读不到值。
   [FIX ] 判据换源（2026-09-21 决策：策略 -1 **且** CIM False）：
         Win32_UserAccount.PasswordExpires —— 微软官方口径 False = 密码过期被禁用，
         且 wmic useraccount set PasswordExpires=FALSE 正是 lusrmgr 里"密码永不过期"
         复选框的等价命令；结构化字段、不依赖语言，**且它就是写侧操作的那个标志**。
         读不到时明文写 <cannot determine>，绝不静默压成 False。
         来源 3/3 换成 Get-LocalUser.PasswordExpires（类里确实存在的属性，空 = 没有
         到期日），仅作佐证；net user 的密码到期专行仍作人可读佐证。
         机实测：策略 -1、net user 密码到期 = 从不、CIM = False —— **目标状态早已
         达成**，预期 SEC12 由 NOT-SET 转 SATISFIED。写入路径一字未动。
         ★ 附带教训："三条独立路径"**必须真的独立** —— 本机策略已是 Unlimited 时，
           三条很可能都在读同一个策略（同一根因的三个视图），不是互相印证。

   【十】P9 悬案结案：**是系统还原，不是脚本缺陷**。
         时序铁证：09:27 执行档 [OK]（Ready → Disabled）→ 09:27 执行后 -Verify
         SATISFIED → 09:52 -Stage Desktop（未动 P9）仍 SATISFIED → **重启后 -Verify
         NOT-SET（PcaPatchDbTask = Ready）**。重启是唯一变量 → Windows 维护栈在启动时
         重新启用它。脚本"每次运行重禁"（幂等）已是正确处置；v11.8 的 self-healing
         说明也如实印出了。**本条不改行为**。
   [ADD ] 摘要新增 "Not at target" 区：NOT-SET 与它的原因并排列出（FAIL / PARTIAL
          早有此待遇，唯独最常见的一档没有，于是这两条只能在滚动里找）。

   【十一】零回读的 FAIL —— 原判"会印出自相矛盾的措辞"，定因**经复核后部分作废**。
         原判断：$evBefore 与 $evAfter **都为空**时落进 else，报告会说 "the read-back
         moved, but not to the expected state（对比上面那两段证据）"—— 而上面一段
         证据都没有；并据此认定"执行模式无人看守"（结论是那道闸只长在 -Verify 里）。
         ★ 与 v11.8 基线逐行对读后更正：**执行模式本来就有人看守** —— Invoke-StepOne
           的分档块之后紧接着就是一次 Get-EvidenceConflict。更关键的是**进入分档块的
           条件正是 `-not $failReason`**，守门人收到的 -Why 因此必为空串，于是它必然
           命中"没有任何证据"那条规则、返回非空、覆盖 $rec.Detail，屏幕前缀也从 '->'
           换成 '!!'。也就是说 v11.8 在零回读下的真实输出是
           "!! no evidence was recorded at all: …"，**并不是**自相矛盾的句子。
           真实缺陷只剩"工具卫生"一级：else 分支把"一个值都没读到"误称为
           "the read-back moved" —— 它看不到（被守门人覆盖），但它是句假话，会误导
           日后改动守门人的人。**"报告在撒谎"与"报告被覆盖"是两件事，我先前混了。**
   [FIX ] FAIL 措辞按"值有没有移动"分档（此前只有 else 一句，把"没动"和"动了没到位"
          混成一句）：
            两侧一字未变     → 动作没触达这个值（写失败、或写到了别处）
            两侧都有且变了   → 动作生效了，只是没到位
            只有一侧有证据   → 缺的那侧根本没插桩（**工具覆盖的缺口**，不是动作失败）
          "两侧都空"这一档**此处不写措辞**：上游有覆盖者，写多长都是死代码 ——
          首次落盘时我正是那样写的，已删。此处只留一句中性占位，保证万一日后守门人
          被改动或移除，留下的也不是假话（"一个值都没读到"谈不上"移动"）。
          教训入技能 §8-45：**定因时先看清这句话要经过谁的手，再决定写到哪一层。**
   [ADD ] 摘要新增零证据闸：任何负判定（FAIL / PARTIAL）而证据为空 → 标黄列出 ID。
          与 -Verify 的那道闸同族、不同源：一个查"读侧留痕覆盖"，一个查"负判定有没有值"。

   【十二】D13 / D14 是"零证据行"的最后两处。
         v11.8 的读侧留痕覆盖报告（真机 43 步）点出 5 项零证据：D13 / D14 / P2 /
         CL1 / SEC11。其中 P2（N/A）、CL1（one-shot）、SEC11（ABSENT）三项**自述里
         就带着读值**，属于正常；**D13 / D14 是真缺口** —— 达标了却看不见凭什么。
   [FIX ] Get-GuiProbe 与 D14 的 -Probe 补读值：InstallationType 一手来源、每个 GUI
          特性的 Installed / InstallState、三个服务的启动类型。标记**分路给**：OK 档
          全标 Ok，NOT-SET 档逐条按真值标，**NA / ABSENT 档照印值但不打不达标标记**
          （不是缺口就不冒充缺口 —— 与"长期黄灯会训练人无视黄灯"同一条教训）。
          预期：零证据清单由 5 项减到 3 项，且剩下 3 项每一项都有自述理由。

   【十三】"Environment snapshot" 之后那行残影（v11.7 是 "]  0s]"，本轮是 "]"，
         真机命令序列里它只出现在执行档、且只出现在快照块之后）。
         v11.8 的 $ProgressPreference = 'SilentlyContinue' **有效**：带计时的那部分
         （Write-Progress）已消失。残留的 "   ]" 已确认**非本脚本所为** —— 全脚本无
         -NoNewline、无 Write-Progress，写不出"半行"。
   [KEEP] 就此结案（2026-09-21 决策）：在变更记录里写明机制边界，不再追。
          不再为它加任何"清行"式防御 —— 那会掩盖真实输出，属于自作聪明。

   【十四】证据块里"哪一侧没插桩"只有一个方向说得出口。
         （★ 本条**不在**原定四项之内，是写行为套件 K 段时"期望变红却没红"逼出来的。）
         装配逻辑分两侧：前检有留痕、后检空 → 主动写 "-- after the action --
         (no instrumented read-back ran)"；反方向（前检空、后检有）→ **一个标头都不打**，
         只剩一行裸内容。于是"这行来自动作前还是动作后"不可辨 —— 而"哪一侧没插桩"
         恰恰决定判负该往哪查。不是笔误：H1d 那条"没有前检留痕时不得凭空造 before
         标头"的规矩不能破，所以**不能靠补标头**解决。
   [FIX ] else 分支补一句尾注 "-- (no pre-action read-back: this step's pre-check is not
          instrumented) --"，与既有那句形成对称。两条硬约束：
           ① 只在 after 非空时加 —— 两侧都空时 Evidence 必须保持**空**：那是"零回读"
              这个事实的表示，摘要里的零证据闸按它触发（塞占位会让闸失灵）；
           ② 只在 FAIL 时加 —— 达标/无判据的步骤说这句只是噪音。
          守门人吃的是 $evAfter **变量**、不是 $rec.Evidence，因此本改动不触及它。
          措辞刻意不叫 "-- before the action --"，以免破坏 H1d 的回归红线。

   【十五】摘要的 ABSENT / N-A / ONE-SHOT 脚注被 NOT-SET 门控吞掉。
         （★ 本条随 **v11.10** 发布；不在原定四项之内，是**上线后真机执行档**逼出来的
           第二处同族缺陷。另起版本号而不并进 11.9 的原因：11.9 已有一份真机执行档，
           文件此后又变，而版本号是操作员分辨"手上这版"的唯一标识，不能两名一物。）
         真机实证（会话 20260921_102804，v11.9 执行档）：计数表印出 " N/A          2"，
         而解释那句话没有出现 —— 它嵌在 `if ($notset.Count -gt 0)` 里面，
         而本次 NOT-SET = 0。外层条件不蕴含内层条件，脚注被连带吞掉。
   [FIX ] 把脚注移出该 if，判据改为"ABSENT / N/A / ONE-SHOT 任一 > 0 即印"。
          措辞与位置（两块之后）不变，属最小修。
   [ROOT] 与【十二】那两处是**同一病根**：局部修复时只搬走了点名的那两块，
          **没有扫同族**。本次补扫了全脚本 107 处门控（工具见
          skills/powershell-hardening-rewrite/scripts/ps_gate_nesting.ps1，
          基于 PowerShell 真 AST，不是缩进猜测），逐条判定"外层条件是否蕴含
          内层内容自己的适用条件" —— 当时 107 处里只有这一处违反。
          ★ 这个数字刻意加上"当时"并点名替代者（v11.11）：这类"关于全脚本的
          量化断言"不再由注释承担，改由 ps_gate_nesting.ps1 -AssertClean 每轮核验
          （与经人工审查的基线逐条比对，新增 / 消失的门控都会被点名待审查）。
          注释里的数字会随代码腐化而无人复查，基线比对不会。详见【十七】。
   [RULE] 输出语句的**外层门控条件必须蕴含它自身的适用条件**。"覆盖声明 / 脚注 /
          证据"描述的是一个**关于数据的事实**，不是数据的一部分 —— 该在事实成立时
          印，而不是在某个无关分支被走到时印。
          同文件的正确写法可直接对照，不必另找范例（**刻意不写行号**：行号随插入
         漂移，且没有任何检查器能发现它过期 —— 见【十七】）：
            · Invoke-VerifyReport 的 evidence coverage 段 —— 一条印 "N printed none"、
              另一条印 "all N ..."，两路都印
            · SEC12 的 source 2/3                        —— 一条印读到的空值、
              另一条印读到的值，两路都印
            · Get-GuiProbe / D14 探针                    —— 各有兜底出口，终值不是"什么都没说"
   [TEST] 行为套件 +3 条：K2f 正例（无 NOT-SET 时脚注照印，且该区不出现）、
          K2g 反例（三计数全 0 时脚注不印，夹具**带** NOT-SET 以排除误读）；
          变异清单 +M14（把脚注焊回 NOT-SET 门控）。套件 149 → 152，变异 13 → 14。
          另：M8 的旧期望 "K2d the footnote appears" 已删除 —— 脚注解耦之后它不再
          随该变异变红，那条绿恰恰是修复生效的证据，留着只会让变异报告误报 MISSED。

   【十六】-Verify 报告不携带版本号，报告无法自证归属。
   [WHAT] -Verify 的报告头只有 "VERIFY - read-back only, nothing will be modified"，
          **不印版本**；命令行 -Verify 直接调 Invoke-VerifyReport，不经 Show-Banner，
          而 Show-Banner 是印版本号的唯一位置。
   [RISK] 判定"这份报告是哪一版跑出来的"只能靠**内容特征反推**（例如"脚注出现 且
          NOT-SET = 0 则必为 v11.10 之后"）。报告一旦被单独保存、转发，或几周后
          翻看日志，归因即失效 —— 而版本号正是操作员分辨"手上这版"的唯一标识
          （v11.9 → v11.10 升版即为此因）。
          与"早期 banner 写死旧版本号"是**一枚硬币的两面**：一次印错、一次不印，
          两者都让归因失效。
   [FIX ] VERIFY 头下补一行 Write-Note "script   : Svr2Desktop v{VER}"，版式与
          执行档的 session / backup 行对齐（9 列 + ": "）。走 Write-Note 而非
          Write-Host，是为了**同时落日志**（跨会话可查）。判定与写入路径一字未动。
   [TEST] 行为套件 +2 条（L 段）：L1 端到端捕获报告输出，断言印出的版本等于
          $script:VER 的值（断言的是**绑定关系**，不是硬编码的版本号）；
          L2 断言该行同时落日志。变异 +M15（删掉该行）。

   【十七】注释里承担了两类**不可维护的断言**：过期行号，与"全脚本只有一处"。
   [WHAT] · 【十五】的对照清单里写死了三处行号（L3916 / L3919 等），而文件在同一
            天内从 4340 行增到 4368 行 —— 这些行号**一轮之内就已过期**。
          · 同一段里写了"全脚本只有这一处违反"，那是 v11.9 扫描的**时点结论**，
            被固化成了**永久事实**。下次有人新增一处同型门控，这句话就是假话，
            而没有任何检查器会去复查它。
   [ROOT] 两者同源：都是"**关于全脚本的量化断言**"写进了注释。注释没有执行者，
          所以这类断言一经写下就**无人负责**。
   [FIX ] ① 对照清单改为写**条件文本**而非行号（"一条印 A、一条印 B，两路都印"），
            条件文本不随插入漂移；
          ② "只有一处"这类断言交给 ps_gate_nesting.ps1 的 **-AssertClean**：与一份
            经人工审查的门控基线（指纹集，**不含行号**）逐条比对，任何新增 / 消失
            的门控都被点名待审查。注释只留规则，不留结论。
   [RULE] 判据：**一条注释如果要靠"现在正好是这样"才成立，它就不该以断言的形式
          存在。** 可执行的事实交给检查器，不可执行的才写注释。
   [TEST] 基线建立后跑一次应报 clean（0 new / 0 removed）。

   本版仍守住一条：**所有步骤的判定阈值与写入路径一字未动**。唯一的判定改动是
   SEC12 换掉一个**永远读不出值**的判据源，依据是属性清单 + 微软官方口径，
   不是为了让数字变绿。
---

 ── v11.12（2026-09-21，臃肿清理：头区变更块移出）────────────
   [MOV ] 变更块 v11.0 → v11.11 共 554 行移出至本文件；脚本头区仅留指向段。
   [DEL ] 无 —— 死代码 Test-KeyExists / Test-TaskDisabled 属 C 方案，本轮未动。
   [FIX ] 判定阈值与写入路径零改动 —— 平移不触碰任何可执行代码；
          语言兼容性 / USAGE / WARNING / 安全模型等状态文档全数保留在脚本头。
---

 ── v11.13（2026-09-21，-Verify 输出精简：摘要视图）────────────
   [ADD ] 参数 -Full：-Verify 摘要视图下逐项展开全部证据行。
   [CHG ] -Verify 默认改摘要视图：SATISFIED 步骤只印判定行，其余状态证据照印 ——
          全绿报告 ~225 行 → ~75 行。红线：非 SATISFIED（FAIL / PARTIAL / NOT-SET /
          CHECK-ERROR / ABSENT / N-A / ONE-SHOT）的证据绝不能被视图折叠。
   [ADD ] 报告头新增 mode 行（summary / full 两路都印），报告自声明视图模式。
   [CHG ] coverage 措辞 printed → recorded：摘要视图下证据行不印但仍逐项采集，
          统计口径从「打印」改为「记录」，与视图解耦。
   [FIX ] 判定阈值与写入路径零改动；日志（Write-StepEvidenceLog）与
          $script:Results（JSON）不受视图影响 —— 屏幕减的是信息出口，不是留痕。
---

 ── v11.14（2026-09-21，执行档输出精简：折叠 SKIP 证据）────────────
   [CHG ] 执行模式默认摘要视图：SKIP（已满足、未动手）的证据行折叠，屏幕只留
          判定行 —— 与 v11.13 折叠 SATISFIED 对偶。全绿执行档 ~230 行 → ~85 行。
   [RED ] 折叠判据**只认 SKIP**：OK（v11.8 决策的 before/after 现场凭据）/ PARTIAL /
          FAIL / N/A / WHATIF 证据照印，绝不被视图折叠（变异 M18/M19/M20 看守）。
   [ADD ] 会话头部 mode 行（summary / full 两路都印）—— 执行档视图自声明。
   [CHG ] -Full 语义统一为「展开全部证据行」，-Verify 与执行档共用。
   [FIX ] 日志（Write-StepEvidenceLog）与 $script:Results 不受视图影响；
          Write-EvidenceLines 头注释同步（原「OK 不调用」为陈旧表述，一并修正）。

 ── v11.15（2026-09-22，Gemini 二审修复：F-01 / F-03）────────────
   [FIX ] F-01 [P1] SEC10 手动回滚提示补第二行：PromptOnSecureDesktop /d 1 ——
          原提示只给 ConsentPromptBehaviorAdmin=5，照做会落入脚本自己在头区
          警告过的 UACME 类绕过口（提示=5 而安全桌面=0）。Restore 脚本本就
          完整还原两值，此处修的是"照手动提示操作"的路径（Gemini 二审发现，
          奥迪到行号核实：L3738 vs 头区 L33-37 自述耦合）。
   [FIX ] F-03 [P2] Restore 服务段补运行状态还原：备份 State=Running 的服务，
          设回 StartupType 后追加 Start-Service（SilentlyContinue）—— 禁停
          的服务（如 DiagTrack）此前还原后仍 Stopped 到重启为止。还原脚本
          头注同步（Gemini 二审发现，Backup-Service State 字段 L445 核实）。
   [RED ] 判定阈值 / 折叠视图 / 证据链零改动 —— 两处均为提示文本与还原脚本
          模板，不动任何采集与判定路径。行为套件 PASS 169 / FAIL 0；
          回放 6/0 与 26/0；AST clean；编码四项全绿；门控基线 1 NEW（即
          F-01 提示行）裁定有意后重录 clean（120 distinct / 121 total）。
   [NOTE] F-02（Bak.Misc 原生命令回放通道）、F-04（SEC12 域账户预检）、
          F-05（powercfg 别名正则，化妆性）本轮未动，见
          Review/2026-09-21_v11.14_Gemini二审.md 时点行动清单。

 ── v11.16（2026-09-28，**宝马线**：机主点单 —— 标题栏完整路径根因修复 + 任务栏结束任务）──
   ★★ 版本号冲突已记录：本仓库里存在**两个 v11.16** —— 上面一条（2026-09-22，特斯拉线，
      第三方审计响应）与下面这一条（2026-09-28，宝马线，机主点单）。两条各自都叫 v11.16、
      内容完全不同，正是本文件反复强调的"**版本号是分辨手上这版的唯一标识，不能两名一物**"。
      成因：宝马机侧在本仓 v11.15 基线上直接改了 v11.16 并推入；特斯拉机侧同时把 v11.15
      推进到 v11.16/v12.0 但当时**本地未纳管 git**，两线各走。
      处置（2026-09-29）：合并两线为 **13.0**（见本文件末尾的合并条目），本条原文保留，
      仅作归属标注 —— 历史记录不改写，避免日后无人能复原当时发生了什么。
   [FIX ] D8 FullPath 配置单元根因修复：标题栏完整路径由 Explorer 从
          HKCU\...\Explorer\CabinetState\FullPath 读取，HKLM 同名键**不被
          Explorer 读取** = 死键。真机实证（本仓首台目标机，Server 2025
          Build 26100）：v11.15 执行档写入 HKLM=1、-Verify 报 SATISFIED，
          标题栏却始终无变化，机主 2026-09-28 仍要求"打开标题栏完整路径"
          时才暴露。写入与断言一并改到 HKCU，HKLM 死键不再写（遗留值无害，
          无需清理）。这是 v8.1 [P0-3]「Defender 无效键」同族错误：写入与
          回读自洽，唯独读这个值的不是 Explorer —— 判据链对，判据对象错。
   [ADD ] D16 任务栏右键「结束任务」：HKCU\...\Explorer\Advanced\
          TaskbarDeveloperSettings\TaskbarEndTask = 1。仅 Win11 风格桌面
          shell（build >= 22000，Server 2025 即此类）存在此设置；经典 Server
          任务栏无此开关，Probe 判 ABSENT（本项不适用），Action 与 Test
          同源条件化（同 D7 TaskbarAl 先例）—— 不对不存在的目标写值
          （D8 教训就地应用）。生效需重启 explorer.exe。
   [RED ] 判定阈值 / 折叠视图 / 证据链引擎零改动；新增步骤走既有
          Add-Step { Action, Test, Probe } 框架，证据行由 Test-RegValue /
          Add-Evidence 标准原语产出。改前快照 _history/Svr2Desktop_v11.15_*.ps1.bak。
   [NOTE] 主机侧（宝马）学习走读后落地本版；行为套件 / 门控基线等
          特斯拉机侧检查器不在本仓，本轮未跑 —— 建议特斯拉下次拉取后
          补跑并对 D8 的新判据做一次真机 -Verify 对照（HKLM 旧值机器上

 ── v11.16（2026-09-22，第三方审计（奥迪 · 主机侧）响应：B-00 假绿复现 / A-02 回滚口径 / 入口收敛）──
   审计报告：`WinTools/Svr2Desktop_Audit_2026-09-22.md`（编号 A-01~A-16 / B-00~B-04）。
   本轮只动五件事，**其余判定阈值与写入路径一字未动**。
   [FIX ] B-00 [P2] powercfg 取值前提被破坏时，判据此前毫无反应 —— 会出**假绿**。
          Get-PowerCfgOutputFacts 自 v11.6 起把"这份输出里有几个设置块"印进证据行，
          但处置是"只报告、不据此改判"，理由是当时还没在真机上见过块数 > 1 的情形。
          该阶段已结束：v11.7 在 P4 四项上零 AMBIGUOUS，"指定 setting 的查询只输出
          一个块"这条前提在该 build 上被真机确认。
          本地夹具复现出的假绿（macOS + pwsh 7，伪造 powercfg 喂真机形态输出）：
          查 DISKIDLE，而输出里另有 DISKIDLETIMEOUT 一块、其值为 0 →
          脚本读到 AC=0（那不是 DISKIDLE 的值，真实值是 0x1e）→
          Test-PowerCfgValue -Expected 0 判 **True**，而证据行里明明写着 AMBIGUOUS。
          证据说了话、判据不听 —— 与 SEC3 那条"属性不存在 ≠ 属性为假"同族。
          现改为短路：块数 > 1 → Reason = 'ambiguous'、Found = $false，判负不冒充绿。
          代价：该档下 Backup-PowerValue 登记 $null → 还原脚本跳过该行。
          "少还原一项"优于"回放一个我们都没读准的值"。单块输出（今天的目标机形态）
          行为**逐字节不变** —— 本地夹具 A 档复跑结果与打补丁前完全一致。
   [FIX ] 措辞随 Reason 分档（三处）。Reason 变三档之后，"没读到"就必须说清是哪一档，
          否则 ambiguous / unreadable 会被写成 "the active scheme exposes no such
          setting"（一句在那些档上**是假话**的结论），或写成 "read-back unavailable
          on this build"（把"我们的读法有问题"伪装成"环境限制" —— 假灰比假红更危险）。
          涉及 Test-PowerCfgValue 的缺值措辞、Set-PowerCfgValue 的写后读回提示、
          P2 探针的 NOT-SET 措辞。
   [FIX ] A-02 [P2] 降级风险摘要里 SEC12 的"手动回滚"命令**方向反了**：原文给的是
          `net accounts /maxpwage:UNLIMITED` —— 那正是降级后的状态，照做等于把降级
          又执行一遍。同段 SEC10 的两条 reg add 方向是对的（v11.15 F-01 刚修过），
          只有这一条错。而正确处理只能是"写回原值"，于是——
   [ADD ] SEC12 先留档改动前的 MaximumPasswordAge。本步骤走 secedit + Set-LocalUser，
          两条都不经过 Reg / Svc / Task / Feat / Power 任何一个备份通道，还原脚本对它
          **零覆盖**；没有原值，那个回滚提示无论怎么写都不可能正确。
          Action 开头用 secedit /export 导出 SECURITYPOLICY、按固定英文键名取
          MaximumPasswordAge，落进 Bak.Misc（→ misc_snapshot.txt，键名为
          MaximumPasswordAgeBefore），屏幕与日志各留一行。临时 inf 带 PID，
          由既有 Clear-StaleScriptTemp 兜残。
   [CHG ] 还原脚本头注口径收窄：原文写 "Rolls the machine back to the state captured
          immediately BEFORE the run"，而它实际只回放 Reg / Svc / Feat / Task / Power
          五条通道。现改为逐条列明，并追加 "NOT replayable here" 段（密码策略、TCP
          全局参数、SMBv1、Defender 偏好、清理阶段删掉的文件）。宁可口径窄，不要宽承诺。
   [CHG ] 入口收敛：不再附 .cmd 启动器，直接以管理员身份跑 .ps1（脚本自带
          #Requires -RunAsAdministrator，未提权会明确拒绝而不是静默半途失败）。
          USAGE 首段改为入口说明，并写明两条 Windows 默认行为：双击 .ps1 的默认动作是
          「编辑」而非运行；文件来自网络 / 共享时先 Unblock-File，执行策略受限时用
          -ExecutionPolicy Bypass。
   [DEL ] POWERSHELL 7 ENHANCEMENTS 删掉 $PSStyle 一项：全脚本零引用，属文档空头承诺
          （审计 A-13）。Test-Json 与 Get-Error 保留 —— 两者在代码中真实使用。
   [TEST] 本轮**可执行**的验证（本机 macOS + pwsh 7；源文件由真 AST 抽函数后
          dot-source，未改一行）：
            · AST 解析 0 error；UTF-8 with BOM + CRLF 保持；
            · E1 Resolve-StageList 六形态 + 非法项（含 Backup 被拒）全通过；
            · E2 net user 密码到期专行 zh / en 均取对、不退回泛匹配；
            · E3 A 档（单块）与打补丁前逐字节一致；B 档（多块）由假绿转为判负，
                 证据行 <read-back ambiguous> + MISMATCH；
            · E4 Get-TaskState 第二来源 / Unread 与 Absent 分档 / 显式空清单边界全通过；
            · E5 宿主守卫 FATAL 退出码 = 1；-Stage 规范化先于宿主检查。
          复跑物：`WinTools/_local_probe_macos/`（run.ps1 / scan.ps1 / 夹具 / 伪造 powercfg）。
   [NOTE] 未复核：行为套件（PASS 169 那套）、门控基线 -AssertClean、变异清单、回放夹具
          本轮**均未运行** —— 它们的宿主目录 skills/powershell-hardening-rewrite/scripts/
          不在本机。本版 [TEST] 不继承 v11.15 的任何既有结论，需在拿到工具目录后补跑。
          这是本版唯一的已知验证缺口。
   [NOTE] 未动（仍挂在审计报告的时点行动清单上）：A-01 的其余部分（即 F-02 的 Bak.Misc
          原生命令回放通道：SEC11 的 Set-MpPreference / SEC3 的 SMBv1 / N1 的 netsh）、
          A-03（-Verify 不落日志、-Json 双重失效）、A-04（NeverDisable 可被 json 清空）、
          A-05（5.1 下 2>&1 + EAP=Stop，待真机一行定论）、A-06、A-07、A-10 ~ A-16。
          B-01 ~ B-04 随 .cmd 退场而失效（原文件移入 _local_probe_macos/ 备查）。
---

 ── v12.0-preview（2026-09-22，收口：审计剩余项 + 原生命令回放通道 + 入口重排）──
   ★ 这是 V12 发布前的**最终预览版**。虚机验证通过后，正式版把 $script:VER 改为
     '12.0'、文件名改回 Svr2Desktop.ps1（脚本内 13 处自引用要一并改回），
     其余一字不动。预览与正式版**必须**有不同的版本号 —— 报告要能归因。
   审计报告：`WinTools/Svr2Desktop_Audit_2026-09-22.md`（A-01~A-16 / B-00~B-04）。

   [FIX ] A-01（与 Gemini F-02 同源的那一半）**原生命令回放通道** Backup-NativeCommand：
          secedit 写的密码策略、netsh 改的 TCP 全局参数、Set-SmbServerConfiguration
          改的 SMBv1、Set-MpPreference 改的 Defender 偏好 —— 这四类改动没有任何
          Reg / Svc / Feat / Task / Power 通道能表达，此前**只被写入**：既无原值、
          也无回放路径。最刺眼的是 SEC11 —— 策略键与服务都还原了，实时防护却还是
          关的，而还原脚本的自述是"回滚到运行前状态"。
          现在每个条目是一条**可回放的 PowerShell 源码行**，由**调用方自己给出**
          （读原值 → 拼回放语句）：只有它知道那条命令的正确等价物是什么。生成器
          只负责原样排进还原脚本的 native commands 段，不做任何解释与推测。
          读不到原值时调用方给一句[SKIP]说明（而不是一个猜的值）—— 宁可留白，
          也不回放一个我们没读准的值。SEC12 的 v11.16 留档产线（Bak.Misc）随之并成
          这一条，不再为同一件事记两处。
   [CHG ] 还原脚本与脚本头注的"可还原"口径第二次收窄：现在只剩两类不可回放 ——
          清理阶段删掉的文件（删除没有撤销），以及本 build 读不出状态的 TCP
          heuristics 开关。
   [FIX ] A-03 `-Verify` 终于有留痕去处。该模式不建备份会话（那会写快照并生成还原
          脚本，与只读语义相悖），而 $script:LogFile 只在备份会话里被赋值 → Write-Log
          直接 return，**整份报告只活在屏幕上**；-Json 也不是有效产物（入口提前
          return + Save-JsonResult 要求 Bak.Dir 非空，双重失效）。而本脚本推荐的
          核心方法论恰恰是"两次 -Verify 的差集就是本次改动的证明"—— 差集要靠留档
          才存在。现在只开一个落点：与备份同根、目录名带 verify_ 前缀，不写快照、
          不生成还原脚本；目录建不出来时明说并退回旧行为（静默失败会让人以为有日志）。
          预演下不建 —— 预演承诺"什么都不写"，日志也不例外。
   [FIX ] A-06 菜单 [V] 与执行档混算统计。Invoke-VerifyReport 此前不清 $script:Results，
          而 [V] 通常是在执行档之后被按下的 —— 计数表把上一轮执行的结果与本轮验证的
          结果混算，$fails / $notset / $silent 三个清单同样跨轮混装。入口处清空。
   [FIX ] A-04 `NeverDisable` 是**守卫**，内置清单是地板：json 只能往上加，不能往下削。
          此前它是普通白名单键、被 json 无条件覆盖，一个 {"NeverDisable": []} 就能把
          Spooler / RpcSs / EventLog 这些守卫全部清空 —— 与"安全降级不能被旁边的 json
          悄悄打开"是同一条规矩的另一面。
   [FIX ] A-07 D14 的存在性判据换成 Get-Service。Get-SvcStartMode 在"服务不存在"与
          "CIM 查询失败"两种情况下都返回 $null，拿它判存在，会让"我们读不出来"伪装成
          "本机没有这一项"（→ ABSENT，语义是"不是缺口"）—— 假灰比假红更危险。
          P9 当年正是用第二条独立来源解决同一类问题，服务这条线漏了。
   [FIX ] A-10 N2（Nagle）与 SEC2（NetBT）补三态探针：此前没有 Probe，而 Test 在
          "接口枚举为空"时返回 $false → **永久 FAIL**，而长期红灯与长期黄灯一样会让
          操作员无视颜色。现在记 NA（本机没有接口键，既不是缺口也不是失败），
          证据只印一行汇总（与 Get-SvcGroupProbe 同一取舍）。
   [FIX ] A-08 N1 标题承诺三项、回读只覆盖两项 —— heuristics 在
          Get-NetOffloadGlobalSetting / Get-NetTCPSetting 上没有对应属性，而 netsh 的
          本地化文本刻意不解析。补一条证据行明说"写了、但回读不到"：覆盖缺口必须留痕，
          不留痕的缺口永远没人修（SEC3 就这样混过 v11.4~v11.7 四轮）。
   [FIX ] A-11 P9 的证据措辞分档：原文案说这些任务是 "still enabled when this run read
          them"，可"读不到"那一档根本没读到启用状态 —— 证据说了它支持不了的话，
          正是守门人专门要杀的形态。现在"调度器报启用"与"状态读不出"分两句。
   [FIX ] A-12 P7 的 NtfsMftZoneReservation 加 Note：该设置只对**新建卷**生效，
          现有卷上写入不改变布局 —— 值达标 ≠ 效果存在，必须把机制说清；
          WARNING 段补 8.3 短名关闭的兼容性代价（本脚本少见的兼容性代价项）。
   [FIX ] A-15 CL1 的递归删除加**重解析点守卫**。Windows PowerShell 5.1 的
          Remove-Item -Recurse 会跟随目录 junction / symlink 删掉**目标**里的内容 ——
          那是越界删除，而 v8.1 的整盘 del /s 被删除正是为这一类。这里是全脚本唯一
          残余的递归删除点。现在遇重解析点只登记进 Kept（原因写明是"结构"而不是
          "被占用"），不递归、不删链。
   [FIX ] A-05 Invoke-Native 在**函数作用域内**把错误偏好降为 Continue 再重定向 stderr。
          5.1 有一个已知行为：原生命令的 stderr 被 2>&1 重定向进成功流时，记录会以
          NativeCommandError 走错误管线，在 Stop 下成为终止性错误 —— 真若如此，
          -AllowNonZero 的逃生口会被静默封死，报错文本还会变成 NativeCommandError
          而不是本函数精心构造的那句"哪个命令、退出码多少、输出什么"。本函数本来
          就逐条检查 $LASTEXITCODE，不需要错误管线代劳。改后 5.1 与 7 行为一致。
   [ADD ] A-16 退出码契约 -ExitOnFail：0 = 无失败，2 = 有 FAIL / CHECK-ERROR，
          1 = 致命错误。判据只算 FAIL 与 CHECK-ERROR —— NOT-SET / ABSENT / N-A /
          ONE-SHOT 都不是失败，算进去会让无人值守部署在完全正常的机器上返回 2。
          只对命令行模式生效：交互菜单里退出码属于操作员的 [Q]。
   [DEL ] A-16 删掉 Invoke-StageByName 的 'Backup' 分支：'Backup' 不是合法 -Stage
          取值（Resolve-StageList 会拒，见审计附篇 E1 实测），Start-Optimization 也
          从不以它调本函数，那段 WantWhatIf 守卫**永远不可达**。为死代码加固本身是
          "检查器替不可达路径背书"的信号。
   [ADD ] A-14 Desktop 阶段结束后一句提示（不加机制）：部分桌面改动要等注销或
          Explorer 重启才被看见，而报告会全绿 —— "跑完全绿却没感觉变快"的第一反应
          是"脚本没用"。
   [CHG ] 入口重排：脚本改名 `Svr2Desktop_v12-preview.ps1`（脚本内 13 处自引用同步），
          双击入口 `Svr2Desktop_v12-preview.cmd` 随行。.cmd 只做四件事（找同名 .ps1、
          选宿主、提权一次、双击时留窗口），并修掉此前四条缺陷：
            · pause 只对"无参数"生效 —— 否则计划任务/cmd /c 也会命中，与它自己头注里
              的 unattended 用法直接矛盾；
            · 提权探针从 `net session` 换成 `fltmc` —— 前者依赖 Server 服务，服务一停
              已提权也判成未提权，会触发静默重入；
            · 重入加 SVR2D_RUNAS 标记（Start-Process 继承环境块），彻底掐断重入循环；
            · 分支一律用 goto 而非括号块 —— cmd 会在执行前展开 %ARGS%，里面一个 ")"
              就能把括号块解析坏。
          .cmd 内不再出现任何脚本名校字面量：%~n0 决定 .ps1 名，两个文件一起改名即可。
   [TEST] 本轮实测（本机 macOS + pwsh 7；源文件由真 AST 抽函数后 dot-source，未改一行）：
            · AST 解析 0 error；UTF-8 with BOM + CRLF 保持；
            · E3 A 档（单块输出＝目标机形态）与打补丁前逐字节一致 → **目标机零回归**；
              B 档（多块）由假绿转判负，证据行 <read-back ambiguous> + MISMATCH；
            · E7 **生成的还原脚本可被 AST 解析（0 error）**，native commands 段结构正确
                  （这一条此前从没有过 —— 没有人 AST 校验过生成物）；
            · E7b -Verify 会话在非 Windows 上下文下如实降级、不抛异常；
            · E8 退出码：无失败 0 / 有 FAIL 2 / 只有 NOT-SET+ABSENT+ONE-SHOT 0 /
                 CHECK-ERROR 2；
            · E1 / E2 / E4 / E5 维持原判（Resolve-StageList 六形态、net user 密码到期
                 专行、Get-TaskState 双来源与空清单边界、宿主守卫）。
          复跑物：`WinTools/_local_probe_macos/`（run.ps1 / run2.ps1 / run3.ps1 / scan.ps1 /
          夹具 / 伪造 powercfg / 历代补丁脚本）。
   [ROOT] 本轮自撞的两个坑，都由 E7 这个新夹具撞出来 —— 它们证明"生成物也要被解析"
          不是洁癖：
            ① 生成回放行时用了单引号串，而单引号串里反引号不是转义符，于是生成的脚本
               带一个裸反引号 → AST 报 Missing closing }；
            ② 改成一行拼接后，"原值读不出"那一档给的是**注释**，`#` 把后面的 `}`
               一起吃掉了 → 同样两个语法错误。
          教训：生成器必须对回放文本免疫 —— 回放语句独立成行放在 try 里，谁给什么
          文本都不会破坏结构。（② 的形态与"局部修复没扫同族"同源：改一行时只想着
          正常值，没想到同一字段还会被喂进注释。）
   [NOTE] 未复核：行为套件（PASS 169 那套）、门控基线 -AssertClean、变异清单**本轮
          仍未运行** —— 宿主目录 skills/powershell-hardening-rewrite/scripts/ 不在本机。
          本版 [TEST] 不继承任何既有结论；这是本版唯一的已知验证缺口，需在拿到工具
          目录后补跑。
   [NOTE] 仍挂着的（本轮之外）：A-01 里与 F-02 相关的回放**覆盖度**（SEC11 的六项偏好
          之外是否还有其他 Set-MpPreference 项、netsh 的其他全局子命令）需真机跑一次
          还原脚本实测；B-00~B-04 除 .cmd 三条外，B-00 已在 v11.16 修完。
---

 ── v12.0-preview2（2026-09-22，真机双轨验证带回的两处证据文案）────────────
   ★ 为什么另起版本号而不并进 preview：preview 已产生**两份真机 -Verify 基线**
     （20260922_135633 走 PS7、20260922_140106 走 5.1）。文件此后又变，而版本号
     是操作员分辨"手上这版"的唯一标识，不能两名一物 —— 与 v11.9 → v11.10 同一条
     理由。文件名不变（Svr2Desktop_v12-preview.ps1），归因靠 $script:VER。
   ★ 本版只动**两处证据文本**：判定阈值、写入路径、回放通道一字未动，
     故执行结果与 preview 逐字节等价，已存基线可继续复用。
   [FIX ] C-01 [观察] D12 的期望值 100 是**统一基准值**，不是"越小越好"。
          Windows 默认 MenuShowDelay / MouseHoverTime 都是 400，从默认出发这两项是
          加速；但真机是一台被前任优化到 50 的机器 —— 对它而言这一项是**减速**。
          50ms 与 100ms 都在"即时"阈值以内、人不可感，因此刻意**不**引入"只快不慢"的
          不等式判定：那需要新增判定语义，且 Action 一旦跳过写入就会与 Test 脱钩，
          制造一条永久 NOT-SET（长期红/黄灯会训练操作员无视颜色 —— 本文件自己写的
          教训）。改为把语义写进 Note，读者不必猜这一格为什么"往慢里改"。
   [FIX ] C-02 [文档] P7 的 Note 例证与真机不符：注释举的是 0x80000003，真机报的是
          **0x80000001**（低两位 01 + bit31 系统管理）。判据本身正确 —— 那一行没有
          MISMATCH，说明 bit0 判定判了达标；只是例证要扩成"两者都是同一意图的系统
          编码，真机报哪个都可能"。
   [TEST] ★ **双轨一致性第一次拿到真机背书**（同一台机、同一份脚本）：
            · PS7 跑（.cmd 自动选 pwsh，13:56:33）与 5.1 跑（14:01:06）的 -Verify 报告
              **逐项一致** —— SATISFIED 10 项同集合（D1/D2/D13/D14/P5/P8/SEC3/OPS4/
              SEC10/SEC12）、NOT-SET 30、N/A 1（P2，同一 Why 与同一 OlSoul_P 方案）、
              ABSENT 1（SEC11）、ONE-SHOT 1（CL1）、探针覆盖 15/43、零证据 3 项
              （P2/CL1/SEC11）全部相同，每一条证据行的实测值也相同。
            · A-03 生效实证：两份日志分别落在
              Svr2Desktop_verify_20260922_135633 / 140106（-Verify 首次有落点）。
            · B-00 安全性实证：P2 报 [block: <none>]、P4 报四个单块身份，**零 AMBIGUOUS**
              → v11.16 新增的"块数 > 1 则判负"守卫在目标机上不会误触发。
            · Probe/Test 同源实证：-Verify 的 10 个 SATISFIED 与 -WhatIf 的 10 个 SKIP
              **完全同一集合**。
   [NOTE] A-05 **部分闭合**：5.1 会话里整条回读路径跑通、无 NativeCommandError
          （SEC12 的 Test 会经 Invoke-Native 调 secedit /export，那一跳在 5.1 下正常）。
          但 A-05 假设的触发条件是"原生命令**往 stderr 写**"，而 -Verify 不调用那些命令
          （-AllowNonZero 的三条 netsh 只在执行档里跑）—— 所以成功路径已证、stderr
          路径未证。判定该假设真伪的一行实验见审计报告闭环三；无论结果如何，
          Invoke-Native 内部已把错误偏好局部化为 Continue，两条路径都安全。
---

 ── v12.0（2026-09-22，**封板发布**）────────────────────────────────────
   ★ v12.0 = 已通过真机验收的 v12.0-preview2 + 三处修复（D-01 / D-03 / D-05）。
     三处**只影响生成的还原脚本**：它的报错质量与一行死代码 —— 判定阈值、写入路径、
     回放语义零改动。因此 preview2 的三段真机闭环证据对 v12.0 依然成立。
     另起版本号的理由同 v11.9 → v11.10：文件又变了，而版本号是分辨"手上这版"的唯一标识。
   ★ 文件名回规范名：`Svr2Desktop.ps1` + `Svr2Desktop.cmd`（脚本内 13 处自引用同步）。
     .cmd 按自己的文件名去找 .ps1，所以两个文件一起改名也不会断。

   [FIX ] D-01 生成的还原脚本里，`Invoke-RestoreReg` 的"删除"分支是无条件记成功：
          `Remove-ItemProperty … -ErrorAction SilentlyContinue` 紧跟一句 `$script:ok++`
          —— 删没删掉都记成功，与 v8.1「逐行无条件写完成」同形，只是范围小。
          真机那次 `applied: 87` 恰好每项都生效，但那是运气不是保证。
          现改为 `-ErrorAction Stop`：失败会抛进 catch、打 `[FAIL] reg <路径> :: <原因>`
          并计 `$fail`。有名字的失败才修得动。
   [DEL ] D-03 删掉生成的还原脚本里 `$touched = 0` —— 模板从早期版本沿袭至今，生成物
          里从未读写过一次。本项目为同类理由删过 Set-RegMultiString 与 Invoke-StageByName
          的死分支，此处一并清掉。
   [FIX ] D-05 scheduled task / power 两段的 catch 此前是静默的（`catch { $fail++ }`），
          而 reg / svc / native 三段都会打 `[FAIL] <名字>`。它们一旦失败，操作员只看到末行
          `failed: 1` 却不知是哪一项 —— 与本文件"结论要么给理由、要么声明理由没采集到"
          的作风相悖。现两段各自点名：`[FAIL] task <路径><名字>: <原因>`、
          `[FAIL] power <子组> <设置项> -> <值>: <原因>`。

   [TEST] 真机验收证据（Windows Server 2025 Datacenter build 26100）：
            · **双轨一致**：PS7 与 5.1 两份 -Verify 报告逐项相同（SATISFIED 同集合、
              探针覆盖 15/43、零证据 3 项，连 P2 的 Why 与方案 GUID 都相同）；
            · **三段闭环**：基线 SATISFIED 10 / NOT-SET 30 → 执行档 OK 30 · FAIL 0
              → 重启后 SATISFIED 39 / NOT-SET 1。`10+30 = 40 = 39+1` ⇒ 29 项转绿、零回退；
            · **P9 自愈项首次被区分开**：执行时 2 项（PcaPatchDbTask / QueueReporting）
              → 重启后只剩 PcaPatchDbTask ⇒ QueueReporting 是永久关闭的，只有 PcaPatchDbTask 真自愈；
            · **Restore 实测 applied 87 / failed 0**，计数精确分解 73 reg + 7 svc + 2 task
              + 4 power + **1 native** = 87；native 只有 N1 一条且**这是正确行为**
              （SEC12 / SEC3 是 SKIP、SEC11 是 N/A，三者从未执行 Action → 不该登记回放）；
            · **还原完整性判据通过**：还原 + 重启后的 -Verify 与**原始基线逐项一致**
              （MenuShowDelay 回到 50、LastAccessUpdate 回到 0x80000001、8dot3 回到 2、
              autotuning 回到 disabled、N2 三接口键消失、NetbiosOptions 回到 0 …）
              ⇒ "所有改动可一键还原"这句承诺**在真机上成立**，且 D-01 的隐忧实测不存在于本次；
            · **回放通道真机执行成功**：输出里那行中文 `确定。` 就是 netsh 的成功回显。
   [ROOT] 本轮撞出一个**夹具自身**的漏洞：三个 harness 的源文件路径写死，改名后 AST 抽取
          落空，却静默复用了上一次的抽取产物 —— 于是"测的是旧代码"，E7 先报了一串假红。
          该洞既能伪造红、也能伪造绿。已修：源文件按候选表解析、缺失即 throw、
          抽取缺函数即 throw、每次打印 `source: <路径> (mtime, 行数)` 自证身份。
          教训与主体同源：**任何"读不到就当作旧值"的静默回退都是假绿通道**。
   [NOTE] 仍未覆盖（如实记录）：① 行为套件（PASS 169）/ 门控基线 -AssertClean / 变异清单
          —— 宿主目录 skills/powershell-hardening-rewrite/scripts/ 不在本机；
          ② A-05 的 5.1 **执行**路径：执行档走的是 PS7，而假设的触发条件（原生命令往 stderr 写）
          只在 5.1 上可能；补法是 5.1 会话里跑 `-Stage Network -Force`（会调用三条 netsh）。
   [NOTE] D-02（native 回放段无回读）经决策人裁定**不做**：还原后的 -Verify 已在工作流层面
          给出值级验证（N1 确已回到 autotuning = disabled），再加一套读法属重复机制。
---

 ── v13.0（2026-09-22，新增引导器与软件部署；调优脚本内容未变）────────────
   ★ 本版**没有改 Svr2Desktop.ps1 一个字节** —— 它的版本号仍是 12.0。
     本项目规矩：版本号标识"手上这版"，内容没变就不该换号。
     V13 = V12 的调优脚本 + 两个新件（引导器 + 部署脚本）。

   [ADD ] `BobWinSvrTurn.cmd` —— 唯一的一键入口，按顺序调两个 .ps1：
            ① `Svr2Desktop.ps1`（调优）→ ② `InitBobSoft.ps1`（部署）
          骨架与 `Svr2Desktop.cmd` 有意保持一致（宿主选择 pwsh 优先 / `fltmc` 提权探针 /
          `SVR2D_RUNAS` 重入标记 / pause 只对"无参数"生效 / 分支一律 goto 不用括号块）
          —— 那四点是 v12 真机验收过的，直接复用。两个 .cmd 头部互相写明"改动要同步"。
          ★ 引导器级开关只有两个（要求单独使用）：`-TuneOnly` / `-DeployOnly`；
             其余参数原样透传给调优脚本。
          ★ **只读意图被尊重**：参数里带 `-Verify` 或 `-WhatIf` 时**跳过部署** ——
             预演不该悄悄装软件。这条是设计时按"最坏误用"反推出来的。
          ★ 退出码合并：两个子脚本同为 0/1/2 契约，任一非 0 即非 0，2 优先于 1。
          ★ 名字与 .ps1 不再同名，所以**不能**再用 `%~n0` 推导脚本名（这是与
             Svr2Desktop.cmd 的唯一结构性差别），两个 .ps1 名字显式写在文件里。

   [ADD ] `InitBobSoft.ps1` v13.0 —— 把 `BobSoft\` 载荷铺到 `C:\Tools`。三种模式：
            a) 子目录  → robocopy `/E` 复制到 `C:\Tools\<同名子目录>`
            b) 压缩包  → 载荷内的 `7za.exe` / `7z.exe` 解压到 `C:\Tools` 本体
                       （包内自带独立目录，由载荷约定 —— 决策人 2026-09-22 定）
            c) 离线 MSI → `msiexec /i /qn /norestart /l*v`，并**回读 MSI 日志的权威状态行**
            非这三类的文件会被 `SKIP` 并**列出原因**（不静默、也不当错误）。
            覆盖策略：**全量覆盖**（决策人定）。MSI 重复运行即进入"修复"模式。
            退出码：0 全成 / 2 有失败 / 1 致命（与调优脚本同一契约）。

   [DESIGN] 三处刻意取舍（都写进注释，供日后复核）：
            · **不用 `[CmdletBinding(SupportsShouldProcess)]` 的隐式拦截**，而是照抄
              v11.1 验证过的写法：把 `$WhatIfPreference` 交还 PowerShell，预演由脚本
              步骤级显式判断 —— 否则预演会刷出一堆与本意无关的 WhatIf 行。
            · **robocopy 而非 `Copy-Item -Recurse`**：后者在目标已存在时会把源目录
              整个塞进去（`C:\Tools\BobSoft\x\sub`），语义陷阱；robocopy 的 `/E`
              是全量覆盖的正解。退出码是**位掩码**（0–7 成功、≥8 失败），
              当普通命令用 `-ne 0` 判断会误报。
            · **msiexec 必须 `Start-Process -Wait -PassThru`**：它是 GUI 子系统程序，
              直接用 `&` 拿不到可靠退出码。且"成功"不止 0 —— 3010（需重启）/ 1641
              （已发起重启）都算成功，判失败是最常见的 MSI 误报。
              MSI 日志末尾固定的 `Installation success or error status: N` 行被解析出来
              作为**权威回读**，比退出码更可信。

   [SCOPE] 与调优脚本的边界（写进了两边头部）：
            · 部署**不在"一键还原"范围内** —— Svr2Desktop 生成的 Restore 脚本只回放
              它自己改过的值，不碰 `C:\Tools`；
            · 部署脚本**不做任何注册表/服务/任务调优**；
            · 部署脚本**不下载任何东西**（离线包随载荷带来）。
            · 交叉核查：CL1 的清理白名单**不含** `C:\Tools` ✓ 不会被误清；
              OPS3 的长路径支持对深层工具目录有正面作用。

   [DROP] 决策人 2026-09-22 裁定**废弃**两项原计划：
            · PowerShell 自动升级（检测 < 7.6 → 公网下载安装 → 重启脚本）—— 砍掉。
              分析结论留档在审计报告：技术可行但引入"从公网拉二进制并静默安装"、
              幂等标记、参数透传、PATH 未刷新、升级轮留下半成品报告等一串风险，
              而收益可以由宿主机侧的 .cmd 选择 pwsh 覆盖掉。
            · 目录名 `BobTools` 废弃，统一用 `BobSoft`，且**与 .cmd 同目录**。

   [TEST] 本地实测（macOS + pwsh 7.9，真 AST 抽函数 + 夹具，源文件未改）：
            · 两个新文件 AST 解析 0 error；编码 UTF-8 with BOM + CRLF（.cmd 为 ASCII）；
            · E9-1 载荷分类 11 例全对：含 `APP.MSI` 大小写、`tar.gz` 多扩展名、
                 `big.7z.001` 归 Archive（交给 7z 处理整组）、`big.7z.002` 归 SplitPart
                 （**必须跳过**，否则每个分卷都会被单独解一遍）；
            · E9-2 退出码语义 20 例全对：robocopy 0/1/3/7 成功、8/16/32 失败；
                 7z 0/1 完成、2/7/8/255 失败；msiexec 0/3010/1641 成功、1603/1618/1638 失败；
            · E9-3 MSI 日志权威状态行解析：成功日志→0、失败日志→1603、
                 取不到时明说"取不到"（不猜）；
            · E9-4 计划构建（夹具目录树）：顺序确为 `Dir,Dir,Archive×3,Msi`、
                 解压器本身不进计划、分卷后续块被跳过、非三类文件被列出原因。
          复跑物：`_local_probe_macos/run4.ps1`。

   [NOTE] 未覆盖：**端到端未跑** —— `InitBobSoft.ps1` 带 `#Requires -RunAsAdministrator`，
          且 robocopy / msiexec 是 Windows 专有，只能在目标机验。
          首次上机建议顺序：① `InitBobSoft.ps1 -WhatIf`（看计划对不对）→
          ② 真跑一次 → ③ 核对 `C:\Tools\_deploy_logs\` 下的日志与汇总表。
---

 ── v13.0-合并（2026-09-29，特斯拉 · 两线合并：Svr2Desktop 随之升至 13.0）──────
   ★ 触发：奥迪在 Gitea 建 `WinTools` 仓（v11.15 封版基线），宝马在其上推了自己的
     v11.16；特斯拉机侧的 v11.16→v12.0→V13 一直在本地、**未纳管 git**。两线各走，
     于是出现"两个 v11.16"。本次把两线合成一个可发布的 13.0。
   [CHG ] `Svr2Desktop.ps1` 版本号 **12.0 → 13.0**（内容变了才换号）。
          ★ 更正本文件上一节的一句："调优脚本内容未变、版本号不动" —— 那是合并前的
          状态；现在合入了宝马的 D8 修复与 D16 新增，内容已变，故一并升到 13.0。
          至此 `Svr2Desktop.ps1` 与 `InitBobSoft.ps1` 同为 13.0，V13 是一个整包。
   [MERGE] 从宝马线合入两项（原文与理由见上面的宝马 v11.16 条）：
            · D8 的 FullPath 改指 HKCU（写侧 + 断言侧同时改，附根因注释）；
            · 新增 D16 任务栏「结束任务」（Win11UI 条件化 + 三态 Probe）。
          并为 D8 补了一条特斯拉侧的自省：2026-09-22 真机执行档里这一项
          before=<absent>/after=1/报 OK —— 当时只看"值有没有移动"，**没有追问
          "谁读这个值"**。宝马是因为机主追问功能没生效才挖到根因的。
          ⇒ 教训归档：**回读只能证明"值就位"，证明不了"它被使用"**；凡写配置的项，
            都要能回答"谁是消费者"。这一条已写进 D8 的注释里。
   [BRING] 从远端仓搬入此前本地没有的件：`Review/`（两份 Gemini 审计文档 ——
           其中 v11.14 二审的时点行动清单正是 F-02/F-04 的去处）、
           `Svr2Desktop.config.json`（带说明的可选配置文件）、
           `Svr2Desktop_v9.0_bat_legacy.bat`（原始社区版留档）、
           `_history/`（13 份逐字节版本快照）、`.gitignore`（.DS_Store）。
   [KEEP ] 本地侧**保留** `Svr2Desktop.cmd`（96 行的 v12 修订版：fltmc 提权探针 /
           SVR2D_RUNAS 重入标记 / pause 仅对无参数生效），**不采用**远端那份 79 行的
           旧版 —— 远端的 v11.15 基线早于这四处修复。两份 .cmd 的差异不是分歧，
           是时间差。
   [TEST] 合并后本地回归（macOS + pwsh 7.6.5，真 AST 抽函数 + 夹具，源文件未改）：
            · AST 解析 0 error；步骤定义数 45 → **46**（+D16）；UTF-8 BOM + CRLF 保持；
            · HKLM CabinetState 残留 = **0**（D8 修复落位）；TaskbarEndTask 出现 5 处；
            · E1/E2/E4 全过（Resolve-StageList 六形态与非法项 / net user 密码到期专行 /
                 Get-TaskState 双来源与空清单边界）；
            · E7 全过（生成的还原脚本 AST 0 error、native 回放段结构正确、D-01/D-03/D-05 到位）；
            · E9 全过（部署载荷分类 / 三套退出码语义 / MSI 日志权威状态 / 计划构建顺序）；
            · **E10（本轮新增，专为 D16）**：非 Win11UI 时 Test 返回 $true
                 （不制造"Action 跳过、Test 判假"的假红死循环）、Probe 判 ABSENT 且
                 带理由与证据行；Win11UI 时 Test 确实走到读值（**分支不短路**）。
          复跑物：`_local_probe_macos/run5.ps1`（E10）等。
   [GIT ] 本目录已 `git init` 并挂上 Gitea 远端（令牌只在本仓 `.git/config`，不入库、
           不入任何镜像）。此后**每次改动先 pull 再改**，避免再出现两线各走。
   [TODO] ① D8 新判据需一次真机 `-Verify` 对照（宝马的请求，也是唯一能证伪"改对了"的
          手段：HKLM 旧值机器上，标题栏是否真的显示出完整路径）；
           ② 行为套件 / 门控基线 / 变异清单仍未跑（宿主目录不在本机）；
           ③ A-05 的 5.1 执行路径仍未覆盖。
---

 ── v13.0-验收（2026-09-29，真机：Windows Server 2025 Datacenter build 26100，PS 7.6.6）──
   运行方式：`Svr2Desktop.cmd` → 菜单 [A]，降级档与 VBS 档均按提示确认；未重启。
   结果：**OK 3 · SKIP 38 · N/A 2 · PARTIAL 1 · FAIL 0 · CHECK-ERROR 0**（合计 44 步 ✓
   与预期步数一致；Desktop 段显示 15 步，即合并进来的 D16 已注册）。

   ★ 本次真实改动只有三项，其中两项是合并进来的新代码 —— 而它们的证据正好印证了
     宝马对 D8 的根因判断：
     · **D8 [OK]**：before `HKCU\...\Explorer\CabinetState\FullPath = 0`（MISMATCH）→
       after `= 1`。**注意这个 before 值**：它不是 `<absent>`，而是系统自己维护着的 **0**
       —— 与宝马在提交里写的"HKCU 的 FullPath 由系统自己维护着 0（资源管理器把文件夹
       选项状态物化在 HKCU）"完全对上。旧实现写 HKLM 时，同一次运行会报 SATISFIED 而这
       个 HKCU 值始终是 0 ⇒ 死键缺陷确凿，修复方向正确。
     · **D16 [OK]**：before `...\TaskbarDeveloperSettings\TaskbarEndTask = <absent>` →
       after `= 1`。build 26100 属 Win11 风格 shell，条件分支走了写入路径（经典任务栏
       分支由本地夹具 E10 覆盖，判 ABSENT）。
     · **P9 [OK]**：`re-disabled 1 task(s) the scheduler still reported as enabled:
       PcaPatchDbTask (Ready)` —— 自愈项第三次被如实呈现；同时可见 `QueueReporting` 已
       由 9/22 的 Ready 转为 **Disabled**，即两项里只有 PcaPatchDbTask 真自愈，结论稳定。
     · **CL1 [PARTIAL]**：清掉 87 项、保留 6 项（三个 vmware 日志 / `Temp\1` /
       `net.blip.desktop` / `CBS.log`），与上一轮同一批占用者，行为一致。
     其余 38 项 SKIP ⇒ V12 的成果未回退；降级档 SEC10/SEC12/SEC13/V1 均 SKIP（早已达成），
     SEC11 仍 N/A（Defender 组件不在）。

   [NOTE] **还差最后一公里**：D8 的"值就位"已证，但"标题栏是否真的显示出完整路径"
          需要重启 explorer.exe 后**目视确认**。这正是本次合并里那条教训（"回读只能证明
          值就位，证明不了它被使用"）的最后一段路 —— 值已经在 Explorer 真正读取的那个
          键上，预期生效，但**未见之前不算闭环**。
   [NOTE] 仍缺：行为套件 / 门控基线 / 变异清单（宿主目录不在本机）；A-05 的 5.1 执行路径。
   [TAG ] 本版在 Gitea 打 `v13.0` 标签（仓内已有 `v11.15` 的先例：封版基线才打标签）。
---

 ── v13.1（2026-09-29，机主点单：备份保留 + 空壳脚本自报）────────────────
   ★ 本版**尚未真机验证**，故**不打标签** —— 与 v13.0 同一规矩：真机跑过才封版。

   [ADD ] CL2「备份保留：只留当天」。每跑一次（含 -Verify）就在备份根下多一个带时间戳的
          目录，累积无上限（真机已 8 个）。机主 2026-09-29 决定：**只保留当天、其余全清**；
          注意不是"清掉当天之前的"——同一天更早那几次也留（一天多跑是常态，且各自带还原脚本）。
          安全约束四条（删除是破坏性的）：① 只动备份根的**直接子目录**，绝不递归到别处；
          ② 目录名必须匹配 `^Svr2Desktop_\d{8}_\d{6}$` 或 `^Svr2Desktop_verify_\d{8}_\d{6}$`，
          认不出的一律跳过**并列出**，绝不"看着像就删"；③ 只删目录不碰文件；
          ④ 每一项逐条留证据（删了哪些、释放多少字节、跳过了哪些），失败计 PARTIAL，
          回读断言"凡报告已删的必须真的不存在"（与 CL1 同一手法）。
   ★ 代价已写进报告与文档：**删旧备份 = 失去回滚到更早状态的能力**。每次运行生成的还原
     脚本只回到"本次运行之前"，所以清掉旧的之后，能回滚的最远点是今天最早那次运行之前。
     要保住全部历史，把 `CleanupEnabled` 置 false（见下一条）或跳过 Cleanup 阶段即可。
   [FIX ] `CleanupEnabled` 这个配置键**此前是死的**：它被读进 $cfg、写进了白名单，却从未被
          任何逻辑使用 —— 一个"承诺了行为却不兑现"的键，与 v8.1 那个无效的 Defender 键同族，
          正是本文件反复要消灭的假绿形态。现让它真正生效：为 false 时 CL1/CL2 都不注册
          （与 S6/S7 的 opt-in 同一做法）。副作用：备份保留随之停用、目录会累积 ——
          "一个开关管住所有删除动作"的必然取舍，方向是安全的。
   [ADD ] **空壳还原脚本自报家门**。起因（E11 夹具实测）：零改动的一轮仍会生成
          `Restore_*.ps1`（设计如此：每次运行都留档），而它五段各自写着
          `# (no … were changed)`、**顶部却没有一句总声明**，操作员得连读五段才能确认；
          再加上 power 段末尾那句无条件的 `powercfg /setactive` 看着像"干过活"。
          这不是假绿，是**阅读成本**。现在：生成物顶部写 `★ NOTHING WAS CHANGED IN THIS RUN`，
          屏幕上同步给一句提示。判据取"六个备份通道是否有任何条目"，任一非空即视为有过动作
          —— **保守方向**：宁可不说"没改"，也不谎报"没改"。
   [CHG ] 备份根解析收敛到 `Get-BackupRoot` 一处。此前这段逻辑抄在 New-BackupSession 与
          New-VerifySession 两处，CL2 要用第三遍 —— 正是"同一份清单抄三份，早晚各写各的"。
   [KEEP] 计划 2（D12 的"100 是统一基准值"说明）经查**已于 v12.0-preview2 落位**，本版无需改动
          —— 真机 13.0 执行档的证据行里已经带着那句 Note。

   [TEST] 本机回归（macOS + pwsh 7.6.5，真 AST 抽步骤块 + 夹具目录树，源文件未改）：
            · AST 0 error；Add-Step 定义数 46 → **47**（+CL2）；UTF-8 BOM + CRLF 保持；
            · **E12（CL2 专项）**：夹具根放 6 个目录 —— 昨天的两个（普通 + verify）**被删**、
              今天的两个**保留**、两个名字认不出的（`Svr2Desktop_backup_old` / `ImportantStuff`）
              **跳过并列明原因**、根下的文件未触碰；plan 计数 removed=2 / kept=2 / skipped=2 / failed=0；
              Test 回读为真；**再跑一遍删 0 个（幂等）**；字节统计经 1MB 文件验证不是常量 0
              （`freed 2.0 MB`）；无失败故未提交 PARTIAL。
            · **E13（空壳声明双向）**：零改动 → 生成物顶部有声明、措辞完整、AST 0 error；
              有改动 → **不打**声明且确有回放行（不谎报"没改"）。
            · 五个既有夹具全绿、零 FAIL：E1/E2/E4（10）、E7（11）、E9（39）、E10（5）、E11（1）。
          复跑物：`_local_probe_macos/run7.ps1`。

   [CHG ] **重启改为两步确认**（机主 2026-09-29 决定）。新增 `Confirm-Reboot`：第一次仍是
          `Reboot now …? [Y/N]`（与全脚本其余确认同一手感），通过之后**要求打出一个词**
          `REBOOT`（大小写无关，空回车也算取消）才真正 `Restart-Computer -Force`。
          理由：重启是本脚本最打断人的动作，而它偏偏在所有写操作完成之后才问 —— 前面已经
          按过好几轮确认，手感上很容易一路 Y 下去，误触的代价是工作现场直接消失。
          按 Y 会被肌肉记忆带走，打字不会。两次回答都落日志（`reboot: first answer …, second answer …`），
          事后能看清这台机器为什么重启过。`-Force` / `-NoRestartPrompt` 的既定语义不变，
          因此**不需要**新的跳过开关 —— 加一个只会是多一个没人用的机制。
   [DEL ] **去掉 `NtfsMftZoneReservation=2`**（P7 的第三项，机主 2026-09-29 决定；即上一版
          说明里列的选项 A）。该值只在**格式化 / 首次以该参数挂载**时被读取并固化进卷结构 ——
          对已存在的卷改注册表不会重排 MFT，真机实证"值就位、收益为 0"；而"保留写入"的期望
          收益（对未来新建卷）**同样不可证伪**（取决于负载形态，无普适结论）。两个方向都无法
          用效果论证时，选动作更少的那个：**不写**，值停在系统默认（0 = 系统自行选择）。
          配套改动：① P7 标题去掉 `larger MFT zone`（标题不该承诺一件它不做的事）；
          ② 该项的断言从 `Test-RegValue -Expected 2` 改为 `Add-Check -Ok $true` —— 既然不写，
          就不该再拿期望值卡它（那会变成一条等不到 2 的**永久假红**），但也不能不留痕：
          证据行改为印出实测值 + `not written by this script: … matters only when a volume is formatted`，
          把"本脚本不动它"和"消费者在何时读它"一并说清（这正是 D8 死键教训的落点）。
   [NOTE] 版本号**不变**（仍 13.1）：本版尚未真机验证，也**没有任何外部产物带着 13.1** ——
          与 v11.9 → v11.10 那次升号的情形不同（那次是 11.9 已产出真机执行档，报告里出现过）。
          所以这两处调整**并入 13.1 条目**，不另起版本号。
   [TEST] 本条调整的本地验证（新增两个夹具）：
            · **E14（P7 专项）**：Action 里**没有任何**指向 `NtfsMftZoneReservation` 的写调用
              （判据用 AST 查"写调用"，不是查"字符串出现过" —— 解释为什么不再写的那段注释里
              本来就会提到它）；另两项仍照写；该项证据行**不带 MISMATCH** ⇒ `Ok=$true` 永远达标、
              且不含 `(want …)` ⇒ 已不是期望值比较；证据行印出实测值并含"本脚本不动它 + 消费者在
              格式化时"两句话。
            · **E15（Confirm-Reboot 四种输入）**：`y`+`REBOOT` → 通过（真重启）；`y`+`no` → 取消；
              `y`+空回车 → 取消；`n` → 在第一步就取消且**根本不出现第二步提示**。
            · 六个既有夹具全绿零 FAIL（E1/E2/E4=10、E7=11、E9=39、E10=5、E11=1、E12/E13=18）。
          复跑物：`_local_probe_macos/run8.ps1`、`run9.ps1`。

   [NOTE] 待真机：① `-Stage Cleanup` 跑一次，看 CL2 删了哪些、释放多少、有没有把不该删的删掉；
          ② 确认 `C:\Svr2DesktopBackup` 剩当天目录后，`-Verify` 仍能正常写入（verify 目录也是当天，不会被自己删掉）。
---

 ── v13.2（2026-09-29，13.1 真机两跑逼出的一处"话说过头"）────────────────
   ★ 版本号必须另起（不能并进 13.1）：**13.1 已经在真机上产出过报告**
     （session 20260929_113404 / 113651，报告头印着 `Svr2Desktop v13.1`）——
     与 v11.9 → v11.10 那次同一条规矩：报告里出现过的版本号不能两名一物。

   [FIX ] 空壳声明的措辞过头了。13.1 写的是 `★ NOTHING WAS CHANGED IN THIS RUN`，而真机
          `-Stage Cleanup` 那一跑里 **CL1 删了 14 个文件、CL2 也动了备份根** —— 只是这些动作
          不进备份通道，脚本仍是空壳。**判据（备份通道是否为空）是对的，话说过头了**：
          该说的是"没有可回放的值"，不是"什么都没改"。
          报告说出证据支持不了的话，正是本文件要杀的那类毛病 —— 哪怕方向是"往坏处说"也不行，
          因为它会掩盖真实发生过的事（操作员会以为清理没跑）。
          现改为：生成物顶部写 `★ THIS SCRIPT HAS NOTHING TO REPLAY: no registry / service /
          feature / scheduled-task / power / native-command value was captured in this run …`
          ＋ 一段明确区分：`NOTE this is about REPLAYABLE values, not about "nothing happened":
          the cleanup stage may well have deleted files in this run. Deletions are not restorable
          in any case … and they never go through the backup channels`。屏幕侧同步改写。
          判据变量同时由 `$anyWork` 改名为 `$anyReplay` —— 它量的本来就是"可回放条目数"，
          旧名字正是这次措辞跑偏的语言根源。
   [ROOT] 改名时**我自己漏改了一处引用**（屏幕侧那句仍指向已不存在的 `$anyWork`，未定义 ⇒
          恒真 ⇒ 每次运行都会打声明）。夹具 E13 的"有可改动 → 不得打声明"那条断言当场把它逮住。
          教训与项目里那条同源：**"读不到就退回旧值"式的静默回退都是假绿通道** ——
          这里更隐蔽，是"引用了不存在的变量"。补做：改完立刻数一遍旧名的残留（本次已做，归零）。

   ── 13.1 真机两跑验收（Windows Server 2025 build 26100 / PS 7.6.6）──
   · `-Stage Cleanup -Force`（20260929_113404）：**CL1 [PARTIAL]** 删 14 / 留 7（多了一个
     `BITF6D6.tmp`，.NET 临时文件被占用，属预期）；**CL2 [OK]** `pruned 0 older session(s),
     freed 0.0 MB; kept 4 from today; skipped 0 unrecognised` ⇒ 备份根里现在**只有今天的 4 个**
     （9/22 那 6 个已不在，待机主确认是否手工清理过）；空壳声明**按预期打出**。
   · `-Stage Performance -Force`（20260929_113651）：**P7 [SKIP]** —— 标题已生效为
     `NTFS tuning (last access off, 8dot3 off)`，且 SKIP 意味着三项都达标（第三项 `Add-Check`
     恒真），**Action 未再写 MFT 值** ✓；**P9 [OK]** 又一次 `re-disabled PcaPatchDbTask (Ready)`
     （自愈项第 4 次复现）；其余 6 项 SKIP、FAIL 0。**这一跑没打空壳声明 —— 因为 P9 确实动了
     计划任务 ⇒ 有可回放条目** ✓ 声明的另一个方向也在真机上得到验证。
   · 观察：P7 报 SKIP 时其证据行进**折叠**（摘要把 SKIP 的证据收起来），所以那句 MFT zone 的说明
     默认只在日志与 `-Full` 里可见。这是折叠规则的必然结果，不建议为它改规则。

   [TEST] 本机回归：E13 断言同步到新措辞并**新增两条**（必须区分"无可回放值/什么都没发生"、
          必须主动点出"清理可能已删文件"）；全量 7 个夹具 **98 条断言、零 FAIL**
          （E1/E2/E4=10、E7=11、E9=39、E10=5、E11=1、E12/E13=20、E14=12）。
          复跑物：`_local_probe_macos/`（run7.ps1 等）。
   [NOTE] 待真机：跑一次 `-Verify` 或任意阶段，确认报告头是 **v13.2**、且空壳声明只在
          "确实无可回放值"时出现（跑 `-Stage Cleanup` 应出现；跑动过值的阶段不应出现）。
---

 ── v13.3（2026-09-29，重启确认词改 OK + 退出码显式化）──────────────────
   ★ 13.2 已封版（打了标签、真机产出过报告）⇒ 内容变更必须另起版本号 = 13.3。

   [CHG ] 重启二次确认的词由 `REBOOT` 改为 **`OK`**（机主 2026-09-29）。目的本就是击穿
          "一次误触 Y"，**不需要长词承担更多** —— OK 两下按键，摩擦刚好，也不必让人
          为一次确认打七个字母。判据 `-eq 'ok'`（大小写无关）；空回车仍取消。提示文案同步。
          ★ 本地夹具 E15 五例：`ok` / `OK` → 通过；**`yes` → 不通过**（正好挡住提示 Yes/No
          场景下肌肉记忆里那个词）；`n` → 第一步即取消；`y` + 空回车 → 取消。
   [FIX ] 退出码显式化 —— **这一条是我主动加的，不是机主要求，一句话可撤**（三行）。
          起因：机主一次输出最上面有 `Script exited with code 1.`，而代码里只有两处 exit
          （FATAL→1、-ExitOnFail 有失败→2），**正常完成路径没有显式 exit** ⇒ 进程退出码
          交给 PowerShell 的默认行为决定。而 `$LASTEXITCODE` 是**粘的**：脚本里直接调用
          原生命令的读值路径（`powercfg /query`、`netsh … show global`）若返回非零，之后
          又没有别的原生命令把它刷成 0，那个非零值就成了**整个进程的退出码** ⇒ 启动器喊
          "Script exited with code 1"，而报告里 FAIL = 0。
          我没有锁定具体是哪条命令返回了 1（需一行测试定案，见 [NOTE]），但**退出码契约
          不该依赖外部命令**，所以先钉死：三条正常收尾路径（-Verify / 交互菜单退出 / 命令行
          完成）一律显式 `exit 0`。`exit 2`（有失败）与 `exit 1`（致命）语义不变。
   [TEST] 全量 7 个夹具 **98 条断言零 FAIL**（10/11/39/5/1/20/12）；AST 0 error；
          入口守卫在 macOS 上仍以 exit 1 拒绝（未被本次改动影响）。
          复跑物：`_local_probe_macos/run9.ps1`（E15）。
   [NOTE] 待真机三点：① 报告头应为 **v13.3**；② 跑完末尾**不应出现** "Script exited with
          code N" —— 这既是本次硬化的验证，也顺带回答"上次那个 1 从哪来"（若仍出现，
          说明另有非零来源，把那条命令告诉我）；③ 试一次重启确认的新词 `OK`。
---