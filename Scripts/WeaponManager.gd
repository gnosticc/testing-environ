# WeaponManager.gd
# This is the complete, merged, and definitive version of the WeaponManager.
# CORRECTED: The attack logic now correctly handles Blade Flurry procs for both
# the primary and Holy Infusion swings, and spawns the flurry at the correct location.

class_name WeaponManager
extends Node

@export var max_weapons: int = 100
var active_weapons: Array[Dictionary] = []
var game_node_ref: Node

# --- NEW: Summon Tracking ---
# This dictionary will store active summon nodes.
# The key is the weapon_id (e.g., &"conjurer_lesser_spirit"), and the value is an Array of the summon nodes.
var _active_summons: Dictionary = {}

# --- Signals ---
signal weapon_added(weapon_data_dict: Dictionary)
signal weapon_removed(weapon_id: StringName)
signal weapon_upgraded(weapon_id: StringName, new_level: int)
signal active_weapons_changed()

func _ready():
	game_node_ref = get_tree().root.get_node_or_null("Game")

# This function is called by weapon controllers (like WarhammerController)
# to reset the shot counter after a special Nth attack.
func reset_weapon_shot_counter(weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index != -1:
		active_weapons[weapon_index]["shot_counter"] = 0
		print_debug("WeaponManager: Shot counter for '", weapon_id, "' reset to 0.")

# NEW: Public function for controllers to update a persistent stat.
func set_specific_weapon_stat(weapon_id: StringName, stat_key: StringName, new_value):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index != -1:
		active_weapons[weapon_index].specific_stats[stat_key] = new_value
	else:
		push_warning("WeaponManager: Attempted to set stat for unknown weapon_id: " + str(weapon_id))

# NEW: Generic function for any weapon to reduce its own current cooldown.
func reduce_cooldown_for_weapon(weapon_id: StringName, reduction_amount: float):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index != -1:
		var weapon_entry = active_weapons[weapon_index]
		var timer = weapon_entry.get("cooldown_timer") as Timer
		if is_instance_valid(timer) and not timer.is_stopped():
			var new_time_left = timer.time_left - reduction_amount
			# To apply the change immediately, we must stop the timer
			# and restart it with the new, shorter duration.
			timer.stop()
			timer.wait_time = max(0.01, new_time_left)
			timer.start()

func add_weapon(blueprint_data: WeaponBlueprintData) -> bool:
	if not is_instance_valid(blueprint_data) or active_weapons.size() >= max_weapons or _get_weapon_entry_index_by_id(blueprint_data.id) != -1:
		return false

	var weapon_entry = {
		"id": blueprint_data.id, "title": blueprint_data.title, "weapon_level": 1,
		"blueprint_resource": blueprint_data, "acquired_upgrade_ids": [],
		"tags": blueprint_data.tags.duplicate(true),
		"specific_stats": blueprint_data.initial_specific_stats.duplicate(true),
		"shot_counter": 0,
		"_flat_mods": {}, "_percent_add_mods": {}, "_percent_mult_final_mods": {},
		"persistent_instance": null
	}
	
	weapon_entry.specific_stats[&"cooldown"] = blueprint_data.cooldown
	weapon_entry.specific_stats[&"attack_speed_multiplier"] = 1.0
	weapon_entry.specific_stats[&"base_lifetime"] = blueprint_data.base_lifetime
	
	for key_enum_value in PlayerStatKeys.Keys.values():
		var key_string: StringName = PlayerStatKeys.KEY_NAMES[key_enum_value]
		weapon_entry._flat_mods[key_string] = 0.0
		weapon_entry._percent_add_mods[key_string] = 0.0
		weapon_entry._percent_mult_final_mods[key_string] = 1.0
		
	# Handle persistent controllers like the Polearm
	if blueprint_data.spawn_as_child and blueprint_data.tags.has(&"controller"):
		var owner_player = get_parent()
		var persistent_instance = blueprint_data.weapon_scene.instantiate()
		owner_player.add_child(persistent_instance)
		weapon_entry["persistent_instance"] = persistent_instance
		
		if persistent_instance.has_method("initialize"):
			var player_stats = owner_player.get_node("PlayerStats")
			# FIX: Create a copy of the stats and inject the weapon ID before passing it.
			var stats_to_pass = weapon_entry.specific_stats.duplicate(true)
			stats_to_pass["id"] = weapon_entry.get("id")
			persistent_instance.initialize(stats_to_pass, player_stats, self)

	# FIX: Restore the original if/else logic for summons vs. standard weapons
	if blueprint_data.tags.has("summon"):
		print_debug("WeaponManager: Weapon '", blueprint_data.id, "' has 'summon' tag. Calling _spawn_persistent_summon.")
		# For summons, we call the spawn logic immediately. It will also be called on upgrade.
		_spawn_persistent_summon(weapon_entry)
	else:
		# For non-summons (including controllers), set up the cooldown timer.
		if blueprint_data.cooldown > 0:
			var cooldown_timer = Timer.new()
			cooldown_timer.name = str(blueprint_data.id) + "CooldownTimer"
			cooldown_timer.wait_time = get_weapon_cooldown_value(weapon_entry)
			cooldown_timer.one_shot = true
			add_child(cooldown_timer)
			weapon_entry["cooldown_timer"] = cooldown_timer
			cooldown_timer.timeout.connect(_on_attack_cooldown_finished.bind(blueprint_data.id))
			cooldown_timer.start()
		
	active_weapons.append(weapon_entry)
	emit_signal("weapon_added", weapon_entry.duplicate(true))
	emit_signal("active_weapons_changed")
	return true

func _on_attack_cooldown_finished(weapon_id: StringName):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return
	var weapon_entry = active_weapons[weapon_index]
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData

	# First, check for persistent controllers like the Polearm
	var persistent_instance = weapon_entry.get("persistent_instance")
	if is_instance_valid(persistent_instance) and persistent_instance.has_method("attack"):
		persistent_instance.attack()
		return # Stop here for controllers

	# --- ALL ORIGINAL LOGIC FOR NON-CONTROLLER WEAPONS ---
	if blueprint_data.tracks_shot_count:
		var current_shots = weapon_entry.get("shot_counter", 0) + 1
		weapon_entry["shot_counter"] = current_shots
		weapon_entry.specific_stats["shot_counter"] = current_shots

	if weapon_entry.specific_stats.get(&"has_arrow_storm", false):
		weapon_entry.shot_counter += 1
		if weapon_entry.shot_counter >= 3:
			weapon_entry.specific_stats["is_arrow_storm_shot"] = true
			weapon_entry.shot_counter = 0
		else:
			weapon_entry.specific_stats["is_arrow_storm_shot"] = false
				
	var riposte_multiplier = 1.0
	if weapon_entry.specific_stats.get(&"has_parry_riposte", false):
		if weapon_entry.specific_stats.get("parry_riposte_bonus_active", false):
			riposte_multiplier = 3.0
		weapon_entry.specific_stats["parry_riposte_bonus_active"] = true

	var reaping_bonus = 0
	
	# The _spawn_attack_instance function is now part of the default logic path
	var primary_attack = _spawn_attack_instance(weapon_entry, reaping_bonus, true, riposte_multiplier)
	
	if is_instance_valid(primary_attack) and weapon_entry.specific_stats.get(&"has_blade_flurry", false):
		if randf() < float(weapon_entry.specific_stats.get(&"blade_flurry_chance", 0.0)):
			get_tree().create_timer(0.2).timeout.connect(_on_blade_flurry_timeout.bind(weapon_entry, riposte_multiplier, primary_attack.global_transform))

	if blueprint_data.tracks_shot_count and weapon_entry["shot_counter"] >= 4:
		if weapon_entry.specific_stats.get(&"has_wrath_of_the_wilds", false):
			weapon_entry["shot_counter"] = 0

	if weapon_entry.specific_stats.get(&"has_holy_infusion", false):
		var owner_player = get_parent() as PlayerCharacter
		if is_instance_valid(owner_player) and is_instance_valid(owner_player.melee_aiming_dot):
			var opposite_local_pos = owner_player.melee_aiming_dot.position * -1
			var opposite_global_pos = owner_player.to_global(opposite_local_pos)
			var opposite_rotation = (owner_player.melee_aiming_dot.global_position - owner_player.global_position).angle() + PI
			var opposite_transform = Transform2D(opposite_rotation, opposite_global_pos)
			
			var opposite_swing = _spawn_attack_instance(weapon_entry, 0, false, riposte_multiplier, opposite_transform)
			if is_instance_valid(opposite_swing) and weapon_entry.specific_stats.get(&"has_blade_flurry", false):
				if randf() < float(weapon_entry.specific_stats.get(&"blade_flurry_chance", 0.0)):
					get_tree().create_timer(0.2).timeout.connect(_on_blade_flurry_timeout.bind(weapon_entry, riposte_multiplier, opposite_swing.global_transform))

	_restart_weapon_cooldown(weapon_entry)
	
func _on_blade_flurry_timeout(weapon_entry, riposte_multiplier, spawn_transform: Transform2D):
	if is_instance_valid(self):
		_spawn_attack_instance(weapon_entry, 0, false, riposte_multiplier, spawn_transform)

func _spawn_attack_instance(weapon_entry: Dictionary, p_reaping_bonus: int = 0, is_initial_swing: bool = false, p_riposte_mult: float = 1.0, p_transform_override = null) -> Node2D:
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(blueprint_data) or not is_instance_valid(owner_player): return null
	
	if not is_instance_valid(blueprint_data.weapon_scene):
		push_error("WeaponManager FATAL ERROR for weapon '", blueprint_data.id, "': The 'weapon_scene' property is null!")
		return null
	
	var weapon_instance = blueprint_data.weapon_scene.instantiate()
	owner_player.add_child(weapon_instance)
	
	var final_transform: Transform2D
	var final_direction: Vector2

	if p_transform_override != null and p_transform_override is Transform2D:
		final_transform = p_transform_override
		final_direction = Vector2.RIGHT.rotated(final_transform.get_rotation())
	else:
		var spawn_position: Vector2 = owner_player.global_position
		if blueprint_data.requires_direction:
			match blueprint_data.targeting_type:
				&"nearest_enemy":
					var nearest_enemy = owner_player._find_nearest_enemy()
					if is_instance_valid(nearest_enemy): final_direction = (nearest_enemy.global_position - owner_player.global_position).normalized()
					else: return null
				&"mouse_location":
					var world_mouse_pos = owner_player.get_global_mouse_position()
					final_direction = (world_mouse_pos - owner_player.global_position).normalized()
					var max_range = float(_calculate_final_weapon_stat(weapon_entry, PlayerStatKeys.KEY_NAMES[PlayerStatKeys.Keys.MAX_CAST_RANGE]))
					max_range += owner_player.player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_MAX_RANGE_ADD)
					spawn_position = owner_player.global_position.move_toward(world_mouse_pos, max_range)
				&"mouse_direction":
					if is_instance_valid(owner_player.melee_aiming_dot) and owner_player.melee_aiming_dot.has_method("get_aiming_direction"):
						final_direction = owner_player.melee_aiming_dot.get_aiming_direction()
					else:
						final_direction = (owner_player.get_global_mouse_position() - owner_player.global_position).normalized()
						if final_direction == Vector2.ZERO: final_direction = Vector2.RIGHT
		
		if blueprint_data.spawn_as_child:
			var local_pos = owner_player.melee_aiming_dot.position if is_instance_valid(owner_player.melee_aiming_dot) and blueprint_data.tags.has("melee") else Vector2.ZERO
			spawn_position = owner_player.to_global(local_pos)
		final_transform = Transform2D(final_direction.angle(), spawn_position)
	
	weapon_instance.global_transform = final_transform
	
	var stats_to_pass = weapon_entry.specific_stats.duplicate(true)
	stats_to_pass["id"] = weapon_entry.get("id")

	for key in weapon_entry.specific_stats.keys():
		var value = weapon_entry.specific_stats[key]
		if value is int or value is float:
			stats_to_pass[key] = _calculate_final_weapon_stat(weapon_entry, key)
	
	stats_to_pass["tags"] = weapon_entry.tags.duplicate(true)
	
	# --- REFACTORED DAMAGE CALCULATION ---
	var weapon_tags = stats_to_pass["tags"]
	var damage_percent = stats_to_pass[&"weapon_damage_percentage"]
	# Step 1: Get the base damage.
	var base_damage = owner_player.player_stats.get_calculated_base_damage(damage_percent)
	# Step 2: Apply tag-specific multipliers.
	var final_damage = owner_player.player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	stats_to_pass["final_damage_amount"] = final_damage * p_riposte_mult
	# --- END REFACTOR ---
	
	if stats_to_pass.has(&"projectile_speed"):
		var base_proj_speed = stats_to_pass[&"projectile_speed"]
		var weapon_proj_speed_mult = _calculate_final_weapon_stat(weapon_entry, &"projectile_speed_multiplier")
		var player_proj_speed_mult = owner_player.player_stats.get_final_stat(PlayerStatKeys.Keys.PROJECTILE_SPEED_MULTIPLIER)
		stats_to_pass[&"final_projectile_speed"] = base_proj_speed * weapon_proj_speed_mult * player_proj_speed_mult
	
	#stats_to_pass[&"reaping_momentum_accumulated_bonus"] = p_reaping_bonus
	if is_initial_swing:
		weapon_entry.specific_stats[&"reaping_momentum_accumulated_bonus"] = 0

	if weapon_instance.has_method("set_attack_properties"):
		weapon_instance.set_attack_properties(final_direction, stats_to_pass, owner_player.player_stats, self)
	
	if weapon_instance.has_signal("attack_hit_enemy"):
		weapon_instance.attack_hit_enemy.connect(_on_attack_hit_enemy.bind(weapon_entry.id), CONNECT_ONE_SHOT)
	#if weapon_instance.has_signal("reaping_momentum_hit"):
		#weapon_instance.reaping_momentum_hit.connect(_on_reaping_momentum_hit.bind(weapon_entry.id))

	return weapon_instance



