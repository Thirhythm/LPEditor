@tool
extends McpTestSuite

## ui/visual/visual_geometry.gd 的坐标换算测试。
##
## 绘制本身（visual_renderer.gd）只能在 _draw 回调里跑，无法在单元测试中直接
## 调用 draw_*，因此这里只覆盖真正可测的纯换算逻辑。

const CONTROL_SIZE := Vector2(800, 400)

func suite_name() -> String:
	return "visual_geometry"


func setup() -> void:
	ChartData.new_chart()
	EditorState.scroll_time = 0
	EditorState.px_per_ms = 0.3
	EditorState.quantize_denominator = ChartDefs.DEFAULT_QUANTIZE_DENOMINATOR
	EditorState.snap_enabled = true


func test_judge_line_sits_at_configured_ratio() -> void:
	var geom := _make_geometry()
	assert_eq(geom.judge_line_y(), CONTROL_SIZE.y * VisualGeometry.JUDGE_LINE_RATIO)


func test_time_to_y_and_back_are_inverse() -> void:
	var geom := _make_geometry()
	var y := geom.time_to_y(1000.0)
	assert_true(absi(geom.y_to_time(y) - 1000) <= 1, "换算往返只允许 1ms 浮点误差")


func test_larger_time_is_higher_on_screen() -> void:
	var geom := _make_geometry()
	assert_true(geom.time_to_y(2000.0) < geom.time_to_y(1000.0), "时间越大 Y 越小（更靠上）")


func test_jittering_scroll_moves_mapping() -> void:
	var geom := _make_geometry()
	var before := geom.time_to_y(1000.0)
	EditorState.scroll_time = 500
	assert_true(geom.time_to_y(1000.0) > before, "视口前滚后同一时刻应更靠下")


func test_x_to_track_clamps_to_track_range() -> void:
	var geom := _make_geometry()
	assert_eq(geom.x_to_track(0.0), 1)
	assert_eq(geom.x_to_track(200.0), 2, "800/4=200 → 第二条轨道")
	assert_eq(geom.x_to_track(-50.0), 1, "左侧越界回落到第一条轨道")
	assert_eq(geom.x_to_track(9999.0), ChartDefs.NUM_TRACKS, "右侧越界回落到最后一条轨道")


func test_track_to_x_range_is_centered() -> void:
	var geom := _make_geometry()
	var range := geom.track_to_x_range(2)
	assert_eq(range["left"], 200.0)
	assert_eq(range["right"], 400.0)
	assert_eq(range["mid"], 300.0)


func test_visible_range_surrounds_scroll_time() -> void:
	var geom := _make_geometry()
	EditorState.scroll_time = 1000
	var visible := geom.visible_time_range()
	assert_true((visible["start"] as int) < 1000, "判定线下方要能看到更早的时间")
	assert_true((visible["end"] as int) > 1000, "判定线上方要能看到更晚的时间")


func test_visible_range_shrinks_when_zoomed_in() -> void:
	var geom := _make_geometry()
	var wide := geom.visible_time_range()
	EditorState.px_per_ms = 3.0
	var tight := geom.visible_time_range()
	assert_true((tight["end"] as int) - (tight["start"] as int)
		< (wide["end"] as int) - (wide["start"] as int), "放大后可见时间跨度应变小")


func test_snap_time_follows_editor_settings() -> void:
	var geom := _make_geometry()
	ChartData.bpm = 120.0
	EditorState.quantize_denominator = 4	# 每格 125ms
	assert_eq(geom.snap_time(190), 250)

	EditorState.snap_enabled = false
	assert_eq(geom.snap_time(190), 190, "关闭吸附后原样返回")


## 造一个带固定尺寸的 Control（由测试框架负责释放）
func _make_geometry() -> VisualGeometry:
	var control := Control.new()
	control.size = CONTROL_SIZE
	track(control)
	return VisualGeometry.new(control)
