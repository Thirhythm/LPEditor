extends Control

# 主编辑器控制器：把各控件（工具栏 / 轨道区 / 标尺 / 属性面板 / 音频）的信号接起来，
# 并协调文件 I/O 与播放流程；实现细节按职责分给 ChartIO / AudioManager / ChartData / EditorState。

# 工具栏条目按钮全部由 MainEditor.tscn 节点编排：
#   List  = 音符 / 行为 分类按钮（索引 0 = 音符，1 = 行为）
#   List2 = NoteItems（音符子类型按钮，索引 0..5）与 ActionItems（行为按钮，索引 6）
#           两组按当前分类切换可见性
@onready var list: ToolList = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List"
@onready var list2: ToolList = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List2"
@onready var note_items: VBoxContainer = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List2/NoteItems"
@onready var action_items: VBoxContainer = $"Panel/VBoxContainer/ParkPanel/HBoxContainer/List2/ActionItems"
@onready var ruler: EditorRuler = $"Panel/VBoxContainer/Ruler"
@onready var property_panel: PropertyPanel = $"Panel/VBoxContainer/ParkPanel/Property"
@onready var visual: EditorVisual = $"TrackUI/CenterContainer/Visual"
@onready var status_label: Label = $"Panel/HBoxContainer/Label"
@onready var audio: AudioManager = $AudioManager

var _current_note_type: String = ""
var _current_category: int = 0
var _pending_action: Callable = Callable()	# 确认保存后要继续的操作（如退出）

# 文件对话框与提示弹窗均为 MainEditor.tscn 场景节点，脚本只负责连接信号与填充内容
@onready var _file_dialog_open: FileDialog = $FileDialogOpen
@onready var _file_dialog_save: FileDialog = $FileDialogSave
@onready var _file_dialog_jacket: FileDialog = $FileDialogJacket
@onready var _file_dialog_audio: FileDialog = $FileDialogAudio
@onready var _file_dialog_export: FileDialog = $FileDialogExport
@onready var _warning_dialog: AcceptDialog = $WarningDialog
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog

func _ready() -> void:
	action_items.visible = false
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
	_connect_file_dialogs()
	_setup_confirm_dialog()
	# 关闭窗口改由本场景处理，以便退出前确认未保存的编辑
	get_tree().auto_accept_quit = false
	ruler.set_notes(ChartData.notes)
	_update_status("左键放置音符，右键删除音符，按下 Enter 可以播放/暂停")

# 播放时：根据 audio 计时驱动 scroll，使播放头固定于 ruler 锚点处
func _process(_delta: float) -> void:
	if not audio.playing:
		return

	if not audio.player.playing:
		audio.mark_finished()
		_update_status("播放结束")
		return

	var time_ms := audio.elapsed_time_ms()
	ruler.update_playhead(time_ms)

	EditorState.scroll_time = time_ms
	EditorState.clamp_scroll()
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

# 用户关闭窗口（标题栏 × / Alt+F4）：先把退出交给 _request_quit() 处理
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()

# --- 工具栏信号 ---

func _on_list_item_pressed(index: int) -> void:
	_current_category = index
	note_items.visible = index == 0
	action_items.visible = index != 0
	list2.reset_selection()
	_current_note_type = ""
	visual.placement_type = ""

func _on_list2_item_pressed(index: int) -> void:
	if _current_category == 0:
		_current_note_type = ChartDefs.tool_note_type(index)
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
	_update_status("")

func _on_visual_note_deleted(index: int) -> void:
	property_panel.set_meta_mode()
	ruler.set_notes(ChartData.notes)
	_update_status("已删除音符 #%d" % index)

func _on_visual_note_placed(index: int) -> void:
	ruler.set_notes(ChartData.notes)
	_update_status("已放置音符 #%d" % index)

func _on_visual_note_moved(index: int) -> void:
	ruler.set_notes(ChartData.notes)
	var note: Dictionary = ChartData.notes[index]
	property_panel.update_selected_note(note, index)
	_update_status("音符已移动 #%d" % index)

func _on_visual_note_resized(index: int) -> void:
	ruler.set_notes(ChartData.notes)
	var note: Dictionary = ChartData.notes[index]
	property_panel.update_selected_note(note, index)
	_update_status("长键时长已修改 #%d [%dms]" % [index, note.get("duration", 0)])

func _on_visual_scroll_changed() -> void:
	ruler.playhead_time = EditorState.scroll_time
	ruler.queue_redraw()
	# 与点击 ruler 定位一致：播放结束后手动滚动视口（轨道区/ruler 滚轮、缩放）算用户重新定位，
	# 取消"从头重播"，下次播放从当前播放头位置开始
	if not audio.playing:
		audio.clear_finished()

