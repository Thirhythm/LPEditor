@tool
extends McpTestSuite

## core/editor_state.gd 测试：撤销/重做、选区清理、视口与量化设置。

func suite_name() -> String:
	return "editor_state"


func setup() -> void:
	ChartData.new_chart()
	EditorState.clear_undo_history()
	EditorState.scroll_time = 0
	EditorState.px_per_ms = ChartDefs.DEFAULT_PX_PER_MS
	EditorState.quantize_denominator = ChartDefs.DEFAULT_QUANTIZE_DENOMINATOR
	EditorState.snap_enabled = true
	EditorState.selected_notes.clear()


func test_fresh_state_has_nothing_to_undo() -> void:
	assert_false(EditorState.can_undo())
	assert_false(EditorState.can_redo())
	assert_false(EditorState.undo())
	assert_false(EditorState.redo())


func test_undo_restores_document_and_session_settings() -> void:
	EditorState.push_undo_state()
	ChartData.title = "Changed"
	ChartData.notes.append({"type": "tap", "time": 0, "column": 1})
	EditorState.quantize_denominator = 16
	EditorState.snap_enabled = false

	assert_true(EditorState.undo())
	assert_eq(ChartData.title, ChartDefs.DEFAULT_TITLE)
	assert_eq(ChartData.notes.size(), 0)
	assert_eq(EditorState.quantize_denominator, ChartDefs.DEFAULT_QUANTIZE_DENOMINATOR)
	assert_true(EditorState.snap_enabled)


func test_redo_reapplies_the_change() -> void:
	EditorState.push_undo_state()
	ChartData.title = "Changed"
	EditorState.undo()

	assert_true(EditorState.redo())
	assert_eq(ChartData.title, "Changed")


func test_undo_clears_selection() -> void:
	EditorState.selected_notes.append({"type": "tap", "time": 0, "column": 1})
	EditorState.push_undo_state()
	EditorState.undo()

	assert_true(EditorState.selected_notes.is_empty(), "撤销后不应残留已失效的选区")


func test_push_after_undo_drops_redo_chain() -> void:
	EditorState.push_undo_state()
	ChartData.title = "A"
	EditorState.undo()
	assert_true(EditorState.can_redo())

	EditorState.push_undo_state()
	assert_false(EditorState.can_redo(), "新操作应作废重做链")


func test_undo_does_not_record_its_own_restore() -> void:
	EditorState.push_undo_state()
	ChartData.title = "A"
	EditorState.undo()

	# 撤销过程中触发的内部写入不应污染撤销栈
	assert_false(EditorState.can_undo())
	assert_true(EditorState.can_redo())


func test_snap_time_respects_toggle() -> void:
	ChartData.bpm = 120.0
	EditorState.quantize_denominator = 4	# 每格 125ms

	assert_eq(EditorState.snap_time(190), 250)
	EditorState.snap_enabled = false
	assert_eq(EditorState.snap_time(190), 190, "关闭吸附后应原样返回")


func test_scroll_step_scales_with_zoom() -> void:
	EditorState.px_per_ms = 0.5
	assert_eq(EditorState.scroll_step_ms(), 400)
	EditorState.px_per_ms = 1.0
	assert_eq(EditorState.scroll_step_ms(), 200)


func test_set_zoom_clamps_to_supported_range() -> void:
	EditorState.set_zoom(999.0)
	assert_eq(EditorState.px_per_ms, ChartDefs.MAX_PX_PER_MS)
	EditorState.set_zoom(0.0)
	assert_eq(EditorState.px_per_ms, ChartDefs.MIN_PX_PER_MS)


func test_clamp_scroll_keeps_time_in_range() -> void:
	ChartData.notes.append({"type": "tap", "time": 0, "column": 1})
	var max_time := ChartData.get_max_scroll_time()

	EditorState.scroll_time = max_time + 9999
	EditorState.clamp_scroll()
	assert_eq(EditorState.scroll_time, max_time)

	EditorState.scroll_time = -500
	EditorState.clamp_scroll()
	assert_eq(EditorState.scroll_time, 0)
