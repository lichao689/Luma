# 小盏 / luma

一个驻留在 macOS 顶部菜单栏的办公室锻炼提醒 App:随手记录、弹性提醒、告诉你今天该练什么。

定位是 **弹性训练决策器**,不是固定日程健身 App。它只维护三件事:

1. 今天做了什么
2. 这周还差什么
3. 现在最适合做什么

## 现状(已验证)

- ✅ `xcodebuild` **BUILD SUCCEEDED**(零警告),App 可启动并驻留菜单栏
- ✅ **54 个逻辑测试全绿** + 1 个 App 层测试(退出顺序)
- ✅ **跟练模式**:逐组引导 → 计时 → 组间休息倒计时 → 练完自动落库
- ✅ **组次与重量记录**:每组单独记录,动作详情显示"上次做到多少"
- ✅ 动作示意窗口(15 个办公室动作:哑铃 + 垫上训练 / 图上重点 / 常见错误 + 媒体自动降级)
- ✅ 动作示意窗口支持视频演示(3 个动作已有 mp4,循环静音播放)+ 本次处方(剂量/节奏/休息/预计)
- ✅ 中英双语本地化(zh-Hans 默认 + en)
- ✅ 可正常退出:弹窗右下角电源按钮,或 ⌘Q
- ✅ CSV 导出(设置 → 数据)

## 架构(两层)

```
LogicPackage/                          ← 纯 Swift 库(可独立测试,无 UI/SwiftData)
  Sources/OfficeWorkoutLogic/
    WorkoutType.swift                  类型 / 完成度枚举(public)
    Models.swift                       UserGoalValues / ReminderMode(public)
    SessionRecord.swift                值类型会话(逻辑层输入,含 note)
    WorkoutStatsService.swift          统计快照(本周 / 连续空窗 / 连续训练天数 / 腰痛)
    RecommendationEngine.swift         推荐引擎(纯函数,返回 key + 插值)
    ExerciseLibrary.swift              动作库(Exercise / MuscleGroup / A·B 分组)
    Prescription.swift                 处方库(组数/次数/单侧/休息/预计时长)
    WorkoutPlanExpander.swift          计划 → 逐组步骤序列(单侧拆左右)
  Tests/OfficeWorkoutLogicTests/
    RecommendationEngineTests.swift    25 个测试(规则 + 优先级 + 边界 + 休息/重启)
    ExerciseLibraryTests.swift         11 个测试(结构不变量 + 分组覆盖 + 无椅凳边界)
    PrescriptionLibraryTests.swift     9 个测试(覆盖完整 / 单侧拆分 / 时长合理)
    WorkoutPlanExpanderTests.swift     9 个测试(步骤顺序 / 左右拆分 / 编号连续)

OfficeWorkoutCoach/                    ← SwiftUI macOS App(菜单栏)
  OfficeWorkoutCoachApp.swift          @main + MenuBarExtra(三态徽标)+ 跟练 Window
  Models/
    WorkoutSession.swift               @Model(SwiftData 持久层)→ asRecord 桥接
    UserGoal.swift                     @Model(单例目标)→ UserGoalValues 桥接
    SetRecord.swift                    @Model(逐组记录:次数 / 重量 / 时间)
  Views/
    MenuBarPopoverView.swift           菜单栏弹窗(今日建议卡片 + 进度条 + 折叠记录)
    WorkoutStartView.swift             跟练模式(ready/working/resting/done 状态机)
    QuickLogView.swift                 完成卡片
    SummaryView.swift                  最近 7 天 + 周总结
    SettingsView.swift                 目标 / 提醒 / 时间窗 / 数据导出
    ExerciseGuideView.swift            动作示意窗口(列表+详情+处方+开练)
  Services/
    WorkoutRepository.swift            ModelContainer 封装(WorkoutStore + CSV 导出)
    NotificationManager.swift          本地通知 + 久坐升级链 + 深链
    UILocalization.swift               把 Logic 层的 key 翻译成显示文案
  Resources/
    Info.plist                         LSUIElement = true(纯菜单栏 App)
    zh-Hans.lproj / en.lproj           Localizable.strings(含动作文案)
    Exercises/                         动作示意媒体(自己往里放,见下文)
```

**为什么分两层**:把"今天该练什么"这类纯决策逻辑放在无 UI、无 SwiftData 的库里,
能用 `swift test` 独立、快速地验证;UI 层只负责展示与持久化。`RecommendationEngine`
返回稳定的 key + 插值值,App 层的 `UILocalization` 负责本地化显示。

