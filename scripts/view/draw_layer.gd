extends Node2D
## A canvas that hands its drawing to a callback, so static parts of the view can be redrawn less often.

var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
