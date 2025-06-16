# StatusEffectComponent.gd
# This component manages active status effects (buffs/debuffs) on an owner node (e.g., Player, Enemy).
# It handles their duration, ticking effects, stacking, and applying their modifiers.
# CORRECTED: The dynamic damage calculation for DoTs now uses a more robust method for creating typed arrays, preventing a parser error.

class_name StatusEffectComponent
extends Node

signal status_effects_changed(owner_node: Node)

# Dictionary to hold currently active status effects.
# Key: StatusEffectData.id (StringName)
# Value: { data, duration_timer, tick_timer, stacks, source, weapon_stats, potency_override, stored_tick_damage }
var active_effects: Dictionary = {}

# Dictionaries to aggregate stat modifications from all active effects.
var _additive_modifiers: Dictionary = {}
var _multiplicative_modifiers: Dictionary = {}
var _active_flags: Dictionary = {}


# Applies a status effect to the owner of this component.
func apply_effect(
		effect_data: StatusEffectData,
		source_node: Node = null,
		p_weapon_stats_for_scaling: Dictionary = {},
		duration_override: float = -1.0,
		potency_override: float = -1.0
	):
	if not is_instance_valid(effect_data) or effect_data.id == &"":
		push_error("StatusEffectComponent: Invalid StatusEffectData provided."); return

	var effect_id: StringName = effect_data.id
	var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
	
	if active_effects.has(effect_id):
		# --- HANDLE RE-APPLICATION OF AN EXISTING EFFECT ---
		var existing_effect = active_effects[effect_id]
		
		# Stacking logic: Increment stacks if the effect is stackable and not at max stacks.
		if effect_data.is_stackable and existing_effect.stacks < effect_data.max_stacks:
			existing_effect.stacks += 1
		
		# Refresh duration if the effect is configured to do so.
		if effect_data.refresh_duration_on_reapply:
			existing_effect.source = source_node
			existing_effect.weapon_stats = p_weapon_stats_for_scaling.duplicate(true)
			existing_effect.potency_override = potency_override
			if final_duration > 0 and is_instance_valid(existing_effect.duration_timer):
				existing_effect.duration_timer.wait_time = final_duration
				existing_effect.duration_timer.start()
	else:
		# --- HANDLE APPLICATION OF A NEW EFFECT ---
		var new_effect_entry = {
			"data": effect_data, "duration_timer": null, "tick_timer": null, "stacks": 1,
			"source": source_node, "weapon_stats": p_weapon_stats_for_scaling.duplicate(true),
			"potency_override": potency_override,
			"stored_tick_damage": 0.0 # This will store the base damage for DoT calculations.
		}
		
		# --- DYNAMIC DAMAGE CALCULATION (for DoTs like Bleed) ---
		# "Snapshot" the damage of the initial hit to ensure the DoT scales correctly.
		var is_dot_effect = false
		for effect in effect_data.effects_while_active:
			if effect is StatModificationEffectData and effect.stat_key == &"health":
				is_dot_effect = true
				break
		
		if is_dot_effect:
			var source_player_stats = source_node.player_stats if is_instance_valid(source_node) and "player_stats" in source_node else null
			if is_instance_valid(source_player_stats):
				var weapon_dmg_percent = float(p_weapon_stats_for_scaling.get(&"weapon_damage_percentage", 1.0))
				
				# FIXED: Use a more robust method to create the typed array to avoid parser errors.
				var weapon_tags: Array[StringName] = []
				var retrieved_tags = p_weapon_stats_for_scaling.get(&"tags", [])
				if retrieved_tags is Array:
					weapon_tags.assign(retrieved_tags)

				new_effect_entry.stored_tick_damage = source_player_stats.get_calculated_player_damage(weapon_dmg_percent, weapon_tags)
			
		# Create and start duration timer if the effect is not permanent.
		if final_duration > 0:
			var duration_timer_node = Timer.new()
			duration_timer_node.name = "DurationTimer_" + str(effect_id)
			duration_timer_node.wait_time = final_duration
			duration_timer_node.one_shot = true
			add_child(duration_timer_node)
			duration_timer_node.timeout.connect(_on_effect_expired.bind(effect_id, duration_timer_node))
			duration_timer_node.start()
			new_effect_entry.duration_timer = duration_timer_node
		
		# Create and start tick timer for effects that apply over time.
		if effect_data.tick_interval > 0:
			var tick_timer_node = Timer.new()
			tick_timer_node.name = "TickTimer_" + str(effect_id)
			tick_timer_node.wait_time = effect_data.tick_interval
			tick_timer_node.one_shot = false
			add_child(tick_timer_node)
			tick_timer_node.timeout.connect(_on_status_effect_tick.bind(effect_id))
			tick_timer_node.start()
			new_effect_entry.tick_timer = tick_timer_node
			if effect_data.tick_on_application:
				_on_status_effect_tick(effect_id)

		active_effects[effect_id] = new_effect_entry
	
	# After any change, recalculate all modifiers and notify the owner.
	_recalculate_and_apply_stat_modifiers() 
	var owner_node = get_parent()
	if is_instance_valid(owner_node) and owner_node.has_method("on_status_effects_changed"):
		owner_node.on_status_effects_changed(owner_node)
	emit_signal("status_effects_changed", owner_node)

