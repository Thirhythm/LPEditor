extends Control
class_name PropertyPanel

# 属性面板组件：编辑谱面元数据、音符属性与特效属性
# 支持折叠/展开，分为元数据模式（meta）、音符编辑模式（note）和特效编辑模式（effect）
# 所有控件均由 Scene/Widget/PropertyPanel.tscn 节点编排，脚本只负责信号连接与数据刷新

const EXPANDED_WIDTH: float = 280.0
const COLLAPSED_WIDTH: float = 32.0

var selected_note: Dictionary = {}
var selected_note_index: int = -1
var selected_effect: Dictionary = {}
var selected_effect_index: int = -1

# --- 折叠按钮与内容容器 ---
@onready var _toggle_button: Button = $HBox/ToggleButton
@onready var _content_container: VBoxContainer = $HBox/ContentScroll/Content

# --- 元数据 UI 控件 ---
@onready var _meta_container: VBoxContainer = $HBox/ContentScroll/Content/MetaContainer
@onready var _title_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/TitleEdit
@onready var _jacket_display: TextureRect = $HBox/ContentScroll/Content/MetaContainer/JacketDisplay
@onready var _jacket_path_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/JacketPathHBox/JacketPathEdit
@onready var _jacket_browse: Button = $HBox/ContentScroll/Content/MetaContainer/JacketPathHBox/JacketBrowse
@onready var _audio_path_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/AudioPathHBox/AudioPathEdit
@onready var _audio_browse: Button = $HBox/ContentScroll/Content/MetaContainer/AudioPathHBox/AudioBrowse
@onready var _bpm_spin: SpinBox = $HBox/ContentScroll/Content/MetaContainer/BpmSpin
@onready var _artist_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/ArtistEdit
@onready var _vocalist_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/VocalistEdit
@onready var _illustrator_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/IllustratorEdit
@onready var _creator_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/CreatorEdit
@onready var _version_edit: LineEdit = $HBox/ContentScroll/Content/MetaContainer/VersionEdit
@onready var _difficulty_option: OptionButton = $HBox/ContentScroll/Content/MetaContainer/DifficultyOption
@onready var _preview_spin: SpinBox = $HBox/ContentScroll/Content/MetaContainer/PreviewHBox/PreviewSpin
@onready var _preview_capture: Button = $HBox/ContentScroll/Content/MetaContainer/PreviewHBox/PreviewCapture
@onready var _preview_end_spin: SpinBox = $HBox/ContentScroll/Content/MetaContainer/PreviewEndHBox/PreviewEndSpin
@onready var _preview_end_capture: Button = $HBox/ContentScroll/Content/MetaContainer/PreviewEndHBox/PreviewEndCapture
@onready var _crystal_spin: SpinBox = $HBox/ContentScroll/Content/MetaContainer/CrystalSpin
@onready var _chapter_spin: SpinBox = $HBox/ContentScroll/Content/MetaContainer/ChapterSpin

# --- 音符属性 UI 控件 ---
@onready var _note_container: VBoxContainer = $HBox/ContentScroll/Content/NoteContainer
@onready var _note_type_option: OptionButton = $HBox/ContentScroll/Content/NoteContainer/NoteTypeOption
@onready var _note_time_spin: SpinBox = $HBox/ContentScroll/Content/NoteContainer/NoteTimeSpin
@onready var _note_column_spin: SpinBox = $HBox/ContentScroll/Content/NoteContainer/NoteColumnSpin
@onready var _hold_duration_container: VBoxContainer = $HBox/ContentScroll/Content/NoteContainer/HoldDurationContainer
@onready var _hold_duration_spin: SpinBox = $HBox/ContentScroll/Content/NoteContainer/HoldDurationContainer/HoldDurationSpin

# --- 特效属性 UI 控件 ---
@onready var _effect_container: VBoxContainer = $HBox/ContentScroll/Content/EffectContainer
@onready var _effect_type_option: OptionButton = $HBox/ContentScroll/Content/EffectContainer/EffectTypeOption
@onready var _effect_start_spin: SpinBox = $HBox/ContentScroll/Content/EffectContainer/EffectStartSpin
@onready var _effect_end_spin: SpinBox = $HBox/ContentScroll/Content/EffectContainer/EffectEndSpin
@onready var _effect_changed_edit: LineEdit = $HBox/ContentScroll/Content/EffectContainer/EffectChangedEdit

