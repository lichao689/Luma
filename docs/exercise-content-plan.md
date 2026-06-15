# 动作示意内容计划

目标: 为 `OfficeWorkoutCoach` 的「力量 A」「力量 B」「腰背恢复」提供一套能快速阅读的动作示意内容。第一版采用静态图 + 标注说明,不做视频。

## 环境边界

本项目优先服务真实办公室环境: **一张瑜伽垫 + 办公室可用哑铃**。动作可以使用哑铃,但不得依赖凳子、椅子、长凳、门框、墙面或健身房固定器械。若某个标准动作常见版本需要家具支撑,必须改成站姿或垫上变体。

## 设计原则

- 每个动作 1 张主图: 1024x1024,浅色背景,线稿/扁平插画风格。
- 图片中不放中文文字。图片只放姿势、方向箭头、受力/对齐提示点;中文解释放在 App 文案里。
- 重点少而准: 每张图最多强调 3 个视觉要点。
- 风格统一: 同一人物比例、同一地面线、蓝色表示正确对齐/发力方向,红色表示需要注意的错误方向或风险点。
- 不追求复杂解剖图。目标是让用户扫一眼知道“身体该怎么摆、哪里不要错”。
- 腰背恢复动作遵循低负荷、可控、疼痛不加重原则。若出现放射痛、麻木、刺痛或疼痛明显加重,应停止并寻求专业建议。

## 资源命名

图片放在:

```text
OfficeWorkoutCoach/Resources/Exercises/
```

文件名使用动作 id:

```text
gobletSquat.png
pushUp.png
shoulderPress.png
gluteBridge.png
plank.png
romanianDeadlift.png
bentOverDumbbellRow.png
reverseLunge.png
proneWRaise.png
sidePlank.png
catCow.png
pelvicTilt.png
deadBug.png
birdDog.png
hipFlexorStretch.png
```

## 力量 A

| 动作 | 目的 | 图上重点 | 降低难度 | 停止条件 |
|---|---|---|---|---|
| 高脚杯深蹲 | 腿、臀、核心抗压 | 膝盖跟脚尖;胸口立起;脚跟踩实 | 减轻哑铃/徒手深蹲/半程 | 膝痛、腰部代偿明显 |
| 俯卧撑 | 胸、肩、核心 | 身体一条线;手肘约 45°;胸口靠近地面 | 跪姿俯卧撑 | 肩前侧刺痛、腰塌无法控制 |
| 站姿哑铃肩推 | 肩、核心稳定 | 肋骨不外翻;哑铃垂直;手腕中立 | 减轻哑铃/单臂轻重量 | 肩刺痛、明显后仰顶腰 |
| 臀桥 | 臀部激活、腰背友好 | 臀部发力;肩-髋-膝成线;不过度顶腰 | 小幅度臀桥 | 腰疼代偿明显 |
| 平板支撑 | 核心抗伸展 | 肩-髋-踝成线;肘在肩下;自然呼吸 | 膝支撑平板 | 腰痛加重、憋气失控 |

## 力量 B

| 动作 | 目的 | 图上重点 | 降低难度 | 停止条件 |
|---|---|---|---|---|
| 罗马尼亚硬拉 | 臀、腘绳肌、髋铰链 | 髋向后推;哑铃贴腿;背部中立 | 减轻哑铃/只到膝盖 | 腰部顶痛、腿后侧麻木 |
| 俯身哑铃划船 | 背部、肩胛控制 | 背部中立;手肘拉向后腰;躯干稳定 | 减轻哑铃/减少前倾 | 下背撑不住、肩颈越练越紧 |
| 反向弓步 | 单腿力量、臀腿、平衡 | 前膝跟脚尖;后脚轻点地;躯干稳定 | 小步幅/半程弓步 | 膝痛、髋前侧夹痛 |
| 俯卧 W 提拉 | 中背、肩胛控制 | 肩胛后收;颈部放松;不耸肩 | 只做肩胛后收 | 颈部紧张或腰背不适 |
| 侧平板 | 侧腹、抗侧屈核心 | 肩-髋-踝成线;肘在肩下;髋不下沉 | 膝支撑侧平板 | 肩肘痛、腰侧不适 |

## 腰背恢复

| 动作 | 目的 | 图上重点 | 降低难度 | 停止条件 |
|---|---|---|---|---|
| 猫牛式 | 温和活动脊柱 | 四点支撑;背部圆起/下沉;动作慢 | 小幅度活动 | 疼痛被拉尖、头晕 |
| 骨盆后倾 | 找到腰背中立与核心控制 | 腰背轻贴地;骨盆向后卷;呼气 | 减小幅度/只配合呼吸 | 腰痛加重 |
| 死虫式 | 核心抗伸展 | 腰背贴地;对侧手脚伸展;慢速呼气 | 只动手或只动腿 | 腰离地且无法控制 |
| 鸟狗式 | 脊柱稳定、抗旋转 | 骨盆不旋转;对侧手脚伸直;背平 | 只伸腿/只伸手 | 腰塌或放射痛 |
| 臀桥 | 臀部激活、减轻腰部代偿 | 臀发力;肩髋膝成线;顶峰停顿 | 小幅度桥式 | 腰部顶痛 |
| 髋屈肌拉伸 | 缓解久坐髋前紧张 | 骨盆微后倾;前侧髋有拉伸;躯干直立 | 站姿弓步拉伸 | 膝盖压痛、腰椎挤压感 |

## Imagegen 提示词模板

```text
Use case: scientific-educational
Asset type: macOS exercise guide image
Primary request: Simple static exercise illustration for <exercise name>.
Subject: One neutral, non-identifiable adult figure demonstrating the correct position.
Style/medium: clean flat educational illustration, simple line art, minimal anatomy, not photorealistic.
Composition/framing: square 1:1, full body visible, generous padding, light warm off-white background, subtle floor line.
Annotation style: use only colored arrows, alignment guide lines, and small colored dots; no words, no letters, no numbers.
Color palette: dark gray figure, blue arrows for correct direction/alignment, red accent only for caution/avoid direction.
Constraints: quick to read, uncluttered, one main pose or two ghosted phases only when necessary.
Avoid: text, watermark, logo, complex gym background, detailed face, exaggerated muscles, medical gore, photorealism.
```

## 生成顺序

1. 腰背恢复 6 张: `catCow`, `pelvicTilt`, `deadBug`, `birdDog`, `gluteBridge`, `hipFlexorStretch`
2. 力量 A 5 张: `gobletSquat`, `pushUp`, `shoulderPress`, `gluteBridge`, `plank`
3. 力量 B 5 张: `romanianDeadlift`, `bentOverDumbbellRow`, `reverseLunge`, `proneWRaise`, `sidePlank`

先做腰背恢复,因为它也服务久坐提醒,使用频率最高。
