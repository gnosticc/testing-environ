# --- enemy_slime_green.gd ---
# File Path: H:\Game Creation\testing-environ\Scripts\enemy_slime_green.gd
# VERSION 2.2: This script is now simplified. It relies entirely on the
# BaseEnemy.gd script to handle all logic, including signal connections.

extends BaseEnemy

func _ready():
	# --- Static Stats for Green Slime (as per user specification) ---
	#max_health = 22
	#contact_damage = 5
	#speed = 38.0
	#experience_to_drop = 2
	#armor = 0
	# --- End Static Stats ---

	super() # Calls BaseEnemy's _ready AFTER stats are set for this specific type
	# BaseEnemy's _ready will now correctly initialize current_health and health_bar
	
	# If you have specific animations for slime different from "move" or "idle"
	# _play_animation("slime_move")