func _on_attack_hit_enemy(hit_count: int, weapon_id: StringName):
	if hit_count > 0:
		var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
		if weapon_index != -1:
			active_weapons[weapon_index].specific_stats["parry_riposte_bonus_active"] = false


func _spawn_persistent_summon(weapon_entry: Dictionary):
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(blueprint_data) or not is_instance_valid(owner_player): return

	var base_max_summons = int(_calculate_final_weapon_stat(weapon_entry, &"max_summons_of_type"))
	var global_summon_add = int(owner_player.player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_COUNT_ADD))
	var final_max_summons = base_max_summons + global_summon_add
	
	# --- REVISED "DESTROY AND RE-CREATE" LOGIC ---
	# 1. Clear out all existing summons for this weapon ID.
	if _active_summons.has(blueprint_data.id):
		# Create a copy of the array because queue_free might modify it during iteration.
		for existing_summon in _active_summons[blueprint_data.id].duplicate():
			if is_instance_valid(existing_summon):
				existing_summon.queue_free()
		_active_summons[blueprint_data.id].clear()
	else:
		_active_summons[blueprint_data.id] = []

	# 2. Spawn a completely new set of summons up to the new maximum.
	for i in range(final_max_summons):
		var summon_instance = blueprint_data.weapon_scene.instantiate()
		if not is_instance_valid(summon_instance): continue

		get_tree().current_scene.add_child(summon_instance)
		summon_instance.global_position = owner_player.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		
		# Add the new instance to the tracking array.
		_active_summons[blueprint_data.id].append(summon_instance)
		# Connect its 'tree_exiting' signal to the cleanup function.
		summon_instance.tree_exiting.connect(_on_summon_destroyed.bind(blueprint_data.id, summon_instance))
		
		if summon_instance.has_method("initialize"):
			var stats_to_pass = _get_calculated_stats_for_instance(weapon_entry)
			# This logic now correctly spaces ALL spirits evenly.
			var start_angle = float(i) / float(final_max_summons) * TAU
			(summon_instance as Node2D).initialize(owner_player, stats_to_pass, start_angle)

