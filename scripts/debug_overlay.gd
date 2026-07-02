extends CanvasLayer

@onready var debug_text: RichTextLabel = $MarginContainer/DebugText

# Dictionary to hold the raw tracked data
var _tracked_properties: Dictionary = {}

func _ready() -> void:
	# Hide by default; toggle it later if desired
	visible = true 

func _process(_delta: float) -> void:
	_update_debug_display()

# Call this from any script to log or update data
func watch_property(property_name: String, value) -> void:
	_tracked_properties[property_name] = str(value)

# Formats the dictionary into a readable UI layout
func _update_debug_display() -> void:
	var display_string: String = ""
	for key in _tracked_properties.keys():
		display_string += "[b]%s:[/b] %s\n" % [key, _tracked_properties[key]]
	
	debug_text.text = display_string
