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
	ChartData.artist = "P"
	ChartData.bpm = 150.0
	ChartData.notes.append({"type": "hold", "time": 100, "column": 2, "duration": 300})

	var data := ChartData.to_dict()
	ChartData.new_chart()
	ChartData.load_from_dict(data)

	assert_eq(ChartData.title, "Song")
	assert_eq(ChartData.artist, "P")
	assert_eq(ChartData.bpm, 150.0)
	assert_eq(ChartData.notes.size(), 1)
	assert_eq(ChartData.notes[0]["duration"], 300)


## 谱面里记的是相对自身的资产路径；载入时按谱面位置还原，面板与播放器才用得上
func test_asset_paths_are_relative_to_the_chart_file() -> void:
	ChartData.jacket_path = "D:/charts/song/cover.png"
	ChartData.audio_path = "D:/charts/song/audio.wav"

	var data := ChartData.to_dict("D:/charts/song/song.lp")
	var general: Dictionary = data["General"]
	assert_eq(general["JacketPath"], "cover.png")
	assert_eq(general["AudioPath"], "audio.wav")

	ChartData.new_chart()
	ChartData.load_from_dict(data, "D:/charts/song/song.lp")
	assert_eq(ChartData.jacket_path, "D:/charts/song/cover.png")
	assert_eq(ChartData.audio_path, "D:/charts/song/audio.wav")


## 不传谱面路径时不做换算：撤销指纹（EditorState.document_signature）走的就是这条路
func test_asset_paths_without_chart_path_are_untouched() -> void:
	ChartData.audio_path = "D:/charts/song/audio.wav"
	assert_eq(ChartData.to_dict()["General"]["AudioPath"], "D:/charts/song/audio.wav")


## 心键的 map 字段已废弃：载入旧谱面时剔除，重新保存后不再导出
func test_load_from_dict_drops_legacy_heart_map() -> void:
	ChartData.load_from_dict({
		"HitObjects": [{"type": "heart", "time": 100, "column": 3, "map": [4, 2, 3, 1]}],
	})

	assert_eq(ChartData.notes.size(), 1)
	assert_false(ChartData.notes[0].has("map"), "载入时应剔除废弃的 map 字段")
	var exported: Dictionary = (ChartData.to_dict()["HitObjects"] as Array)[0]
	assert_false(exported.has("map"), "导出结果也不应包含 map")


# --- General 字段 ---

func test_general_writes_artist_illustrator_and_preview_fields() -> void:
	ChartData.title = "test"
	ChartData.artist = "DELA/雨狸"
	ChartData.vocalist = "洛天依/言和/乐正绫"
	ChartData.illustrator = "Lune"
	ChartData.creator = "chuanyuan"
	ChartData.bpm = 120.0
	ChartData.preview_ms = 162300
	ChartData.preview_end_ms = 194820
	ChartData.crystal = 40
	ChartData.chapter = 1

	var general: Dictionary = ChartData.to_dict()["General"]
	assert_eq(general["Artist"], "DELA/雨狸")
	assert_eq(general["Illustrator"], "Lune")
	assert_eq(general["Preview"], 162300)
	assert_eq(general["PreviewEnd"], 194820)
	assert_eq(general["Crystal"], 40)
	assert_eq(general["Chapter"], 1)
	assert_false(general.has("Producer"), "Producer 已被 Artist 取代")

	ChartData.new_chart()
	ChartData.load_from_dict({"General": general})
	assert_eq(ChartData.artist, "DELA/雨狸")
	assert_eq(ChartData.illustrator, "Lune")
	assert_eq(ChartData.preview_ms, 162300)
	assert_eq(ChartData.preview_end_ms, 194820)
	assert_eq(ChartData.crystal, 40)
	assert_eq(ChartData.chapter, 1)


func test_load_falls_back_to_legacy_producer_field() -> void:
	ChartData.load_from_dict({"General": {"Producer": "旧制作人"}})
	assert_eq(ChartData.artist, "旧制作人", "读不到 Artist 时应回退到旧字段 Producer")


func test_missing_preview_fields_use_defaults() -> void:
	ChartData.load_from_dict({"General": {"Title": "Only Title"}})
	assert_eq(ChartData.preview_ms, 0)
	assert_eq(ChartData.preview_end_ms, 0)
	assert_eq(ChartData.crystal, 0)
	assert_eq(ChartData.chapter, ChartDefs.DEFAULT_CHAPTER)