func _on_summon_destroyed(weapon_id: StringName, summon_instance: Node):
	if _active_summons.has(weapon_id) and _active_summons[weapon_id].has(summon_instance):
		_active_summons[weapon_id].erase(summon_instance)

# NEW HELPER: Consolidates the logic for calculating the final stats to pass to an instance.
func _get_calculated_stats_for_instance(weapon_entry: Dictionary) -> Dictionary:
	# FIX: Start with a deep copy of all specific stats, including flags and other data types.
	var calculated_stats = weapon_entry.specific_stats.duplicate(true)
	var owner_player_stats = (get_parent() as PlayerCharacter).player_stats
	
	# Now, iterate through the copied stats and overwrite the numerical values with their final calculated values.
	for key in calculated_stats.keys():
		var value = calculated_stats[key]
		if value is int or value is float:
			calculated_stats[key] = _calculate_final_weapon_stat(weapon_entry, key)
	
	# Add the other essential data to the final dictionary.
	calculated_stats["tags"] = weapon_entry.tags.duplicate(true)
	calculated_stats["id"] = weapon_entry.id
	calculated_stats["weapon_level"] = weapon_entry.weapon_level
	
	# This logic remains correct for applying summon-specific damage.
	if calculated_stats.has(&"weapon_damage_percentage"):
		calculated_stats[&"weapon_damage_percentage"] *= owner_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_SUMMON_DAMAGE_MULTIPLIER)
	
	return calculated_stats


