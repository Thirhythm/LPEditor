# LPEditor

Godot 4.7 谱面编辑器（4 键下落式）：加载音频、在轨道区摆放音符、编辑谱面元数据，并导出 `.lpz` 谱面包。

## 运行

- 用 Godot 4.7+ 打开本目录（`project.godot`）
- 主场景：`res://ui/main_editor/main_editor.tscn`

常用操作：

| 操作 | 快捷键 / 方式 |
| --- | --- |
| 播放 / 暂停 | `Space` |
| 从开头重播 | 播放结束后按 `Space`：未手动移动视口时跳回开头，移动过则从当前播放头位置播放 |
| 撤销 / 重做 | `Ctrl+Z` / `Ctrl+Y` |
| 删除选中音符 | `Delete` |
| 滚动视口 | 滚轮 |
| 缩放 | `Ctrl` + 滚轮 |
| 放置音符 | 先在工具栏选择类型，再点击轨道区 |
| 移动 / 改长键时长 | 拖拽音符本体 / 拖拽长键尾部 |
| 删除音符 | 右键点击音符 |
| 退出 | 关闭窗口（标题栏 × / Alt+F4）：有未保存的改动时询问「保存 / 不保存 / 取消」 |

## 目录结构

```
assets/icons/            图标资源
audio/                   音频播放
  audio_manager.gd         播放 / 暂停 / 定位，并把分析结果写入 ChartData
core/                    纯逻辑层：不依赖场景树，可脱离编辑器测试
  chart_defs.gd            常量与纯函数（轨道、量化、配色、导出校验）
  chart_data.gd            谱面文档：元数据 + 音符 + 序列化（全部静态成员）
  editor_state.gd          编辑会话：视口、量化、选区、撤销（全部静态成员）
  undo_history.gd          通用快照式撤销栈
  wav_reader.gd            WAV(RIFF/PCM) 解析与波形降采样
docs/                    架构说明
tests/                   测试套件（`test_*.gd`，自动发现）
ui/                      界面层，按功能分目录，场景与脚本放在一起
  main_editor/             main_editor.tscn 主场景 + 控制器
                           chart_io.gd 谱面读写与 .lpz 导出
  visual/                  轨道编辑区
                           visual.gd 交互 / visual_geometry.gd 换算 / visual_renderer.gd 绘制
  ruler/                   顶部标尺：波形、音符缩略图、播放头
  property_panel/          属性面板（元数据 / 音符 / 编辑器设置）
  tool_list/               工具栏列表组件（另含暂未被引用的 drawer.tscn）
```

## 架构与数据流

```
ui/*  ──读取/写入──>  ChartData（谱面文档）      静态类
  │                   EditorState（编辑会话）    静态类
  └──调用──────────>  AudioManager / ChartIO / VisualRenderer / VisualGeometry
                        └──> WavReader / UndoHistory  （core 纯逻辑）
```

- `ChartData` 承载「一份谱面」：元数据、音符、音频时长与波形、当前文件路径。
- `EditorState` 承载「一次编辑会话」：滚动位置、缩放、量化与吸附、选区，以及撤销/重做；
  撤销快照 = 文档字段 + 会话设置，所以「撤销一次属性面板改动」不会丢失量化设置。
- 两者都是**类静态成员**（`ChartData.title`、`EditorState.scroll_time`），因此不依赖
  autoload 注册与场景树，可直接被任意层引用，也能在测试里独立驱动。
- `core/` 不反向依赖 `ui/`；`ui/` 之间通过信号与公开方法通信，不直接访问彼此内部状态。

更完整的说明见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 测试

测试位于 `res://tests/`，每个文件继承 `McpTestSuite`（需带 `@tool`），方法名以 `test_` 开头。

在 Godot 内通过 Godot AI 插件的 `test_run` 工具运行（可指定套件，例如 `suite: "chart_defs"`）。

当前覆盖 5 个套件 / 53 个用例：

| 套件 | 覆盖内容 |
| --- | --- |
| `chart_defs` | 拍点换算、量化吸附、音符构造、颜色、导出校验 |
| `chart_data` | 序列化往返、深拷贝快照、滚动范围计算 |
| `editor_state` | 撤销/重做、重做链作废、选区清理、缩放与滚动钳制、未保存更改判定 |
| `wav_reader` | 波形降采样峰值、缺失文件与非 WAV 数据的错误路径 |
| `visual_geometry` | 时间 ↔ Y 换算、轨道命中、可见范围、吸附 |

## 代码约定

- 缩进用 **Tab**，换行符 **LF**（与 `.gitattributes` 一致）。
- 目录与文件名使用 `snake_case`；一个功能一个目录，场景与其脚本同目录。
- 界面控件一律在场景（`.tscn`）中编排，脚本只做 `@onready` 引用与信号连接，不用 `Control.new()` 搭界面。
- `core/` 脚本带 `@tool`，便于编辑器内解析与单元测试。
- 新增 `class_name` 脚本后，让编辑器执行一次文件系统扫描（编辑器重新获得焦点即可）后再引用它。
