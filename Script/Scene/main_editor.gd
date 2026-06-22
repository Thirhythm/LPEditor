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

# 播放状态
var _is_playing: bool = false
var _audio_player: AudioStreamPlayer
var _playback_start_time_ms: int = 0   # Time.get_ticks_msec() 播放起始时刻
var _playback_start_offset_ms: int = 0 # 起始时播放头位置

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
	
	# 音频播放器
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	set_process(true)
	
	# 菜单
	_setup_menus()
	_create_file_dialogs()
	
	# 初始数据
	ruler.set_notes(EditorChartState.notes)
	
	_update_status("就绪")

func _process(_delta: float) -> void:
	if not _is_playing:
		return
	
	# 检测播放结束
	if not _audio_player.playing:
		_pause_playback()
		return
	
	# 同步播放头 — 用独立计时避免 get_playback_position 抖动
	var elapsed := Time.get_ticks_msec() - _playback_start_time_ms
	var time_ms := _playback_start_offset_ms + elapsed
	ruler.update_playhead(time_ms)
	
	# 平滑滚动跟随播放头（保持在屏幕 30% 处）
	var old_scroll := EditorChartState.scroll_time
	var w := ruler.size.x
	var target_scroll := time_ms - int(w * 0.3 / EditorChartState.px_per_ms)
	EditorChartState.scroll_time = int(lerpf(
		float(EditorChartState.scroll_time),
		float(target_scroll),
		_delta * 8.0
	))
	EditorChartState.clamp_scroll()
	# 仅在滚动位置变化时触发 Ruler 重绘（update_playhead 已触发一次）
	if EditorChartState.scroll_time != old_scroll:
		ruler.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_playback()
			get_viewport().set_input_as_handled()

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
	# 非播放状态下滚动轨道时，同步播放头到当前视图位置
	if not _is_playing:
		ruler.update_playhead(EditorChartState.scroll_time)

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
	# 播放中拖动播放头：跳转播放位置并重置计时基准
	if _is_playing:
		_audio_player.play(float(time_ms) / 1000.0)
		_playback_start_time_ms = Time.get_ticks_msec()
		_playback_start_offset_ms = time_ms
	_update_status("播放头: %d ms" % time_ms)

# ============================================================
# 播放控制
# ============================================================

func _toggle_playback() -> void:
	if _is_playing:
		_pause_playback()
	else:
		_start_playback()

func _start_playback() -> void:
	if EditorChartState.audio_path.is_empty():
		_update_status("无音频文件，无法播放")
		return
	
	var stream := _get_audio_stream()
	if stream == null:
		_update_status("无法加载音频文件")
		return
	
	_audio_player.stream = stream
	_audio_player.play(float(ruler.playhead_time) / 1000.0)
	
	# 记录独立计时起点（避免音频回调抖动影响播放头绘制）
	_playback_start_time_ms = Time.get_ticks_msec()
	_playback_start_offset_ms = ruler.playhead_time
	
	_is_playing = true
	_update_status("播放中...")

func _pause_playback() -> void:
	_audio_player.stop()
	_is_playing = false
	_update_status("已暂停")

func _stop_playback() -> void:
	_audio_player.stop()
	_is_playing = false
	ruler.update_playhead(0)
	EditorChartState.scroll_time = 0
	_update_status("播放结束")

## 获取 AudioStream：优先 ResourceLoader，回退手动构建 AudioStreamWAV
func _get_audio_stream() -> AudioStream:
	# 尝试 ResourceLoader
	var resource: Resource = load(EditorChartState.audio_path)
	if resource != null and resource is AudioStream:
		return resource as AudioStream
	
	# 回退：手动解析 WAV 并构建 AudioStreamWAV
	return _build_wav_stream_from_path()

## 从文件路径手动解析 WAV 并构建 AudioStreamWAV（无需 .import）
func _build_wav_stream_from_path() -> AudioStreamWAV:
	var file := _open_audio_file()
	if file == null:
		return null
	
	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		file.close()
		return null
	file.get_32()
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		file.close()
		return null
	
	var sample_rate := 0
	var num_channels := 1
	var bits_per_sample := 16
	var data_offset := 0
	var data_size := 0
	var file_end := file.get_length()
	
	while file.get_position() + 8 <= file_end:
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()
		
		if chunk_id == "fmt ":
			var audio_format := file.get_16()
			if audio_format != 1:
				file.close()
				return null
			num_channels = file.get_16()
			sample_rate = file.get_32()
			file.get_32()
			file.get_16()
			bits_per_sample = file.get_16()
			if chunk_size > 16:
				file.get_buffer(chunk_size - 16)
		elif chunk_id == "data":
			data_offset = file.get_position()
			data_size = chunk_size
			break
		else:
			file.get_buffer(chunk_size)
	
	if sample_rate <= 0 or data_size <= 0:
		file.close()
		return null
	
	file.seek(data_offset)
	var raw_data := file.get_buffer(data_size)
	file.close()
	
	var wav := AudioStreamWAV.new()
	wav.data = raw_data
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = num_channels >= 2
	return wav

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
	_stop_playback()
	EditorChartState.new_chart()
	property_panel.set_meta_mode()
	visual.deselect()
	ruler.set_notes(EditorChartState.notes)
	_update_status("新建谱面")

func _on_open_file_selected(path: String) -> void:
	_stop_playback()
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
	_pause_playback()
	EditorChartState.audio_path = path
	_update_audio_duration()
	property_panel.refresh()

# ============================================================
# 工具方法
# ============================================================

