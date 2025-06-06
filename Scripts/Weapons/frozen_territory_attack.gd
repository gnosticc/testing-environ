extends Node2D 

@export var orbit_distance: float = 60.0  
const ROTATION_DURATION: float = 3.0     
const ORBIT_SPEED_BASE: float = TAU / ROTATION_DURATION 
var current_orbit_speed: float = ORBIT_SPEED_BASE
var initial_orbit_angle_offset: float = 0.0 

var final_damage_amount: int = 8 
var final_aoe_scale: Vector2 = Vector2(1,1) 
const SLOW_FACTOR: float = 0.5 
var final_slow_duration: float = 2.0

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite") as AnimatedSprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D            
@onready var effect_duration_timer: Timer = get_node_or_null("EffectDurationTimer") as Timer 
@onready var collision_shape_for_scaling: CollisionShape2D = get_node_or_null("DamageArea/CollisionShape2D") as CollisionShape2D

var current_angle: float = 0.0
var _enemies_in_area: Array[Node2D] = [] 
var _hit_this_pulse: Array[Node2D] = []  
var _hit_reset_timer: Timer 
var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}
var actual_effect_duration: float = ROTATION_DURATION 


func _ready():
	if not is_instance_valid(animated_sprite): print("WARNING (FrozenTerritoryAttack): AnimatedSprite missing.")
	if not is_instance_valid(damage_area): print("ERROR (FrozenTerritoryAttack): DamageArea missing."); call_deferred("queue_free"); return
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_damage_area_body_entered")):
			damage_area.body_entered.connect(self._on_damage_area_body_entered)
		if not damage_area.is_connected("body_exited", Callable(self, "_on_damage_area_body_exited")):
			damage_area.body_exited.connect(self._on_damage_area_body_exited)
	
	if not is_instance_valid(effect_duration_timer): print("ERROR (FrozenTerritoryAttack): EffectDurationTimer missing!"); call_deferred("queue_free"); return
	else:
		effect_duration_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		effect_duration_timer.one_shot = true 
		if not effect_duration_timer.is_connected("timeout", Callable(self, "queue_free")):
			effect_duration_timer.timeout.connect(self.queue_free)
	
	_hit_reset_timer = Timer.new(); _hit_reset_timer.name = "HitResetTimerInternal"
	_hit_reset_timer.process_mode = Node.PROCESS_MODE_ALWAYS; _hit_reset_timer.one_shot = false 
	add_child(_hit_reset_timer)
	if not _hit_reset_timer.is_connected("timeout", Callable(self, "_on_internal_hit_reset_timeout")):
		_hit_reset_timer.timeout.connect(self._on_internal_hit_reset_timeout)

	if _stats_have_been_set: _apply_all_stats_and_start_timers()
	else: _apply_visual_scale() 

	current_angle = initial_orbit_angle_offset 
	_update_orbit_position() 
	
	if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("active"):
		animated_sprite.play("active")


func _physics_process(delta: float):
	if is_instance_valid(effect_duration_timer) and not effect_duration_timer.is_stopped():
		current_angle += current_orbit_speed * delta
		current_angle = fmod(current_angle, TAU) 
		_update_orbit_position()

func _update_orbit_position():
	position.x = orbit_distance * cos(current_angle)
	position.y = orbit_distance * sin(current_angle)

func set_owner_stats(stats: Dictionary): 
	_received_stats = stats.duplicate(true)
	_stats_have_been_set = true
	if is_inside_tree(): _apply_all_stats_and_start_timers()

