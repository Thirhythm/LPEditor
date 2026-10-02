# 架构说明

本文说明 LPEditor 的分层、数据流与重构后的目录约定，供后续维护者快速定位代码。

## 1. 分层

```
core/    纯逻辑，无场景树依赖（可单测）
audio/   播放与音频分析，桥接 core 与 Godot 音频 API
ui/      界面：场景 + 控件脚本，按功能分目录
tests/   针对 core 与可测 UI 逻辑的测试套件
```

依赖方向单向向下：`ui/` → `audio/` → `core/`。`core/` 中任何文件都不应 `get_node`、不引用节点路径、不读取场景。

## 2. 两个核心静态类

| 类 | 职责 | 关键成员 |
| --- | --- | --- |
| `core/chart_data.gd`（`ChartData`） | 一份谱面文档 | 元数据（`title` / `artist` / `vocalist` / `illustrator` / `creator` / `difficulty` / `version` / `bpm` / `preview_ms` / `preview_end_ms` / `crystal` / `chapter`）、`notes` / `effects` / `audio_path` / `jacket_path` / `audio_duration_ms` / `waveform_samples` / `current_file_path`，`to_dict()` / `load_from_dict()` / `get_max_scroll_time()` / `capture_snapshot()` |
| `core/editor_state.gd`（`EditorState`） | 一次编辑会话 | `scroll_time` / `px_per_ms` / `quantize_denominator` / `snap_enabled` / `selected_notes`，`push_undo_state()` / `undo()` / `redo()` / `clamp_scroll()` / `snap_time()` / `mark_saved()` / `is_dirty()` |

选择「类静态成员」而不是 autoload 的原因：

1. 不依赖 `project.godot` 的 autoload 注册，改动后编辑器无需重启即可解析；
2. 不依赖场景树，测试可以直接驱动（`tests/test_editor_state.gd` 完全不创建节点）；
3. 访问形式与 autoload 单例一致（`ChartData.notes`），迁移成本低。

代价：静态状态在编辑器与运行的游戏进程之间不共享（这与 autoload 行为一致，无实际影响）。

## 3. 撤销 / 重做

```
EditorState.push_undo_state()
        │
        ├─ ChartData.capture_snapshot()        文档字段（notes 深拷贝）
        ├─ quantize_denominator / snap_enabled 会话字段
        └─ UndoHistory.push(snapshot)          入栈并清空重做链
```

`undo()` / `redo()` 先捕获当前快照压入对侧栈，再恢复取出的快照；恢复期间 `_is_undoing` 为真，
避免内部写入产生新的撤销点（`tests/test_editor_state.gd::test_undo_does_not_record_its_own_restore` 覆盖该行为）。

## 4. UI 组件与信号

```
MainEditor（ui/main_editor/main_editor.tscn）
├─ AudioManager           播放控制；音频分析结果写入 ChartData
├─ Panel/…/List, List2    工具列表（ToolList，按钮由场景编排）
├─ Panel/…/Ruler          EditorRuler：波形 + 缩略图 + 播放头
├─ Panel/…/Property       PropertyPanel：元数据 / 音符 / 特效 / 设置，折叠展开
├─ TrackUI/…/Visual       EditorVisual：轨道编辑区
└─ ConfirmDialog          未保存更改确认（保存 / 不保存 / 取消）
```

- `EditorVisual` 通过 `note_selected` / `note_deselected` / `note_placed` / `note_moved` /
  `note_resized` / `note_deleted` / `scroll_changed` 通知主控制器，主控制器再刷新其它面板。
- 特效走同一套模式：`effect_selected` / `effect_deselected` / `effect_start_set` /
  `effect_end_set` / `effect_deleted` 由 `EditorVisual` 发出，`effect_changed` 由 `PropertyPanel` 发出。
- `PropertyPanel` 通过 `meta_changed` / `note_changed` / `effect_changed` 通知内容变化，
  通过 `jacket_browse_requested` / `audio_browse_requested` / `preview_capture_requested`
  请求主控制器代劳（弹曲绘 / 音频文件对话框、把播放头回填成预览时间）；
  另有 `panel_toggled` 报告折叠状态，目前没有接收方。
- 主控制器不持有数据副本，所有读写都落到 `ChartData` / `EditorState`。
- `TrackUI` 是浮在 `Panel` 之上的独立图层（`clip_contents = true`），启动时与每次窗口尺寸变化、
  属性面板折叠时，`MainEditor._update_layout()` 都会按标尺底部 / 工具栏右侧 / 属性面板左侧 /
  状态栏顶部的**实际位置**重算它的 offsets（而不是把像素写死在场景里），所以轨道区既不压到标尺或
  两侧面板，也会跟着窗口一起变。
