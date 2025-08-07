## File: res/Scripts/StatusEffects/StatusEffectComponent.gd
# MERGED: This version contains your script's logic combined with the new global signal emission.

class_name StatusEffectComponent
extends Node

signal status_effects_changed(owner_node: Node)

var active_effects: Dictionary = {}

var _temp_flat_add_modifiers: Dictionary = {}
var _temp_percent_add_modifiers: Dictionary = {}
var _additive_modifiers: Dictionary = {}
var _multiplicative_modifiers: Dictionary = {}
var _active_flags: Dictionary = {}

# NEW: Timestamp for Catalytic Reaction cooldown
var _last_catalytic_proc_timestamp: float = 0.0


# NEW: Function to enforce a 1-second cooldown on catalytic reactions for this specific enemy instance.
func can_trigger_catalytic_reaction() -> bool:
	var current_time_ms = Time.get_ticks_msec()
	if current_time_ms - _last_catalytic_proc_timestamp > 1000.0: # 1000ms = 1 second
		_last_catalytic_proc_timestamp = current_time_ms
		return true
	return false
	
func apply_effect(
		effect_data: StatusEffectData,
		source_node: Node = null,
		p_weapon_stats_for_scaling: Dictionary = {},
		duration_override: float = -1.0,
		potency_override: float = -1.0,
		p_unique_id_override: StringName = &""
	):
	if not is_instance_valid(effect_data) or effect_data.id == &"":
		push_error("StatusEffectComponent: Invalid StatusEffectData provided."); return

	if effect_data.unique_id != &"":
		for key in active_effects:
			var existing_effect = active_effects[key]
			if is_instance_valid(existing_effect.data) and existing_effect.data.unique_id == effect_data.unique_id:
				# An effect of the same unique type already exists.
				var existing_magnitude = _get_effect_magnitude(existing_effect)
				var new_magnitude = _get_effect_magnitude({"data": effect_data, "potency_override": potency_override})
				
				if new_magnitude > existing_magnitude:
					# The new effect is stronger, so remove the old one before applying the new one.
					remove_effect_by_unique_id(key)
				else:
					# The existing effect is stronger or equal, just refresh its duration and return.
					if effect_data.refresh_duration_on_reapply and is_instance_valid(existing_effect.duration_timer):
						var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
						existing_effect.duration_timer.wait_time = final_duration
						existing_effect.duration_timer.start()
					return # Do not proceed to apply the weaker effect.
					
	var base_id = effect_data.id
	var final_effect_key = base_id
	var is_newly_applied = false

	if p_unique_id_override != &"":
		final_effect_key = p_unique_id_override
	elif effect_data.is_stackable and not effect_data.refresh_duration_on_reapply:
		var stack_counter = 0
		while active_effects.has(str(base_id) + str(stack_counter)):
			stack_counter += 1
		final_effect_key = str(base_id) + str(stack_counter)

	if active_effects.has(final_effect_key):
		# Handle re-application of an existing effect.
		var existing_effect = active_effects[final_effect_key]
		if effect_data.is_stackable and existing_effect.stacks < effect_data.max_stacks:
			existing_effect.stacks += 1
		if effect_data.refresh_duration_on_reapply:
			var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
			if final_duration > 0 and is_instance_valid(existing_effect.duration_timer):
				existing_effect.duration_timer.wait_time = final_duration
				existing_effect.duration_timer.start()
	else:
		# Handle application of a new effect.
		is_newly_applied = true
		var new_effect_entry = {
			"base_id": base_id, "unique_id": final_effect_key,
			"data": effect_data, "duration_timer": null, "tick_timer": null, "stacks": 1,
			"source": source_node, "weapon_stats": p_weapon_stats_for_scaling.duplicate(true),
			"potency_override": potency_override, "stored_tick_damage": 0.0
		}

		# DoT logic
		var is_dot_effect = false
		for effect in effect_data.effects_while_active:
			if effect is StatModificationEffectData and effect.stat_key == &"health":
				is_dot_effect = true
				break
		if is_dot_effect:
			if potency_override >= 0.0:
				new_effect_entry.stored_tick_damage = potency_override
			else:
				var source_player_stats = source_node.player_stats if is_instance_valid(source_node) and "player_stats" in source_node else null
				if is_instance_valid(source_player_stats):
					var weapon_dmg_percent = float(p_weapon_stats_for_scaling.get(&"weapon_damage_percentage", 1.0))
					var weapon_tags: Array[StringName] = []
					var retrieved_tags = p_weapon_stats_for_scaling.get(&"tags", [])
					if retrieved_tags is Array: weapon_tags.assign(retrieved_tags)
					
					# --- REFACTORED DAMAGE CALCULATION ---
					var base_damage = source_player_stats.get_calculated_base_damage(weapon_dmg_percent)
					var final_damage = source_player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
					new_effect_entry.stored_tick_damage = final_damage
					# --- END REFACTOR ---
		
		var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
		print_debug("Applied '", effect_data.display_name, "' to '", get_parent().name, "' for ", final_duration, " seconds.")

		if final_duration > 0:
			var duration_timer = Timer.new(); duration_timer.name = "DurationTimer_" + str(final_effect_key)
			duration_timer.one_shot = true; duration_timer.wait_time = final_duration
			duration_timer.timeout.connect(_on_effect_expired.bind(final_effect_key))
			add_child(duration_timer); duration_timer.start()
			new_effect_entry.duration_timer = duration_timer

		if effect_data.id == &"living_conduit":
			var conduit_interval = float(p_weapon_stats_for_scaling.get(&"conduit_arc_interval", 0.5))
			if conduit_interval > 0:
				var tick_timer = Timer.new()
				tick_timer.name = "TickTimer_" + str(final_effect_key)
				tick_timer.wait_time = conduit_interval
				tick_timer.timeout.connect(_on_status_effect_tick.bind(final_effect_key))
				add_child(tick_timer)
				tick_timer.start()
				if effect_data.tick_on_application:
					_on_status_effect_tick(final_effect_key)
				new_effect_entry.tick_timer = tick_timer
		else:
			if effect_data.tick_interval > 0:
				var tick_timer = Timer.new()
				tick_timer.name = "TickTimer_" + str(final_effect_key)
				tick_timer.wait_time = effect_data.tick_interval
				tick_timer.timeout.connect(_on_status_effect_tick.bind(final_effect_key))
				add_child(tick_timer)
				tick_timer.start()
				if effect_data.tick_on_application:
					_on_status_effect_tick(final_effect_key)
				new_effect_entry.tick_timer = tick_timer
				
		active_effects[final_effect_key] = new_effect_entry

		if is_instance_valid(effect_data.visual_effect_scene):
			var owner_node = get_parent()
			if is_instance_valid(owner_node):
				var visual_instance = effect_data.visual_effect_scene.instantiate()
				if visual_instance.has_method("initialize"):
					visual_instance.initialize(
						owner_node,
						final_duration,
						effect_data.visual_anchor_point,
						effect_data.visual_scale_multiplier
					)
				else:
					owner_node.add_child(visual_instance)
				# Store the reference in our dictionary entry.
				new_effect_entry.visual_instance = visual_instance
	
	if is_newly_applied:
		CombatEvents.emit_signal("status_effect_applied", get_parent(), effect_data.id, source_node)
		
	_recalculate_and_apply_stat_modifiers()
	var owner_node_for_signal = get_parent()
	if is_instance_valid(owner_node_for_signal): 
		emit_signal("status_effects_changed", owner_node_for_signal)

