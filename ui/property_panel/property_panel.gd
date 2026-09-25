extends Control
class_name PropertyPanel

# 属性面板组件：编辑谱面元数据和音符属性
# 支持折叠/展开，分为元数据模式（meta）和音符编辑模式（note）
# 所有控件均由 Scene/Widget/PropertyPanel.tscn 节点编排，脚本只负责信号连接与数据刷新

const EXPANDED_WIDTH: float = 280.0
const COLLAPSED_WIDTH: float = 32.0

var selected_note: Dictionary = {}
var selected_note_index: int = -1

# --- 折叠按钮与内容容器 ---
@onready var _toggle_button: Button = $HBox/ToggleButton
@onready var _content_container: VBoxContainer = $HBox/Content

# --- 元数据 UI 控件 ---
@onready var _meta_container: VBoxContainer = $HBox/Content/MetaContainer
@onready var _title_edit: LineEdit = $HBox/Content/MetaContainer/TitleEdit
@onready var _jacket_display: TextureRect = $HBox/Content/MetaContainer/JacketDisplay
@onready var _jacket_path_edit: LineEdit = $HBox/Content/MetaContainer/JacketPathHBox/JacketPathEdit
@onready var _jacket_browse: Button = $HBox/Content/MetaContainer/JacketPathHBox/JacketBrowse
@onready var _audio_path_edit: LineEdit = $HBox/Content/MetaContainer/AudioPathHBox/AudioPathEdit
@onready var _audio_browse: Button = $HBox/Content/MetaContainer/AudioPathHBox/AudioBrowse
@onready var _bpm_spin: SpinBox = $HBox/Content/MetaContainer/BpmSpin
@onready var _producer_edit: LineEdit = $HBox/Content/MetaContainer/ProducerEdit
@onready var _vocalist_edit: LineEdit = $HBox/Content/MetaContainer/VocalistEdit
@onready var _creator_edit: LineEdit = $HBox/Content/MetaContainer/CreatorEdit
@onready var _difficulty_option: OptionButton = $HBox/Content/MetaContainer/DifficultyOption

# --- 音符属性 UI 控件 ---
@onready var _note_container: VBoxContainer = $HBox/Content/NoteContainer
@onready var _note_type_option: OptionButton = $HBox/Content/NoteContainer/NoteTypeOption
@onready var _note_time_spin: SpinBox = $HBox/Content/NoteContainer/NoteTimeSpin
@onready var _note_column_spin: SpinBox = $HBox/Content/NoteContainer/NoteColumnSpin
@onready var _hold_duration_container: Control = $HBox/Content/NoteContainer/HoldDurationContainer
@onready var _hold_duration_spin: SpinBox = $HBox/Content/NoteContainer/HoldDurationContainer/HoldVBox/HoldDurationSpin
@onready var _heart_map_container: Control = $HBox/Content/NoteContainer/HeartMapContainer
@onready var _heart_map_edit: LineEdit = $HBox/Content/NoteContainer/HeartMapContainer/MapVBox/HeartMapEdit

# --- 编辑器设置（常驻面板） ---
@onready var _settings_container: VBoxContainer = $HBox/Content/SettingsContainer
@onready var _quantize_option: OptionButton = $HBox/Content/SettingsContainer/QuantizeOption
@onready var _snap_toggle: CheckBox = $HBox/Content/SettingsContainer/SnapToggle

var _is_expanded: bool = true
var _mode: int = 0	# 0: meta, 1: note
var _text_undo_pushed: bool = false

func _ready() -> void:
	_connect_scene_signals()
	_switch_to_meta_mode()

# 场景节点的信号连接
func _connect_scene_signals() -> void:
	_toggle_button.pressed.connect(_on_toggle_pressed)

	_title_edit.text_changed.connect(_on_title_changed)
	_title_edit.focus_entered.connect(_reset_text_undo)

	_jacket_path_edit.text_changed.connect(_on_jacket_path_changed)
	_jacket_path_edit.focus_entered.connect(_reset_text_undo)
	_jacket_browse.pressed.connect(_on_jacket_browse_pressed)

	_audio_path_edit.text_changed.connect(_on_audio_path_changed)
	_audio_path_edit.focus_entered.connect(_reset_text_undo)
	_audio_browse.pressed.connect(_on_audio_browse_pressed)

	_bpm_spin.value_changed.connect(_on_bpm_changed)
	_producer_edit.text_changed.connect(_on_producer_changed)
	_producer_edit.focus_entered.connect(_reset_text_undo)
	_vocalist_edit.text_changed.connect(_on_vocalist_changed)
	_vocalist_edit.focus_entered.connect(_reset_text_undo)
	_creator_edit.text_changed.connect(_on_creator_changed)
	_creator_edit.focus_entered.connect(_reset_text_undo)
	_difficulty_option.item_selected.connect(_on_difficulty_changed)

	_note_type_option.item_selected.connect(_on_note_type_changed)
	_note_time_spin.value_changed.connect(_on_note_time_changed)
	_note_column_spin.value_changed.connect(_on_note_column_changed)
	_hold_duration_spin.value_changed.connect(_on_hold_duration_changed)
	_heart_map_edit.text_changed.connect(_on_heart_map_changed)
	_heart_map_edit.focus_entered.connect(_reset_text_undo)

	_quantize_option.item_selected.connect(_on_quantize_changed)
	_snap_toggle.toggled.connect(_on_snap_toggled)