# --- 编辑器设置（常驻面板） ---
@onready var _settings_container: VBoxContainer = $HBox/ContentScroll/Content/SettingsContainer
@onready var _quantize_option: OptionButton = $HBox/ContentScroll/Content/SettingsContainer/QuantizeOption
@onready var _snap_toggle: CheckBox = $HBox/ContentScroll/Content/SettingsContainer/SnapToggle

var _is_expanded: bool = true
var _mode: int = 0	# 0: meta, 1: note
var _text_undo_pushed: bool = false

func _ready() -> void:
	_apply_meta_ranges()
	_connect_scene_signals()
	_switch_to_meta_mode()

## 数值范围与 ChartDefs 同源：面板钳制显示值、载入时收敛文档值，两边用同一组常量，
## 免得出现「文档里是 -3、面板显示 1」这种对不上的情况
func _apply_meta_ranges() -> void:
	_preview_spin.max_value = ChartDefs.MAX_PREVIEW_MS
	_preview_end_spin.max_value = ChartDefs.MAX_PREVIEW_MS
	_crystal_spin.max_value = ChartDefs.MAX_CRYSTAL
	_chapter_spin.min_value = ChartDefs.MIN_CHAPTER
	_chapter_spin.max_value = ChartDefs.MAX_CHAPTER

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
	_artist_edit.text_changed.connect(_on_artist_changed)
	_artist_edit.focus_entered.connect(_reset_text_undo)
	_vocalist_edit.text_changed.connect(_on_vocalist_changed)
	_vocalist_edit.focus_entered.connect(_reset_text_undo)
	_illustrator_edit.text_changed.connect(_on_illustrator_changed)
	_illustrator_edit.focus_entered.connect(_reset_text_undo)
	_creator_edit.text_changed.connect(_on_creator_changed)
	_creator_edit.focus_entered.connect(_reset_text_undo)
	_version_edit.text_changed.connect(_on_version_changed)
	_version_edit.focus_entered.connect(_reset_text_undo)
	_difficulty_option.item_selected.connect(_on_difficulty_changed)

	_preview_spin.value_changed.connect(_on_preview_changed)
	_preview_capture.pressed.connect(_on_preview_capture_pressed.bind(false))
	_preview_end_spin.value_changed.connect(_on_preview_end_changed)
	_preview_end_capture.pressed.connect(_on_preview_capture_pressed.bind(true))
	_crystal_spin.value_changed.connect(_on_crystal_changed)
	_chapter_spin.value_changed.connect(_on_chapter_changed)

	_note_type_option.item_selected.connect(_on_note_type_changed)
	_note_time_spin.value_changed.connect(_on_note_time_changed)
	_note_column_spin.value_changed.connect(_on_note_column_changed)
	_hold_duration_spin.value_changed.connect(_on_hold_duration_changed)

	_effect_type_option.item_selected.connect(_on_effect_type_changed)
	_effect_start_spin.value_changed.connect(_on_effect_start_changed)
	_effect_end_spin.value_changed.connect(_on_effect_end_changed)
	_effect_changed_edit.text_changed.connect(_on_effect_changed_text_changed)
	_effect_changed_edit.focus_entered.connect(_reset_text_undo)

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
	_effect_container.visible = false
	_refresh_meta_fields()
	_refresh_settings_fields()

func _switch_to_note_mode() -> void:
	_mode = 1
	_meta_container.visible = false
	_note_container.visible = true
	_effect_container.visible = false
	_refresh_note_fields()
	_refresh_settings_fields()

func _switch_to_effect_mode() -> void:
	_mode = 2
	_meta_container.visible = false
	_note_container.visible = false
	_effect_container.visible = true
	_refresh_effect_fields()
	_refresh_settings_fields()

# --- 字段刷新 ---

func _refresh_meta_fields() -> void:
	_block_meta_edit_signals(true)
	_title_edit.text = ChartData.title
	_artist_edit.text = ChartData.artist
	_vocalist_edit.text = ChartData.vocalist
	_illustrator_edit.text = ChartData.illustrator
	_creator_edit.text = ChartData.creator
	_version_edit.text = ChartData.version
	_jacket_path_edit.text = ChartData.jacket_path
	_audio_path_edit.text = ChartData.audio_path
	_block_meta_edit_signals(false)

	_bpm_spin.set_value_no_signal(ChartData.bpm)
	_preview_spin.set_value_no_signal(float(ChartData.preview_ms))
	_preview_end_spin.set_value_no_signal(float(ChartData.preview_end_ms))
	_crystal_spin.set_value_no_signal(float(ChartData.crystal))
	_chapter_spin.set_value_no_signal(float(ChartData.chapter))

	_difficulty_option.set_block_signals(true)
	_difficulty_option.select(ChartDefs.difficulty_index(ChartData.difficulty))
	_difficulty_option.set_block_signals(false)

	_update_jacket_display()