func get_effect_stack_count(p_base_id: StringName) -> int:
	if active_effects.has(p_base_id):
		return active_effects[p_base_id].get("stacks", 0)
	return 0

# This function is called by PolearmController to manually remove a buff.
func remove_effect_by_unique_id(effect_unique_id: StringName):
	if active_effects.has(effect_unique_id):
		var effect_entry = active_effects.get(effect_unique_id)
		active_effects.erase(effect_unique_id)
		
		if effect_entry:
			if effect_entry.has("visual_instance") and is_instance_valid(effect_entry.get("visual_instance")):
				effect_entry.get("visual_instance").queue_free()
			if is_instance_valid(effect_entry.duration_timer):
				effect_entry.duration_timer.queue_free()
			if is_instance_valid(effect_entry.tick_timer):
				effect_entry.tick_timer.queue_free()
			
			# Recalculate stats now that the effect is gone
			_recalculate_and_apply_stat_modifiers()
			var owner_node = get_parent()
			if is_instance_valid(owner_node): 
				emit_signal("status_effects_changed", owner_node)

func _on_status_effect_tick(effect_unique_id: StringName):
	if not active_effects.has(effect_unique_id): return
	var owner = get_parent()
	if not is_instance_valid(owner): return
	var effect_entry = active_effects[effect_unique_id]
	var status_data = effect_entry.data as StatusEffectData
	
	if status_data.id == &"living_conduit":
		_execute_living_conduit_arc(effect_entry)
		
	for effect in status_data.effects_while_active:
		if effect is StatModificationEffectData:
			var stat_mod = effect as StatModificationEffectData
			if stat_mod.stat_key == &"health" and stat_mod.modification_type == &"flat_add":
				var damage_per_tick = 0.0
				
				# --- MODIFIED TICK DAMAGE LOGIC ---
				# --- CORRECTED TICK DAMAGE LOGIC ---
				# Toxic Soil now uses the default logic to spread its damage over the duration.
				if status_data.id == &"poison":
					# Poison deals a percentage of the stored damage per tick.
					damage_per_tick = effect_entry.stored_tick_damage * 0.5
				else: # Default behavior for Bleed, Toxic Soil, etc.
					if status_data.duration > 0 and status_data.tick_interval > 0:
						var num_ticks = status_data.duration / status_data.tick_interval
						if num_ticks > 0:
							damage_per_tick = effect_entry.stored_tick_damage / num_ticks
				
				if status_data.is_stackable:
					damage_per_tick *= effect_entry.stacks
				
				var final_tick_damage = absf(damage_per_tick)
				final_tick_damage = maxf(1.0, final_tick_damage)
				if owner.has_method("take_damage"):
					owner.take_damage(final_tick_damage, effect_entry.source)
	# --- NEW: Arcing Logic for Living Conduit ---
	if status_data.id == &"living_conduit":
		_execute_living_conduit_arc(effect_entry)

