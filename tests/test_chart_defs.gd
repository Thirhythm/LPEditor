@tool
extends McpTestSuite

## core/chart_defs.gd 纯函数测试：不依赖场景树，可在编辑器内直接运行。

func suite_name() -> String:
	return "chart_defs"


# --- 拍点与量化 ---

func test_beat_ms_uses_bpm() -> void:
	assert_eq(ChartDefs.beat_ms(60.0), 1000.0, "60 BPM 应为 1000ms/拍")
	assert_eq(ChartDefs.beat_ms(120.0), 500.0, "120 BPM 应为 500ms/拍")


func test_beat_ms_falls_back_on_invalid_bpm() -> void:
	assert_eq(ChartDefs.beat_ms(0.0), ChartDefs.beat_ms(ChartDefs.DEFAULT_BPM))
	assert_eq(ChartDefs.beat_ms(-10.0), ChartDefs.beat_ms(ChartDefs.DEFAULT_BPM))


func test_snap_time_rounds_to_quantized_grid() -> void:
	# 120 BPM + 1/4 量化 → 每格 125ms
	assert_eq(ChartDefs.snap_time(70, 120.0, 4), 125, "70ms 更靠近 125ms 网格")
	assert_eq(ChartDefs.snap_time(60, 120.0, 4), 0, "60ms 更靠近 0ms 网格")
	assert_eq(ChartDefs.snap_time(190, 120.0, 4), 250)
	assert_eq(ChartDefs.snap_time(0, 120.0, 4), 0)


func test_snap_ms_scales_with_denominator() -> void:
	assert_eq(ChartDefs.snap_ms(120.0, 4), 125.0)
	assert_eq(ChartDefs.snap_ms(120.0, 8), 62.5)


func test_quantize_index_mapping_round_trips() -> void:
	for denominator in ChartDefs.QUANTIZE_DENOMINATORS:
		var index := ChartDefs.quantize_index_for(denominator)
		assert_eq(ChartDefs.quantize_denominator_at(index), denominator)


func test_quantize_lookup_falls_back_on_unknown_values() -> void:
	assert_eq(
		ChartDefs.quantize_denominator_at(999),
		ChartDefs.DEFAULT_QUANTIZE_DENOMINATOR,
		"越界索引应回落到默认量化"
	)
	assert_eq(
		ChartDefs.quantize_index_for(3),
		ChartDefs.quantize_index_for(ChartDefs.DEFAULT_QUANTIZE_DENOMINATOR),
		"非法分母应回落到默认量化的索引"
	)


# --- 音符 ---

func test_note_end_time_handles_hold() -> void:
	assert_eq(ChartDefs.note_end_time({"type": "tap", "time": 500}), 500)
	assert_eq(ChartDefs.note_end_time({"type": "hold", "time": 500, "duration": 250}), 750)


func test_is_hold_requires_duration() -> void:
	assert_true(ChartDefs.is_hold({"type": "hold", "duration": 100}))
	assert_false(ChartDefs.is_hold({"type": "hold"}), "缺少 duration 时不视为长键")


func test_make_note_adds_type_specific_fields() -> void:
	var tap := ChartDefs.make_note("tap", 100, 2)
	assert_eq(tap["type"], "tap")
	assert_eq(tap["time"], 100)
	assert_eq(tap["column"], 2)
	assert_false(tap.has("duration"))

	var hold := ChartDefs.make_note("hold", 100, 2)
	assert_eq(hold["duration"], ChartDefs.HOLD_DEFAULT_DURATION_MS)

	var heart := ChartDefs.make_note("heart", 100, 2)
	assert_true(heart.has("map"))
	assert_eq((heart["map"] as Array).size(), ChartDefs.NUM_TRACKS)


func test_make_note_defaults_to_tap_for_unknown_type() -> void:
	assert_eq(ChartDefs.make_note("", 0, 1)["type"], "tap")
	assert_eq(ChartDefs.make_note("bogus", 0, 1)["type"], "bogus", "未知类型按原样保留")


func test_tool_note_type_maps_index_zero_to_select_mode() -> void:
	assert_eq(ChartDefs.tool_note_type(0), "", "索引 0 是选择模式")
	assert_eq(ChartDefs.tool_note_type(1), "tap")
	assert_eq(ChartDefs.tool_note_type(ChartDefs.NOTE_TYPES.size()), "heart", "最后一个索引应指向 heart")
	assert_eq(ChartDefs.tool_note_type(999), "", "越界索引返回空串")


func test_note_color_is_stable_and_distinct() -> void:
	assert_eq(ChartDefs.note_color("tap"), ChartDefs.note_color("tap"))
	assert_ne(ChartDefs.note_color("tap"), ChartDefs.note_color("hold"))
	assert_eq(ChartDefs.note_color("unknown"), Color(0.7, 0.7, 0.7), "未知类型使用中性色")


func test_difficulty_index_falls_back_to_first() -> void:
	assert_eq(ChartDefs.difficulty_index("EZ"), 0)
	assert_eq(ChartDefs.difficulty_index("HD"), 2)
	assert_eq(ChartDefs.difficulty_index("???"), 0)


# --- 导出校验 ---

func test_missing_export_fields_lists_every_gap() -> void:
	var missing := ChartDefs.missing_export_fields({
		"title": "Untitled",
		"audio_path": "",
		"jacket_path": "",
	})
	assert_eq(missing.size(), 3, "标题 / 音频 / 曲绘 都应报告")


func test_missing_export_fields_empty_when_complete() -> void:
	var missing := ChartDefs.missing_export_fields({
		"title": "Song",
		"audio_path": "res://song.wav",
		"jacket_path": "res://cover.png",
	})
	assert_true(missing.is_empty())
