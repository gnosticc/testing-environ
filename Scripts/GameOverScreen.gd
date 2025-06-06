# GameOverScreen.gd
extends CanvasLayer # Changed from Control for better layering

# Signal to notify the main game that the player wants to restart
signal restart_game_requested

# Adjust path if your RestartButton is nested differently within GameOverScreen.tscn
@onready var restart_button: Button = $RestartButton 

func _ready():
	if restart_button:
		# Ensure connection is made only once
		if not restart_button.is_connected("pressed", Callable(self, "_on_restart_button_pressed")):
			restart_button.pressed.connect(self._on_restart_button_pressed)
	else:
		print("ERROR (GameOverScreen): RestartButton node not found! Path was: $RestartButton")

func _on_restart_button_pressed():
	# self.hide() # Hiding is optional as the scene will be reloaded
	emit_signal("restart_game_requested")