func _on_effect_expired(effect_unique_id: StringName):
	if active_effects.has(effect_unique_id):
		var effect_entry = active_effects.get(effect_unique_id)
		active_effects.erase(effect_unique_id)
		
		if effect_entry:
			if effect_entry.has("visual_instance") and is_instance_valid(effect_entry.get("visual_instance")):
				effect_entry.get("visual_instance").queue_free()

			var weapon_stats = effect_entry.weapon_stats
			var status_data = effect_entry.data as StatusEffectData
			var owner = get_parent()
			if is_instance_valid(status_data):
				print_debug("Status Effect Expired: '", status_data.display_name, "' on '", owner.name, "'")
  
			# --- Centralized Expiration Logic ---
			if is_instance_valid(status_data) and status_data.id == &"living_conduit":
				if weapon_stats.get(&"has_overload", false):
					_execute_overload_effect(effect_entry)
				
				if weapon_stats.get(&"has_lingering_charge", false):
					if owner is BaseEnemy:
						CombatEvents.emit_signal("lingering_charge_triggered", owner.global_position, weapon_stats, effect_entry.source, owner)
			# --- End Centralized Logic ---

			# Standard cleanup
			if is_instance_valid(effect_entry.duration_timer): 
				effect_entry.duration_timer.queue_free()
			if is_instance_valid(effect_entry.tick_timer): 
				effect_entry.tick_timer.queue_free()
			
			_recalculate_and_apply_stat_modifiers()
			if is_instance_valid(owner): 
				emit_signal("status_effects_changed", owner)

			if is_instance_valid(status_data) and status_data.next_status_effect_on_expire != &"":
				var next_effect_id = status_data.next_status_effect_on_expire
				var next_effect_path = "res://DataResources/StatusEffects/" + str(next_effect_id) + "_status.tres"
				if ResourceLoader.exists(next_effect_path):
					var next_effect_data = load(next_effect_path) as StatusEffectData
					if is_instance_valid(next_effect_data):
						apply_effect(next_effect_data, effect_entry.source, effect_entry.weapon_stats)

