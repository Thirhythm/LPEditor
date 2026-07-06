extends Control
class_name PropertyPanel

# 属性面板组件：编辑谱面元数据和音符属性
# 支持折叠/展开，分为元数据模式（meta）和音符编辑模式（note）

const EXPANDED_WIDTH: float = 280.0
const COLLAPSED_WIDTH: float = 32.0

var selected_note: Dictionary = {}
var selected_note_index: int = -1

var _toggle_button: Button
var _content_container: VBoxContainer

# --- 元数据 UI 控件 ---
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
var _quantize_option: OptionButton
var _snap_toggle: CheckBox

# --- 音符属性 UI 控件 ---
var _note_container: VBoxContainer
var _note_type_option: OptionButton
var _note_time_spin: SpinBox
var _note_column_spin: SpinBox
var _hold_duration_container: Control
var _hold_duration_spin: SpinBox
var _heart_map_container: Control
var _heart_map_edit: LineEdit

# --- 编辑器设置（常驻面板） ---
var _settings_container: VBoxContainer

var _is_expanded: bool = true
var _mode: int = 0	# 0: meta, 1: note
var _text_undo_pushed: bool = false

func _push_text_undo() -> void:
	if _text_undo_pushed:
		return
	EditorChartState.push_undo_state()
	_text_undo_pushed = true

func _reset_text_undo() -> void:
	_text_undo_pushed = false

func _ready() -> void:
	custom_minimum_size = Vector2(EXPANDED_WIDTH, 0)
	_build_ui()
	_switch_to_meta_mode()

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	_toggle_button = Button.new()
	_toggle_button.text = "<"
	_toggle_button.custom_minimum_size = Vector2(24, 0)
	_toggle_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_toggle_button.pressed.connect(_on_toggle_pressed)
	hbox.add_child(_toggle_button)

	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_content_container)

	# --- 元数据区域 ---
	_meta_container = VBoxContainer.new()
	_meta_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.add_child(_meta_container)

	_add_section_label(_meta_container, "谱面名称")
	_title_edit = _add_line_edit(_meta_container, "Title")
	_title_edit.text_changed.connect(_on_title_changed)
	_title_edit.focus_entered.connect(_reset_text_undo)

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
	_jacket_path_edit.focus_entered.connect(_reset_text_undo)
	_jacket_browse = Button.new()
	_jacket_browse.text = "..."
	_jacket_browse.custom_minimum_size = Vector2(32, 0)
	_jacket_browse.pressed.connect(_on_jacket_browse_pressed)
	jacket_path_hbox.add_child(_jacket_browse)

	_add_section_label(_meta_container, "音频文件")
	var audio_path_hbox := HBoxContainer.new()
	_meta_container.add_child(audio_path_hbox)
	_audio_path_edit = _add_line_edit(audio_path_hbox, "音频路径...")
	_audio_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_path_edit.text_changed.connect(_on_audio_path_changed)
	_audio_path_edit.focus_entered.connect(_reset_text_undo)
	_audio_browse = Button.new()
	_audio_browse.text = "..."
	_audio_browse.custom_minimum_size = Vector2(32, 0)
	_audio_browse.pressed.connect(_on_audio_browse_pressed)
	audio_path_hbox.add_child(_audio_browse)

	_add_section_label(_meta_container, "BPM")
	_bpm_spin = SpinBox.new()
	_bpm_spin.min_value = 1.0
	_bpm_spin.max_value = 999.0
	_bpm_spin.step = 1.0
	_bpm_spin.value = EditorChartState.bpm
	_bpm_spin.value_changed.connect(_on_bpm_changed)
	_meta_container.add_child(_bpm_spin)

	_add_section_label(_meta_container, "制作人 (Producer)")
	_producer_edit = _add_line_edit(_meta_container, "Producer")
	_producer_edit.text_changed.connect(_on_producer_changed)
	_producer_edit.focus_entered.connect(_reset_text_undo)

	_add_section_label(_meta_container, "歌手 (Vocalist)")
	_vocalist_edit = _add_line_edit(_meta_container, "Vocalist")
	_vocalist_edit.text_changed.connect(_on_vocalist_changed)
	_vocalist_edit.focus_entered.connect(_reset_text_undo)

	_add_section_label(_meta_container, "谱面作者 (Creator)")
	_creator_edit = _add_line_edit(_meta_container, "Creator")
	_creator_edit.text_changed.connect(_on_creator_changed)
	_creator_edit.focus_entered.connect(_reset_text_undo)

	_add_section_label(_meta_container, "难度")
	_difficulty_option = OptionButton.new()
	_difficulty_option.add_item("EZ (简单)")
	_difficulty_option.add_item("NM (普通)")
	_difficulty_option.add_item("HD (困难)")
	_difficulty_option.item_selected.connect(_on_difficulty_changed)
	_meta_container.add_child(_difficulty_option)

	# --- 音符属性区域 ---
	_note_container = VBoxContainer.new()
	_note_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_container.visible = false
	_content_container.add_child(_note_container)

	_add_section_label(_note_container, "音符类型")
	_note_type_option = OptionButton.new()
	_note_type_option.add_item("tap (蓝键)")
	_note_type_option.add_item("drag (黄键)")
	_note_type_option.add_item("release (红键)")
	_note_type_option.add_item("hold (长键)")
	_note_type_option.add_item("heart (心键)")
	_note_type_option.item_selected.connect(_on_note_type_changed)
	_note_container.add_child(_note_type_option)

	_add_section_label(_note_container, "判定时间 (ms)")
	_note_time_spin = SpinBox.new()
	_note_time_spin.min_value = 0.0
	_note_time_spin.max_value = 99999999.0
	_note_time_spin.step = 1.0
	_note_time_spin.value_changed.connect(_on_note_time_changed)
	_note_container.add_child(_note_time_spin)

	_add_section_label(_note_container, "轨道")
	_note_column_spin = SpinBox.new()
	_note_column_spin.min_value = 1.0
	_note_column_spin.max_value = 4.0
	_note_column_spin.step = 1.0
	_note_column_spin.value_changed.connect(_on_note_column_changed)
	_note_container.add_child(_note_column_spin)

	# hold 类型的持续时长设置
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

	# heart 类型的轨道映射设置
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
	_heart_map_edit.focus_entered.connect(_reset_text_undo)
	map_vbox.add_child(_heart_map_edit)

	# --- 编辑器设置（常驻） ---
	_settings_container = VBoxContainer.new()
	_settings_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.add_child(_settings_container)

	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 8)
	_settings_container.add_child(sep)

	_add_section_label(_settings_container, "量化")
	_quantize_option = OptionButton.new()
	_quantize_option.add_item("1/2")
	_quantize_option.add_item("1/4")
	_quantize_option.add_item("1/5")
	_quantize_option.add_item("1/6")
	_quantize_option.add_item("1/7")
	_quantize_option.add_item("1/8")
	_quantize_option.add_item("1/9")
	_quantize_option.add_item("1/10")
	_quantize_option.add_item("1/12")
	_quantize_option.add_item("1/16")
	_quantize_option.add_item("1/32")
	_quantize_option.add_item("1/48")
	_quantize_option.item_selected.connect(_on_quantize_changed)
	_settings_container.add_child(_quantize_option)

	_add_section_label(_settings_container, "音符吸附")
	_snap_toggle = CheckBox.new()
	_snap_toggle.text = "启用"
	_snap_toggle.button_pressed = EditorChartState.snap_enabled
	_snap_toggle.toggled.connect(_on_snap_toggled)
	_settings_container.add_child(_snap_toggle)

