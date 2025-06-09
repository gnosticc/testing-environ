# StatusEffectComponent.gd
# This component manages active status effects (buffs/debuffs) on an owner node (e.g., Player, Enemy).
# It handles their duration, ticking effects, and applying their modifiers.
# It now integrates with GameStatConstants and routes flag changes to PlayerStats.
class_name StatusEffectComponent
extends Node

signal status_effects_changed(owner_node: Node) # Emitted when effects are applied, removed, or recalculated

# Dictionary to hold currently active status effects.
# Key: StatusEffectData.id (StringName)
# Value: Dictionary { "data": StatusEffectData, "duration_timer": Timer, "tick_timer": Timer,
#                     "stacks": int, "source": Node, "weapon_stats": Dictionary, "potency_override": float }
var active_effects: Dictionary = {}

# This dictionary locally aggregates stat modifiers from active effects for easy querying.
# IMPORTANT: These modifiers are *local* to StatusEffectComponent.
# For these to affect the owner's actual stats (e.g., in PlayerStats.gd), PlayerStats.gd
# must be updated to query these values or have its own temporary modifier system.
var current_stat_modifiers: Dictionary = {}


func _ready():
	# Basic check: Ensure the parent is a 2D or 3D node, which is typical for game entities.
	if not get_parent() is Node2D and not get_parent() is Node3D:
		push_warning("StatusEffectComponent WARNING: Owner (", get_parent().name if get_parent() else "None", ") is not Node2D/3D. This component is typically attached to such nodes.")

# Applies a status effect to the owner of this component.
# effect_data: The StatusEffectData resource defining the effect.
# source_node: The node that applied the effect (e.g., PlayerCharacter, Enemy).
# p_weapon_stats_for_scaling: Dictionary of weapon-specific stats for scaling certain effects (e.g., Bleed damage).
# duration_override: Optional duration (in seconds) to override the effect_data's default.
# potency_override: Optional potency multiplier to override the effect_data's default.
func apply_effect(
		effect_data: StatusEffectData,
		source_node: Node = null,
		p_weapon_stats_for_scaling: Dictionary = {},
		duration_override: float = -1.0,
		potency_override: float = -1.0
	):
	if not is_instance_valid(effect_data):
		push_error("ERROR (StatusEffectComponent): apply_effect called with invalid effect_data (null).")
		return
	if effect_data.id == &"":
		push_error("ERROR (StatusEffectComponent): StatusEffectData has an empty ID, cannot apply effect.")
		return

	var effect_id: StringName = effect_data.id
	var final_duration = duration_override if duration_override >= 0.0 else effect_data.duration
	
	# Check if the effect is already active on the owner
	if active_effects.has(effect_id):
		var existing_effect_entry = active_effects[effect_id]
		
		# If re-application refreshes duration, update and restart timers
		if effect_data.refresh_duration_on_reapply:
			existing_effect_entry.source = source_node
			existing_effect_entry.weapon_stats = p_weapon_stats_for_scaling.duplicate(true)
			existing_effect_entry.potency_override = potency_override # Update potency override on reapply

			# Update duration timer
			if final_duration > 0: # If it has a finite duration
				if is_instance_valid(existing_effect_entry.duration_timer):
					existing_effect_entry.duration_timer.wait_time = final_duration
					existing_effect_entry.duration_timer.start() # Restart timer
				else: # If timer was nullified (e.g., -1 duration changed to positive)
					var duration_timer_node = Timer.new()
					duration_timer_node.name = "DurationTimer_" + str(effect_id)
					duration_timer_node.wait_time = final_duration
					duration_timer_node.one_shot = true
					add_child(duration_timer_node)
					duration_timer_node.timeout.connect(Callable(self, "_on_effect_expired").bind(effect_id, duration_timer_node))
					duration_timer_node.start()
					existing_effect_entry.duration_timer = duration_timer_node
			else: # If duration is infinite (-1) or becomes 0
				if is_instance_valid(existing_effect_entry.duration_timer):
					existing_effect_entry.duration_timer.stop()
					existing_effect_entry.duration_timer.queue_free()
					existing_effect_entry.duration_timer = null

			# Update tick timer (for DoT/HoT effects)
			if effect_data.tick_interval > 0:
				if is_instance_valid(existing_effect_entry.tick_timer):
					existing_effect_entry.tick_timer.wait_time = effect_data.tick_interval
					existing_effect_entry.tick_timer.start() # Restart timer
				else: # If timer was nullified
					var tick_timer_node = Timer.new()
					tick_timer_node.name = "TickTimer_" + str(effect_id)
					tick_timer_node.wait_time = effect_data.tick_interval
					tick_timer_node.one_shot = false
					add_child(tick_timer_node)
					tick_timer_node.timeout.connect(Callable(self, "_on_status_effect_tick").bind(effect_id))
					tick_timer_node.start()
					existing_effect_entry.tick_timer = tick_timer_node
				
				if effect_data.tick_on_application: # Perform an immediate tick if specified
					_on_status_effect_tick(effect_id)
			else: # No ticking for this effect
				if is_instance_valid(existing_effect_entry.tick_timer):
					existing_effect_entry.tick_timer.stop()
					existing_effect_entry.tick_timer.queue_free()
					existing_effect_entry.tick_timer = null

		else: # If re-application does NOT refresh duration (e.g., unique effects)
			return # Do nothing on reapply

	else: # Effect is not active, create a new entry
		var new_effect_entry: Dictionary = {
			"data": effect_data,
			"duration_timer": null,
			"tick_timer": null,
			"stacks": 1, # Start with 1 stack
			"source": source_node,
			"weapon_stats": p_weapon_stats_for_scaling.duplicate(true),
			"potency_override": potency_override
		}
		
		# Create and start duration timer if duration is finite
		if final_duration > 0:
			var duration_timer_node = Timer.new()
			duration_timer_node.name = "DurationTimer_" + str(effect_id)
			duration_timer_node.wait_time = final_duration
			duration_timer_node.one_shot = true
			add_child(duration_timer_node)
			duration_timer_node.timeout.connect(Callable(self, "_on_effect_expired").bind(effect_id, duration_timer_node))
			duration_timer_node.start()
			new_effect_entry.duration_timer = duration_timer_node
		
		# Create and start tick timer if tick_interval is positive
		if effect_data.tick_interval > 0:
			var tick_timer_node = Timer.new()
			tick_timer_node.name = "TickTimer_" + str(effect_id)
			tick_timer_node.wait_time = effect_data.tick_interval
			tick_timer_node.one_shot = false # Ticks repeatedly
			add_child(tick_timer_node)
			tick_timer_node.timeout.connect(Callable(self, "_on_status_effect_tick").bind(effect_id))
			tick_timer_node.start()
			new_effect_entry.tick_timer = tick_timer_node
			if effect_data.tick_on_application: # Perform an immediate tick if specified
				_on_status_effect_tick(effect_id)

		active_effects[effect_id] = new_effect_entry
	
	_recalculate_and_apply_stat_modifiers() # Re-aggregate modifiers from all active effects
	emit_signal("status_effects_changed", get_parent()) # Notify owner of status changes