func _get_effect_magnitude(effect_entry: Dictionary) -> float:
	var magnitude = 0.0
	var data = effect_entry.data as StatusEffectData
	if not is_instance_valid(data): return 0.0
	
	for effect in data.effects_while_active:
		if effect is StatModificationEffectData:
			var stat_mod = effect as StatModificationEffectData
			# For simplicity, we'll just sum the values. A more complex system
			# might weigh different modification types differently.
			magnitude += abs(stat_mod.get_value())
	
	var potency_override = effect_entry.get("potency_override", -1.0)
	if potency_override != -1.0:
		magnitude *= potency_override
		
	return magnitude

# --- NEW FUNCTION to handle owner's death ---
func _on_owner_death():
	for effect_unique_id in active_effects.keys():
		var effect_entry = active_effects[effect_unique_id]
		if is_instance_valid(effect_entry.data) and effect_entry.data.id == &"living_conduit":
			if effect_entry.weapon_stats.get(&"has_overload", false):
				_execute_overload_effect(effect_entry)
			if effect_entry.weapon_stats.get(&"has_lingering_charge", false):
				if get_parent() is BaseEnemy:
					# FIX: Pass the dying enemy (get_parent()) as the fourth argument.
					CombatEvents.emit_signal("lingering_charge_triggered", get_parent().global_position, effect_entry.weapon_stats, effect_entry.source, get_parent())



	# --- NEW: Overload Logic ---

func _recalculate_and_apply_stat_modifiers():
	# Clear all modifier dictionaries
	_temp_flat_add_modifiers.clear()
	_temp_percent_add_modifiers.clear()
	_multiplicative_modifiers.clear()
	_active_flags.clear()
	
	# Initialize all dictionaries with default values for every possible stat
	for key_enum_value in PlayerStatKeys.Keys.values():
		var key_string = PlayerStatKeys.KEY_NAMES[key_enum_value]
		_temp_flat_add_modifiers[key_string] = 0.0
		_temp_percent_add_modifiers[key_string] = 0.0
		_multiplicative_modifiers[key_string] = 1.0

	# Iterate through active effects and populate the modifier dictionaries
	for key in active_effects:
		var effect_entry = active_effects[key]
		var status_data = effect_entry.data as StatusEffectData
		if is_instance_valid(status_data):
			for effect in status_data.effects_while_active:
				if not is_instance_valid(effect): continue
				
				if effect is StatModificationEffectData:
					var stat_mod = effect as StatModificationEffectData
					var mod_value = stat_mod.get_value()
					var potency_override = effect_entry.get("potency_override", -1.0)

					if potency_override != -1.0:
						# For flat and percent_add, the potency override *is* the value.
						if stat_mod.modification_type == &"flat_add" or stat_mod.modification_type == &"percent_add_to_base":
							mod_value = potency_override
						# For multipliers, the potency affects the multiplier value itself.
						else:
							mod_value *= potency_override

					if status_data.is_stackable: mod_value *= effect_entry.stacks
					
					var stat_key = stat_mod.stat_key
					var type = stat_mod.modification_type
					
					if not (stat_key == &"health" and type == &"flat_add"):
						# FIX: Check if the key exists before attempting to modify it.
						# This allows the component to handle both global and local stats.
						match type:
							&"flat_add":
								if not _temp_flat_add_modifiers.has(stat_key): _temp_flat_add_modifiers[stat_key] = 0.0
								_temp_flat_add_modifiers[stat_key] += mod_value
							&"percent_add_to_base":
								if not _temp_percent_add_modifiers.has(stat_key): _temp_percent_add_modifiers[stat_key] = 0.0
								_temp_percent_add_modifiers[stat_key] += mod_value
							&"percent_mult_final":
								if not _multiplicative_modifiers.has(stat_key): _multiplicative_modifiers[stat_key] = 1.0
								_multiplicative_modifiers[stat_key] *= (1.0 + mod_value)
				
				elif effect is CustomFlagEffectData:
					var flag_effect = effect as CustomFlagEffectData
					_active_flags[flag_effect.flag_key] = flag_effect.flag_value
	
	emit_signal("status_effects_changed", get_parent())

