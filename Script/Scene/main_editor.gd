extends Control

# 主编辑器控制器，管理所有组件之间的信号连接和业务逻辑协调
# 职责：工具栏操作、文件 I/O、播放控制、状态更新

const TOOL_NOTE_TYPE: Array[String] = ["", "tap", "drag", "release", "hold", "heart"]

var list2_note_item: Array[Dictionary] = [
	{ "text": "选择", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "蓝键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "黄键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "红键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "长键", "icon": "res://Asset/Icon/tap.png" },
	{ "text": "心键", "icon": "res://Asset/Icon/tap.png" },
]

var list2_action_item: Array[Dictionary] = [
	{ "text": "变速", "icon": "res://Asset/Icon/speedometer2.svg" },
]

@onready var list: VBoxContainer = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List"
@onready var list2: VBoxContainer = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List2"
@onready var ruler: EditorRuler = $"Panel/VBoxContainer/Ruler"
@onready var property_panel: PropertyPanel = $"Panel/VBoxContainer/ParkPanel/Property"
@onready var visual: EditorVisual = $"TrackUI/CenterContainer/Visual"
@onready var status_label: Label = $"Panel/HBoxContainer/Label"
@onready var audio: AudioManager = $AudioManager

var _current_note_type: String = ""
var _current_category: int = 0

var _file_dialog_open: FileDialog
var _file_dialog_save: FileDialog
var _file_dialog_jacket: FileDialog
var _file_dialog_audio: FileDialog
var _file_dialog_export: FileDialog

func _ready() -> void:
	list2.item = list2_note_item
	list2.refresh()
	list.item_pressed.connect(_on_list_item_pressed)
	list2.item_pressed.connect(_on_list2_item_pressed)

	property_panel.meta_changed.connect(_on_meta_changed)
	property_panel.note_changed.connect(_on_note_changed)
	property_panel.jacket_browse_requested.connect(_on_jacket_browse)
	property_panel.audio_browse_requested.connect(_on_audio_browse)

	visual.note_selected.connect(_on_visual_note_selected)
	visual.note_deselected.connect(_on_visual_note_deselected)
	visual.note_deleted.connect(_on_visual_note_deleted)
	visual.note_placed.connect(_on_visual_note_placed)
	visual.scroll_changed.connect(_on_visual_scroll_changed)
	visual.note_moved.connect(_on_visual_note_moved)
	visual.note_resized.connect(_on_visual_note_resized)

	ruler.playhead_moved.connect(_on_playhead_moved)
	
	set_process(true)
	_setup_menus()
	_create_file_dialogs()
	ruler.set_notes(EditorChartState.notes)
	_update_status("就绪")

# 播放时：根据 audio 计时驱动 scroll，使播放头固定于 ruler 锚点处
func _process(_delta: float) -> void:
	if not audio.playing:
		return

	if not audio.player.playing:
		audio.pause_playback()
		_update_status("播放结束")
		return

	var time_ms := audio.elapsed_time_ms()
	ruler.update_playhead(time_ms)

	EditorChartState.scroll_time = time_ms
	EditorChartState.clamp_scroll()
	ruler.queue_redraw()

# 空格键切换播放/暂停，Ctrl+Z 撤销，Ctrl+Y 重做
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_playback()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y and event.ctrl_pressed:
			_redo()
			get_viewport().set_input_as_handled()

# --- 工具栏信号 ---

func _on_list_item_pressed(index: int) -> void:
	_current_category = index
	list2.item = list2_note_item if index == 0 else list2_action_item
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

	if _current_note_type.is_empty():
		_update_status("选择模式")
	else:
		_update_status("放置: %s" % _current_note_type)

# --- Visual 信号 ---

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
	ruler.set_notes(EditorChartState.notes)
	_update_status("已放置音符 #%d" % index)

func _on_visual_note_moved(index: int) -> void:
	ruler.set_notes(EditorChartState.notes)
	var note: Dictionary = EditorChartState.notes[index]
	property_panel.update_selected_note(note, index)
	_update_status("音符已移动 #%d" % index)

func _on_visual_note_resized(index: int) -> void:
	ruler.set_notes(EditorChartState.notes)
	var note: Dictionary = EditorChartState.notes[index]
	property_panel.update_selected_note(note, index)
	_update_status("长键时长已修改 #%d [%dms]" % [index, note.get("duration", 0)])

func _on_visual_scroll_changed() -> void:
	ruler.playhead_time = EditorChartState.scroll_time
	ruler.queue_redraw()

# --- Property 信号 ---

func _on_meta_changed() -> void:
	ruler.set_notes(EditorChartState.notes)
	visual.queue_redraw()

func _on_note_changed(index: int) -> void:
	ruler.set_notes(EditorChartState.notes)
	_update_status("音符已更新 #%d" % index)

# --- Ruler 信号 ---

func _on_playhead_moved(time_ms: int) -> void:
	property_panel.set_meta_mode()
	if audio.playing:
		audio.seek(time_ms)
	_update_status("播放头: %d ms" % time_ms)

# --- 播放控制 ---

func _toggle_playback() -> void:
	if audio.playing:
		audio.pause_playback()
		_update_status("已暂停")
		return

	if not audio.start_playback(ruler.playhead_time):
		_update_status("无音频文件，无法播放")
		return

	_update_status("播放中...")

# --- 菜单栏 ---

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
		6: _export_chart()

func _on_edit_menu(id: int) -> void:
	match id:
		0: _undo()
		1: _redo()

func _undo() -> void:
	if EditorChartState.undo():
		_after_state_restore()
		_update_status("撤销")

func _redo() -> void:
	if EditorChartState.redo():
		_after_state_restore()
		_update_status("重做")

func _after_state_restore() -> void:
	property_panel.set_meta_mode()
	visual.deselect()
	visual.queue_redraw()
	ruler.set_notes(EditorChartState.notes)
	ruler.queue_redraw()

# --- 文件对话框 ---

func _create_file_dialogs() -> void:
	_file_dialog_open = FileDialog.new()
	_file_dialog_open.use_native_dialog = true
	_file_dialog_open.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog_open.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_open.add_filter("*.json", "谱面文件 (*.json)")
	_file_dialog_open.file_selected.connect(_on_open_file_selected)
	add_child(_file_dialog_open)

	_file_dialog_save = FileDialog.new()
	_file_dialog_save.use_native_dialog = true
	_file_dialog_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog_save.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_save.add_filter("*.json", "谱面文件 (*.json)")
	_file_dialog_save.file_selected.connect(_on_save_file_selected)
	add_child(_file_dialog_save)

	_file_dialog_jacket = FileDialog.new()
	_file_dialog_jacket.use_native_dialog = true
	_file_dialog_jacket.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog_jacket.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_jacket.add_filter("*.png, *.jpg, *.jpeg, *.bmp, *.webp", "图片文件")
	_file_dialog_jacket.file_selected.connect(_on_jacket_file_selected)
	add_child(_file_dialog_jacket)

	_file_dialog_audio = FileDialog.new()
	_file_dialog_audio.use_native_dialog = true
	_file_dialog_audio.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog_audio.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_audio.add_filter("*.mp3, *.ogg, *.wav, *.flac", "音频文件")
	_file_dialog_audio.file_selected.connect(_on_audio_file_selected)
	add_child(_file_dialog_audio)

	_file_dialog_export = FileDialog.new()
	_file_dialog_export.use_native_dialog = true
	_file_dialog_export.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog_export.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_export.add_filter("*.lpz", "谱面压缩包 (*.lpz)")
	_file_dialog_export.file_selected.connect(_on_export_file_selected)
	add_child(_file_dialog_export)

# --- 文件操作 ---

func _new_chart() -> void:
	audio.stop_playback()
	EditorChartState.push_undo_state()
	EditorChartState.new_chart()
	property_panel.set_meta_mode()
	visual.deselect()
	ruler.set_notes(EditorChartState.notes)
	_update_status("新建谱面")

func _on_open_file_selected(path: String) -> void:
	audio.stop_playback()
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

	EditorChartState.push_undo_state()
	EditorChartState.load_from_dict(data)
	EditorChartState.current_file_path = path
	audio.load_audio()
	var max_time := EditorChartState.get_max_scroll_time()
	EditorChartState.scroll_time = clampi(EditorChartState.scroll_time, 0, max_time)
	ruler.playhead_time = clampi(ruler.playhead_time, 0, max_time)
	ruler.update_playhead(ruler.playhead_time)
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

func _on_jacket_browse() -> void:
	_file_dialog_jacket.popup_centered()

func _on_jacket_file_selected(path: String) -> void:
	EditorChartState.push_undo_state()
	EditorChartState.jacket_path = path
	property_panel.refresh()

func _on_audio_browse() -> void:
	_file_dialog_audio.popup_centered()

func _on_audio_file_selected(path: String) -> void:
	audio.pause_playback()
	EditorChartState.push_undo_state()
	EditorChartState.audio_path = path
	audio.load_audio()
	var max_time := EditorChartState.get_max_scroll_time()
	ruler.playhead_time = clampi(ruler.playhead_time, 0, max_time)
	EditorChartState.scroll_time = clampi(EditorChartState.scroll_time, 0, max_time)
	ruler.update_playhead(ruler.playhead_time)
	property_panel.refresh()

# --- 导出 ---

func _export_chart() -> void:
	var missing: Array[String] = []
	if EditorChartState.title.is_empty() or EditorChartState.title == "Untitled":
		missing.append("标题")
	if EditorChartState.audio_path.is_empty():
		missing.append("音频文件")
	if EditorChartState.jacket_path.is_empty():
		missing.append("曲绘")

	if not missing.is_empty():
		var msg := "以下参数未填写完毕:\n"
		for field in missing:
			msg += "  · " + field + "\n"
		msg += "请在属性面板中填写后重试"
		_show_warning(msg)
		return

	_file_dialog_export.current_file = EditorChartState.title + ".lpz"
	_file_dialog_export.popup_centered()

func _on_export_file_selected(path: String) -> void:
	var final_path := path
	if not final_path.ends_with(".lpz"):
		final_path += ".lpz"
	var err := _do_export(final_path)
	if err == OK:
		_update_status("导出成功: %s" % final_path.get_file())
	else:
		_show_warning("导出失败，错误代码: %d" % err)

func _do_export(path: String) -> int:
	var packer := ZIPPacker.new()
	var err := packer.open(path)
	if err != OK:
		return err

	var chart_dict := EditorChartState.to_dict()
	chart_dict["General"].erase("AudioPath")
	chart_dict["General"].erase("JacketPath")
	var json_bytes := JSON.stringify(chart_dict, "\t").to_utf8_buffer()
	packer.start_file("chart.lp")
	packer.write_file(json_bytes)
	packer.close_file()

	if not EditorChartState.audio_path.is_empty():
		if not FileAccess.file_exists(EditorChartState.audio_path):
			packer.close()
			return ERR_FILE_NOT_FOUND
		var audio_file := FileAccess.open(EditorChartState.audio_path, FileAccess.READ)
		if audio_file:
			var audio_data := audio_file.get_buffer(audio_file.get_length())
			var ext := EditorChartState.audio_path.get_extension()
			packer.start_file("audio" if ext.is_empty() else "audio." + ext)
			packer.write_file(audio_data)
			packer.close_file()
			audio_file.close()

	if not EditorChartState.jacket_path.is_empty():
		if not FileAccess.file_exists(EditorChartState.jacket_path):
			packer.close()
			return ERR_FILE_NOT_FOUND
		var jacket_file := FileAccess.open(EditorChartState.jacket_path, FileAccess.READ)
		if jacket_file:
			var jacket_data := jacket_file.get_buffer(jacket_file.get_length())
			var ext := EditorChartState.jacket_path.get_extension()
			packer.start_file("cover" if ext.is_empty() else "cover." + ext)
			packer.write_file(jacket_data)
			packer.close_file()
			jacket_file.close()

	packer.close()
	return OK

func _show_warning(text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "提示"
	dialog.dialog_text = text
	dialog.ok_button_text = "确定"
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

# --- 状态栏 ---

func _update_status(text: String) -> void:
	if status_label:
		status_label.text = text