# Called repeatedly by a status effect's tick_timer.
func _on_status_effect_tick(effect_id: StringName):
	if not active_effects.has(effect_id): return
	
	var owner = get_parent()
	if not is_instance_valid(owner): return
	
	var effect_entry = active_effects[effect_id]
	var status_data = effect_entry.data as StatusEffectData
	
	for effect in status_data.effects_while_active:
		if effect is StatModificationEffectData:
			var stat_mod = effect as StatModificationEffectData
			
			# This specifically handles ticking damage effects like Bleed.
			if stat_mod.stat_key == &"health" and stat_mod.modification_type == &"flat_add":
				var damage_per_tick = 0.0
				if status_data.duration > 0 and status_data.tick_interval > 0:
					# Divide the total stored damage by the number of ticks to get damage per tick.
					var num_ticks = status_data.duration / status_data.tick_interval
					damage_per_tick = effect_entry.stored_tick_damage / num_ticks

				var actual_potency_override = effect_entry.get("potency_override", -1.0)
				if actual_potency_override >= 0.0:
					damage_per_tick *= actual_potency_override

				damage_per_tick *= effect_entry.stacks

				var final_tick_damage = absf(damage_per_tick)
				final_tick_damage = maxf(1.0, final_tick_damage)
				
				if owner.has_method("take_damage"):
					owner.take_damage(final_tick_damage, effect_entry.source)

# Called when an effect's duration timer expires.
func _on_effect_expired(effect_id_expired: StringName, duration_timer_ref: Timer):
	if active_effects.has(effect_id_expired):
		var effect_entry = active_effects[effect_id_expired]
		var status_data_to_check = effect_entry.data as StatusEffectData
		
		var tick_timer = effect_entry.get("tick_timer") as Timer
		if is_instance_valid(tick_timer):
			tick_timer.stop(); tick_timer.queue_free()

		active_effects.erase(effect_id_expired)
		
		_recalculate_and_apply_stat_modifiers()
		var owner_node = get_parent()
		if is_instance_valid(owner_node) and owner_node.has_method("on_status_effects_changed"):
			owner_node.on_status_effects_changed(owner_node)
		emit_signal("status_effects_changed", owner_node)
		
		if is_instance_valid(status_data_to_check) and status_data_to_check.next_status_effect_on_expire != &"":
			var next_effect_id = status_data_to_check.next_status_effect_on_expire
			var next_effect_path = "res://DataResources/StatusEffects/" + str(next_effect_id) + "_status.tres"
			if ResourceLoader.exists(next_effect_path):
				var next_effect_data = load(next_effect_path) as StatusEffectData
				if is_instance_valid(next_effect_data):
					apply_effect(next_effect_data, effect_entry.source, effect_entry.weapon_stats)

	if is_instance_valid(duration_timer_ref):
		duration_timer_ref.queue_free()

# Recalculates the aggregated stat modifiers from all currently active effects.
func _recalculate_and_apply_stat_modifiers():
	_additive_modifiers.clear()
	_multiplicative_modifiers.clear()
	_active_flags.clear()

	# Initialize all modifier dictionaries to neutral values.
	for key_enum_value in PlayerStatKeys.Keys.values():
		_multiplicative_modifiers[PlayerStatKeys.KEY_NAMES[key_enum_value]] = 1.0
		_additive_modifiers[PlayerStatKeys.KEY_NAMES[key_enum_value]] = 0.0

	for effect_id in active_effects:
		var effect_entry = active_effects[effect_id]
		var status_effect_data_res = effect_entry.data as StatusEffectData
		
		if is_instance_valid(status_effect_data_res):
			for effect_res in status_effect_data_res.effects_while_active:
				if not is_instance_valid(effect_res): continue

				if effect_res is StatModificationEffectData:
					var stat_mod = effect_res as StatModificationEffectData
					var mod_value = stat_mod.get_value()
					
					var potency_override = effect_entry.get("potency_override", -1.0)
					if potency_override >= 0.0: mod_value *= potency_override
					
					if status_effect_data_res.is_stackable:
						mod_value *= effect_entry.stacks
					
					var key = stat_mod.stat_key
					var type = stat_mod.modification_type

					# Do not aggregate damage-over-time ticks as a persistent modifier.
					if not (key == &"health" and type == &"flat_add"):
						match type:
							&"flat_add", &"percent_add_to_base":
								_additive_modifiers[key] = _additive_modifiers.get(key, 0.0) + mod_value
							&"percent_mult_final":
								_multiplicative_modifiers[key] = _multiplicative_modifiers.get(key, 1.0) * (1.0 + mod_value)
				
				elif effect_res is CustomFlagEffectData:
					var flag_effect = effect_res as CustomFlagEffectData
					# If the flag is already true from another source, don't set it to false.
					if _active_flags.get(flag_effect.flag_key, false) == false:
						_active_flags[flag_effect.flag_key] = flag_effect.flag_value
	
	emit_signal("status_effects_changed", get_parent())

# --- Getter Functions ---

func get_sum_of_additive_modifiers(stat_key: StringName) -> float:
	return _additive_modifiers.get(stat_key, 0.0)

func get_product_of_multiplicative_modifiers(stat_key: StringName) -> float:
	return _multiplicative_modifiers.get(stat_key, 1.0)

func has_flag(flag_key: StringName) -> bool:
	return _active_flags.get(flag_key, false)

func has_status_effect(effect_id: StringName) -> bool:
	return active_effects.has(effect_id)