func _execute_living_conduit_arc(effect_entry: Dictionary):
	var owner = get_parent()
	if not is_instance_valid(owner): return

	var weapon_stats = effect_entry.weapon_stats
	var arc_radius = float(weapon_stats.get(&"conduit_arc_radius", 125.0))
	var max_initial_targets = int(weapon_stats.get(&"conduit_arc_max_targets", 1))
	var arc_damage_percent = float(weapon_stats.get(&"conduit_arc_damage_percentage", 0.75))
	var chain_count = int(weapon_stats.get(&"conduit_arc_chain_count", 0))
	
	var source_player = effect_entry.source as PlayerCharacter
	if not is_instance_valid(source_player): return
	
	# --- REFACTORED DAMAGE CALCULATION ---
	var weapon_tags: Array[StringName] = weapon_stats.get("tags", [])
	var base_damage = source_player.player_stats.get_calculated_base_damage(arc_damage_percent)
	var arc_damage = source_player.player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	# --- END REFACTOR ---

	var initial_targets = _find_arc_targets(owner.global_position, arc_radius, max_initial_targets, [owner])
	var all_hit_this_tick = initial_targets.duplicate()

	for target in initial_targets:
		if is_instance_valid(target):
			target.take_damage(arc_damage, effect_entry.source)
			_spawn_lightning_arc_visual(owner.global_position, target.global_position)
			_check_for_resonance(weapon_stats, source_player)

			var current_chain_origin = target
			for _i in range(chain_count):
				var next_target_array = _find_arc_targets(current_chain_origin.global_position, arc_radius, 1, all_hit_this_tick)
				if next_target_array.is_empty():
					break
				
				var next_target = next_target_array[0]
				next_target.take_damage(arc_damage, effect_entry.source)
				_spawn_lightning_arc_visual(current_chain_origin.global_position, next_target.global_position)
				all_hit_this_tick.append(next_target)
				_check_for_resonance(weapon_stats, source_player)
				current_chain_origin = next_target

func _check_for_resonance(weapon_stats: Dictionary, source_player: PlayerCharacter):
	if weapon_stats.get(&"conduit_grants_resonance", false):
		if randf() < 0.05:
			var resonance_buff = load("res://DataResources/StatusEffects/arcane_surge_buff.tres") as StatusEffectData
			if is_instance_valid(resonance_buff):
				source_player.status_effect_component.apply_effect(resonance_buff, source_player)
				
func _execute_overload_effect(effect_entry: Dictionary):
	var owner = get_parent()
	if not is_instance_valid(owner): return

	var weapon_stats = effect_entry.weapon_stats
	var source_player = effect_entry.source as PlayerCharacter
	if not is_instance_valid(source_player): return

	var overload_radius = float(weapon_stats.get(&"overload_radius", 60.0))
	var overload_damage_percent = float(weapon_stats.get(&"conduit_arc_damage_percentage", 0.75))
	
	# --- REFACTORED DAMAGE CALCULATION ---
	var weapon_tags: Array[StringName] = weapon_stats.get("tags", [])
	var base_damage = source_player.player_stats.get_calculated_base_damage(overload_damage_percent)
	var overload_damage = source_player.player_stats.apply_tag_damage_multipliers(base_damage, weapon_tags)
	# --- END REFACTOR ---

	var explosion_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/OverloadExplosion.tscn")
	if is_instance_valid(explosion_scene):
		var explosion_instance = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion_instance)
		explosion_instance.global_position = owner.global_position
		if explosion_instance.has_method("initialize"):
			explosion_instance.initialize(overload_damage, overload_radius, source_player)

