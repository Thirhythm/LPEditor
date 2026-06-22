extends Node

class Segment:
	var start_time: int = 0 ## 单位为毫秒(ms) 
	var end_time: int = 0 ## 单位为毫秒(ms)
	var speed: float = 0.0
	var cumulative: float = 0.0
	var cumulative_end: float = 0.0
	
	func calculate_cumulative_end(base_speed: float) -> float:
		cumulative_end = cumulative + base_speed * speed * (end_time - start_time) / 1000.0
		return cumulative_end

var segments: Array[Segment] = []

## 单位为 像素/秒 (pixel/s)
@export var BASE_SPEED: float = 1500.0

## 音符生成的位置到视窗底部距离（视窗高度为720px，放大缩小视窗都不影响）
@export var SPAWN_DISTANCE: float = 1000.0

var seg_pos_index: int = 0
var seg_time_index: int = 0
var seg_elasped_time_index: int = 0



func scroll_to_pos(time: int) -> float:
	if segments.is_empty():
		return BASE_SPEED * time / 1000.0
	
	seg_pos_index = clampi(seg_pos_index, 0, segments.size() - 1)
	
	var seg: Segment = segments[seg_pos_index]
	# 当 time 正好在目前 seg 的 end_time 前
	if time >= seg.start_time and time < seg.end_time:
		return seg.cumulative + BASE_SPEED * seg.speed * (time - seg.start_time) / 1000.0
	
	# 当 time 在目前 seg 的 end_time 之后
	if time >= seg.end_time:
		for i in range(seg_pos_index + 1, segments.size()):
			seg = segments[i]
			if time >= seg.start_time and time < seg.end_time:
				seg_pos_index = i
				return seg.cumulative + BASE_SPEED * seg.speed * (time - seg.start_time) / 1000.0
		
		var last_seg: Segment = segments[-1]
		seg_pos_index = segments.size() - 1
		return last_seg.cumulative + BASE_SPEED * last_seg.speed * (time - last_seg.start_time) / 1000.0
	
	# 当 time 在目前 seg 的 start_time 之前
	for i in range(seg_pos_index - 1, -1, -1):
		seg = segments[i]
		if time >= seg.start_time and time < seg.end_time:
			seg_pos_index = i
			return seg.cumulative + BASE_SPEED * seg.speed * (time - seg.start_time) / 1000.0
	
	# 保险情况下的二分查找
	var l = 0
	var r = segments.size() - 1
	while l <= r:
		var m = (l + r) >> 1
		seg = segments[m]
		if time >= seg.start_time and time < seg.end_time:
			seg_pos_index = m
			return seg.cumulative + BASE_SPEED * seg.speed * (time - seg.start_time) / 1000.0
		elif time < seg.start_time:
			r = m - 1
		else:
			l = m + 1
	
	var last_seg: Segment = segments[-1]
	seg_pos_index = segments.size() - 1
	return last_seg.cumulative + BASE_SPEED * last_seg.speed * (time - last_seg.start_time) / 1000.0