func _restart_weapon_cooldown(weapon_entry: Dictionary):
	var timer = weapon_entry.get("cooldown_timer") as Timer
	if is_instance_valid(timer):
		timer.wait_time = get_weapon_cooldown_value(weapon_entry)
		timer.start()

func get_weapon_cooldown_value(weapon_entry: Dictionary) -> float:
	var base_cooldown = _calculate_final_weapon_stat(weapon_entry, &"cooldown")
	var attack_speed_mult = _calculate_final_weapon_stat(weapon_entry, &"attack_speed_multiplier") # This is weapon-specific attack speed
	
	var owner_player = get_parent() as PlayerCharacter
	if not is_instance_valid(owner_player): return base_cooldown
	var p_player_stats = owner_player.player_stats
	
	var final_cooldown = base_cooldown
	
	# Check if the weapon is a summon/pet. If so, global attack speed stats should not affect its spawn rate.
	var is_summon = weapon_entry.tags.has(&"summon") or weapon_entry.tags.has(&"pet")

	if not is_summon:
		# --- This logic now ONLY applies to non-summon weapons ---
		var global_attack_speed_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
		var total_speed_multiplier = attack_speed_mult * global_attack_speed_mult
		
		var global_cooldown_reduction_mult = p_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_COOLDOWN_REDUCTION_MULT)
		
		if total_speed_multiplier > 0.01:
			final_cooldown /= total_speed_multiplier
		
		if global_cooldown_reduction_mult > 0.01:
			final_cooldown *= global_cooldown_reduction_mult
		# --- End of non-summon logic ---
	
	# Tag-Based Cooldown Logic (This is a percentage reduction, so it can apply to all)
	if weapon_entry.tags.has(&"magical"):
		final_cooldown *= (1.0 - p_player_stats.get_final_stat(PlayerStatKeys.Keys.GLOBAL_MAGIC_COOLDOWN_REDUCTION))
		
	return maxf(0.02, final_cooldown) # Ensure cooldown doesn't drop below a minimum threshold.


