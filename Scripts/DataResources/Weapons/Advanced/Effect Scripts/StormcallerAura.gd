# --- Path: res://Scripts/Weapons/Advanced/Effects/StormcallerAura.gd ---
class_name StormcallerAura
extends Node2D

@onready var arc_timer: Timer = $ArcTimer

var _weapon_manager: WeaponManager
var _player_stats: PlayerStats

func initialize(p_weapon_manager: WeaponManager, p_player_stats: PlayerStats):
	_weapon_manager = p_weapon_manager
	_player_stats = p_player_stats
	arc_timer.timeout.connect(_on_arc_timer_timeout)
	_update_timer()

func _update_timer():
	# FIX: Use the correct function to get the weapon data entry.
	var weapon_index = _weapon_manager._get_weapon_entry_index_by_id(&"magus_living_conduit")
	if weapon_index != -1:
		var weapon_data = _weapon_manager.active_weapons[weapon_index]
		var weapon_stats = _weapon_manager._get_calculated_stats_for_instance(weapon_data)
		var interval = float(weapon_stats.get(&"conduit_arc_interval", 0.5))
		arc_timer.wait_time = interval
		if arc_timer.is_stopped():
			arc_timer.start()

func _on_arc_timer_timeout():
	var owner = get_parent()
	if not is_instance_valid(owner): return

	var weapon_index = _weapon_manager._get_weapon_entry_index_by_id(&"magus_living_conduit")
	if weapon_index == -1: return
	var weapon_data = _weapon_manager.active_weapons[weapon_index]
	
	# FIX: Get the stats dictionary locally for this function call.
	var weapon_stats = _weapon_manager._get_calculated_stats_for_instance(weapon_data)
	var arc_radius = float(weapon_stats.get(&"conduit_arc_radius", 125.0))
	var max_targets = int(weapon_stats.get(&"conduit_arc_max_targets", 1))
	var arc_damage_percent = float(weapon_stats.get(&"conduit_arc_damage_percentage", 0.75))
	
	var weapon_tags = weapon_stats.get("tags", []) as Array[StringName]
	var base_damage = _player_stats.get_calculated_base_damage(arc_damage_percent)
	var arc_damage = _player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)

	# FIX: The source of the effect is the player who owns the aura.
	var source_player = _player_stats.get_parent()

	var targets = (owner as PlayerCharacter)._find_nearest_enemies(max_targets, owner.global_position)
	for target in targets:
		if is_instance_valid(target):
			# FIX: Pass the source_player variable.
			target.take_damage(arc_damage, source_player, {}, weapon_tags)
			_spawn_lightning_arc_visual(owner.global_position, target.global_position)
			
			if weapon_stats.get(&"conduit_grants_resonance", false):
				if randf() < 0.01:
					var resonance_buff = load("res://DataResources/StatusEffects/arcane_surge_buff.tres") as StatusEffectData
					if is_instance_valid(resonance_buff):
						source_player.status_effect_component.apply_effect(resonance_buff, source_player)

func _spawn_lightning_arc_visual(start_pos: Vector2, end_pos: Vector2):
	var arc_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/LightningArc.tscn")
	if is_instance_valid(arc_scene):
		var arc_instance = arc_scene.instantiate()
		get_tree().current_scene.add_child(arc_instance)
		if arc_instance.has_method("initialize"):
			arc_instance.initialize(start_pos, end_pos)
