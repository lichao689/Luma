# Apple Health 数据桥接（P1）

小盏的 macOS 客户端通过用户选择的 JSON 文件接收健康数据。仓库内的独立 iOS 工具 `HealthBridgeIOS/LumaHealthBridge.xcodeproj` 负责请求读取权限、读取可见数据和导出文件。工具只做这条接入路径，不包含训练跟练、Apple Watch App、后台同步或服务器上传。

## 为什么需要 iPhone / iPad 工具

Apple 的 HealthKit 框架在 macOS 上提供部分符号以便跨平台编译，但 macOS 没有可读写的 HealthKit 数据库。原生 Mac App 必须检查 `HKHealthStore.isHealthDataAvailable()`，不能因成功链接框架就宣称能读取 Apple 健康。本项目让 iOS 17 及以上的设备读取本地健康库；Apple Watch 生成的记录需先通过 Apple 的健康同步出现在该设备上。[Apple：设置 HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)；[框架概览](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework)。

## 使用流程

1. 用 Xcode 打开独立项目，选择自己的签名团队，将工具安装到支持健康数据的 iPhone 或 iPad。
2. 选择最近 7、30 或 90 天，点击“授权并读取”。系统分别请求运动、步数、睡眠的读取权限；`toShare` 为空，不请求写入权限。
3. 查看本次可见记录数量，点击“保存健康数据文件”。文件只在用户选择的位置保存；可用 AirDrop 等方式传给 Mac。
4. 在 Mac 小盏的“设置 → 数据”中选择健康数据导入，查看导入预览后确认。只有 `running` 运动进入跑步记录；步行、骑行、力量训练和其他运动保留为健康数据上下文，不自动视作完成计划 A / B。
5. 后续重新读取、导出、导入即可更新。相同文件再次导入不会重复创建跑步记录；旧文件也不会复活已删除的记录。

App 自身不发送网络请求，不写回健康库。导出的 JSON 是可读的健康数据文件，文件保存位置和后续传输方式由用户决定。iOS 本地仅额外保留查询锚点和已经观察到的删除 ID，使用文件保护写入 Application Support。

## 授权与空结果的含义

`requestAuthorization` 完成只表示系统处理了授权请求。Apple 为保护隐私，不向 App 透露用户是否拒绝了读取权限。空查询结果可能代表没有记录、未授权该类别，或仅允许较近时间的数据；界面不能显示“已获得全部权限”，也不能据此推断“今天没有运动”。[Apple：健康数据授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)；[授权请求结果](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:completion:))。

工具保留这些区别：步数 `nil` 表示没有可见数量，睡眠没有可见的 asleep 区间时返回 `nil`；二者都不替换为零。某类新导出为空时，也不删除以前导入的记录。历史步数在后续不可见时保留原值及原 `observedAt`，因此展示的是上次可见观察，不保证是当前健康库的完整状态。

## JSON v1 数据契约

入口为共享 Swift 包中的 `HealthBridgeCodec.encode/decode`，数据类型为 `HealthBridgePacket`。文件限制为 16 MiB、最多 100,000 条数据和删除标记；解码拒绝未知格式/版本、重复样本 ID、无效时区、非有限或负数数量，以及无效时间区间。

| 字段 / 类型 | 语义与单位 |
| --- | --- |
| `format` / `schemaVersion` | 固定为 `luma-health` / `1`。 |
| 包 `id` | 每次读取导出生成一个 UUID；同一文件不变，用于导入、完整备份和文件夹同步去重。 |
| 所有日期字段 | JSON 数值为 **自 2001-01-01 00:00:00 UTC 起的秒数**，即 Foundation reference date；保留 `Date` 的小数秒精度。解码器也接受带时区的 ISO 8601 字符串。不是 Unix epoch 毫秒。 |
| `generatedAt`、`periodStart` / `periodEnd` | 本次查询的观察时间和所选时间窗口；当前一天仅观察到 `generatedAt`。 |
| `timeZoneIdentifier` | 导出时设备日历时区；日界线按该时区计算，允许夏令时导致的 23 / 25 小时日。 |
| `workouts` | 保留 HealthKit UUID、源 App bundle ID、活动类别、起止时间。`durationSeconds` 为 `HKWorkout.duration` 的活动秒数，可能小于起止时间差，因为训练可暂停。 |
| `stepDays` | 每个本地日的 `start/end`、时区、可选 `count`（步）、`observedAt` 和 `sourceBundleIdentifiers`。日期桶由时区及起止时间识别；`count` 缺失不等于零。 |
| `sleepSamples` | 保留 HealthKit UUID、源 bundle ID、起止时间以及 `inBed/awake/asleepUnspecified/asleepCore/asleepDeep/asleepREM` 原始类别。 |
| `deletedWorkoutIDs` / `deletedSleepIDs` | 只含明确获知的删除 UUID。绝不根据日期范围外或读取结果中缺失的记录推断删除。 |