# --- Property 信号 ---

func _on_meta_changed() -> void:
	ruler.set_notes(ChartData.notes)
	visual.queue_redraw()

func _on_note_changed(index: int) -> void:
	ruler.set_notes(ChartData.notes)
	_update_status("音符已更新 #%d" % index)

# --- Ruler 信号 ---

func _on_playhead_moved(time_ms: int) -> void:
	property_panel.set_meta_mode()
	if audio.playing:
		audio.seek(time_ms)
	else:
		# 播放已结束/暂停时手动定位：以新位置为准，不要再从头重播
		audio.clear_finished()
	_update_status("")

# --- 播放控制 ---

func _toggle_playback() -> void:
	if audio.playing:
		audio.pause_playback()
		_update_status("已暂停")
		return

	# 播到末尾自然结束后再按空格：先回到开头，再从头播放
	if audio.finished:
		_rewind_to_start()

	if not audio.start_playback(ruler.playhead_time):
		_update_status("无音频文件，无法播放")
		return

	_update_status("播放中...")


## 播放头与视口回到开头（重置滚动目标，ruler 会平滑滚回起点）
func _rewind_to_start() -> void:
	ruler.update_playhead(0)
	EditorState.scroll_time = 0
	EditorState.clamp_scroll()
	ruler.queue_redraw()
	visual.queue_redraw()

# --- 菜单栏 ---

func _setup_menus() -> void:
	var file_menu: PopupMenu = $"Panel/VBoxContainer/MenuBar/File"
	file_menu.id_pressed.connect(_on_file_menu)
	var edit_menu: PopupMenu = $"Panel/VBoxContainer/MenuBar/Edit"
	edit_menu.id_pressed.connect(_on_edit_menu)

func _on_file_menu(id: int) -> void:
	match id:
		0: 	_confirm_unsaved("谱面有未保存的更改，是否保存？", _new_chart)
		1: 	_confirm_unsaved("谱面有未保存的更改，是否保存？", _file_dialog_open.popup_centered)
		2: _save_chart()
		3: _file_dialog_save.popup_centered()
		6: _export_chart()

func _on_edit_menu(id: int) -> void:
	match id:
		0: _undo()
		1: _redo()

func _undo() -> void:
	if EditorState.undo():
		_after_state_restore()
		_update_status("撤销")

func _redo() -> void:
	if EditorState.redo():
		_after_state_restore()
		_update_status("重做")

func _after_state_restore() -> void:
	property_panel.set_meta_mode()
	visual.deselect()
	visual.queue_redraw()
	ruler.set_notes(ChartData.notes)
	ruler.queue_redraw()

# --- 文件对话框 ---

# 对话框节点、原生对话框开关、文件模式、访问权限与过滤器均已由 MainEditor.tscn 编排，
# 脚本只负责连接各自的选择信号
func _connect_file_dialogs() -> void:
	_file_dialog_open.file_selected.connect(_on_open_file_selected)
	_file_dialog_save.file_selected.connect(_on_save_file_selected)
	_file_dialog_jacket.file_selected.connect(_on_jacket_file_selected)
	_file_dialog_audio.file_selected.connect(_on_audio_file_selected)
	_file_dialog_export.file_selected.connect(_on_export_file_selected)

# --- 文件操作 ---

func _new_chart() -> void:
	audio.stop_playback()
	EditorState.push_undo_state()
	ChartData.new_chart()
	EditorState.mark_saved()
	property_panel.set_meta_mode()
	visual.deselect()
	ruler.set_notes(ChartData.notes)
	_update_status("新建谱面")

func _on_open_file_selected(path: String) -> void:
	audio.stop_playback()
	var result := ChartIO.load_chart(path)
	if not result["ok"]:
		_update_status(result["error"])
		return

	EditorState.push_undo_state()
	ChartData.load_from_dict(result["data"])
	ChartData.current_file_path = path
	EditorState.mark_saved()	# 刚载入的内容即「已保存」基准
	_after_chart_loaded(path)

## 载入谱面后的统一收尾：重载音频、修正视口、刷新各控件
func _after_chart_loaded(path: String) -> void:
	audio.load_audio()
	var max_time := ChartData.get_max_scroll_time()
	EditorState.scroll_time = clampi(EditorState.scroll_time, 0, max_time)
	ruler.playhead_time = clampi(ruler.playhead_time, 0, max_time)
	ruler.update_playhead(ruler.playhead_time)
	property_panel.set_meta_mode()
	visual.deselect()
	ruler.set_notes(ChartData.notes)
	_update_status("")

## 保存到当前路径；需要另存为时弹出对话框并返回 false（保存异步完成）
func _save_chart() -> bool:
	if ChartData.current_file_path.is_empty():
		_file_dialog_save.popup_centered()
		return false
	return _do_save(ChartData.current_file_path)

