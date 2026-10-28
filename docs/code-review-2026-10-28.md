# 小盏 / luma 代码审查与改进建议

审查日期:2026-10-28
审查范围:`LogicPackage/`(逻辑层)、`OfficeWorkoutCoach/`(App 层)、`tools/`
出发点:**让 App 真正帮用户"系统地把锻炼做完"**,而不只是记录和提醒。

---

## 一、结论

当前产品在"决策"和"记录"两件事上做得不错:推荐引擎是纯函数、有 25 个测试钉住规则,
统计快照与 UI 解耦,提醒链路(久坐升级)移植得干净。

**但它缺了中间最关键的一环 —— "执行"。**

用户点「开始 力量 A」,直接跳到一张要求填写「完成度 / 主观强度 / 时长」的表单。
问题很明显:**用户还没开始练,却被要求填写练完之后才知道的东西**。
这不是交互细节问题,是流程顺序反了。

结果就是:App 能告诉你"今天该练什么",却没法陪你"练完",最后只能靠回忆补录一个数字。
而要"系统完成锻炼",需要的恰恰是中间那段:动作顺序、每组做几个、组间休息多久、练到第几组了。

好消息是:**这些数据其实已经写好了**。`ExerciseGuideView.swift:296-478` 里
`ExercisePrescription` 已经为 14 个"动作×计划"组合定义了剂量、节奏、休息、预计时长。
只是它被写成视图层里的 `private struct`,逻辑层拿不到,所以跟练模式无从复用。

---

## 二、必须修的缺陷(P0)

### 1. 通知的"开始 8 分钟"按钮点了没反应 —— 双单例 bug

`NotificationManager.swift` 里定义了两个单例:

```swift
static let shared = NotificationManager()          // 第 17 行
static let sharedInstance = NotificationManager()  // 第 56 行
```

App 注入环境用的是 `sharedInstance`(`OfficeWorkoutCoachApp.swift:9`),
而用户点击通知时,回调里把深链写到了**另一个实例**:

```swift
// NotificationManager.swift:311
if isStart { NotificationManager.shared.pendingDeepLink = .startMinimal }
```

`MenuBarPopoverView` 观察的是 `notifier.pendingDeepLink`(即 `sharedInstance`),
永远收不到 → **点击通知动作"开始 8 分钟"不会跳转**,只会把 App 拉到前台。

修复:删掉 `shared`,统一用 `sharedInstance`(或反过来),并让两处引用同一个。

### 2. `.rest` 是死代码 —— 没有过度训练保护

`Recommendation.Action` 定义了 `.rest`(`RecommendationEngine.swift:10`),
`MenuBarPopoverView` 为它准备了图标和文案(`popover.cta.rest` "今天休息"),
但 `recommend()` 里**没有任何分支会返回 `.rest`**。

后果:即使本周目标全部达成、连续练了 7 天没休息,引擎仍会返回 `.recovery`。
**系统永远不会建议你休息**,这在"系统训练"里是硬伤 —— 恢复本身是训练的一部分。

建议补一条规则,优先级放在规则 3 之后:

```
若 连续训练天数 >= N(默认 6)且本周目标已达成 → 建议休息
```

需要在 `WorkoutStats` 增加 `consecutiveActiveDays` 字段。

### 3. 腰痛识别会把普通备注误判

`WorkoutStatsService.swift:6`:

```swift
public static let terms = ["腰紧", "腰酸", "腰痛", "腰不舒服", "backtight", "back tight", "back"]
```

- `"back"` 这个 term 太宽泛。英文备注写 `"back to normal"`、`"feel good, back hurts less"`
  都会被判为腰痛,触发"腰背恢复"推荐并屏蔽硬拉/弓步。
- 另外 `terms` 里的中文词(`腰紧`/`腰酸`)**永远匹配不到** `bodyFeeling` 字段 ——
  因为存进去的是枚举 rawValue(`backTight`),不是显示文案。这些词只对 `notes` 生效,
  设计意图与实现不一致。

建议:`bodyFeeling` 改为结构化判断(直接比较枚举),`terms` 只用于扫描 `notes`,
并去掉过于宽泛的 `"back"`(改成 `"back pain"` / `"backache"` / `"lower back"`)。

---

## 三、功能改进(按"帮助系统完成锻炼"的价值排序)

### P1 · 跟练模式(WorkoutStartView)—— 这是核心缺口

现在点「开始」= 打开记录表单。应该改成:

```
开始 → 动作 1 详情(视频/要领/剂量) → [开始本组] 计时 → 完成 → 组间休息倒计时
     → 下一组 ... → 动作 2 ... → 全部完成 → 自动生成记录(可补备注)
```

落地要点:
1. **把 `ExercisePrescription` 从视图层搬到 `LogicPackage`**,改成 `public` 的
   `Prescription` 类型,挂在 `Exercise` 上或独立查询。这样才能被跟练页复用、被单测覆盖。
2. 新增 `WorkoutStartView`(独立 Window,和动作示意窗口同一套尺寸策略)。
3. 训练中禁止久坐提醒插话(见 P3)。
4. 结束时把实际完成情况写回,而不是让用户手填。

这一步做完,App 才真正从"提醒器"变成"教练"。

### P2 · 记录粒度:加入组次与重量

`WorkoutSession` 目前只有 `type / duration / completion / intensity / bodyFeeling / notes`。
**没有重量,没有组次** → 无法做渐进超负荷,也无法回答"我比上个月强了吗"。

建议新增:

```swift
@Model final class SetRecord {
    var exerciseID: String
    var setIndex: Int
    var reps: Int
    var weightKg: Double?
    var completedAt: Date
    var session: WorkoutSession?   // 反向关系
}
```

配套:
- 跟练时每组结束记录 reps(±按钮)和重量(可选,办公室哑铃可以只记"轻/中/重")
- 动作详情页显示"上次:12kg × 10,10,9",给本次一个目标
- `planCode` 字段目前从不赋值,应改成记录实际使用的计划(A/B/自定义)

### P3 · 提醒与训练打通

- **语义错位**:久坐提醒文案说"做一组腰背恢复:猫牛式、臀桥…",但点它的 START 按钮
  跳到的是 **8 分钟最低版**(`DeepLink.startMinimal`)。应该跳到腰背恢复跟练。
- **训练中免打扰**:跟练进行中应暂停久坐计时(`activeSince` 重置),否则练到一半被弹窗打断。
- 冷却时间 `cooldown = 2700`(45 分钟)是硬编码常量,建议放进设置。
- `UserDefaults` 里 `flex.lastFired.yyyy-MM-dd` 每天新增一个 key、永不清理,
  一年 365 个。建议改为单个 key 存最后一次日期。

### P4 · 数据只进不出

练了一年的数据锁在 SwiftData 里,重装/换机就没了,也无法用 Excel 分析。
建议加:
- 导出 CSV(日期、类型、时长、完成度、强度、感觉、备注、各组次)
- 导入/恢复
- 至少提供"导出备份"入口,放在设置里

### P5 · 推荐引擎的规则补强

| 问题 | 现状 | 建议 |
|---|---|---|
| 今天跑过就永远推荐恢复 | 规则 2 无条件生效 | 加"用户主动改选"入口,或仅在距跑步 <4 小时时生效 |
| A/B 交替不看间隔 | 只看 `lastStrengthType` | 用已算好但未使用的 `daysSinceLastStrength`,同一肌群 48h 内不重复 |
| 无过度训练保护 | 见 P0-2 | 加连续训练天数规则 |
| 不区分"没时间" | 只有 full/minimal 两档 | 加"10 分钟版"(每动作 2 组),覆盖中间场景 |

---

## 四、UI 改进

### 1. 菜单栏徽标信息过载(最显眼的问题)

现在菜单栏显示:`S 0/1 0/7 / R 0/2 0/14 / R 0/2` —— 9 个数字、约 200pt 宽。

问题:
- **两个 "R" 分别是"恢复"和"跑步"**,缩写重复,扫一眼无法区分
- 用户真正想知道的是"我今天还差什么",而不是六组比值
- 占用菜单栏空间过多,和其他 App 抢位置

建议改为**三态极简**:

| 状态 | 显示 |
|---|---|
| 今日未达标 | 图标 + `1/3`(今日完成项数/总项数) |
| 今日全达标 | 图标填充 + 绿色勾 |
| 本周也全达标 | 图标 + 轻微高亮 |

周进度、分项明细移到弹窗内 —— 那里空间足够,而且用户点开就是要看细节。

### 2. 弹窗结构:从"表单堆叠"到"决策界面"

现在首页 4 个区块用 3 条 `Divider` 硬切,视觉上是平铺的表单。
而"快速记录"里 6 个按钮(力量A/力量B/跑步/恢复/最低版/休息)全部平铺 ——
**推荐引擎已经告诉你该做什么了,这 6 个按钮反而制造选择困难**。

