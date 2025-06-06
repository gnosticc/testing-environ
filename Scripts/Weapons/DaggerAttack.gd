extends Node2D

var final_damage_amount: int = 10
var final_applied_scale: Vector2 = Vector2(1.0, 1.0) 
var facing_direction: Vector2 = Vector2.RIGHT 
var current_frame_index_to_display: int = 0

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite") as AnimatedSprite2D
@onready var display_duration_timer: Timer = get_node_or_null("DisplayDurationTimer") as Timer
@onready var damage_area: Area2D = get_node_or_null("DamageArea") as Area2D

const SLASH_ANIMATION_NAME_IN_SPRITEFRAMES = "slash" 
const BASE_DISPLAY_DURATION: float = 0.1 
const FADE_DURATION: float = 0.15 

var actual_display_duration: float = BASE_DISPLAY_DURATION
var current_attack_speed_multiplier: float = 1.0

var _enemies_hit_this_slash: Array[Node2D] = []
var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}

func _ready():
	if not is_instance_valid(animated_sprite): print("ERROR (DaggerAttack): AnimatedSprite missing."); call_deferred("queue_free"); return
	if not is_instance_valid(damage_area): print("ERROR (DaggerAttack): DamageArea missing."); call_deferred("queue_free"); return
	else:
		if not damage_area.is_connected("body_entered", Callable(self, "_on_damage_area_body_entered")):
			damage_area.body_entered.connect(self._on_damage_area_body_entered)
	if not is_instance_valid(display_duration_timer): print("ERROR (DaggerAttack): DisplayDurationTimer missing!"); call_deferred("queue_free"); return
	else:
		display_duration_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		display_duration_timer.one_shot = true
		if not display_duration_timer.is_connected("timeout", Callable(self, "_on_display_duration_timer_timeout")):
			display_duration_timer.timeout.connect(self._on_display_duration_timer_timeout)
	
	if _stats_have_been_set: 
		_apply_all_effects_and_start_timer()

func set_attack_properties(p_direction: Vector2, p_attack_stats: Dictionary, p_frame_index: int):
	_received_stats = p_attack_stats.duplicate(true)
	_stats_have_been_set = true
	current_frame_index_to_display = p_frame_index
	facing_direction = p_direction.normalized() if p_direction.length_squared() > 0 else Vector2.RIGHT
	
	if is_inside_tree(): 
		_apply_all_effects_and_start_timer()

func _apply_all_effects_and_start_timer():
	if not _stats_have_been_set: return
	if not (is_instance_valid(animated_sprite) and is_instance_valid(damage_area) and is_instance_valid(display_duration_timer)):
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
	final_applied_scale.x = weapon_inherent_base_scale.x * p_aoe_mult
	final_applied_scale.y = weapon_inherent_base_scale.y * p_aoe_mult
	
	_apply_visual_scale()

	current_attack_speed_multiplier = _received_stats.get("attack_speed_multiplier", 1.0)
	if current_attack_speed_multiplier <= 0: current_attack_speed_multiplier = 0.01
	actual_display_duration = BASE_DISPLAY_DURATION / current_attack_speed_multiplier
	
	display_duration_timer.wait_time = actual_display_duration
	if not display_duration_timer.is_stopped(): display_duration_timer.stop()
	display_duration_timer.start()
	
	if is_instance_valid(animated_sprite): animated_sprite.speed_scale = current_attack_speed_multiplier

	if facing_direction != Vector2.ZERO: self.rotation = facing_direction.angle() - PI 
	_setup_visual_frame(current_frame_index_to_display)

func _apply_visual_scale():
	if is_instance_valid(animated_sprite): animated_sprite.scale = final_applied_scale
	if is_instance_valid(damage_area): damage_area.scale = final_applied_scale


func _setup_visual_frame(frame_idx: int):
	if not is_instance_valid(animated_sprite): return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(SLASH_ANIMATION_NAME_IN_SPRITEFRAMES):
		animated_sprite.animation = SLASH_ANIMATION_NAME_IN_SPRITEFRAMES 
		var frame_count = animated_sprite.sprite_frames.get_frame_count(SLASH_ANIMATION_NAME_IN_SPRITEFRAMES)
		var target_frame = frame_idx
		if not (frame_idx >= 0 and frame_idx < frame_count): target_frame = 0
		
		animated_sprite.animation = SLASH_ANIMATION_NAME_IN_SPRITEFRAMES 
		animated_sprite.stop(); animated_sprite.frame = target_frame 
	else: 
		print("WARNING (DaggerAttack '", name, "'): Animation '", SLASH_ANIMATION_NAME_IN_SPRITEFRAMES, "' not found.")


func _on_display_duration_timer_timeout():
	if is_instance_valid(damage_area):
		damage_area.monitoring = false; damage_area.monitorable = false
	_start_fade_out()

func _start_fade_out():
	var tween = create_tween().set_parallel(true) 
	if is_instance_valid(animated_sprite):
		tween.tween_property(animated_sprite, "modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(queue_free)


func _on_damage_area_body_entered(body: Node2D):
	if _enemies_hit_this_slash.has(body): return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(final_damage_amount); _enemies_hit_this_slash.append(body)