func _find_arc_targets(p_center: Vector2, p_radius: float, p_max_targets: int, p_exclude_list: Array) -> Array[Node2D]:
	# FIX: Explicitly type the array to match the function's return signature.
	var valid_targets: Array[Node2D] = []
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		if is_instance_valid(enemy) and not p_exclude_list.has(enemy) and not enemy.is_dead():
			if p_center.distance_squared_to(enemy.global_position) < p_radius * p_radius:
				valid_targets.append(enemy)
				
	# If we found more targets than we can hit, we just take the first few.
	# A more advanced implementation could sort by distance, but this is fine.
	if valid_targets.size() > p_max_targets:
		valid_targets.resize(p_max_targets)
		
	return valid_targets

func _spawn_lightning_arc_visual(start_pos: Vector2, end_pos: Vector2):
	var arc_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/LightningArc.tscn")
	if is_instance_valid(arc_scene):
		var arc_instance = arc_scene.instantiate()
		get_tree().current_scene.add_child(arc_instance)
		if arc_instance.has_method("initialize"):
			arc_instance.initialize(start_pos, end_pos)

func consume_effect_and_apply_next(effect_unique_id: StringName):
	if active_effects.has(effect_unique_id):
		var effect_entry = active_effects[effect_unique_id]
		active_effects.erase(effect_unique_id)
		
		if effect_entry:
			if is_instance_valid(effect_entry.duration_timer): 
				effect_entry.duration_timer.queue_free()
			if is_instance_valid(effect_entry.tick_timer): 
				effect_entry.tick_timer.queue_free()
			
			var status_data = effect_entry.data as StatusEffectData
			if is_instance_valid(status_data) and status_data.next_status_effect_on_expire != &"":
				var next_effect_id = status_data.next_status_effect_on_expire
				var next_effect_path = "res://DataResources/StatusEffects/Alchemist/" + str(next_effect_id) + ".tres"
				if ResourceLoader.exists(next_effect_path):
					var next_effect_data = load(next_effect_path) as StatusEffectData
					if is_instance_valid(next_effect_data):
						apply_effect(next_effect_data, effect_entry.source, effect_entry.weapon_stats)
		
		_recalculate_and_apply_stat_modifiers()
		var owner_node = get_parent()
		if is_instance_valid(owner_node): 
			emit_signal("status_effects_changed", owner_node)


# --- Getter Functions ---

func get_sum_of_flat_add_modifiers(stat_key: StringName) -> float:
	return _temp_flat_add_modifiers.get(stat_key, 0.0)

func get_sum_of_percent_add_modifiers(stat_key: StringName) -> float:
	return _temp_percent_add_modifiers.get(stat_key, 0.0)

func get_product_of_multiplicative_modifiers(stat_key: StringName) -> float:
	return _multiplicative_modifiers.get(stat_key, 1.0)

func has_flag(flag_key: StringName) -> bool:
	return _active_flags.get(flag_key, false)

func has_status_effect(effect_id: StringName) -> bool:
	return has_status_effect_with_base_id(effect_id)

func has_status_effect_with_base_id(p_base_id: StringName) -> bool:
	for key in active_effects:
		if active_effects[key].get("base_id") == p_base_id:
			return true
	return false

func has_status_effect_by_unique_id(p_unique_id: StringName) -> bool:
	return active_effects.has(p_unique_id)

func get_stats_from_effect_source_by_unique_id(p_unique_id: StringName) -> Dictionary:
	if active_effects.has(p_unique_id):
		return active_effects[p_unique_id].get("weapon_stats", {})
	return {}
