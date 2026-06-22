extends Control

## 音符工具栏项
var list2_note_item: Array[Dictionary] = [
	{ "text": "选择", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "蓝键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "黄键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "红键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "长键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "心键", "icon": "res://Asset/Icon/tap.png" },
]

## 行为工具栏项
var list2_action_item: Array[Dictionary] = [
	{ "text": "变速", "icon": "res://Asset/Icon/speedometer2.svg" },
]

## 工具索引到 note type 的映射
const TOOL_NOTE_TYPE: Array[String] = ["", "tap", "drag", "release", "hold", "heart"]

@onready var list: VBoxContainer = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List"
@onready var list2: VBoxContainer = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List2"
@onready var ruler: EditorRuler = $"Panel/VBoxContainer/Ruler"
@onready var property_panel: PropertyPanel = $"Panel/VBoxContainer/ParkPanel/Property"
@onready var visual: EditorVisual = $"TrackUI/CenterContainer/Visual"
@onready var status_label: Label = $"Panel/HBoxContainer/Label"

# 当前选中的工具
var _current_note_type: String = ""       # 空字符串 = 选择模式
var _current_category: int = 0            # 0: 音符, 1: 行为

# 文件对话框
var _file_dialog_open: FileDialog
var _file_dialog_save: FileDialog
var _file_dialog_jacket: FileDialog
var _file_dialog_audio: FileDialog

# ============================================================
# 初始化
# ============================================================

func _ready() -> void:
	# 工具栏
	list2.item = list2_note_item
	list2.refresh()
	list.item_pressed.connect(_on_list_item_pressed)
	list2.item_pressed.connect(_on_list2_item_pressed)
	
	# 属性面板信号
	property_panel.meta_changed.connect(_on_meta_changed)
	property_panel.note_changed.connect(_on_note_changed)
	property_panel.jacket_browse_requested.connect(_on_jacket_browse)
	property_panel.audio_browse_requested.connect(_on_audio_browse)
	
	# Visual 信号
	visual.note_selected.connect(_on_visual_note_selected)
	visual.note_deselected.connect(_on_visual_note_deselected)
	visual.note_deleted.connect(_on_visual_note_deleted)
	visual.note_placed.connect(_on_visual_note_placed)
	visual.scroll_changed.connect(_on_visual_scroll_changed)
	
	# Ruler 信号
	ruler.playhead_moved.connect(_on_playhead_moved)
	
	# 菜单
	_setup_menus()
	_create_file_dialogs()
	
	# 初始数据
	ruler.set_notes(EditorChartState.notes)
	
	_update_status("就绪")

func _process(_delta: float) -> void:
	pass

# ============================================================
# 工具栏交互
# ============================================================

func _on_list_item_pressed(index: int) -> void:
	_current_category = index
	if index == 0:
		list2.item = list2_note_item
	elif index == 1:
		list2.item = list2_action_item
	list2.refresh()
	_current_note_type = ""
	visual.placement_type = ""

func _on_list2_item_pressed(index: int) -> void:
	if _current_category == 0:
		_current_note_type = TOOL_NOTE_TYPE[index] if index < TOOL_NOTE_TYPE.size() else ""
		visual.placement_type = _current_note_type
	else:
		_current_note_type = ""
		visual.placement_type = ""
	
	print("[MainEditor] 工具切换 category=%d index=%d note_type='%s' visual.placement_type='%s'" % [_current_category, index, _current_note_type, visual.placement_type])
	
	if _current_note_type.is_empty():
		_update_status("选择模式")
	else:
		_update_status("放置: %s" % _current_note_type)

# ============================================================
# Visual 回调
# ============================================================

func _on_visual_note_selected(index: int, note: Dictionary) -> void:
	property_panel.set_note(note, index)
	_update_status("选中音符 #%d [%s] %dms" % [index, note.get("type", "?"), note.get("time", 0)])

func _on_visual_note_deselected() -> void:
	property_panel.set_meta_mode()
	_update_status("已取消选择")

func _on_visual_note_deleted(index: int) -> void:
	property_panel.set_meta_mode()
	ruler.set_notes(EditorChartState.notes)
	_update_status("已删除音符 #%d" % index)

func _on_visual_note_placed(index: int) -> void:
	print("[MainEditor] 收到 note_placed index=%d" % index)
	ruler.set_notes(EditorChartState.notes)
	_update_status("已放置音符 #%d" % index)

func _on_visual_scroll_changed() -> void:
	ruler.queue_redraw()

# ============================================================
# 属性面板回调
# ============================================================

func _on_meta_changed() -> void:
	ruler.set_notes(EditorChartState.notes)

func _on_note_changed(index: int) -> void:
	ruler.set_notes(EditorChartState.notes)
	_update_status("音符已更新 #%d" % index)

# ============================================================
# Ruler 回调
# ============================================================