# Called repeatedly by a status effect's tick_timer.
func _on_status_effect_tick(effect_id: StringName):
	if not active_effects.has(effect_id): return # Ensure effect is still active
	
	var owner = get_parent()
	if not is_instance_valid(owner):
		push_warning("StatusEffectComponent: Owner invalid during tick for effect '", effect_id, "'.")
		return
	
	var effect_entry = active_effects[effect_id]
	var status_data = effect_entry.data as StatusEffectData
	
	# Apply all effects defined in StatusEffectData's 'effects_while_active' array.
	for effect in status_data.effects_while_active:
		if not is_instance_valid(effect): continue

		# --- Stat Modification Effects (e.g., Damage-over-Time) ---
		if effect is StatModificationEffectData:
			var stat_mod = effect as StatModificationEffectData
			
			# Special handling for Health modification (typically damage over time)
			if stat_mod.stat_key == GameStatConstants.KEY_NAMES[GameStatConstants.Keys.MAX_HEALTH] \
			and stat_mod.modification_type == &"flat_add":
				var damage_per_tick = stat_mod.get_value()
				var actual_potency_override = effect_entry.get("potency_override", -1.0)
				# Apply potency override if specified and valid
				if actual_potency_override >= 0.0:
					damage_per_tick *= actual_potency_override

				var final_tick_damage = absf(damage_per_tick) # Ensure damage is positive
				final_tick_damage = maxf(1.0, final_tick_damage) # Ensure at least 1 damage
				
				# Owner must have a 'take_damage' method
				if owner.has_method("take_damage"):
					owner.take_damage(final_tick_damage, effect_entry.source)
				else:
					push_warning("StatusEffectComponent: Owner '", owner.name, "' does not have 'take_damage' method for effect '", effect_id, "'.")
		# Add other specific tick effects here if needed (e.g., resource regeneration)