func _refresh_settings_fields() -> void:
	_quantize_option.set_block_signals(true)
	_quantize_option.select(ChartDefs.quantize_index_for(EditorState.quantize_denominator))
	_quantize_option.set_block_signals(false)

	_snap_toggle.set_block_signals(true)
	_snap_toggle.button_pressed = EditorState.snap_enabled
	_snap_toggle.set_block_signals(false)

func _block_meta_edit_signals(block: bool) -> void:
	_title_edit.set_block_signals(block)
	_artist_edit.set_block_signals(block)
	_vocalist_edit.set_block_signals(block)
	_illustrator_edit.set_block_signals(block)
	_creator_edit.set_block_signals(block)
	_version_edit.set_block_signals(block)
	_jacket_path_edit.set_block_signals(block)
	_audio_path_edit.set_block_signals(block)

func _refresh_note_fields() -> void:
	if selected_note.is_empty():
		return

	var ntype: String = selected_note.get("type", ChartDefs.NOTE_TYPES[0])
	_note_type_option.set_block_signals(true)
	_note_type_option.select(ChartDefs.note_type_index(ntype))
	_note_type_option.set_block_signals(false)

	_note_time_spin.set_value_no_signal(selected_note.get("time", 0) as float)
	_note_column_spin.set_value_no_signal(selected_note.get("column", 1) as float)

	var is_hold := ntype == ChartDefs.NOTE_TYPE_HOLD
	_hold_duration_container.visible = is_hold
	if is_hold:
		_hold_duration_spin.set_value_no_signal(selected_note.get("duration", 0) as float)

func _refresh_effect_fields() -> void:
	if selected_effect.is_empty():
		return

	_effect_type_option.set_block_signals(true)
	_effect_type_option.select(ChartDefs.effect_type_index(selected_effect.get("type", "")))
	_effect_type_option.set_block_signals(false)

	_effect_start_spin.set_value_no_signal(float(selected_effect.get("time", 0) as int))
	_effect_end_spin.set_value_no_signal(float(ChartDefs.effect_end_time(selected_effect)))

	var parts := PackedStringArray()
	for value in ChartDefs.normalize_changed(selected_effect.get("changed", [])):
		parts.append(str(value))
	_effect_changed_edit.set_block_signals(true)
	_effect_changed_edit.text = ",".join(parts)
	_effect_changed_edit.set_block_signals(false)

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
signal effect_changed(index: int)
signal jacket_browse_requested()
signal audio_browse_requested()
signal preview_capture_requested(is_end: bool)

func set_meta_mode() -> void:
	selected_note = {}
	selected_note_index = -1
	selected_effect = {}
	selected_effect_index = -1
	_switch_to_meta_mode()

func set_note(note: Dictionary, index: int) -> void:
	selected_note = note.duplicate(true)
	selected_note_index = index
	selected_effect = {}
	selected_effect_index = -1
	_switch_to_note_mode()

func set_effect(effect: Dictionary, index: int) -> void:
	selected_note = {}
	selected_note_index = -1
	selected_effect = effect.duplicate(true)
	selected_effect_index = index
	_switch_to_effect_mode()

func update_selected_note(note: Dictionary, index: int) -> void:
	if selected_note_index != index or _mode != 1:
		return
	selected_note = note.duplicate(true)
	_refresh_note_fields()

func refresh() -> void:
	match _mode:
		0: _refresh_meta_fields()
		1: _refresh_note_fields()
		2: _refresh_effect_fields()
	_refresh_settings_fields()

# --- 元数据编辑回调 ---

func _on_title_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.title = new_text
	emit_signal("meta_changed")

func _on_jacket_path_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.jacket_path = new_text
	_update_jacket_display()
	emit_signal("meta_changed")

