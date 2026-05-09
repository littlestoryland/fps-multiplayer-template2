extends Button

func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_pressed("pause"):
		grab_focus()


func _on_options_pressed() -> void:
	pass # Replace with function body.


func _on_pressed() -> void:
	pass # Replace with function body.