- 轨道区另有宽高上限：`TRACK_AREA_MAX_WIDTH_RATIO` / `TRACK_AREA_MAX_HEIGHT_RATIO`
  （占窗口总宽 / 总高的比例）。中间区域超过上限时，多出来的部分平分到两侧，轨道区居中 ——
  轨道是编辑工作面，超宽或超高的窗口上放任铺满会把音符拉得过大。
  宽度上限还有个保底：不低于轨道自身的最小宽度之和，否则窄窗口上会把轨道切掉一截。
- 属性面板的四段内容（谱面 / 音符 / 特效 / 设置）叠起来比一屏还高，所以内容装在
  `HBox/ContentScroll`（`ScrollContainer`）里滚动；外层 `HBox` 必须用全屏 anchors 撑满面板 ——
  `ScrollContainer` 的最小高度不包含内容，若让它按最小尺寸定位，整个面板会塌成一条。
- `ParkPanel` 带 `size_flags_vertical = 3`，会吃掉窗口下方的全部余高（最小 470px）：窗口越大
  面板可视区越高、要滚的越少（1080p 下可视 902px，需滚 318px；1440p 下内容全部可见）。
  主内容列的底边由 `_update_layout()` 钉在状态栏上方，否则伸展开后会铺到窗口底被状态栏压住。

## 5. 特效（Effects）

特效是「一段时间内生效的谱面变化」，序列化后与 `HitObjects` 同级：

```json
"Effects": [
    { "type": "change", "time": 5000, "changed": [2, 3, 4, 1], "duration": 2000 }
]
```

- `time` 是开始时间，`duration` 是持续时间；面板上按「开始时间 / 结束时间」两个字段编辑，
  改任一端都保持另一端不动（时长随之伸缩）；
- `changed` 固定 `EFFECT_CHANGED_SIZE`（= 轨道数）项，每项取值 1..`NUM_TRACKS`；
  面板上用逗号分隔填写（与 heart 音符的 `map` 同一套写法），
  `ChartDefs.normalize_changed()` 负责把填写的列表补足 / 收敛到合法范围；
- 定义与构造集中在 `ChartDefs` 的「特效」段（`EFFECT_TYPES` / `make_effect()` /
  `effect_end_time()` / `EFFECT_COLOR`），`ChartData.effects` 与序列化、撤销快照、
  `get_max_scroll_time()` 同步维护。

放置流程（两次点击定区间）：

```
点「行为 → 添加特效」
        │  MainEditor._begin_add_effect()：建默认特效 → ChartData.effects → push_undo
        ▼
EditorVisual.begin_effect_placement(index)     光标变十字，进入放置模式
        │
        ├─ 第 1 次点击 → 写入 time（量化吸附），继续等待
        └─ 第 2 次点击 → 写入 duration = max(点击时间 − time, EFFECT_MIN_DURATION_MS)，退出放置
```

`VisualRenderer._draw_effects()` 把区间画成横跨四条轨道的半透明色带，作为背景层画在
网格线与音符**之下**（`draw_all()` 里的顺序是 底色 → 特效 → 网格线 → 音符 → 播放头），
开始 / 结束各有一条边界线，选中时加白色描边。音符命中优先于特效，
因此铺满轨道区的色带不会挡住音符的选中与拖拽。

退出放置的时机：切换工具或分类、删除正在放置的特效、撤销与载入谱面，都会调用
`EditorVisual.cancel_effect_placement()`；已创建的特效保留在文档里，可用撤销移除。

放置完成后区间仍可继续用鼠标调整，规则与长键的拖拽同构：

| 抓取位置 | 行为 | 光标 |
| --- | --- | --- |
| 开始 / 结束边界线 | 只动被抓的那一端，另一端固定；抓起始边越过结束边时时长收敛到 `EFFECT_MIN_DURATION_MS` | `CURSOR_VSIZE` |
| 色带内部 | 整个区间平移，时长不变（按按下时的抓取时间做相对位移，抓中间不会跳） | `CURSOR_MOVE` |

边界命中半径 `EFFECT_EDGE_HIT_RADIUS` = 8px，两条边都够得着时取更近的那条；
落在区间内部时半径收缩到带高的 35%，这样被拖短（乃至缩到 1ms）的区间中间仍留得出
拖本体平移的余地。命中顺序与 `_on_left_click` 一致：长键尾 → 音符 → 特效边界 → 特效本体，
所以音符压在色带上时光标提示的仍是拖音符。

按下时压一次撤销点，拖动过程中直接改 `ChartData.effects` 并重绘，松开时用
`effect_adjusted` 通知主控制器刷新面板与状态栏（只是点了一下没真拖动则不通知）。

## 6. visual 三分

原 `visual.gd`（530 行）按职责拆为：

| 文件 | 内容 | 依赖 |
| --- | --- | --- |
| `ui/visual/visual.gd` | 交互：滚轮、点击命中、放置、拖拽、删除、平滑滚动 | 转发几何调用 |
| `ui/visual/visual_geometry.gd` | 时间 ↔ Y、X ↔ 轨道、可见时间范围、量化吸附 | `EditorState` / `ChartDefs` |
| `ui/visual/visual_renderer.gd` | 轨道底色、BPM 网格、音符、判定线 | `ChartData` / `ChartDefs` / `VisualGeometry` |

