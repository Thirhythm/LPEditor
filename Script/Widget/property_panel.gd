extends Control
class_name PropertyPanel

## 面板展开宽度
const EXPANDED_WIDTH: float = 280.0
## 面板收起宽度
const COLLAPSED_WIDTH: float = 32.0

## 当前选中的音符（空字典表示未选中）
var selected_note: Dictionary = {}
## 当前选中的音符索引（-1 表示未选中）
var selected_note_index: int = -1

# ============================================================
# UI 节点引用
# ============================================================
var _toggle_button: Button
var _content_container: VBoxContainer

# 谱面元信息控件
var _meta_container: VBoxContainer
var _title_edit: LineEdit
var _jacket_display: TextureRect
var _jacket_path_edit: LineEdit
var _jacket_browse: Button
var _audio_path_edit: LineEdit
var _audio_browse: Button
var _bpm_spin: SpinBox
var _producer_edit: LineEdit
var _vocalist_edit: LineEdit
var _creator_edit: LineEdit
var _difficulty_option: OptionButton

# 音符属性控件
var _note_container: VBoxContainer
var _note_type_option: OptionButton
var _note_time_spin: SpinBox
var _note_column_spin: SpinBox
var _hold_duration_container: Control
var _hold_duration_spin: SpinBox
var _heart_map_container: Control
var _heart_map_edit: LineEdit

# 状态
var _is_expanded: bool = true
var _mode: int = 0  # 0: 元信息模式, 1: 音符模式

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	custom_minimum_size = Vector2(EXPANDED_WIDTH, 0)
	_build_ui()
	_switch_to_meta_mode()