## 把 ChartData.jacket_path 指向的图片读进预览框。
## 路径来自文件对话框，是文件系统里的普通图片文件而不是 res:// 下的导入资源，
## 所以既不能用 ResourceLoader.exists() 判断存在性，也不能用 load() 读取
## （那样只有当图片恰好被 Godot 导入过才显示得出来）。
## 读不出来时清空预览，避免上一次的曲绘残留在面板上。
func _update_jacket_display() -> void:
	var path := ChartData.jacket_path
	# 先判存在：路径框是逐字输入的，中间状态会让 Image.load() 往控制台刷报错
	if path.is_empty() or not FileAccess.file_exists(path):
		_jacket_display.texture = null
		return

	var image := Image.new()
	if image.load(path) != OK:
		_jacket_display.texture = null
		return
	_jacket_display.texture = ImageTexture.create_from_image(image)

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

func _on_artist_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.artist = new_text
	emit_signal("meta_changed")

func _on_illustrator_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.illustrator = new_text
	emit_signal("meta_changed")

func _on_vocalist_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.vocalist = new_text
	emit_signal("meta_changed")

func _on_creator_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.creator = new_text
	emit_signal("meta_changed")

func _on_version_changed(new_text: String) -> void:
	_push_text_undo()
	ChartData.version = new_text
	emit_signal("meta_changed")

func _on_difficulty_changed(index: int) -> void:
	EditorState.push_undo_state()
	ChartData.difficulty = ChartDefs.DIFFICULTIES[
		clampi(index, 0, ChartDefs.DIFFICULTIES.size() - 1)
	]
	emit_signal("meta_changed")

func _on_preview_changed(value: float) -> void:
	EditorState.push_undo_state()
	ChartData.preview_ms = int(value)
	emit_signal("meta_changed")

func _on_preview_end_changed(value: float) -> void:
	EditorState.push_undo_state()
	ChartData.preview_end_ms = int(value)
	emit_signal("meta_changed")

## 「取播放头」按钮：播放头位置只有主控制器知道，交给它回填
func _on_preview_capture_pressed(is_end: bool) -> void:
	emit_signal("preview_capture_requested", is_end)

func _on_crystal_changed(value: float) -> void:
	EditorState.push_undo_state()
	ChartData.crystal = int(value)
	emit_signal("meta_changed")

func _on_chapter_changed(value: float) -> void:
	EditorState.push_undo_state()
	ChartData.chapter = int(value)
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
	selected_note["type"] = ChartDefs.note_type_at(index)
	ChartDefs.normalize_note_fields(selected_note)

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

# --- 特效属性编辑回调 ---

## 把面板上的副本写回 ChartData 并通知主控制器；下标越界时只发信号不回写
func _commit_effect() -> void:
	if selected_effect_index >= 0 and selected_effect_index < ChartData.effects.size():
		ChartData.effects[selected_effect_index] = selected_effect
	emit_signal("effect_changed", selected_effect_index)

func _on_effect_type_changed(index: int) -> void:
	if selected_effect.is_empty():
		return
	EditorState.push_undo_state()
	selected_effect["type"] = ChartDefs.effect_type_at(index)
	_commit_effect()

## 改开始时间时保持结束时间不动（时长随之伸缩）
func _on_effect_start_changed(value: float) -> void:
	if selected_effect.is_empty():
		return
	EditorState.push_undo_state()
	var end := ChartDefs.effect_end_time(selected_effect)
	var start := int(value)
	selected_effect["time"] = start
	selected_effect["duration"] = maxi(end - start, ChartDefs.EFFECT_MIN_DURATION_MS)
	_commit_effect()
	_refresh_effect_fields()

## 改结束时间时开始时间不动
func _on_effect_end_changed(value: float) -> void:
	if selected_effect.is_empty():
		return
	EditorState.push_undo_state()
	var start := selected_effect.get("time", 0) as int
	selected_effect["duration"] = maxi(int(value) - start, ChartDefs.EFFECT_MIN_DURATION_MS)
	_commit_effect()
	_refresh_effect_fields()

## changed 用逗号分隔填写，长度与取值由 normalize_changed 收敛
func _on_effect_changed_text_changed(new_text: String) -> void:
	if selected_effect.is_empty():
		return
	_push_text_undo()
	var parsed: Array[int] = []
	for part in new_text.split(",", false):
		parsed.append(part.strip_edges().to_int())
	if parsed.is_empty():
		return
	selected_effect["changed"] = ChartDefs.normalize_changed(parsed)
	_commit_effect()
