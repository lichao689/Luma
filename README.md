# 小盏 / luma

一个驻留在 macOS 菜单栏的办公室训练助手：根据近期活动、目标和身体反馈安排训练，支持自定义计划、逐组跟练、历史趋势、备份和手动跨 Mac 同步。

核心是回答三个问题：今天做过什么、这周还差什么、现在适合训练还是恢复。数据默认存放在本机；只有你明确导出或确认文件夹同步时才写到所选位置。

## 当前功能

| 方向 | 使用入口与行为 |
| --- | --- |
| 推荐 | 菜单栏的今日建议。结合周目标、训练日上限、力量/肌群间隔、近期时长和强度、明确休息、疼痛、疲劳及腿部酸痛。 |
| 自定义计划 | “选择或编辑训练计划”：选择 A/B/恢复/最低版模板及 8、15、25 分钟预算；调整动作、顺序、组数、次数、休息，保存或另存计划。 |
| 跟练 | 一个训练窗口管理同一会话；暂停/继续、实际次数与重量、计时保持、单侧动作、跳过休息或加 30 秒、提前结束后保存部分完成。 |
| 进阶 | 在跟练中显示基于完整组记录的保守建议；点击接受才填入建议重量。缺少数据、疼痛或未知主观强度不会触发加重。 |
| 历史 | 7/30/90 天活动次数与分钟图；按动作查看实际次数、保持秒数或重量趋势；删除前确认。 |
| 数据 | 设置 → 数据：完整 JSON 备份/恢复、带明确单位的 CSV、健康文件导入、共享目录同步。 |
| 健康桥 | 最小 iPhone 配套工具读取可见的运动、步数、睡眠并导出 JSON；Mac 预览后导入。只把跑步计入跑步目标。 |
| 提醒 | 工作时间窗、柔性/周目标/久坐提醒；“开始”“稍后”“今天休息”均有实际操作；训练、会议、休息和设置变化会取消或抑制延迟升级。 |

Mac 界面提供简体中文和英文。动作库保留 15 个办公室动作及图示/文字/视频资源的自动降级。

### 验证状态

这轮 P0/P1 的实施范围、产品决定与设备验收清单见 [docs/p0-p1.md](docs/p0-p1.md)。纯逻辑可在 Linux 或 macOS 使用 Swift 6 独立测试；macOS App、SwiftData 集成测试和 iOS helper 的 SDK 构建由 [Luma validation](.github/workflows/apple-validation.yml) 检查。请以对应提交的 CI 结果为准，不能把旧版本的构建结果视为这轮改动的验收。

通知实际投递、既有 SwiftData 数据升级、iPhone 健康权限、真实健康源删除传播和两台 Mac 的文件传输仍需按清单在设备上验证。

## 架构

| 层 | 路径 | 职责 |
| --- | --- | --- |
| 纯 Swift 逻辑 | `LogicPackage/Sources/OfficeWorkoutLogic/` | 推荐与统计、动作/处方、训练计划、执行状态机、进阶、备份合并、历史聚合、健康文件契约、提醒资格。 |
| macOS App | `OfficeWorkoutCoach/` | SwiftUI 菜单栏、计划与跟练窗口、Charts、通知、SwiftData、用户选择的文件操作。 |
| iPhone 健康桥 | `HealthBridgeIOS/` | 只读 HealthKit 与手动文件导出；独立 Xcode 工程，共用逻辑包，无服务器。 |
| 测试 | `LogicPackage/Tests/`、`OfficeWorkoutCoachTests/` | 纯行为边界与原生 SwiftData 事务/恢复/去重测试。 |

`RecommendationEngine` 返回本地化 key 与插值，`WorkoutExecution` 只接收显式时钟和用户输入。`WorkoutCoordinator` 保留当前训练状态，`WorkoutStore` 负责每次操作的单次保存和失败回滚。

## 构建与测试

要求：macOS 14+；支持 Swift 6 的 Xcode。iPhone 健康桥要求 iOS 17+。在仓库根目录执行：

