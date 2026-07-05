extends VBoxContainer

# 工具栏组件

signal item_pressed(index: int)

@export var item: Array[Dictionary] = []
@export var arrangement: int = 0	# 0: 横向, 1: 纵向

var _item_buttons: Array[Button] = []

func _ready() -> void:
	_build_items()

func _build_items() -> void:
	if arrangement == 1:
		custom_minimum_size.x = 70
	else:
		custom_minimum_size.x = 150

	for i in item.size():
		var item_button := Button.new()
		item_button.text = item[i]["text"]
		item_button.icon = load(item[i]["icon"])

		if arrangement == 1:
			item_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			item_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

		if i == 0:
			item_button.disabled = true

		item_button.pressed.connect(_on_item_button_pressed.bind(i))
		_item_buttons.append(item_button)
		add_child(item_button)

func refresh() -> void:
	for i in _item_buttons:
		remove_child(i)
		i.queue_free()
	_item_buttons.clear()
	_build_items()

func _on_item_button_pressed(index: int) -> void:
	item_pressed.emit(index)

	for i in _item_buttons.size():
		_item_buttons[i].disabled = false

	_item_buttons[index].disabled = true