func _on_playhead_moved(time_ms: int) -> void:
	property_panel.set_meta_mode()
	_update_status("播放头: %d ms" % time_ms)

# ============================================================
# 菜单设置
# ============================================================

func _setup_menus() -> void:
	var file_menu: PopupMenu = $"Panel/VBoxContainer/MenuBar/File"
	file_menu.id_pressed.connect(_on_file_menu)
	var edit_menu: PopupMenu = $"Panel/VBoxContainer/MenuBar/Edit"
	edit_menu.id_pressed.connect(_on_edit_menu)

func _on_file_menu(id: int) -> void:
	match id:
		0: _new_chart()
		1: _file_dialog_open.popup_centered()
		2: _save_chart()
		3: _file_dialog_save.popup_centered()

func _on_edit_menu(id: int) -> void:
	match id:
		0: pass  # 撤销
		1: pass  # 重做

# ============================================================
# 文件对话框
# ============================================================

func _create_file_dialogs() -> void:
	_file_dialog_open = FileDialog.new()
	_file_dialog_open.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog_open.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_open.add_filter("*.json", "谱面文件 (*.json)")
	_file_dialog_open.file_selected.connect(_on_open_file_selected)
	add_child(_file_dialog_open)
	
	_file_dialog_save = FileDialog.new()
	_file_dialog_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog_save.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_save.add_filter("*.json", "谱面文件 (*.json)")
	_file_dialog_save.file_selected.connect(_on_save_file_selected)
	add_child(_file_dialog_save)
	
	_file_dialog_jacket = FileDialog.new()
	_file_dialog_jacket.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog_jacket.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_jacket.add_filter("*.png, *.jpg, *.jpeg, *.bmp, *.webp", "图片文件")
	_file_dialog_jacket.file_selected.connect(_on_jacket_file_selected)
	add_child(_file_dialog_jacket)
	
	_file_dialog_audio = FileDialog.new()
	_file_dialog_audio.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog_audio.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_audio.add_filter("*.mp3, *.ogg, *.wav, *.flac", "音频文件")
	_file_dialog_audio.file_selected.connect(_on_audio_file_selected)
	add_child(_file_dialog_audio)

# ============================================================
# 文件操作
# ============================================================

func _new_chart() -> void:
	EditorChartState.new_chart()
	property_panel.set_meta_mode()
	visual.deselect()
	ruler.set_notes(EditorChartState.notes)
	_update_status("新建谱面")

func _on_open_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_update_status("无法打开文件: %s" % path)
		return
	
	var content := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(content) != OK:
		_update_status("JSON 解析失败: %s" % json.get_error_message())
		return
	
	var data = json.get_data()
	if not data is Dictionary:
		_update_status("无效的谱面格式")
		return
	
	EditorChartState.load_from_dict(data)
	EditorChartState.current_file_path = path
	_update_audio_duration()
	property_panel.set_meta_mode()
	visual.deselect()
	ruler.set_notes(EditorChartState.notes)
	_update_status("已打开: %s [%d 音符]" % [path.get_file(), EditorChartState.notes.size()])

func _save_chart() -> void:
	if EditorChartState.current_file_path.is_empty():
		_file_dialog_save.popup_centered()
		return
	_do_save(EditorChartState.current_file_path)

func _on_save_file_selected(path: String) -> void:
	_do_save(path)

func _do_save(path: String) -> void:
	var json_text := JSON.stringify(EditorChartState.to_dict(), "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_update_status("无法保存文件: %s" % path)
		return
	file.store_string(json_text)
	file.close()
	EditorChartState.current_file_path = path
	_update_status("已保存: %s [%d 音符]" % [path.get_file(), EditorChartState.notes.size()])

# ============================================================
# 曲绘 / 音频浏览
# ============================================================

func _on_jacket_browse() -> void:
	_file_dialog_jacket.popup_centered()

func _on_jacket_file_selected(path: String) -> void:
	EditorChartState.jacket_path = path
	property_panel.refresh()

func _on_audio_browse() -> void:
	_file_dialog_audio.popup_centered()

func _on_audio_file_selected(path: String) -> void:
	EditorChartState.audio_path = path
	_update_audio_duration()
	property_panel.refresh()

# ============================================================
# 工具方法
# ============================================================

## 尝试加载音频文件并获取时长，设置滚动边界
func _update_audio_duration() -> void:
	EditorChartState.audio_duration_ms = 0
	if EditorChartState.audio_path.is_empty():
		return
	
	# 尝试加载音频资源并获取时长
	var resource: Resource = load(EditorChartState.audio_path)
	if resource != null and resource is AudioStream:
		var duration_sec := (resource as AudioStream).get_length()
		if duration_sec > 0:
			EditorChartState.audio_duration_ms = int(duration_sec * 1000.0)

func _update_status(text: String) -> void:
	if status_label:
		status_label.text = text