# Called when an effect's duration timer expires.
# effect_id_expired: The ID of the effect that expired.
# duration_timer_ref: Reference to the timer that triggered the expiration.
func _on_effect_expired(effect_id_expired: StringName, duration_timer_ref: Timer):
	if active_effects.has(effect_id_expired):
		var effect_entry = active_effects[effect_id_expired]
		var status_data_to_check = effect_entry.data as StatusEffectData
		
		# Stop and free the tick timer if it exists
		var tick_timer = effect_entry.get("tick_timer") as Timer
		if is_instance_valid(tick_timer):
			tick_timer.stop()
			tick_timer.queue_free()

		# Remove the effect from active effects
		active_effects.erase(effect_id_expired)
		_recalculate_and_apply_stat_modifiers() # Re-aggregate modifiers after removal
		emit_signal("status_effects_changed", get_parent()) # Notify owner of status changes
		
		# NEW: Check if this expired effect should trigger another status effect
		if is_instance_valid(status_data_to_check) and status_data_to_check.next_status_effect_on_expire != &"":
			var next_effect_id = status_data_to_check.next_status_effect_on_expire
			
			# Construct the path to the next status effect resource based on conventions
			# This now matches your assumed file structure: res://DataResources/StatusEffects/effect_id_status.tres
			var next_effect_path = "res://DataResources/StatusEffects/" + str(next_effect_id) + "_status.tres"
			
			if ResourceLoader.exists(next_effect_path):
				var next_effect_data = load(next_effect_path) as StatusEffectData
				if is_instance_valid(next_effect_data):
					# Apply the next effect, passing source and weapon stats for continuity
					apply_effect(next_effect_data, effect_entry.source, effect_entry.weapon_stats)
				else:
					push_warning("StatusEffectComponent: Loaded next status effect data at '", next_effect_path, "' is not a valid StatusEffectData resource.")
			else:
				push_warning("StatusEffectComponent: Could not find next status effect resource at: " + next_effect_path)
	
	# Always free the duration timer, even if the effect was already removed (e.g., manually)
	if is_instance_valid(duration_timer_ref):
		duration_timer_ref.queue_free()
		
# Manually removes a status effect from the owner.
func remove_effect(effect_id_to_remove: StringName):
	if active_effects.has(effect_id_to_remove):
		var effect_entry = active_effects[effect_id_to_remove]
		
		# Stop and free associated timers
		var duration_timer = effect_entry.get("duration_timer") as Timer
		if is_instance_valid(duration_timer):
			duration_timer.stop()
			duration_timer.queue_free()
		var tick_timer = effect_entry.get("tick_timer") as Timer
		if is_instance_valid(tick_timer):
			tick_timer.stop()
			tick_timer.queue_free()
			
		active_effects.erase(effect_id_to_remove)
		_recalculate_and_apply_stat_modifiers() # Re-aggregate modifiers after removal
		emit_signal("status_effects_changed", get_parent()) # Notify owner of status changes