## 构建

```sh
cd /Volumes/WorkSSD/codes/luma

# 构建 App(会自动解析本地 LogicPackage)
xcodebuild -project OfficeWorkoutCoach.xcodeproj \
           -scheme OfficeWorkoutCoach -configuration Debug build

# 运行逻辑测试
swift test --package-path LogicPackage
```

> 若测试报 `sandbox-exec: sandbox_apply: Operation not permitted`(较新的 macOS 上
> SwiftPM 编译 manifest 时会遇到),加 `--disable-sandbox` 即可:
> `swift test --package-path LogicPackage --disable-sandbox`
>
> 同理,在受限沙箱环境(某些 IDE 内置终端)里 `xcodebuild` 可能报
> `swift-plugin-server ... produced malformed response` —— 这是 Swift 编译器给宏插件
> 套的 `sandbox-exec` 跑不起来导致的,与代码无关。给编译器关掉沙箱即可:
> `EXTRA_XCODEBUILD_ARGS='OTHER_SWIFT_FLAGS="-disable-sandbox"' tools/install_app.sh`

或在 Xcode 中双击 `OfficeWorkoutCoach.xcodeproj`,⌘R 运行。

## 打开、更新、部署

这是一个纯菜单栏 App(`LSUIElement = true`),启动后不会出现在 Dock 里,只会出现在 macOS 顶部菜单栏。
如果替换了图标、资源或代码,正在运行的旧进程不会热更新,需要退出并重新打开。

本机安装/更新推荐用脚本:

```sh
cd /Volumes/WorkSSD/codes/luma
tools/install_app.sh
```

脚本会构建 Release 版本,停止旧的 `OfficeWorkoutCoach` / `luma` 进程,复制到 `~/Applications/luma.app`,
然后重新打开。想安装到系统 `/Applications` 时可用:

```sh
DEST_DIR=/Applications tools/install_app.sh
```

给其他电脑部署时,先打包:

```sh
cd /Volumes/WorkSSD/codes/luma
tools/package_app.sh
```

生成的 zip 在 `dist/` 下。把 zip 拷到另一台 Mac,解压后拖到 `Applications` 打开即可。
也可以生成 DMG:

```sh
tools/package_dmg.sh
```

DMG 里包含 `luma.app` 和 `Applications` 快捷方式,打开后把 app 拖进去即可。
当前构建是本地签名/个人分发用途;如果 Gatekeeper 拦截,可右键 App 选择「打开」。
若仍被 quarantine 标记拦住,在信任来源的前提下可运行:

```sh
xattr -dr com.apple.quarantine /Applications/luma.app
```

正式对外分发需要 Apple Developer ID 签名和 notarization。

## 推荐引擎规则(优先级从高到低)

1. 近 3 天有腰部不适且今天没动 → 腰背恢复(屏蔽硬拉 / 弓步)
2. 今天已跑步 → 腰背恢复(不加腿部力量)
3. 本周力量 ≥ 目标 → 跑步 / 恢复 / **休息**(连续训练 ≥ 6 天且周目标已达成时才出「休息」)
4. 连续 ≥ 2 天完全无运动 → 8 分钟最低版
5. 需要力量 → A / B 交替(上次 A→推 B,反之;无记录→A;中断 ≥ 7 天回到 A)

规则在 `LogicPackage/Tests/OfficeWorkoutLogicTests/` 中逐条钉死。
腰痛识别不只看结构化选项,也扫备注文本:中文按「腰 + 酸/痛/紧/疼/僵/麻」共现判断,
英文按 `back` 与症状词共现判断,避免单出现 `back` 就误判。

## 跟练模式

点「今日建议」卡片右下角「开始」,或动作示意窗口里的「开始这个动作」,会打开跟练窗口:

- 按 `PrescriptionLibrary` 把计划展开成逐组步骤,单侧动作自动拆左右(如反向弓步 3 组 × 每侧 → 6 步)
- `ready → working → resting → done` 四态:计时类动作(平板 / 侧平板 / 拉伸)到时间自动进入休息,
  次数类动作手动点「完成」
- 组间休息倒计时可跳过、可加 15 秒,休息时长来自处方
- 顶部显示「第 n / N 步」与整体进度条,可随时暂停或提前结束
- 结束时一次性写入 `WorkoutSession` + 每条 `SetRecord`(次数 / 重量 / 时间),动作详情页下次会显示「上次做到多少」
- 跟练期间自动置 `isWorkoutInProgress`,抑制久坐提醒,避免练到一半被弹窗打断