func _build_ui() -> void:
	# 顶层 HBoxContainer — 按钮 + 内容
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)
	
	# 折叠按钮
	_toggle_button = Button.new()
	_toggle_button.text = "<"
	_toggle_button.custom_minimum_size = Vector2(24, 0)
	_toggle_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_toggle_button.pressed.connect(_on_toggle_pressed)
	hbox.add_child(_toggle_button)
	
	# 内容容器
	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_content_container)
	
	# ---- 谱面元信息容器 ----
	_meta_container = VBoxContainer.new()
	_meta_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.add_child(_meta_container)
	
	# 标题
	_add_section_label(_meta_container, "谱面名称")
	_title_edit = _add_line_edit(_meta_container, "Title")
	_title_edit.text_changed.connect(_on_title_changed)
	
	# 曲绘
	_add_section_label(_meta_container, "曲绘")
	_jacket_display = TextureRect.new()
	_jacket_display.custom_minimum_size = Vector2(0, 120)
	_jacket_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_jacket_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_jacket_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meta_container.add_child(_jacket_display)
	
	var jacket_path_hbox := HBoxContainer.new()
	_meta_container.add_child(jacket_path_hbox)
	_jacket_path_edit = _add_line_edit(jacket_path_hbox, "曲绘路径...")
	_jacket_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jacket_path_edit.text_changed.connect(_on_jacket_path_changed)
	_jacket_browse = Button.new()
	_jacket_browse.text = "..."
	_jacket_browse.custom_minimum_size = Vector2(32, 0)
	_jacket_browse.pressed.connect(_on_jacket_browse_pressed)
	jacket_path_hbox.add_child(_jacket_browse)
	
	# 音频
	_add_section_label(_meta_container, "音频文件")
	var audio_path_hbox := HBoxContainer.new()
	_meta_container.add_child(audio_path_hbox)
	_audio_path_edit = _add_line_edit(audio_path_hbox, "音频路径...")
	_audio_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_path_edit.text_changed.connect(_on_audio_path_changed)
	_audio_browse = Button.new()
	_audio_browse.text = "..."
	_audio_browse.custom_minimum_size = Vector2(32, 0)
	_audio_browse.pressed.connect(_on_audio_browse_pressed)
	audio_path_hbox.add_child(_audio_browse)
	
	# BPM
	_add_section_label(_meta_container, "BPM")
	_bpm_spin = SpinBox.new()
	_bpm_spin.min_value = 1.0
	_bpm_spin.max_value = 999.0
	_bpm_spin.step = 1.0
	_bpm_spin.value = EditorChartState.bpm
	_bpm_spin.value_changed.connect(_on_bpm_changed)
	_meta_container.add_child(_bpm_spin)
	
	# 制作人
	_add_section_label(_meta_container, "制作人 (Producer)")
	_producer_edit = _add_line_edit(_meta_container, "Producer")
	_producer_edit.text_changed.connect(_on_producer_changed)
	
	# 歌手
	_add_section_label(_meta_container, "歌手 (Vocalist)")
	_vocalist_edit = _add_line_edit(_meta_container, "Vocalist")
	_vocalist_edit.text_changed.connect(_on_vocalist_changed)
	
	# 谱面作者
	_add_section_label(_meta_container, "谱面作者 (Creator)")
	_creator_edit = _add_line_edit(_meta_container, "Creator")
	_creator_edit.text_changed.connect(_on_creator_changed)
	
	# 难度
	_add_section_label(_meta_container, "难度")
	_difficulty_option = OptionButton.new()
	_difficulty_option.add_item("EZ (简单)")
	_difficulty_option.add_item("NM (普通)")
	_difficulty_option.add_item("HD (困难)")
	_difficulty_option.item_selected.connect(_on_difficulty_changed)
	_meta_container.add_child(_difficulty_option)
	
	# ---- 音符属性容器 ----
	_note_container = VBoxContainer.new()
	_note_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_container.visible = false
	_content_container.add_child(_note_container)
	
	# 音符类型
	_add_section_label(_note_container, "音符类型")
	_note_type_option = OptionButton.new()
	_note_type_option.add_item("tap (蓝键)")
	_note_type_option.add_item("drag (黄键)")
	_note_type_option.add_item("release (红键)")
	_note_type_option.add_item("hold (长键)")
	_note_type_option.add_item("heart (心键)")
	_note_type_option.item_selected.connect(_on_note_type_changed)
	_note_container.add_child(_note_type_option)
	
	# 判定时间
	_add_section_label(_note_container, "判定时间 (ms)")
	_note_time_spin = SpinBox.new()
	_note_time_spin.min_value = 0.0
	_note_time_spin.max_value = 99999999.0
	_note_time_spin.step = 1.0
	_note_time_spin.value_changed.connect(_on_note_time_changed)
	_note_container.add_child(_note_time_spin)
	
	# 轨道
	_add_section_label(_note_container, "轨道")
	_note_column_spin = SpinBox.new()
	_note_column_spin.min_value = 1.0
	_note_column_spin.max_value = 4.0
	_note_column_spin.step = 1.0
	_note_column_spin.value_changed.connect(_on_note_column_changed)
	_note_container.add_child(_note_column_spin)
	
	# hold 持续时间（默认隐藏）
	_hold_duration_container = Control.new()
	_hold_duration_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_container.add_child(_hold_duration_container)
	
	var dur_vbox := VBoxContainer.new()
	dur_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hold_duration_container.add_child(dur_vbox)
	
	_add_section_label(dur_vbox, "持续时间 (ms)")
	_hold_duration_spin = SpinBox.new()
	_hold_duration_spin.min_value = 1.0
	_hold_duration_spin.max_value = 99999999.0
	_hold_duration_spin.step = 1.0
	_hold_duration_spin.value_changed.connect(_on_hold_duration_changed)
	dur_vbox.add_child(_hold_duration_spin)
	
	# heart 轨道映射（默认隐藏）
	_heart_map_container = Control.new()
	_heart_map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_container.add_child(_heart_map_container)
	
	var map_vbox := VBoxContainer.new()
	map_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heart_map_container.add_child(map_vbox)
	
	_add_section_label(map_vbox, "轨道映射 (map)")
	_heart_map_edit = LineEdit.new()
	_heart_map_edit.placeholder_text = "e.g. 4,2,3,1"
	_heart_map_edit.text_changed.connect(_on_heart_map_changed)
	map_vbox.add_child(_heart_map_edit)