绘制方法全部为静态方法并接收 `Control` 参数（需要 `get_theme_default_font()`，故不是 `CanvasItem`）。

> 音符绘制按类型分派：长键画竖条加头尾把手，其余（tap / drag / release / heart）
> 统一画矩形，彼此只有配色不同 —— heart 用的是 `#700f0f`。

## 7. 文件读写

`ui/main_editor/chart_io.gd`（`ChartIO`）承担 `.lp` 的读写与 `.lpz` 打包，全部返回
`{ ok, error }` / `{ ok, error, data }`，由 `MainEditor` 决定提示方式。
它不引用任何节点，因此可脱离界面测试与复用。

导出包结构：`chart.lp`（去掉 `AudioPath` / `JacketPath` 的 JSON）+ `audio.<ext>` + `cover.<ext>`。

### `General` 段

右侧属性面板的「谱面」区与 `General` 一一对应，`to_dict()` 的输出顺序即下面的顺序：

```
Title / Artist / Vocalist / Illustrator / Creator / Difficulty / Version / BPM /
Preview / PreviewEnd / Crystal / Chapter / JacketPath / AudioPath
```

- `Preview` / `PreviewEnd` 是试听区间的起止毫秒值，面板上各有一个「取播放头」按钮回填；
- `Crystal` 是解锁本曲需要的虚拟货币数，`Chapter` 是所属章节（默认 1）；
- `Difficulty` 是编辑器保留的难度标记；
- `JacketPath` / `AudioPath` 是编辑器选文件用的本地路径，导出时会被剔除。

载入旧谱面时若没有 `Artist` 字段，会回退读取旧的 `Producer`，重新保存即升级成新格式。

### 未保存更改

`EditorState.document_signature()`（`ChartData.to_dict()` 的 JSON 指纹）与上次保存时记下的
`_saved_signature` 比较得出 `is_dirty()`：用整份文档比较，因此撤销回保存点也会变回「已保存」。
`mark_saved()` 在新建、打开、保存成功后调用。

关闭窗口时 `MainEditor` 接管 `NOTIFICATION_WM_CLOSE_REQUEST`（`_ready()` 里把
`get_tree().auto_accept_quit` 置 false），有未保存更改才弹出 `ConfirmDialog`：

| 按钮 | 结果 |
| --- | --- |
| 保存（确定） | 保存成功后继续退出；无路径时先弹另存为，选完文件再退出 |
| 不保存（custom_action `discard`） | 放弃改动直接退出 |
| 取消（取消 / ESC） | 中止退出 |

「保存后继续」通过 `_pending_action` 实现：待续操作在弹窗时挂起，`_do_save()` 成功、
另存为对话框完成时才执行；保存失败或另存为被取消则作废。

## 8. 目录迁移对照（本次重构）

| 旧路径 | 新路径 |
| --- | --- |
| `Script/EditorChartState.gd`（autoload） | `core/chart_data.gd` + `core/editor_state.gd` + `core/undo_history.gd` |
| `Script/Audio/audio_manager.gd` | `audio/audio_manager.gd`（WAV 解析移到 `core/wav_reader.gd`） |
| `Script/Scene/main_editor.gd` | `ui/main_editor/main_editor.gd`（IO 移到 `chart_io.gd`） |
| `Script/Widget/visual.gd` | `ui/visual/visual.gd` + `visual_geometry.gd` + `visual_renderer.gd` |
| `Script/Widget/ruler.gd` | `ui/ruler/ruler.gd` |
| `Script/Widget/property_panel.gd` | `ui/property_panel/property_panel.gd` |
| `Script/Widget/list.gd` | `ui/tool_list/tool_list.gd` |
| `Scene/MainEditor.tscn` | `ui/main_editor/main_editor.tscn` |
| `Scene/Widget/List.tscn` | `ui/tool_list/tool_list.tscn` |
| `Scene/Widget/PropertyPanel.tscn` | `ui/property_panel/property_panel.tscn` |
| `Scene/Widget/Drawer.tscn` | `ui/tool_list/drawer.tscn`（仍未被任何场景引用） |
| `Asset/Icon/*` | `assets/icons/*` |

脚本 uid 在移动中保持不变，因此场景中的 `ext_resource` 引用依然有效（同时已同步 `path` 字段）。

## 9. 后续可继续拆分的方向

- `property_panel.gd`（约 370 行）可再拆出「元数据段 / 音符段 / 设置段」三个子控件；
- `EditorVisual` 的拖拽状态机（`_drag_mode` / `_drag_note_index`）可抽成 `VisualDragController`；
- `tool_list/drawer.tscn` 若确认无用可直接删除；
- 导出格式若要支持更多资源（如难度分层），建议在 `ChartIO` 内新增打包器而不是回到主控制器。