## 尝试加载音频文件并获取时长，设置滚动边界
func _update_audio_duration() -> void:
	EditorChartState.audio_duration_ms = 0
	EditorChartState.waveform_samples.clear()
	if EditorChartState.audio_path.is_empty():
		return
	
	# 优先用 FileAccess 直接解析 WAV（无需 .import）
	if _open_wav_for_parsing():
		return
	
	# 回退：通过 ResourceLoader 加载（适用于已导入的非 WAV 格式）
	var resource: Resource = load(EditorChartState.audio_path)
	if resource != null and resource is AudioStream:
		var duration_sec := (resource as AudioStream).get_length()
		if duration_sec > 0:
			EditorChartState.audio_duration_ms = int(duration_sec * 1000.0)
		if resource is AudioStreamWAV:
			_generate_waveform_from_stream(resource as AudioStreamWAV)

# ============================================================
# WAV 直接解析（绕过 Godot 导入系统）
# ============================================================

## 解析 EditorChartState.audio_path 指向的 WAV 文件，获取时长和波形
## 返回 true 表示成功解析并已设置 waveform_samples
func _open_wav_for_parsing() -> bool:
	var file := _open_audio_file()
	if file == null:
		return false
	
	# 验证 RIFF/WAVE 头
	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		file.close()
		return false
	file.get_32()  # 文件总大小（不含 RIFF 头）
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		file.close()
		return false
	
	# 查找 fmt 和 data 块
	var sample_rate := 0
	var num_channels := 1
	var bits_per_sample := 16
	var data_offset := 0
	var data_size := 0
	var file_end := file.get_length()
	
	while file.get_position() + 8 <= file_end:
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()
		
		if chunk_id == "fmt ":
			var audio_format := file.get_16()
			if audio_format != 1:  # 仅支持 PCM
				file.close()
				return false
			num_channels = file.get_16()
			sample_rate = file.get_32()
			file.get_32()  # byte_rate
			file.get_16()  # block_align
			bits_per_sample = file.get_16()
			if chunk_size > 16:
				file.get_buffer(chunk_size - 16)
		elif chunk_id == "data":
			data_offset = file.get_position()
			data_size = chunk_size
			break
		else:
			file.get_buffer(chunk_size)
	
	if sample_rate <= 0 or data_size <= 0:
		file.close()
		return false
	
	# 计算时长
	var bytes_per_sample := bits_per_sample / 8
	var bytes_per_frame := bytes_per_sample * num_channels
	var total_frames := data_size / bytes_per_frame
	var duration_sec := float(total_frames) / sample_rate
	EditorChartState.audio_duration_ms = int(duration_sec * 1000.0)
	
	# 读取 PCM 数据
	file.seek(data_offset)
	var raw_data := file.get_buffer(data_size)
	file.close()
	
	# 生成波形
	_downsample_waveform(raw_data, total_frames, sample_rate, num_channels, bits_per_sample)
	return true

## 将 PCM 原始数据降采样为 1000Hz 的波形振幅数组
func _downsample_waveform(raw_data: PackedByteArray, total_frames: int, sample_rate: int,
		num_channels: int, bits_per_sample: int) -> void:
	var output_rate := 1000  # 每毫秒一个采样点
	var duration_sec := float(total_frames) / sample_rate
	var num_output := maxi(int(duration_sec * output_rate), 1)
	var result := PackedFloat32Array()
	result.resize(num_output)
	
	var bytes_per_sample := bits_per_sample / 8
	var bytes_per_frame := bytes_per_sample * num_channels
	var frames_per_output := float(total_frames) / float(num_output)
	var is_16bit := bits_per_sample == 16
	
	for i in range(num_output):
		var start_frame := int(i * frames_per_output)
		var end_frame := int(min(float(total_frames), (i + 1) * frames_per_output))
		var peak: float = 0.0
		
		for f in range(start_frame, end_frame):
			var offset := f * bytes_per_frame
			var frame_sum: float = 0.0
			
			for ch in range(num_channels):
				var ch_offset := offset + ch * bytes_per_sample
				var sample: float
				if is_16bit:
					var lo := raw_data[ch_offset] as int
					var hi := raw_data[ch_offset + 1] as int
					var s16 := (hi << 8) | lo
					if s16 >= 32768:
						s16 -= 65536
					sample = float(s16) / 32768.0
				else:
					sample = float(raw_data[ch_offset]) / 128.0 - 1.0
				frame_sum += sample
			
			var avg := frame_sum / float(num_channels)
			peak = maxf(peak, absf(avg))
		
		result[i] = peak
	
	EditorChartState.waveform_samples = result

## 将 res:// 路径转为文件系统绝对路径后打开
func _open_audio_file() -> FileAccess:
	var path := EditorChartState.audio_path
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	return FileAccess.open(path, FileAccess.READ)

# ============================================================
# ResourceLoader 回退路径
# ============================================================

## 从 AudioStreamWAV 生成波形采样（降采样至 1000Hz）
func _generate_waveform_from_stream(stream: AudioStreamWAV) -> void:
	var data := stream.data
	if data.is_empty():
		return
	
	var is_stereo := stream.stereo
	var mix_rate := stream.mix_rate
	var fmt := stream.format
	
	var bytes_per_sample := 2 if fmt == AudioStreamWAV.FORMAT_16_BITS else 1
	var num_channels := 2 if is_stereo else 1
	var bytes_per_frame := bytes_per_sample * num_channels
	var total_frames := data.size() / bytes_per_frame
	if total_frames <= 0:
		return
	
	_downsample_waveform(data, total_frames, mix_rate, num_channels, bytes_per_sample * 8)

func _update_status(text: String) -> void:
	if status_label:
		status_label.text = text
