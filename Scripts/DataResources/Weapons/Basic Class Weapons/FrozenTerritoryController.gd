# File: res://Scripts/DataResources/Weapons/Basic Class Weapons/FrozenTerritoryController.gd
# MODIFIED: Now spawns the RimeheartAura scene if the upgrade is active.

class_name FrozenTerritoryController
extends Node2D

@export var instance_scene: PackedScene
const ABSOLUTE_ZERO_SCENE = preload("res://Scenes/Weapons/Projectiles/AbsoluteZeroBlizzard.tscn")
# NEW: Preload the RimeheartAura scene.
const RIMEHEART_AURA_SCENE = preload("res://Scenes/Weapons/Projectiles/RimeheartAura.tscn")


func set_attack_properties(_direction: Vector2, p_attack_stats: Dictionary, p_player_stats: PlayerStats):
	var received_stats_copy = p_attack_stats.duplicate(true) 
	var owner_player = p_player_stats.get_parent() as PlayerCharacter
	if not is_instance_valid(owner_player): queue_free(); return

	# --- Absolute Zero Logic ---
	if received_stats_copy.get(&"has_absolute_zero", false):
		if is_instance_valid(ABSOLUTE_ZERO_SCENE):
			var blizzard_instance = ABSOLUTE_ZERO_SCENE.instantiate()
			owner_player.add_child(blizzard_instance)
			blizzard_instance.global_position = owner_player.global_position
			blizzard_instance.initialize(p_player_stats, owner_player)
	
	# --- NEW: Rimeheart Logic ---
	if received_stats_copy.get(&"has_rimeheart", false):
		if is_instance_valid(RIMEHEART_AURA_SCENE):
			var aura_instance = RIMEHEART_AURA_SCENE.instantiate()
			owner_player.add_child(aura_instance) # Attach to player to follow them
			aura_instance.global_position = owner_player.global_position
			
			var weapon_damage_percent = float(received_stats_copy.get(&"weapon_damage_percentage", 1.0))
			var orb_damage = int(round(maxf(1.0, p_player_stats.get_calculated_player_damage(weapon_damage_percent, received_stats_copy.get(&"tags",[])))))
			var duration = float(received_stats_copy.get(&"base_lifetime", 3.0)) * p_player_stats.get_final_stat(PlayerStatKeys.Keys.EFFECT_DURATION_MULTIPLIER)
			
			aura_instance.initialize(owner_player, received_stats_copy, orb_damage, duration)

	if not is_instance_valid(instance_scene): queue_free(); return
	
	var instance_count = int(received_stats_copy.get(&"number_of_orbits", 1))
	var angle_step = TAU / float(instance_count)

	for i in range(instance_count):
		var instance = instance_scene.instantiate() as FrozenTerritoryInstance
		owner_player.add_child(instance)
		var start_angle = i * angle_step
		instance.initialize(owner_player, received_stats_copy, start_angle)
		
	queue_free()