func test_load_sanitizes_bad_preview_and_unlock_values() -> void:
	ChartData.load_from_dict({"General": {
		"Preview": null, "PreviewEnd": 1e19, "Crystal": -5, "Chapter": 0,
	}})
	assert_eq(ChartData.preview_ms, 0, "null 应回退到默认值")
	assert_eq(ChartData.preview_end_ms, ChartDefs.MAX_PREVIEW_MS, "超大值应收敛到上限")
	assert_eq(ChartData.crystal, 0, "负值应收敛到下限")
	assert_eq(ChartData.chapter, ChartDefs.MIN_CHAPTER, "0 应收敛到章节下限")


## General 里出现坏值时不能中断整个载入，否则会留下上一份谱面的音符混在新文件里
func test_bad_general_value_does_not_abort_loading() -> void:
	ChartData.load_from_dict({"General": {"Title": "OLD"}})
	ChartData.notes.append({"type": "tap", "time": 1, "column": 1})
	ChartData.effects.append(ChartDefs.make_effect("change", 5, 5))

	ChartData.load_from_dict({
		"General": {"Title": "NEW", "Preview": null},
		"HitObjects": [{"type": "tap", "time": 99, "column": 2}],
	})

	assert_eq(ChartData.title, "NEW")
	assert_eq(ChartData.notes.size(), 1, "坏值不应中断载入")
	assert_eq(ChartData.notes[0]["time"], 99, "新谱面的音符必须被载入")
	assert_eq(ChartData.effects.size(), 0, "旧谱面的特效必须被清掉")


func test_new_chart_resets_preview_and_unlock_fields() -> void:
	ChartData.preview_ms = 100
	ChartData.preview_end_ms = 200
	ChartData.crystal = 5
	ChartData.chapter = 9
	ChartData.illustrator = "X"
	ChartData.new_chart()

	assert_eq(ChartData.preview_ms, 0)
	assert_eq(ChartData.preview_end_ms, 0)
	assert_eq(ChartData.crystal, 0)
	assert_eq(ChartData.chapter, ChartDefs.DEFAULT_CHAPTER)
	assert_eq(ChartData.illustrator, "")


func test_snapshot_covers_preview_and_unlock_fields() -> void:
	ChartData.preview_ms = 1234
	ChartData.preview_end_ms = 5678
	ChartData.crystal = 7
	ChartData.chapter = 3
	var snapshot := ChartData.capture_snapshot()

	ChartData.preview_ms = 9999
	ChartData.crystal = 0
	ChartData.chapter = 1
	ChartData.restore_snapshot(snapshot)

	assert_eq(ChartData.preview_ms, 1234, "预览字段必须进撤销快照")
	assert_eq(ChartData.preview_end_ms, 5678)
	assert_eq(ChartData.crystal, 7)
	assert_eq(ChartData.chapter, 3)


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


# --- 特效 ---

func test_dict_round_trip_keeps_effects() -> void:
	ChartData.effects.append({
		"type": "change", "time": 5000, "changed": [2, 3, 4, 1], "duration": 2000,
	})
	var data := ChartData.to_dict()
	assert_true(data.has("Effects"), "Effects 与 HitObjects 同级")
	assert_eq((data["Effects"] as Array).size(), 1)

	ChartData.new_chart()
	ChartData.load_from_dict(data)

	assert_eq(ChartData.effects.size(), 1)
	assert_eq(ChartData.effects[0]["duration"], 2000)
	assert_eq(ChartData.effects[0]["changed"], [2, 3, 4, 1])


func test_load_from_dict_without_effects_clears_them() -> void:
	ChartData.effects.append({"type": "change", "time": 0, "changed": [1, 2, 3, 4], "duration": 10})
	ChartData.load_from_dict({"General": {}})
	assert_eq(ChartData.effects.size(), 0, "旧谱面没有 Effects 段时不应残留")


func test_snapshot_restore_covers_effects() -> void:
	ChartData.effects.append({"type": "change", "time": 100, "changed": [1, 2, 3, 4], "duration": 50})
	var snapshot := ChartData.capture_snapshot()

	ChartData.effects[0]["time"] = 999
	ChartData.restore_snapshot(snapshot)

	assert_eq(ChartData.effects.size(), 1)
	assert_eq(ChartData.effects[0]["time"], 100, "特效必须进快照，否则撤销会丢历史")


func test_to_dict_does_not_leak_effects() -> void:
	ChartData.effects.append({"type": "change", "time": 5, "changed": [1, 2, 3, 4], "duration": 5})
	var data := ChartData.to_dict()

	(data["Effects"] as Array)[0]["time"] = 4321
	assert_eq(ChartData.effects[0]["time"], 5, "导出结果修改后不应影响文档内部数据")


func test_max_scroll_time_uses_latest_effect_end() -> void:
	ChartData.effects.append({"type": "change", "time": 2000, "changed": [1, 2, 3, 4], "duration": 1500})
	assert_eq(ChartData.get_max_scroll_time(), 3500 + ChartDefs.SCROLL_TAIL_MS)


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
