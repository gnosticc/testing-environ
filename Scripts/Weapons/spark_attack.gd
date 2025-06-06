extends Area2D

var final_damage_amount: int = 14 
var final_speed: float = 250.0    
var final_applied_scale: Vector2 = Vector2(1,1)
var direction: Vector2 = Vector2.RIGHT 
var max_hits: int = 1; var hit_count: int = 0

@onready var spark_visual: AnimatedSprite2D = get_node_or_null("spark_animation") as AnimatedSprite2D
@onready var lifetime_timer: Timer = get_node_or_null("LifetimeTimer") as Timer
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

const FLY_ANIMATION_NAME = "spark_attack_frames" 
var _stats_have_been_set: bool = false
var _received_stats: Dictionary = {}

func _ready():
	if not is_instance_valid(spark_visual): print("WARNING (SparkAttack): spark_animation missing.")
	if not is_instance_valid(collision_shape): print("WARNING (SparkAttack): CollisionShape2D missing.")

	if not is_instance_valid(lifetime_timer): print("ERROR (SparkAttack): LifetimeTimer missing!"); call_deferred("queue_free"); return
	else:
		lifetime_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		lifetime_timer.wait_time = 3.0; lifetime_timer.one_shot = true 
		if not lifetime_timer.is_connected("timeout", Callable(self, "queue_free")):
			lifetime_timer.timeout.connect(self.queue_free)
	
	if direction != Vector2.ZERO: rotation = direction.angle() # Adjust if sprite faces left
	
	if _stats_have_been_set: _apply_all_stats_effects()
	else: 
		_apply_visual_scale()
		if is_instance_valid(spark_visual) and spark_visual.sprite_frames and spark_visual.sprite_frames.has_animation(FLY_ANIMATION_NAME):
			spark_visual.play(FLY_ANIMATION_NAME)


func _physics_process(delta: float):
	global_position += direction * final_speed * delta

func set_owner_stats(stats: Dictionary):
	_received_stats = stats.duplicate(true)
	_stats_have_been_set = true
	if is_inside_tree(): _apply_all_stats_effects()

func _apply_all_stats_effects():
	if not _stats_have_been_set: return

	var base_w_damage = _received_stats.get("damage", 14) 
	var p_dmg_mult = _received_stats.get("damage_multiplier", 1.0)
	var p_flat_dmg = _received_stats.get("base_damage_bonus", 0.0)
	final_damage_amount = int(round(base_w_damage * p_dmg_mult + p_flat_dmg))
	
	var base_w_speed = _received_stats.get("speed", 250.0)
	var p_proj_spd_mult = _received_stats.get("projectile_speed_multiplier", 1.0)
	final_speed = base_w_speed * p_proj_spd_mult
	
	var weapon_inherent_scl_val = _received_stats.get("inherent_visual_scale", Vector2(1.0, 1.0))
	var weapon_inherent_base_scale: Vector2
	if weapon_inherent_scl_val is Vector2: weapon_inherent_base_scale = weapon_inherent_scl_val
	elif weapon_inherent_scl_val is float: weapon_inherent_base_scale = Vector2(weapon_inherent_scl_val, weapon_inherent_scl_val)
	else: weapon_inherent_base_scale = Vector2(1.0, 1.0)
	
	var p_proj_size_mult = _received_stats.get("projectile_size_multiplier", 1.0)
	final_applied_scale.x = weapon_inherent_base_scale.x * p_proj_size_mult
	final_applied_scale.y = weapon_inherent_base_scale.y * p_proj_size_mult
	
	_apply_visual_scale()
	
	if is_instance_valid(spark_visual): 
		if spark_visual.sprite_frames and spark_visual.sprite_frames.has_animation(FLY_ANIMATION_NAME):
			if not spark_visual.is_playing() or spark_visual.animation != FLY_ANIMATION_NAME:
				spark_visual.play(FLY_ANIMATION_NAME) 
	
	if is_instance_valid(lifetime_timer) and lifetime_timer.is_stopped(): lifetime_timer.start()


func _apply_visual_scale():
	if is_instance_valid(spark_visual): spark_visual.scale = final_applied_scale
	if is_instance_valid(collision_shape): collision_shape.scale = final_applied_scale


func _on_body_entered(body: Node2D): 
	if hit_count >= max_hits: return 
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(final_damage_amount); hit_count += 1
		if hit_count >= max_hits: call_deferred("queue_free") 
	elif body.is_in_group("world_obstacles"): call_deferred("queue_free") 

func set_direction(fired_direction: Vector2):
	direction = fired_direction.normalized() if fired_direction.length_squared() > 0 else Vector2.RIGHT
	if is_inside_tree() and direction != Vector2.ZERO: rotation = direction.angle() # Adjust if sprite faces left
