# FIX: Added a public function to check the ready status of Philosopher's Stone.
# Added a debug print for Self-Experimentation.
# =====================================================================
class_name ExperimentalMaterialsManager
extends Node2D

@export var vial_projectile_scene: PackedScene
@export var chemtrail_scene: PackedScene

var _specific_stats: Dictionary
var _owner_player_stats: PlayerStats
var _weapon_manager: WeaponManager
var _owner_player: PlayerCharacter
var _is_initialized: bool = false
var _is_philosophers_stone_ready: bool = true # FIX: Store runtime state separately

@onready var primary_attack_timer: Timer = $PrimaryAttackTimer
@onready var self_experimentation_timer: Timer = $SelfExperimentationTimer
@onready var philosophers_stone_cooldown_timer: Timer = $PhilosophersStoneCooldownTimer
@onready var chemtrail_spawn_timer: Timer = $ChemtrailSpawnTimer

var _attack_sequence_index: int = 0

func _ready():
	primary_attack_timer.timeout.connect(_on_primary_attack_timer_timeout)
	self_experimentation_timer.timeout.connect(_on_self_experimentation_timer_timeout)
	philosophers_stone_cooldown_timer.timeout.connect(_on_philosophers_stone_cooldown_ready)
	chemtrail_spawn_timer.timeout.connect(_on_chemtrail_spawn_timer_timeout)
	CombatEvents.catalytic_reaction_requested.connect(_on_catalytic_reaction_requested)
	
	if _is_initialized:
		update_stats(_specific_stats)

func initialize(p_stats: Dictionary, p_player_stats: PlayerStats, p_weapon_manager: WeaponManager):
	_specific_stats = p_stats
	_owner_player_stats = p_player_stats
	_weapon_manager = p_weapon_manager
	_owner_player = p_player_stats.get_parent()
	_is_initialized = true
	
	# Set initial state from blueprint
	_is_philosophers_stone_ready = p_stats.get("philosophers_stone_ready", true)
	
	if is_node_ready():
		update_stats(p_stats)

func update_stats(new_stats: Dictionary):
	_specific_stats = new_stats

	var base_cooldown = float(_specific_stats.get("cooldown", 1.5))
	var final_cooldown = base_cooldown / _owner_player_stats.get_final_stat(PlayerStatKeys.Keys.ATTACK_SPEED_MULTIPLIER)
	primary_attack_timer.wait_time = max(0.1, final_cooldown)

	if primary_attack_timer.is_stopped():
		primary_attack_timer.start()

	if _specific_stats.get("has_self_experimentation", false):
		self_experimentation_timer.wait_time = float(_specific_stats.get("self_experimentation_cooldown", 12.0))
		if self_experimentation_timer.is_stopped():
			self_experimentation_timer.start()
	else:
		if not self_experimentation_timer.is_stopped():
			self_experimentation_timer.stop()

	if _specific_stats.get("has_leaky_canisters", false):
		if chemtrail_spawn_timer.is_stopped():
			chemtrail_spawn_timer.start()
	else:
		if not chemtrail_spawn_timer.is_stopped():
			chemtrail_spawn_timer.stop()

func _on_primary_attack_timer_timeout():
	if not is_instance_valid(_owner_player): return
	if not is_instance_valid(vial_projectile_scene): return

	var target_direction = Vector2.ZERO
	match _attack_sequence_index:
		0: target_direction = Vector2.LEFT
		1: target_direction = Vector2.UP
		2: target_direction = Vector2.RIGHT
		3: target_direction = Vector2.DOWN
	
	_spawn_vial(target_direction, false)
	_attack_sequence_index = (_attack_sequence_index + 1) % 4

	if _specific_stats.get("has_dual_lobs", false):
		_spawn_vial(Vector2.ZERO, true)

func _spawn_vial(direction: Vector2, is_random_offset: bool):
	var vial = vial_projectile_scene.instantiate()
	get_tree().current_scene.add_child(vial)
	vial.global_position = _owner_player.global_position
	if vial.has_method("initialize"):
		vial.initialize(direction, is_random_offset, _specific_stats, _owner_player_stats)

func _on_self_experimentation_timer_timeout():
	var buffs = [
		"res://DataResources/StatusEffects/Alchemist/self_experimentation_damage_buff.tres",
		"res://DataResources/StatusEffects/Alchemist/self_experimentation_speed_buff.tres",
		"res://DataResources/StatusEffects/Alchemist/self_experimentation_movespeed_buff.tres"
	]
	var chosen_buff_path = buffs.pick_random()
	var buff_data = load(chosen_buff_path) as StatusEffectData
	
	if is_instance_valid(buff_data) and is_instance_valid(_owner_player.status_effect_component):
		print_debug("Self-Experimentation: Applying buff '", buff_data.display_name, "' for ", _specific_stats.get("self_experimentation_duration", 6.0), " seconds.")
		var duration = float(_specific_stats.get("self_experimentation_duration", 6.0))
		_owner_player.status_effect_component.apply_effect(buff_data, _owner_player, {}, duration)

func _on_catalytic_reaction_requested(enemy: BaseEnemy, weapon_tags: Array[StringName]):
	if not _is_initialized or not is_instance_valid(enemy): return

	if weapon_tags.has(&"physical"):
		call_deferred("_spawn_physical_reaction", enemy)
	
	if weapon_tags.has(&"magical"):
		call_deferred("_spawn_magical_reaction", enemy)

func _spawn_physical_reaction(enemy: BaseEnemy):
	if not is_instance_valid(enemy): return
	var caustic_status = load("res://DataResources/StatusEffects/Alchemist/caustic_injection_status.tres") as StatusEffectData
	if is_instance_valid(caustic_status):
		enemy.status_effect_component.apply_effect(caustic_status, _owner_player, _specific_stats)

func _spawn_magical_reaction(enemy: BaseEnemy):
	if not is_instance_valid(enemy): return
	var eruption_scene = load("res://Scenes/Weapons/Advanced/Effect Scenes/VolatileEruption.tscn")
	if is_instance_valid(eruption_scene):
		var eruption = eruption_scene.instantiate()
		get_tree().current_scene.add_child(eruption)
		eruption.global_position = enemy.global_position
		if eruption.has_method("initialize"):
			eruption.initialize(_specific_stats, _owner_player_stats)

func _on_philosophers_stone_cooldown_ready():
	_is_philosophers_stone_ready = true
	print_debug("Philosopher's Stone is ready.")

func _on_chemtrail_spawn_timer_timeout():
	if not is_instance_valid(chemtrail_scene): return
	var segment = chemtrail_scene.instantiate()
	var effects_container = get_tree().current_scene.get_node_or_null("EffectsContainer")
	if is_instance_valid(effects_container):
		effects_container.add_child(segment)
	else:
		get_tree().current_scene.add_child(segment)

	segment.global_position = _owner_player.global_position
	if segment.has_method("initialize"):
		segment.initialize(_specific_stats, _owner_player_stats)

func trigger_philosophers_stone_cooldown():
	_is_philosophers_stone_ready = false
	print_debug("Philosopher's Stone has been used. Cooldown started (360s).")
	philosophers_stone_cooldown_timer.start()

func is_philosophers_stone_ready() -> bool:
	return _is_philosophers_stone_ready