```sh
swift test --package-path LogicPackage

xcodebuild test -project OfficeWorkoutCoach.xcodeproj \
  -scheme OfficeWorkoutCoach -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -project HealthBridgeIOS/LumaHealthBridge.xcodeproj \
  -scheme LumaHealthBridge -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

也可在 Xcode 打开 `OfficeWorkoutCoach.xcodeproj`，选择 `OfficeWorkoutCoach` 后运行。iPhone 真机安装需要配置自己的签名团队，详见 [健康桥指南](docs/healthkit-bridge.md)。

## 打开、更新、部署

这是菜单栏 App（`LSUIElement = true`），启动后在屏幕顶部菜单栏出现，不显示 Dock 图标。更新前先保存或丢弃当前训练；关闭跟练窗口会暂停并在本次应用运行期间保留进度，退出后不恢复未保存进度。

本机安装或更新可使用：

```sh
tools/install_app.sh
```

脚本构建 Release、停止旧进程、复制到 `~/Applications/luma.app` 并打开。也可用 `DEST_DIR=/Applications tools/install_app.sh` 指定安装位置。打包脚本 `tools/package_app.sh` 和 `tools/package_dmg.sh` 在 `dist/` 生成分发文件。正式对外分发仍需 Apple Developer ID 签名和 notarization。

## 推荐规则

优先考虑疼痛、明确休息和连续活动天数，然后考虑疲劳、酸痛、近期高强度、代理负荷、跑步恢复、力量间隔与肌群重叠。条件允许时才考虑周目标与 A/B 交替；连续两个已经结束的日历日没有活动时可推荐最低版。

- 新用户每周力量默认 3 次；已有设置保留。每日力量值表示训练日上限，不表示必须每天练力量。
- 默认力量间隔 48 小时、同肌群间隔 36 小时、跑步或高强度缓冲 24 小时，连续活动达到 6 天可安排休息。
- `时长 × 主观强度` 只用作软件调度信号，没有医学单位；未知强度保持为未知。恢复与进阶参数集中在 `RecommendationPolicy`、`ProgressionPolicy`，这些默认值不构成个体化处方。
- 部分完成仍影响恢复，完整目标计数只接受完整完成。未来时间记录、重复身份和缺失值有独立边界测试。
- 疼痛时暂停训练建议，不会仅因某个动作被命名为“恢复”就默认适合继续做。

## 跟练与进阶

今日建议、动作示意中的“开始计划”或计划入口都会打开同一个训练窗口。准备页显示实际估算时长；模板的分钟选项是训练量预算，用户按自己的节奏完成。

次数类动作需要填写实际完成次数；保持类动作记录计时秒数。左右侧是独立步骤。暂停时间不计入训练时长；系统睡眠会暂停；休息结束只进入下一组准备状态。提前结束会保留已完成的组，并在保存前确认主观强度、身体感受和备注。

进阶判断使用最近两次训练的所有相关组，要求独立会话、足够近且间隔合理、每侧每组齐全、达到目录上限与自定义目标中的较高值、主观强度适中并使用同一已知重量。默认建议增加 0.5 kg 且不超过原重量 5%；器械步进不满足时保持原负荷。未完成或高强度可以提出减重，疼痛时提示暂停。任何建议都不自动写成完成记录。

## 提醒

默认工作日为周一至周五 09:30–18:30，久坐触发阈值为 60 分钟；空闲达到 10 分钟视为一次休息。柔性提醒每天最多一次，强监督模式还可在工作时间窗内的周五/周六提醒周目标。

标准/强监督久坐升级为通知后 2 分钟语音、通知后累计 10 分钟对话框。每次升级都重新检查当前环境。轻提醒模式不升级。会议或演示应用在前台、训练进行中、选择稍后、明确休息、关闭功能或离开工作时间窗时，延迟任务会被取消或抑制。

通知“开始”直接打开相应跟练；“稍后”暂停提醒 10 分钟；“今天休息”记录休息并停止当天训练催促。关闭提醒与时间窗均在设置中操作。

## 备份、恢复与同步

- **JSON**：完整保存训练、逐组实际值、目标/提醒偏好、自定义计划、已导入健康数据及删除标记。导入先校验并显示预览，然后合并；重复文件不会重复新增，相同 ID 内容冲突会停止导入。目标偏好默认保留本机，明确勾选才使用备份值。
- **CSV**：每组一行，分开保存 `reps`、`hold_seconds`、`side`、`weight_kg`；适合表格分析，不作为完整恢复格式。
- **跨 Mac**：在各台 Mac 选择同一 iCloud Drive 或共享目录，手动“预览同步 → 确认合并”。各设备写入独立快照，删除标记随快照传播，目标差异保留本机。目录提供者负责文件传输；此版本没有自动 CloudKit 后台复制。
- **健康数据**：必须由 iPhone 工具导出后再在 Mac 导入；授权空态不等于零，UUID 去重，睡眠重叠只计一次。数据文件和同步快照包含已导入的健康信息，只在用户选择的位置写入。

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

## 后续范围

自动后台 CloudKit 同步、完整移动训练客户端、崩溃后的未保存训练恢复、LLM 周总结属于后续独立迭代。
