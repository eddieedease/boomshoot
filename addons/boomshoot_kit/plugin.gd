## Registers the level-building dock.
##
## The map parts themselves all declare `class_name`, so they already show up in
## the Add Node dialog. The dock exists for speed: it drops a part where you are
## looking, snapped to the grid, with undo support.
@tool
extends EditorPlugin

const BuildDock := preload("res://addons/boomshoot_kit/build_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = BuildDock.new()
	_dock.name = "Boomshoot"
	_dock.set(&"plugin", self)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