运动 UUID 直接取 `HKObject.uuid`，不会用时间、名称或日期重新造 ID。原始的活动秒数、睡眠样本和来源都保留在健康包中，Mac 跑步记录使用已有的分钟字段。该导入不会猜测主观强度、身体感受、动作组数或负重。[Apple：对象 UUID](https://developer.apple.com/documentation/healthkit/hkobject/uuid)；[训练活动时长](https://developer.apple.com/documentation/healthkit/hkworkout/duration)。

### 步数和睡眠聚合

步数总量来自 `HKStatisticsCollectionQuery` 的 `.cumulativeSum`，让 HealthKit 先合并多个来源。工具不把 iPhone 和 Apple Watch 原始样本简单相加。Apple 只在 `.separateBySource` 查询中提供来源数组，因此工具额外执行一次按源查询来保留来源列表，但不使用该查询的分来源数量计算总量。列表表示该日可见数据涉及的源，不提供各源在最终合并数量中的权重。[Apple：统计合并行为](https://developer.apple.com/documentation/healthkit/hkstatistics)；[统计来源](https://developer.apple.com/documentation/healthkit/hkstatistics/sources)。

睡眠统计先筛选四种 asleep 状态，裁剪到展示时间窗口，再计算区间并集；重复记录和不同来源重叠的睡眠区间只计时一次。`inBed` 和 `awake` 不增加睡眠时长。这个统计没有做阶段质量评分，也不会把多个来源相互矛盾的睡眠分期当作医学结论。[Apple：睡眠类别](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)。

### 去重、更新与删除

Mac 存储原始导出包，按 `generatedAt`（相同时再按包 UUID）排序后归并。相同样本 UUID 使用较新的快照；步数按日期桶更新，不跨文件累加，新的非空观察替换旧值。相同观察时间的同 UUID 运动或睡眠内容不同、同一步数日期桶的两个已知数量不同，都作为冲突拒绝；相同时间和数量的来源列表取并集，不增加步数。导入相同包 ID 但内容不同的文件也会作为冲突拒绝，不覆盖原包。聚合结果用于展示，不能冒充一次新的原始导出存档。

本地删除的跑步 UUID 作为 tombstone 保留，并优先于后续导入。iOS 对运动与睡眠分别保存 `HKAnchoredObjectQuery` 锚点，把 Apple 返回的 `HKDeletedObject` UUID 累积到导出包。扩大查询范围时先读取旧锚点的删除结果，再建立更早起点的新锚点；删除标记始终保留。导入旧文件不会撤销删除。[Apple：锚定查询及删除对象](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)。

这些删除变化需要再次运行 iOS 工具并传输文件。删除工具、清空其数据或更换设备会丢失该设备此前保存的锚点；工具不能承诺重建此前未观察到的删除历史。无权限、无记录或有限读取范围也不能当作批量删除信号。步数是日期汇总，没有逐样本 tombstone；重新可见的非空汇总可以修正数量，变为空值则保留最近一次已知观察。

## 构建与验证

在仓库根目录运行共享逻辑测试：

```sh
swift test --package-path LogicPackage --filter HealthBridgeTests
```

在安装 Xcode 16 或更新版本的 Mac 上，无签名构建 iOS 模拟器目标：

```sh
xcodebuild -project HealthBridgeIOS/LumaHealthBridge.xcodeproj \
  -scheme LumaHealthBridge -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

项目引用 `../LogicPackage`，不需要服务端密钥、账号令牌或第三方依赖。真机运行需在 Signing & Capabilities 中设置开发团队、可用 bundle ID 及 HealthKit 能力；仓库不写入任何个人签名信息。

共享逻辑的 14 个测试覆盖数据往返、小数秒精度、重复导入、来源更新、同时间冲突、旧文件重放、本地/源删除、睡眠并集、未知步数、夏令时日、非法数值与文件大小限制。Linux 可运行这些逻辑测试和 Swift 语法解析，但不能替代 Apple SDK 编译或设备权限验证。

发布前的实际验收包括：在真机分别允许全部、部分和拒绝读取，核对空状态；对照健康 App 检查当天步数和跨日睡眠；导入同一文件两次确认无重复；在健康 App 删除已导入运动/睡眠后再次导出确认删除传播；在 Mac 删除跑步后重导入旧文件确认不复活。Apple Watch 数据需先在 iPhone 健康 App 可见。这些涉及 Apple 健康库、系统授权和真实同步的行为仍需设备验收，不能用模拟器构建成功代替。