func _calculate_final_weapon_stat(weapon_entry: Dictionary, stat_key: StringName) -> float:
	var base_value = float(weapon_entry.specific_stats.get(stat_key, 0.0))
	var flat_mod = float(weapon_entry._flat_mods.get(stat_key, 0.0))
	var percent_add_mod = float(weapon_entry._percent_add_mods.get(stat_key, 0.0))
	var percent_mult_final_mod = float(weapon_entry._percent_mult_final_mods.get(stat_key, 1.0))
	return (base_value + flat_mod) * (1.0 + percent_add_mod) * percent_mult_final_mod
	
func apply_weapon_upgrade(weapon_id: StringName, upgrade_data: WeaponUpgradeData):
	var weapon_index = _get_weapon_entry_index_by_id(weapon_id)
	if weapon_index == -1: return

	var weapon_entry = active_weapons[weapon_index]
	var owner_player = get_parent() as PlayerCharacter

	# Set the acquired flag on the weapon itself for prerequisite checks
	if upgrade_data.set_acquired_flag_on_weapon != &"":
		weapon_entry.specific_stats[upgrade_data.set_acquired_flag_on_weapon] = true

	# --- DELEGATION PATTERN: WeaponManager now processes ALL effects from a weapon upgrade ---
	for effect in upgrade_data.effects:
		if not is_instance_valid(effect): continue
		
		# Check the target scope to determine where to apply the effect
		if effect.target_scope == &"player_stats":
			# If the effect targets the player, delegate it to PlayerStats
			if effect is StatModificationEffectData:
				owner_player.player_stats.apply_stat_modification(effect)
			elif effect is CustomFlagEffectData:
				owner_player.player_stats.apply_custom_flag(effect)
			else:
				push_warning("WeaponManager: Unhandled player-scoped effect type in weapon upgrade: " + str(effect.get_class()))
		else:
			# Otherwise, apply the effect to the weapon itself
			if effect is StatModificationEffectData:
				var stat_mod = effect as StatModificationEffectData
				var key = stat_mod.stat_key
				var value = stat_mod.get_value()
				match stat_mod.modification_type:
					&"flat_add": weapon_entry._flat_mods[key] = weapon_entry._flat_mods.get(key, 0.0) + value
					&"percent_add_to_base": weapon_entry._percent_add_mods[key] = weapon_entry._percent_add_mods.get(key, 0.0) + value
					&"percent_mult_final": weapon_entry._percent_mult_final_mods[key] = weapon_entry._percent_mult_final_mods.get(key, 1.0) * (1.0 + value)
					&"override_value": weapon_entry.specific_stats[key] = value
			
			elif effect is CustomFlagEffectData:
				var flag_mod = effect as CustomFlagEffectData
				weapon_entry.specific_stats[flag_mod.flag_key] = flag_mod.flag_value
			
			elif effect is StatusEffectApplicationData:
				if not weapon_entry.specific_stats.has(&"on_hit_status_applications"):
					weapon_entry.specific_stats[&"on_hit_status_applications"] = []
				weapon_entry.specific_stats[&"on_hit_status_applications"].append(effect)
			
			elif effect is AddTagEffectData:
				var add_tag_effect = effect as AddTagEffectData
				if add_tag_effect.target_scope == &"weapon_behavior":
					var tag_to_add: StringName = add_tag_effect.tag_to_add
					if not weapon_entry.tags.has(tag_to_add):
						weapon_entry.tags.append(tag_to_add)
			
			elif effect is AddToSequenceEffectData:
				var seq_effect = effect as AddToSequenceEffectData
				if seq_effect.target_scope == &"weapon_specific_stats":
					if weapon_entry.specific_stats.has(seq_effect.array_key) and weapon_entry.specific_stats[seq_effect.array_key] is Array:
						weapon_entry.specific_stats[seq_effect.array_key].append(seq_effect.dictionary_to_add)
					else:
						push_warning("WeaponManager: AddToSequenceEffectData failed. Key '", seq_effect.array_key, "' not found or not an Array in weapon stats.")
	
	weapon_entry.weapon_level += 1
	weapon_entry.acquired_upgrade_ids.append(upgrade_data.upgrade_id)

	if upgrade_data.upgrade_id == &"living_conduit_stormcaller":
		if not owner_player.get_node_or_null("StormcallerAura"):
			var stormcaller_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/StormcallerAura.tscn")
			if is_instance_valid(stormcaller_scene):
				var aura_instance = stormcaller_scene.instantiate()
				aura_instance.name = "StormcallerAura"
				owner_player.add_child(aura_instance)
				if aura_instance.has_method("initialize"):
					aura_instance.initialize(self, owner_player.player_stats)
					
	# --- NEW: Push stat updates to active summons ---
	# --- CORE FIX FOR SUMMONS ---
	var blueprint_data = weapon_entry.blueprint_resource as WeaponBlueprintData
	if blueprint_data.tags.has("summon"):
		_spawn_persistent_summon(weapon_entry)
		if _active_summons.has(weapon_id):
			var calculated_summon_stats = _get_calculated_stats_for_instance(weapon_entry)
			for summon_instance in _active_summons[weapon_id]:
				if is_instance_valid(summon_instance) and summon_instance.has_method("update_stats"):
					summon_instance.update_stats(calculated_summon_stats)

	var persistent_instance = weapon_entry.get("persistent_instance")
	if is_instance_valid(persistent_instance) and persistent_instance.has_method("update_stats"):
		var stats_to_pass = _get_calculated_stats_for_instance(weapon_entry)
		persistent_instance.update_stats(stats_to_pass)
		
	emit_signal("weapon_upgraded", weapon_id, weapon_entry.weapon_level)
	emit_signal("active_weapons_changed")

func _get_weapon_entry_index_by_id(weapon_id: StringName) -> int:
	for i in range(active_weapons.size()):
		if active_weapons[i].id == weapon_id: return i
	return -1
	
func get_active_weapons_data_for_level_up() -> Array[Dictionary]:
	var weapons_data_copy: Array[Dictionary] = []
	for weapon_entry in active_weapons:
		var display_data = {
			"id": weapon_entry.id,
			"title": weapon_entry.title,
			"weapon_level": weapon_entry.weapon_level,
			"specific_stats": weapon_entry.specific_stats.duplicate(true),
			"blueprint_resource_path": weapon_entry.blueprint_resource.resource_path if is_instance_valid(weapon_entry.blueprint_resource) else ""
		}
		weapons_data_copy.append(display_data)
	return weapons_data_copy