# --- UI 构建辅助 ---

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

# --- 模式切换 ---

func _switch_to_meta_mode() -> void:
	_mode = 0
	_meta_container.visible = true
	_note_container.visible = false
	_refresh_meta_fields()
	_refresh_settings_fields()

func _switch_to_note_mode() -> void:
	_mode = 1
	_meta_container.visible = false
	_note_container.visible = true
	_refresh_note_fields()
	_refresh_settings_fields()

# --- 字段刷新 ---

func _refresh_meta_fields() -> void:
	_block_meta_edit_signals(true)
	_title_edit.text = EditorChartState.title
	_producer_edit.text = EditorChartState.producer
	_vocalist_edit.text = EditorChartState.vocalist
	_creator_edit.text = EditorChartState.creator
	_jacket_path_edit.text = EditorChartState.jacket_path
	_audio_path_edit.text = EditorChartState.audio_path
	_block_meta_edit_signals(false)

	_bpm_spin.set_value_no_signal(EditorChartState.bpm)

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

	if not EditorChartState.jacket_path.is_empty() and ResourceLoader.exists(EditorChartState.jacket_path):
		var tex := load(EditorChartState.jacket_path)
		if tex:
			_jacket_display.texture = tex

func _refresh_settings_fields() -> void:
	var denom_to_idx: Dictionary = {
		2: 0, 4: 1, 5: 2, 6: 3, 7: 4, 8: 5,
		9: 6, 10: 7, 12: 8, 16: 9, 32: 10, 48: 11
	}
	var q_idx = denom_to_idx.get(EditorChartState.quantize_denominator, 1)
	_quantize_option.set_block_signals(true)
	_quantize_option.select(q_idx)
	_quantize_option.set_block_signals(false)

	_snap_toggle.set_block_signals(true)
	_snap_toggle.button_pressed = EditorChartState.snap_enabled
	_snap_toggle.set_block_signals(false)

func _block_meta_edit_signals(block: bool) -> void:
	_title_edit.set_block_signals(block)
	_producer_edit.set_block_signals(block)
	_vocalist_edit.set_block_signals(block)
	_creator_edit.set_block_signals(block)
	_jacket_path_edit.set_block_signals(block)
	_audio_path_edit.set_block_signals(block)

