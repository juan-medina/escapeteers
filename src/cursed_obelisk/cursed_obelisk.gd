# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Destructible arcane obelisk that projects an immunity aura to nearby allies until shattered.
class_name CursedObelisk
extends Enemy

enum ObeliskState {
	DORMANT,
	ACTIVE,
	DESTROYED,
}

const AURA_RADIUS: float = 144.0
const BASE_HEALTH: float = 240.0
const HEALTH_PER_LEVEL: float = 75.0
const DORMANT_MODULATE: Color = Color(0.42, 0.42, 0.52, 1.0)
const HEALTH_BAR_COLOR: Color = Color(0.75, 0.35, 1.0, 1.0)
const ACTIVE_RING_COLOR: Color = Color(0.75, 0.35, 1.0, 0.78)
const DORMANT_RING_COLOR: Color = Color(0.35, 0.30, 0.45, 0.45)
const DESTROYED_RING_COLOR: Color = Color(0.30, 0.30, 0.35, 0.30)

var obelisk_state: ObeliskState = ObeliskState.DORMANT
var aura_radius: float = AURA_RADIUS

@onready var _aura: ObeliskAura = $ObeliskAura
@onready var _ground_indicator: GroundIndicator = $GroundIndicator
@onready var _particles: CPUParticles2D = $CursedParticles
@onready var _shatter_particles: CPUParticles2D = $ShatterParticles
@onready var _light: PointLight2D = $ObeliskLight


func _ready() -> void:
	enemy_id = &""
	super._ready()
	set_physics_process(false)
	set_process(false)
	_unregister_active_enemy()
	hurtbox.set_disabled(true)
	_collision_shape.set_deferred(&"disabled", false)
	collision_layer = 8
	collision_mask = 0
	_health_bar.set_fill_color(HEALTH_BAR_COLOR)
	_health_bar.visible = false
	_base_modulate = DORMANT_MODULATE
	_animated_sprite.modulate = DORMANT_MODULATE
	_animated_sprite.play(&"dormant")
	_ground_indicator.custom_ring_color = DORMANT_RING_COLOR
	_aura.radius = AURA_RADIUS
	_aura.set_active(false)
	_particles.emitting = false
	_light.enabled = false


func activate(obelisk_level: int, custom_aura_radius: float = AURA_RADIUS) -> void:
	if obelisk_state != ObeliskState.DORMANT:
		return
	obelisk_state = ObeliskState.ACTIVE
	aura_radius = custom_aura_radius
	level = obelisk_level
	max_health = BASE_HEALTH + float(maxi(0, obelisk_level - 1)) * HEALTH_PER_LEVEL
	health = max_health
	is_dead = false
	_health_bar.set_level(obelisk_level)
	_health_bar.update_health(health, max_health)
	_health_bar.visible = true
	hurtbox.set_disabled(false)
	_register_active_enemy()
	_base_modulate = Color.WHITE
	_animated_sprite.modulate = Color.WHITE
	_animated_sprite.play(&"active")
	_ground_indicator.custom_ring_color = ACTIVE_RING_COLOR
	_aura.radius = aura_radius
	_aura.set_active(true)
	_particles.emitting = true
	_light.enabled = true
	_play_pop_tween()


func set_tether_world_positions(world_positions: Array[Vector2]) -> void:
	var local_pts: Array[Vector2] = []
	for pos: Vector2 in world_positions:
		local_pts.append(to_local(pos))
	_aura.set_tethers(local_pts)


func play(anim_name: StringName = ANIM_IDLE) -> void:
	var resolved: StringName = &"dormant" if anim_name == ANIM_IDLE else anim_name
	_animated_sprite.play(resolved)


func sync_screen_state(_camera_pos: Vector2) -> void:
	is_on_screen = true


func set_target_candidate(_hero_candidate: Hero, _force: bool = false) -> void:
	pass


func apply_knockback(_force: Vector2) -> void:
	pass


func apply_slow(_factor: float, _duration: float) -> void:
	pass


func apply_stun(_duration: float) -> void:
	pass


func apply_burn(_dps: float, _duration: float, _source_hero: Hero = null) -> void:
	pass


func apply_taunt(_taunter: Hero) -> void:
	pass


func take_damage(amount: float, flash_hurt: bool = true) -> void:
	if obelisk_state != ObeliskState.ACTIVE or is_dead:
		return
	super.take_damage(amount, flash_hurt)


func _set_sleeping(_sleeping: bool, _force: bool = false) -> void:
	pass


func _on_death() -> void:
	obelisk_state = ObeliskState.DESTROYED
	_unregister_active_enemy()
	disable_collisions()
	_health_bar.visible = false
	_aura.set_active(false)
	_particles.emitting = false
	_light.enabled = false
	_ground_indicator.custom_ring_color = DESTROYED_RING_COLOR
	_status_vfx.clear()
	_base_modulate = Color.WHITE
	_animated_sprite.modulate = Color.WHITE
	_animated_sprite.play(&"destroyed")
	_shatter_particles.restart()
	Audio.play_sfx(Audio.Sfx.SHORTCUT_OPEN)


func _on_animation_finished() -> void:
	pass


func _play_pop_tween() -> void:
	scale = Vector2(1.25, 0.80)
	var tween: Tween = create_tween()
	tween.tween_property(self, ^"scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