func _push_text_undo() -> void:
	if _text_undo_pushed:
		return
	EditorState.push_undo_state()
	_text_undo_pushed = true

func _reset_text_undo() -> void:
	_text_undo_pushed = false

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
	_title_edit.text = ChartData.title
	_producer_edit.text = ChartData.producer
	_vocalist_edit.text = ChartData.vocalist
	_creator_edit.text = ChartData.creator
	_jacket_path_edit.text = ChartData.jacket_path
	_audio_path_edit.text = ChartData.audio_path
	_block_meta_edit_signals(false)

	_bpm_spin.set_value_no_signal(ChartData.bpm)

	_difficulty_option.set_block_signals(true)
	_difficulty_option.select(ChartDefs.difficulty_index(ChartData.difficulty))
	_difficulty_option.set_block_signals(false)

	if not ChartData.jacket_path.is_empty() and ResourceLoader.exists(ChartData.jacket_path):
		var tex := load(ChartData.jacket_path)
		if tex:
			_jacket_display.texture = tex

func _refresh_settings_fields() -> void:
	_quantize_option.set_block_signals(true)
	_quantize_option.select(ChartDefs.quantize_index_for(EditorState.quantize_denominator))
	_quantize_option.set_block_signals(false)

	_snap_toggle.set_block_signals(true)
	_snap_toggle.button_pressed = EditorState.snap_enabled
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
	ChartData.title = new_text
	emit_signal("meta_changed")

func _on_jacket_path_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.jacket_path = new_text
	if ResourceLoader.exists(new_text):
		var tex := load(new_text)
		if tex:
			_jacket_display.texture = tex
	emit_signal("meta_changed")

func _on_jacket_browse_pressed() -> void:
	emit_signal("jacket_browse_requested")

func _on_audio_path_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.audio_path = new_text
	emit_signal("meta_changed")

func _on_audio_browse_pressed() -> void:
	emit_signal("audio_browse_requested")

func _on_bpm_changed(value: float) -> void:
	EditorState.push_undo_state()
	ChartData.bpm = value
	emit_signal("meta_changed")

func _on_producer_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.producer = new_text
	emit_signal("meta_changed")

func _on_vocalist_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.vocalist = new_text
	emit_signal("meta_changed")

func _on_creator_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.creator = new_text
	emit_signal("meta_changed")

func _on_difficulty_changed(index: int) -> void:
	EditorState.push_undo_state()
	ChartData.difficulty = ChartDefs.DIFFICULTIES[
		clampi(index, 0, ChartDefs.DIFFICULTIES.size() - 1)
	]
	emit_signal("meta_changed")

func _on_quantize_changed(index: int) -> void:
	EditorState.push_undo_state()
	EditorState.quantize_denominator = ChartDefs.quantize_denominator_at(index)
	emit_signal("meta_changed")

func _on_snap_toggled(button_pressed: bool) -> void:
	EditorState.push_undo_state()
	EditorState.snap_enabled = button_pressed
	emit_signal("meta_changed")

# --- 音符属性编辑回调 ---

func _on_note_type_changed(index: int) -> void:
	if selected_note.is_empty():
		return
	EditorState.push_undo_state()
	var type_str: String
	match index:
		0: type_str = "tap"
		1: type_str = "drag"
		2: type_str = "release"
		3: type_str = "hold"
		4: type_str = "heart"
		_: type_str = "tap"

	selected_note["type"] = type_str

	if type_str == "hold" and not selected_note.has("duration"):
		selected_note["duration"] = 500
	if type_str == "heart" and not selected_note.has("map"):
		selected_note["map"] = [1, 2, 3, 4]
	if type_str != "hold" and selected_note.has("duration"):
		selected_note.erase("duration")
	if type_str != "heart" and selected_note.has("map"):
		selected_note.erase("map")

	if selected_note_index >= 0 and selected_note_index < ChartData.notes.size():
		ChartData.notes[selected_note_index] = selected_note

	_refresh_note_fields()
	emit_signal("note_changed", selected_note_index)

func _on_note_time_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	EditorState.push_undo_state()
	selected_note["time"] = int(value)
	if selected_note_index >= 0 and selected_note_index < ChartData.notes.size():
		ChartData.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_note_column_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	EditorState.push_undo_state()
	selected_note["column"] = int(value)
	if selected_note_index >= 0 and selected_note_index < ChartData.notes.size():
		ChartData.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)

func _on_hold_duration_changed(value: float) -> void:
	if selected_note.is_empty():
		return
	EditorState.push_undo_state()
	selected_note["duration"] = int(value)
	if selected_note_index >= 0 and selected_note_index < ChartData.notes.size():
		ChartData.notes[selected_note_index] = selected_note
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
		if selected_note_index >= 0 and selected_note_index < ChartData.notes.size():
			ChartData.notes[selected_note_index] = selected_note
	emit_signal("note_changed", selected_note_index)