# Recalculates the aggregated stat modifiers from all currently active effects.
# This function populates the 'current_stat_modifiers' dictionary, which is then
# used by getter methods (e.g., get_sum_of_additive_modifiers).
#
# IMPORTANT: For these temporary modifiers to affect the owner's actual stats
# (e.g., PlayerStats.gd), the owner's PlayerStats instance MUST be updated
# to query these values from StatusEffectComponent or to maintain its own
# temporary modifier tracking system. This is a crucial next step for PlayerStats.gd.
func _recalculate_and_apply_stat_modifiers():
	current_stat_modifiers.clear() # Clear previous calculations
	var owner = get_parent()
	if not is_instance_valid(owner):
		push_error("StatusEffectComponent: Owner is invalid during stat recalculation."); return

	# Iterate through all active effects and aggregate their stat modifications
	for effect_id in active_effects:
		var effect_entry = active_effects[effect_id]
		var status_effect_data_res: StatusEffectData = effect_entry.data
		
		if is_instance_valid(status_effect_data_res) and not status_effect_data_res.effects_while_active.is_empty():
			for actual_effect_data_res in status_effect_data_res.effects_while_active:
				if not is_instance_valid(actual_effect_data_res): continue

				# --- Stat Modification Effects (Aggregating into local dictionary) ---
				if actual_effect_data_res is StatModificationEffectData:
					var stat_mod_effect = actual_effect_data_res as StatModificationEffectData
					var mod_value = stat_mod_effect.get_value()
					var actual_potency_override = effect_entry.get("potency_override", -1.0)
					
					# Apply potency override to the modification value
					if actual_potency_override >= 0.0:
						mod_value *= actual_potency_override
					
					# Apply stack count to the modification value
					mod_value *= effect_entry.stacks
					
					var key_to_mod: StringName = stat_mod_effect.stat_key # This should already be a StringName
					var mod_type: StringName = &"" + str(stat_mod_effect.modification_type) # Ensure StringName

					# Aggregate based on modification type.
					# (Excluding health flat_add, as it's handled by ticks)
					if not (key_to_mod == GameStatConstants.KEY_NAMES[GameStatConstants.Keys.MAX_HEALTH] \
					and mod_type == &"flat_add"):
						
						match mod_type:
							&"flat_add":
								current_stat_modifiers[key_to_mod] = current_stat_modifiers.get(key_to_mod, 0.0) + mod_value
							&"percent_add_to_base":
								current_stat_modifiers[key_to_mod] = current_stat_modifiers.get(key_to_mod, 0.0) + mod_value
							&"percent_mult_final":
								# Multipliers stack multiplicatively here.
								# Ensure initial value is 1.0 for these.
								current_stat_modifiers[key_to_mod] = current_stat_modifiers.get(key_to_mod, 1.0) * (1.0 + mod_value)
							&"override_value":
								current_stat_modifiers[key_to_mod] = mod_value
							_:
								push_warning("StatusEffectComponent: Unhandled modification type '", mod_type, "' for stat '", key_to_mod, "'.")
				
				# --- Custom Flag Effects (Route to PlayerStats.gd) ---
				elif actual_effect_data_res is CustomFlagEffectData:
					var flag_effect = actual_effect_data_res as CustomFlagEffectData
					# Flags are directly applied to the owner's PlayerStats (if it exists)
					if owner.has_node("PlayerStats"):
						var p_stats = owner.get_node("PlayerStats") as PlayerStats
						if is_instance_valid(p_stats) and p_stats.has_method("apply_custom_flag"):
							p_stats.apply_custom_flag(flag_effect)
						else:
							push_warning("StatusEffectComponent: Owner's PlayerStats node invalid or missing 'apply_custom_flag' for flag '", flag_effect.flag_key, "'.")
					else:
						push_warning("StatusEffectComponent: Owner has no 'PlayerStats' node to apply flag '", flag_effect.flag_key, "'.")
				
				# --- Trigger Ability Effects (Currently handled by owner) ---
				elif actual_effect_data_res is TriggerAbilityEffectData:
					# Trigger abilities are generally handled by the owner (PlayerCharacter, Enemy)
					# based on status effect flags/states, not directly by StatusEffectComponent
					pass
				
				else:
					push_warning("StatusEffectComponent: Status effect contains unhandled effect type: ", actual_effect_data_res.get_class())
	
	# Signal owner that status effects (and their aggregated modifiers) have changed.
	# The owner should then re-query its stats.
	emit_signal("status_effects_changed", owner)


# --- Getter Functions for aggregated temporary modifiers ---
# These functions allow the owner's PlayerStats (or other systems) to query
# the total temporary modifiers applied by active status effects.
#
# Once PlayerStats.gd is updated to manage temporary modifiers directly,
# these methods might become internal or less frequently used, as PlayerStats
# would then handle the full aggregation.

func get_sum_of_additive_modifiers(stat_key: StringName) -> float:
	# Returns the sum of 'flat_add' and 'percent_add_to_base' modifiers aggregated by this component.
	# This requires careful consideration of how PlayerStats.gd will apply these.
	return current_stat_modifiers.get(stat_key, 0.0)

func get_product_of_multiplicative_modifiers(stat_key: StringName) -> float:
	# Returns the product of 'percent_mult_final' modifiers aggregated by this component.
	# This requires careful consideration of how PlayerStats.gd will apply these.
	return current_stat_modifiers.get(stat_key, 1.0)

func get_flat_sum_modifier(stat_key: StringName) -> float:
	# A more generic getter for flat additions.
	return current_stat_modifiers.get(stat_key, 0.0)

func has_status_effect(effect_id: StringName) -> bool:
	return active_effects.has(effect_id)

func get_effect_stacks(effect_id: StringName) -> int:
	if active_effects.has(effect_id): return active_effects[effect_id].stacks
	return 0

func get_effect_data_resource(effect_id: StringName) -> StatusEffectData:
	if active_effects.has(effect_id): return active_effects[effect_id].data
	return null

# Note: The 'has_flag' method from the original script is removed here.
# Flags are now directly applied to PlayerStats.gd via apply_custom_flag(),
# and PlayerStats.gd itself will have the authoritative 'get_flag' method.
# StatusEffectComponent's role is to *apply* the flag, not store or query it directly.
