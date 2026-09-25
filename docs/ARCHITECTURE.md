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
| `core/chart_data.gd`（`ChartData`） | 一份谱面文档 | `title` / `bpm` / `notes` / `audio_path` / `jacket_path` / `audio_duration_ms` / `waveform_samples` / `current_file_path`，`to_dict()` / `load_from_dict()` / `get_max_scroll_time()` / `capture_snapshot()` |
| `core/editor_state.gd`（`EditorState`） | 一次编辑会话 | `scroll_time` / `px_per_ms` / `quantize_denominator` / `snap_enabled` / `selected_notes`，`push_undo_state()` / `undo()` / `redo()` / `clamp_scroll()` / `snap_time()` |

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
├─ Panel/…/Property       PropertyPanel：元数据 / 音符 / 设置，折叠展开
└─ TrackUI/…/Visual       EditorVisual：轨道编辑区
```

- `EditorVisual` 通过 `note_selected` / `note_deselected` / `note_placed` / `note_moved` /
  `note_resized` / `note_deleted` / `scroll_changed` 通知主控制器，主控制器再刷新其它面板。
- `PropertyPanel` 通过 `meta_changed` / `note_changed` / `jacket_browse_requested` /
  `audio_browse_requested` / `panel_toggled` 反向通知。
- 主控制器不持有数据副本，所有读写都落到 `ChartData` / `EditorState`。

## 5. visual 三分

原 `visual.gd`（530 行）按职责拆为：

| 文件 | 内容 | 依赖 |
| --- | --- | --- |
| `ui/visual/visual.gd` | 交互：滚轮、点击命中、放置、拖拽、删除、平滑滚动 | 转发几何调用 |
| `ui/visual/visual_geometry.gd` | 时间 ↔ Y、X ↔ 轨道、可见时间范围、量化吸附 | `EditorState` / `ChartDefs` |
| `ui/visual/visual_renderer.gd` | 轨道底色、BPM 网格、音符、判定线 | `ChartData` / `ChartDefs` / `VisualGeometry` |

绘制方法全部为静态方法并接收 `Control` 参数（需要 `get_theme_default_font()`，故不是 `CanvasItem`）。

> 顺带修复：原 `_draw_heart_note()` 已定义但从未被调用，heart 音符在轨道区不可见；
> 新渲染器按类型分派，heart 音符现在会正常绘制。

## 6. 文件读写

`ui/main_editor/chart_io.gd`（`ChartIO`）承担 `.lp` 的读写与 `.lpz` 打包，全部返回
`{ ok, error }` / `{ ok, error, data }`，由 `MainEditor` 决定提示方式。
它不引用任何节点，因此可脱离界面测试与复用。

导出包结构：`chart.lp`（去掉 `AudioPath` / `JacketPath` 的 JSON）+ `audio.<ext>` + `cover.<ext>`。

## 7. 目录迁移对照（本次重构）

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

## 8. 后续可继续拆分的方向

- `property_panel.gd`（约 370 行）可再拆出「元数据段 / 音符段 / 设置段」三个子控件；
- `EditorVisual` 的拖拽状态机（`_drag_mode` / `_drag_note_index`）可抽成 `VisualDragController`；
- `tool_list/drawer.tscn` 若确认无用可直接删除；
- 导出格式若要支持更多资源（如难度分层），建议在 `ChartIO` 内新增打包器而不是回到主控制器。
