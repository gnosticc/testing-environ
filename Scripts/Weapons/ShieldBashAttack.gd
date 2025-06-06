extends Node2D

var final_damage_amount: int = 10
var final_applied_aoe_scale: Vector2 = Vector2(1.0, 1.0) 
var final_knockback_distance: float = 40.0
var facing_direction: Vector2 = Vector2.RIGHT 
var player_node_ref: PlayerCharacter 

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite") as AnimatedSprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D
@onready var duration_timer: Timer = get_node_or_null("DurationTimer") as Timer

const BASH_ANIMATION_NAME = "bash" 
const BASE_ATTACK_DURATION: float = 0.4 
var actual_attack_duration: float = BASE_ATTACK_DURATION
var current_attack_speed_multiplier: float = 1.0 

var _enemies_hit_this_attack: Array[Node2D] = []
var _stats_have_been_set: bool = false 
var _received_stats: Dictionary = {} 

func _ready():
	if not is_instance_valid(animated_sprite): print("ERROR (ShieldBash): AnimatedSprite missing."); call_deferred("queue_free"); return
	if not is_instance_valid(damage_area): print("ERROR (ShieldBash): DamageArea missing."); call_deferred("queue_free"); return
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_damage_area_body_entered")):
			damage_area.body_entered.connect(self._on_damage_area_body_entered)
	if not is_instance_valid(duration_timer): print("ERROR (ShieldBash): DurationTimer missing!"); call_deferred("queue_free"); return
	else:
		duration_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		duration_timer.one_shot = true
		if not duration_timer.is_connected("timeout", Callable(self, "queue_free")):
			duration_timer.timeout.connect(self.queue_free)
	
	if _stats_have_been_set: 
		_apply_visuals_and_timer_logic()

func set_attack_properties(p_direction: Vector2, p_player_ref: PlayerCharacter, p_attack_stats: Dictionary):
	_received_stats = p_attack_stats.duplicate(true) 
	_stats_have_been_set = true

	facing_direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	player_node_ref = p_player_ref
	
	if is_inside_tree(): 
		_apply_visuals_and_timer_logic()

func _apply_visuals_and_timer_logic():
	if not _stats_have_been_set: return
	if not (is_instance_valid(animated_sprite) and is_instance_valid(damage_area) and is_instance_valid(duration_timer)):
		print("ERROR (ShieldBash): Critical nodes missing in _apply_visuals_and_timer_logic.")
		call_deferred("queue_free"); return

	var base_w_damage = _received_stats.get("damage", 10)
	var p_dmg_mult = _received_stats.get("damage_multiplier", 1.0)
	var p_flat_dmg = _received_stats.get("base_damage_bonus", 0.0)
	final_damage_amount = int(round(base_w_damage * p_dmg_mult + p_flat_dmg))
	
	var weapon_inherent_scl_val = _received_stats.get("inherent_visual_scale", Vector2(1.0, 1.0))
	var weapon_inherent_base_scale: Vector2
	if weapon_inherent_scl_val is Vector2: weapon_inherent_base_scale = weapon_inherent_scl_val
	elif weapon_inherent_scl_val is float: weapon_inherent_base_scale = Vector2(weapon_inherent_scl_val, weapon_inherent_scl_val)
	else: weapon_inherent_base_scale = Vector2(1.0, 1.0)
		
	var p_aoe_mult = _received_stats.get("aoe_area_multiplier", 1.0) 
	final_applied_aoe_scale.x = weapon_inherent_base_scale.x * p_aoe_mult
	final_applied_aoe_scale.y = weapon_inherent_base_scale.y * p_aoe_mult
	
	final_knockback_distance = _received_stats.get("knockback_distance", 40.0) 
	current_attack_speed_multiplier = _received_stats.get("attack_speed_multiplier", 1.0)

	if facing_direction != Vector2.ZERO: self.rotation = facing_direction.angle() - PI 
	
	_apply_visual_scale()

	if current_attack_speed_multiplier <= 0: current_attack_speed_multiplier = 0.01
	actual_attack_duration = BASE_ATTACK_DURATION / current_attack_speed_multiplier
	
	duration_timer.wait_time = actual_attack_duration
	if not duration_timer.is_stopped(): duration_timer.stop()
	duration_timer.start()

	animated_sprite.speed_scale = current_attack_speed_multiplier
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(BASH_ANIMATION_NAME):
		animated_sprite.play(BASH_ANIMATION_NAME)

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_aoe_scale
	if is_instance_valid(damage_area): damage_area.scale = final_applied_aoe_scale 

func _on_damage_area_body_entered(body: Node2D):
	if _enemies_hit_this_attack.has(body): return
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"): body.take_damage(final_damage_amount)
		if body.has_method("apply_knockback") and is_instance_valid(player_node_ref):
			var knockback_dir = (body.global_position - player_node_ref.global_position).normalized()
			if knockback_dir.length_squared() == 0: 
				knockback_dir = (body.global_position - self.global_position).normalized() 
				if knockback_dir.length_squared() == 0: knockback_dir = facing_direction 
			body.apply_knockback(knockback_dir, final_knockback_distance) 
		_enemies_hit_this_attack.append(body)