func _refresh_note_fields() -> void:
	if selected_note.is_empty():
		return

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

	_note_time_spin.set_value_no_signal(selected_note.get("time", 0) as float)
	_note_column_spin.set_value_no_signal(selected_note.get("column", 1) as float)

	var is_hold = ntype == "hold"
	_hold_duration_container.visible = is_hold
	if is_hold:
		_hold_duration_spin.set_value_no_signal(selected_note.get("duration", 0) as float)

	var is_heart = ntype == "heart"
	_heart_map_container.visible = is_heart
	if is_heart:
		var arr: Array = selected_note.get("map", [])
		_heart_map_edit.set_block_signals(true)
		_heart_map_edit.text = ",".join(arr)
		_heart_map_edit.set_block_signals(false)

# --- 折叠/展开 ---

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

signal panel_toggled(expanded: bool)
signal meta_changed()
signal note_changed(index: int)
signal jacket_browse_requested()
signal audio_browse_requested()

func set_meta_mode() -> void:
	selected_note = {}
	selected_note_index = -1
	_switch_to_meta_mode()

func set_note(note: Dictionary, index: int) -> void:
	selected_note = note.duplicate(true)
	selected_note_index = index
	_switch_to_note_mode()

func update_selected_note(note: Dictionary, index: int) -> void:
	if selected_note_index != index or _mode != 1:
		return
	selected_note = note.duplicate(true)
	_refresh_note_fields()

func refresh() -> void:
	if _mode == 0:
		_refresh_meta_fields()
	else:
		_refresh_note_fields()
	_refresh_settings_fields()

# --- 元数据编辑回调 ---

func _on_title_changed(new_text: String) -> void:
	_push_text_undo()
	EditorChartState.title = new_text
	emit_signal("meta_changed")

func _on_jacket_path_changed(new_text: String) -> void:
	_push_text_undo()
	EditorChartState.jacket_path = new_text
	if ResourceLoader.exists(new_text):
		var tex := load(new_text)
		if tex:
			_jacket_display.texture = tex
	emit_signal("meta_changed")

func _on_jacket_browse_pressed() -> void:
	emit_signal("jacket_browse_requested")

func _on_audio_path_changed(new_text: String) -> void:
	_push_text_undo()
	EditorChartState.audio_path = new_text
	emit_signal("meta_changed")

func _on_audio_browse_pressed() -> void:
	emit_signal("audio_browse_requested")

func _on_bpm_changed(value: float) -> void:
	EditorChartState.push_undo_state()
	EditorChartState.bpm = value
	emit_signal("meta_changed")

func _on_producer_changed(new_text: String) -> void:
	_push_text_undo()
	EditorChartState.producer = new_text
	emit_signal("meta_changed")

func _on_vocalist_changed(new_text: String) -> void:
	_push_text_undo()
	EditorChartState.vocalist = new_text
	emit_signal("meta_changed")

func _on_creator_changed(new_text: String) -> void:
	_push_text_undo()
	EditorChartState.creator = new_text
	emit_signal("meta_changed")

func _on_difficulty_changed(index: int) -> void:
	EditorChartState.push_undo_state()
	match index:
		0: EditorChartState.difficulty = "EZ"
		1: EditorChartState.difficulty = "NM"
		2: EditorChartState.difficulty = "HD"
	emit_signal("meta_changed")

func _on_quantize_changed(index: int) -> void:
	EditorChartState.push_undo_state()
	var idx_to_denom: Array[int] = [2, 4, 5, 6, 7, 8, 9, 10, 12, 16, 32, 48]
	if index >= 0 and index < idx_to_denom.size():
		EditorChartState.quantize_denominator = idx_to_denom[index]
	emit_signal("meta_changed")

func _on_snap_toggled(button_pressed: bool) -> void:
	EditorChartState.push_undo_state()
	EditorChartState.snap_enabled = button_pressed
	emit_signal("meta_changed")

# --- 音符属性编辑回调 ---

func _on_note_type_changed(index: int) -> void:
	if selected_note.is_empty():
		return
	EditorChartState.push_undo_state()
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

	if type_str == "hold" and not selected_note.has("duration"):
		selected_note["duration"] = 500
	if type_str == "heart" and not selected_note.has("map"):
		selected_note["map"] = [1, 2, 3, 4]
	if type_str != "hold" and selected_note.has("duration"):
		selected_note.erase("duration")
	if type_str != "heart" and selected_note.has("map"):
		selected_note.erase("map")

	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note

	_refresh_note_fields()
	emit_signal("note_changed", selected_note_index)

func _on_note_time_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	EditorChartState.push_undo_state()
	selected_note["time"] = int(value)
	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_note_column_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	EditorChartState.push_undo_state()
	selected_note["column"] = int(value)
	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_hold_duration_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	EditorChartState.push_undo_state()
	selected_note["duration"] = int(value)
	if selected_note_index >= 0 and selected_note_index < EditorChartState.notes.size():
		EditorChartState.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_heart_map_changed(new_text: String) -> void:
	if selected_note.is_empty():
		return
	_push_text_undo()
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