## 提醒策略

- **柔性提醒**:当天无记录且在工作时间窗内,最多 1 次/天。
- **周目标提醒**(强监督模式):周五 / 周六若力量还差,提醒补练,最多 1 次/周。
- **久坐提醒**:移植自 `tools/health-reminder/sedentary_reminder.sh` 的语义:
  - 空闲检测用 `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .null)` 替代 `ioreg HIDIdleTime`
  - 工作窗口默认周一–周五 09:30–18:30(可在设置改)
  - 触发阈值默认 45 分钟,可在设置里调
  - 会议 / 演示应用(zoom / 腾讯会议 / Teams / FaceTime / Keynote / PowerPoint)前台时延迟 10 分钟
  - 升级链:阈值到 → 通知;2 分钟未动 → 语音(`AVSpeechSynthesizer`);再 10 分钟 → 模态弹窗
  - 由 App 内 60 秒 tick 驱动,不再依赖 launchd
  - 点久坐通知 → 直接打开「腰背恢复」跟练;点柔性 / 周目标通知 → 打开最低版训练
  - 跟练进行中自动抑制久坐提醒

所有提醒都可在设置中关闭或调阈值。

## 数据

设置 → 「数据」可以导出全部记录为 CSV。有逐组记录的训练按组展开(每行一组),
没有组次记录的按会话汇总;字段包含日期、类型、时长、动作、组号、次数 / 秒数、重量。

## 与现有 shell 久坐提醒器的关系

`tools/health-reminder/` 是一个独立的 zsh + launchd 久坐提醒器,与本 App 的久坐功能重叠。
App 验证稳定后,可卸载它:`tools/health-reminder/uninstall.sh`,由 App 接管。

## 动作示意(图片 / 文字)

每个动作都按办公室环境设计:一张瑜伽垫 + 可用哑铃,但不依赖凳子、椅子、长凳、墙面或健身房固定器械。
示意优先级 **图片 > 文字**,
缺媒体时自动降级、文字始终显示,不会报错。

- **文字**:每个动作写了目标肌群、图上重点、动作要领、降低难度、常见错误和停止条件。**已内置**,无需任何额外文件。
- **图片**:当前内置 15 张静态示意图。媒体文件**缺失不影响使用**。想替换或新增,按下面规则放文件即可。
- **视频**:代码仍保留视频优先的自动降级结构,但当前产品方向先使用静态图。

### 怎么加示意图

1. 把文件放进 `OfficeWorkoutCoach/Resources/Exercises/`,文件名用动作 id:
   - 图片:`gobletSquat.png`(也支持 `.jpg` / `.jpeg` / `.gif`)
   - 视频扩展仍支持:`gobletSquat.mp4`(也支持 `.mov` / `.m4v`)
2. `Resources/Exercises` 已作为文件夹资源加入 Copy Bundle Resources。命令行构建时,新增同名文件后**无需改工程文件**。
3. 动作 ↔ 文件名对照(即 `ExerciseLibrary` 里的 `id`):

   | 动作 | id | 动作 | id |
   |---|---|---|---|
   | 高脚杯深蹲 | `gobletSquat` | 罗马尼亚硬拉 | `romanianDeadlift` |
   | 俯卧撑 | `pushUp` | 俯身哑铃划船 | `bentOverDumbbellRow` |
   | 哑铃肩推 | `shoulderPress` | 反向弓步 | `reverseLunge` |
   | 臀桥 | `gluteBridge` | 俯卧 W 提拉 | `proneWRaise` |
   | 平板支撑 | `plank` | 侧平板 | `sidePlank` |
   | 猫牛式 | `catCow` | 骨盆后倾 | `pelvicTilt` |
   | 死虫式 | `deadBug` | 鸟狗式 | `birdDog` |
   | 髋屈肌拉伸 | `hipFlexorStretch` | — | — |

同名视频优先于图片。新增动作只需在 `ExerciseLibrary.swift` 加一条 `Exercise(...)` 并在
`planA` / `planB` / `recoverySet` 里引用,文案补进两个 `Localizable.strings`。

入口:菜单栏弹窗底部「动作示意」按钮 → 独立窗口(左侧按力量 A/B/恢复分组,右侧详情)。

## 后续迭代

- (可选)LLM 周总结、HealthKit 接入
- (可选)训练历史曲线、重量进阶建议