func _on_save_file_selected(path: String) -> void:
	_do_save(path)

func _do_save(path: String) -> bool:
	var result := ChartIO.save_chart(path, ChartData.to_dict())
	if not result["ok"]:
		_update_status(result["error"])
		# 保存失败：放弃挂起的操作（如退出），避免带着未保存的改动继续
		_pending_action = Callable()
		return false
	ChartData.current_file_path = path
	EditorState.mark_saved()
	_update_status("已保存")
	_flush_pending_action()
	return true

func _on_jacket_browse() -> void:
	_file_dialog_jacket.popup_centered()

func _on_jacket_file_selected(path: String) -> void:
	EditorState.push_undo_state()
	ChartData.jacket_path = path
	property_panel.refresh()

func _on_audio_browse() -> void:
	_file_dialog_audio.popup_centered()

func _on_audio_file_selected(path: String) -> void:
	audio.pause_playback()
	EditorState.push_undo_state()
	ChartData.audio_path = path
	audio.load_audio()
	var max_time := ChartData.get_max_scroll_time()
	ruler.playhead_time = clampi(ruler.playhead_time, 0, max_time)
	EditorState.scroll_time = clampi(EditorState.scroll_time, 0, max_time)
	ruler.update_playhead(ruler.playhead_time)
	property_panel.refresh()

# --- 导出 ---

func _export_chart() -> void:
	var missing := ChartDefs.missing_export_fields({
		"title": ChartData.title,
		"audio_path": ChartData.audio_path,
		"jacket_path": ChartData.jacket_path,
	})

	if not missing.is_empty():
		var msg := "以下内容未填写完毕:\n"
		for field in missing:
			msg += "  · " + field + "\n"
		msg += "请在属性面板中填写后重试"
		_show_warning(msg)
		return

	_file_dialog_export.current_file = ChartData.title + ChartIO.EXTENSION
	_file_dialog_export.popup_centered()

func _on_export_file_selected(path: String) -> void:
	var final_path := ChartIO.ensure_extension(path)
	var result := ChartIO.export_lpz(
		final_path, ChartData.to_dict(), ChartData.audio_path, ChartData.jacket_path
	)
	if result["ok"]:
		_update_status("导出成功: %s" % final_path.get_file())
		return
	_show_warning("导出失败：%s" % result["error"])
# 使用场景中的提示弹窗节点，内容按需填充
func _show_warning(text: String) -> void:
	_warning_dialog.dialog_text = text
	_warning_dialog.popup_centered()

# --- 未保存更改确认 ---

# ConfirmDialog 的三个按钮语义：
#   保存   （确定按钮）        → 保存成功后再继续
#   不保存 （custom_action）   → 放弃改动直接继续
#   取消   （取消按钮 / ESC）  → 中止本次操作
func _setup_confirm_dialog() -> void:
	# 第三个按钮只能运行时添加（AcceptDialog 的自定义按钮无法在场景里编排）
	_confirm_dialog.add_button("不保存", true, "discard")
	_confirm_dialog.confirmed.connect(_on_unsaved_save)
	_confirm_dialog.canceled.connect(_on_unsaved_cancel)
	_confirm_dialog.custom_action.connect(_on_unsaved_custom)
	_file_dialog_save.canceled.connect(_on_save_dialog_canceled)

## 有未保存编辑时弹窗询问，确认后才执行 action；无改动时直接执行
func _confirm_unsaved(message: String, action: Callable) -> void:
	if not EditorState.is_dirty():
		action.call()
		return
	_pending_action = action
	_confirm_dialog.dialog_text = message
	_confirm_dialog.popup_centered()

func _on_unsaved_save() -> void:
	_save_chart()	# 走 _do_save()：保存成功即继续，需另存为时由保存对话框收尾

func _on_unsaved_cancel() -> void:
	_pending_action = Callable()

func _on_unsaved_custom(action: StringName) -> void:
	if action != &"discard":
		return
	_confirm_dialog.hide()	# 自定义按钮不像确定/取消那样自动关闭弹窗
	_flush_pending_action()

## 另存为对话框被取消：挂起的操作用户没确认，直接作废
func _on_save_dialog_canceled() -> void:
	_pending_action = Callable()

func _flush_pending_action() -> void:
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()

# --- 退出 ---

## 退出前确认：有未保存编辑时询问是否保存
func _request_quit() -> void:
	_confirm_unsaved("谱面有未保存的更改，是否保存？", _quit_now)

func _quit_now() -> void:
	audio.stop_playback()
	get_tree().quit()

# --- 状态栏 ---

func _update_status(text: String) -> void:
	if status_label:
		status_label.text = text
