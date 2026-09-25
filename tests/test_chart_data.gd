@tool
extends McpTestSuite

## core/chart_data.gd 测试：序列化往返、深拷贝快照、滚动范围计算。

func suite_name() -> String:
	return "chart_data"


func setup() -> void:
	ChartData.new_chart()


func test_new_chart_resets_document() -> void:
	ChartData.title = "X"
	ChartData.notes.append({"type": "tap", "time": 0, "column": 1})
	ChartData.new_chart()

	assert_eq(ChartData.title, ChartDefs.DEFAULT_TITLE)
	assert_eq(ChartData.notes.size(), 0)
	assert_eq(ChartData.current_file_path, "")


func test_dict_round_trip_keeps_metadata_and_notes() -> void:
	ChartData.title = "Song"
	ChartData.producer = "P"
	ChartData.bpm = 150.0
	ChartData.notes.append({"type": "hold", "time": 100, "column": 2, "duration": 300})

	var data := ChartData.to_dict()
	ChartData.new_chart()
	ChartData.load_from_dict(data)

	assert_eq(ChartData.title, "Song")
	assert_eq(ChartData.producer, "P")
	assert_eq(ChartData.bpm, 150.0)
	assert_eq(ChartData.notes.size(), 1)
	assert_eq(ChartData.notes[0]["duration"], 300)


func test_load_from_dict_tolerates_missing_sections() -> void:
	var data := {"General": {"Title": "Only Title"}}
	ChartData.load_from_dict(data)

	assert_eq(ChartData.title, "Only Title")
	assert_eq(ChartData.notes.size(), 0)
	assert_eq(ChartData.bpm, ChartDefs.DEFAULT_BPM, "缺失字段回落到默认值")


func test_snapshot_restore_is_a_deep_copy() -> void:
	ChartData.notes.append({"type": "tap", "time": 10, "column": 1})
	var snapshot := ChartData.capture_snapshot()

	ChartData.notes[0]["time"] = 999
	ChartData.restore_snapshot(snapshot)

	assert_eq(ChartData.notes[0]["time"], 10, "快照必须是深拷贝，否则撤销会丢历史")


func test_to_dict_does_not_leak_internal_arrays() -> void:
	ChartData.notes.append({"type": "tap", "time": 5, "column": 1})
	var data := ChartData.to_dict()

	(data["HitObjects"] as Array)[0]["time"] = 4321
	assert_eq(ChartData.notes[0]["time"], 5, "导出结果修改后不应影响文档内部数据")


func test_max_scroll_time_defaults_without_content() -> void:
	assert_eq(ChartData.get_max_scroll_time(), ChartDefs.MIN_SCROLL_TIME_MS)


func test_max_scroll_time_prefers_audio_duration() -> void:
	ChartData.audio_duration_ms = 5000
	assert_eq(ChartData.get_max_scroll_time(), 5000 + ChartDefs.SCROLL_TAIL_MS)


func test_max_scroll_time_uses_latest_hold_end() -> void:
	ChartData.notes.append({"type": "hold", "time": 2000, "column": 1, "duration": 1500})
	assert_eq(ChartData.get_max_scroll_time(), 3500 + ChartDefs.SCROLL_TAIL_MS)


func test_audio_analysis_can_be_cleared() -> void:
	ChartData.audio_duration_ms = 1234
	ChartData.waveform_samples = PackedFloat32Array([0.5, 1.0])
	ChartData.clear_audio_analysis()

	assert_eq(ChartData.audio_duration_ms, 0)
	assert_true(ChartData.waveform_samples.is_empty())