# ============================================================
# UI 构建辅助
# ============================================================

func _add_section_label(parent: Control, text: String) -> void:
	var margin := Control.new()
	margin.custom_minimum_size = Vector2(0, 8)
	parent.add_child(margin)
	
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	parent.add_child(label)

func _add_line_edit(parent: Control, placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(le)
	return le

# ============================================================
# 模式切换
# ============================================================

func _switch_to_meta_mode() -> void:
	_mode = 0
	_meta_container.visible = true
	_note_container.visible = false
	_refresh_meta_fields()

func _switch_to_note_mode() -> void:
	_mode = 1
	_meta_container.visible = false
	_note_container.visible = true
	_refresh_note_fields()

# ============================================================
# 刷新界面
# ============================================================

func _refresh_meta_fields() -> void:
	_title_edit.text = EditorChartState.title
	_producer_edit.text = EditorChartState.producer
	_vocalist_edit.text = EditorChartState.vocalist
	_creator_edit.text = EditorChartState.creator
	_bpm_spin.set_value_no_signal(EditorChartState.bpm)
	_jacket_path_edit.text = EditorChartState.jacket_path
	_audio_path_edit.text = EditorChartState.audio_path
	
	# 难度选择（阻塞信号避免触发 _on_difficulty_changed）
	match EditorChartState.difficulty:
		"NM":
			_difficulty_option.set_block_signals(true)
			_difficulty_option.select(1)
			_difficulty_option.set_block_signals(false)
		"HD":
			_difficulty_option.set_block_signals(true)
			_difficulty_option.select(2)
			_difficulty_option.set_block_signals(false)
		_:
			_difficulty_option.set_block_signals(true)
			_difficulty_option.select(0)
			_difficulty_option.set_block_signals(false)
	
	# 加载曲绘缩略图
	if not EditorChartState.jacket_path.is_empty() and ResourceLoader.exists(EditorChartState.jacket_path):
		var tex := load(EditorChartState.jacket_path)
		if tex:
			_jacket_display.texture = tex

func _refresh_note_fields() -> void:
	if selected_note.is_empty():
		return
	
	# 音符类型（阻塞信号，防止 select() 触发 item_selected 导致递归）
	var ntype = selected_note.get("type", "tap")
	var type_idx: int
	match ntype:
		"drag":     type_idx = 1
		"release":  type_idx = 2
		"hold":     type_idx = 3
		"heart":    type_idx = 4
		_:          type_idx = 0
	_note_type_option.set_block_signals(true)
	_note_type_option.select(type_idx)
	_note_type_option.set_block_signals(false)
	
	# 时间
	_note_time_spin.set_value_no_signal(selected_note.get("time", 0) as float)
	
	# 轨道
	_note_column_spin.set_value_no_signal(selected_note.get("column", 1) as float)
	
	# hold duration
	var is_hold = ntype == "hold"
	_hold_duration_container.visible = is_hold
	if is_hold:
		_hold_duration_spin.set_value_no_signal(selected_note.get("duration", 0) as float)
	
	# heart map
	var is_heart = ntype == "heart"
	_heart_map_container.visible = is_heart
	if is_heart:
		var arr: Array = selected_note.get("map", [])
		_heart_map_edit.text = ",".join(arr)

# ============================================================
# 折叠/展开
# ============================================================

func _on_toggle_pressed() -> void:
	_is_expanded = not _is_expanded
	if _is_expanded:
		custom_minimum_size = Vector2(EXPANDED_WIDTH, 0)
		_toggle_button.text = "<"
		_content_container.visible = true
	else:
		custom_minimum_size = Vector2(COLLAPSED_WIDTH, 0)
		_toggle_button.text = ">"
		_content_container.visible = false
	emit_signal("panel_toggled", _is_expanded)

# ============================================================
# 外部调用接口
# ============================================================

signal panel_toggled(expanded: bool)
signal meta_changed()
signal note_changed(index: int)
signal jacket_browse_requested()
signal audio_browse_requested()

## 设置为元信息模式
func set_meta_mode() -> void:
	selected_note = {}  # 新建空字典，不清除数组引用
	selected_note_index = -1
	_switch_to_meta_mode()

## 设置为音符编辑模式
func set_note(note: Dictionary, index: int) -> void:
	selected_note = note.duplicate(true)  # 防御性复制，避免直接引用数组元素
	selected_note_index = index
	_switch_to_note_mode()

## 刷新当前模式
func refresh() -> void:
	if _mode == 0:
		_refresh_meta_fields()
	else:
		_refresh_note_fields()

# ============================================================
# 元信息字段变更回调
# ============================================================

func _on_title_changed(new_text: String) -> void:
	EditorChartState.title = new_text
	emit_signal("meta_changed")

func _on_jacket_path_changed(new_text: String) -> void:
	EditorChartState.jacket_path = new_text
	if ResourceLoader.exists(new_text):
		var tex := load(new_text)
		if tex:
			_jacket_display.texture = tex
	emit_signal("meta_changed")

func _on_jacket_browse_pressed() -> void:
	emit_signal("jacket_browse_requested")

func _on_audio_path_changed(new_text: String) -> void:
	EditorChartState.audio_path = new_text
	emit_signal("meta_changed")

func _on_audio_browse_pressed() -> void:
	emit_signal("audio_browse_requested")

func _on_bpm_changed(value: float) -> void:
	EditorChartState.bpm = value
	emit_signal("meta_changed")

func _on_producer_changed(new_text: String) -> void:
	EditorChartState.producer = new_text
	emit_signal("meta_changed")

func _on_vocalist_changed(new_text: String) -> void:
	EditorChartState.vocalist = new_text
	emit_signal("meta_changed")

func _on_creator_changed(new_text: String) -> void:
	EditorChartState.creator = new_text
	emit_signal("meta_changed")

func _on_difficulty_changed(index: int) -> void:
	match index:
		0:
			EditorChartState.difficulty = "EZ"
		1:
			EditorChartState.difficulty = "NM"
		2:
			EditorChartState.difficulty = "HD"
	emit_signal("meta_changed")

# ============================================================
# 音符属性变更回调
# ============================================================

func _on_note_type_changed(index: int) -> void:
	if selected_note.is_empty():
		return
	var type_str: String
	match index:
		0: type_str = "tap"
		1: type_str = "drag"
		2: type_str = "release"
		3: type_str = "hold"
		4: type_str = "heart"
		_: type_str = "tap"
	
	var old_type = selected_note.get("type", "")
	selected_note["type"] = type_str
	
	# 新类型为 hold 时确保有 duration
	if type_str == "hold" and not selected_note.has("duration"):
		selected_note["duration"] = 500
	# 新类型为 heart 时确保有 map
	if type_str == "heart" and not selected_note.has("map"):
		selected_note["map"] = [1, 2, 3, 4]
	# 非 hold 时移除 duration
	if type_str != "hold" and selected_note.has("duration"):
		selected_note.erase("duration")
	# 非 heart 时移除 map
	if type_str != "heart" and selected_note.has("map"):
		selected_note.erase("map")
	
	# 同步到 EditorChartState
	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note
	
	_refresh_note_fields()
	emit_signal("note_changed", selected_note_index)

func _on_note_time_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	selected_note["time"] = int(value)
	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_note_column_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	selected_note["column"] = int(value)
	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_hold_duration_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	selected_note["duration"] = int(value)
	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_heart_map_changed(new_text: String) -> void:
	if selected_note.is_empty():
		return
	var parts := new_text.split(",", false)
	var arr: Array[int] = []
	for p in parts:
		var num := p.strip_edges().to_int()
		if num >= 1 and num <= 4:
			arr.append(num)
	if not arr.is_empty():
		selected_note["map"] = arr
		if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
			EditorChartState.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)