func _apply_all_stats_and_start_timers():
	if not _stats_have_been_set: return
	if not (is_instance_valid(effect_duration_timer) and is_instance_valid(_hit_reset_timer)):
		print("ERROR (FrozenTerritory): Timers not valid in _apply_all_stats_and_start_timers.")
		return

	var base_w_damage = _received_stats.get("damage", 8)
	var p_dmg_mult = _received_stats.get("damage_multiplier", 1.0)
	var p_flat_dmg = _received_stats.get("base_damage_bonus", 0.0)
	final_damage_amount = int(round(base_w_damage * p_dmg_mult + p_flat_dmg))
	
	var weapon_inherent_scl_val = _received_stats.get("inherent_visual_scale", Vector2(1.0, 1.0))
	var weapon_inherent_base_scale: Vector2
	if weapon_inherent_scl_val is Vector2: weapon_inherent_base_scale = weapon_inherent_scl_val
	elif weapon_inherent_scl_val is float: weapon_inherent_base_scale = Vector2(weapon_inherent_scl_val, weapon_inherent_scl_val)
	else: weapon_inherent_base_scale = Vector2(1.0, 1.0)
	
	var p_aoe_mult = _received_stats.get("aoe_area_multiplier", 1.0) 
	final_aoe_scale.x = weapon_inherent_base_scale.x * p_aoe_mult
	final_aoe_scale.y = weapon_inherent_base_scale.y * p_aoe_mult
	
	var p_effect_dur_mult = _received_stats.get("effect_duration_multiplier", 1.0)
	var base_slow_dur = _received_stats.get("slow_duration", 2.0) 
	final_slow_duration = base_slow_dur * p_effect_dur_mult 
	
	var attack_speed_multiplier = _received_stats.get("attack_speed_multiplier", 1.0)
	if attack_speed_multiplier <= 0: attack_speed_multiplier = 0.01
	current_orbit_speed = ORBIT_SPEED_BASE * attack_speed_multiplier
	if is_instance_valid(animated_sprite): animated_sprite.speed_scale = attack_speed_multiplier

	var base_effect_duration = _received_stats.get("base_effect_duration", ROTATION_DURATION) 
	actual_effect_duration = base_effect_duration * p_effect_dur_mult 
	
	effect_duration_timer.wait_time = actual_effect_duration 
	if not effect_duration_timer.is_stopped(): effect_duration_timer.stop()
	effect_duration_timer.start()

	var base_pulse_interval = _received_stats.get("cooldown", 0.5) 
	_hit_reset_timer.wait_time = base_pulse_interval / attack_speed_multiplier 
	if _hit_reset_timer.is_stopped(): _hit_reset_timer.start()
	else: _hit_reset_timer.stop(); _hit_reset_timer.start()

	orbit_distance = _received_stats.get("orbit_distance", 60.0) 
	initial_orbit_angle_offset = _received_stats.get("initial_angle_offset", 0.0) 
	current_angle = initial_orbit_angle_offset 
	
	_apply_visual_scale()
	_update_orbit_position() 


func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_aoe_scale
	if is_instance_valid(damage_area): damage_area.scale = final_aoe_scale


func _on_damage_area_body_entered(body: Node2D):
	if is_instance_valid(effect_duration_timer) and effect_duration_timer.is_stopped(): return 
	if body.is_in_group("enemies") and not _enemies_in_area.has(body): 
		_enemies_in_area.append(body); _try_damage_enemy(body) 

func _on_damage_area_body_exited(body: Node2D):
	if body.is_in_group("enemies") and _enemies_in_area.has(body): _enemies_in_area.erase(body)
	if _hit_this_pulse.has(body): _hit_this_pulse.erase(body)

func _on_internal_hit_reset_timeout():
	_hit_this_pulse.clear() 
	var current_enemies = _enemies_in_area.duplicate() 
	for enemy_node in current_enemies:
		if is_instance_valid(enemy_node): _try_damage_enemy(enemy_node)
		else: _enemies_in_area.erase(enemy_node) 

func _try_damage_enemy(enemy_node: Node2D):
	if not _hit_this_pulse.has(enemy_node): 
		if enemy_node.has_method("take_damage"): enemy_node.take_damage(final_damage_amount)
		if enemy_node.has_method("apply_slow_debuff"): enemy_node.apply_slow_debuff(final_slow_duration, SLOW_FACTOR)
		_hit_this_pulse.append(enemy_node) 