建议:
- 今日建议卡片做成视觉主体(大图标 + 一句话理由 + 一个主按钮),占据上半屏
- 6 个快速记录收进「其他」折叠区,默认只显示"改选"链接
- 进度区改成三条细进度条,而不是数字 chip

### 3. 记录完成没有任何反馈

`QuickLogView.save()` → `onDone()` → `backToHome()`,只是切页。
用户感知不到"这次记录成功了吗?进度涨了吗?"

建议:保存后显示 0.6 秒的完成态(勾 + "已记录 力量 A · 25 分钟"),
并让弹窗内的进度条做一次增长动画。菜单栏徽标同步更新,但用户此刻看的是弹窗。

### 4. 色彩与控件不统一

- **三套色彩语言**:徽标用绿/红 chip(`OfficeWorkoutCoachApp.swift:232`),
  今日建议用 `.tint`,趋势图用 `accentColor` 且未达标用 `secondary.opacity(0.3)`
- **三种按钮样式混用**:`.borderedProminent`(主操作)、`.bordered`(快速记录)、
  `.borderless`(页脚图标)
- 徽标是手绘 `NSImage`(200 行绘制代码),硬编码 `NSColor.white` 和
  `calibratedRed: 0.86...`,**不随系统强调色和深色模式适配**

建议:定义一套语义色(达标=绿、未达标=橙、进行中=蓝),徽标简化为单色 template
图标 + 极简数字,让系统自动处理明暗。

### 5. 窗口尺寸不一致

- 弹窗 `.frame(width: 320)`,`QuickLogView` 内又设 `.frame(width: 300)` → 切换页面时宽度跳动
- `SummaryView` 固定 `height: 460`,内容少时底部大片留白

建议统一由容器控制宽度,子页面只控制内容。

### 6. 动作示意窗口止步于"看"

处方信息(3 组 × 8-12 次、休息 45-75 秒)已经完整展示,但**只是只读文本**,
不能从这里直接开始跟练。这是通往 P1 最自然的位置 —— 加一个「开始这个动作」按钮即可。

---

## 五、架构改进

| 问题 | 位置 | 影响 |
|---|---|---|
| 处方数据在视图层 | `ExerciseGuideView.swift:296-478` | 无法复用、无法测试,跟练模式做不了 |
| `asRecord` 丢信息 | `WorkoutSession.swift:55` | 只传 id/date/type/bodyFeeling,时长/完成度/强度进不了逻辑层,统计只能用"次数"这一个维度 |
| 徽标手绘 200 行 | `OfficeWorkoutCoachApp.swift:161-268` | 维护成本高,明暗/强调色不适配 |
| App 层测试仅 1 个 | `OfficeWorkoutCoachTests/` | 推荐引擎有 25 个测试,但所有 UI 派生逻辑(徽标文案、进度计算、格式化)零覆盖 |

---

## 六、建议路线图

**第一步 · 修 bug(半天)**
1. 合并 `NotificationManager` 双单例 → 通知按钮恢复可用
2. 补 `.rest` 规则 + `consecutiveActiveDays` → 有休息建议
3. 修正腰痛关键词 → 减少误判

**第二步 · 跟练模式(核心,2-3 天)**
4. `ExercisePrescription` 下沉到 `LogicPackage` 并补测试
5. 新增 `WorkoutStartView`:动作序列 → 计时 → 组间休息 → 完成
6. 从"今日建议"和"动作示意"两处都能进入
7. 训练中抑制久坐提醒

**第三步 · 让它能追踪进步(2 天)**
8. 引入 `SetRecord`(组次 + 重量)
9. 动作详情显示"上次成绩",跟练时给目标
10. 周总结加入"重量/次数趋势"

**第四步 · 打磨(1-2 天)**
11. 菜单栏徽标简化为三态
12. 弹窗重排:建议卡为主体,快速记录折叠
13. 保存反馈 + 进度动画
14. 数据导出 CSV

---

## 附:值得保留的设计

审查中也有几处做得比同类产品好,改进时不要推翻:

- **推荐引擎是纯函数**,输入 `WorkoutStats` + `UserGoalValues`,无 I/O —— 所以 25 个测试
  能秒级跑完,规则改动有安全感。这个分层必须保住。
- **文案 key 与逻辑分离**(`Recommendation` 只返回 key + 插值,`UILocalization` 负责翻译),
  中英文都能兜住。
- **久坐提醒的升级链**(通知 → 2 分钟语音 → 10 分钟模态)比大多数提醒 App 认真,
  会议应用自动延后这个细节很实用。
- **媒体自动降级**(视频 > 图片 > 占位,文字始终显示),不会因为缺素材报错。
