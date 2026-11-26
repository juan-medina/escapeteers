# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EventDirector
extends RefCounted

const EVENT_MUSIC_FADE_IN: float = 0.35
const EVENT_MUSIC_FADE_OUT: float = 0.65
const EVENT_SHAKE_STRENGTH: float = 4.0
const EVENT_SHAKE_DURATION: float = 0.25
const EVENT_WARNING_COLOR: Color = Color(1.0, 0.28, 0.28, 1.0)
const EVENT_CLEAR_COLOR: Color = Color(1.0, 0.85, 0.35, 1.0)

var _hud: Hud
var _fog: Fog
var _camera: Camera2D
var _active_event_room: Rect2i = Rect2i()
var _shake_timer: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0


func setup(hud: Hud, fog: Fog, camera: Camera2D) -> void:
	_hud = hud
	_fog = fog
	_camera = camera


func on_event_armed(room: Rect2i) -> void:
	_active_event_room = room
	Audio.play_sfx(Audio.Sfx.EVENT_START)
	Audio.set_music_track(Audio.MusicTrack.EVENT, EVENT_MUSIC_FADE_IN)
	_fog.set_event_atmosphere(true)
	trigger_shake(EVENT_SHAKE_STRENGTH, EVENT_SHAKE_DURATION)
	_hud.show_event_banner(&"! WARNING !", &"Blood Spike Arena", &"Clear all enemies to disarm spikes", EVENT_WARNING_COLOR)


func on_event_disarmed(room: Rect2i) -> void:
	if room != _active_event_room:
		return
	_active_event_room = Rect2i()
	Audio.set_music_track(Audio.MusicTrack.GAME, EVENT_MUSIC_FADE_OUT)
	_fog.set_event_atmosphere(false)


func on_event_cleared(room: Rect2i) -> void:
	Audio.play_sfx(Audio.Sfx.EVENT_CLEAR)
	if room == _active_event_room:
		_active_event_room = Rect2i()
		Audio.set_music_track(Audio.MusicTrack.GAME, EVENT_MUSIC_FADE_OUT)
		_fog.set_event_atmosphere(false)
	_hud.show_event_banner(&"ARENA CLEARED", &"Blood Spike Arena", &"Bonus reward dropped!", EVENT_CLEAR_COLOR)


func on_player_died() -> void:
	_active_event_room = Rect2i()


func trigger_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_timer = maxf(_shake_timer, duration)


func update(delta: float) -> void:
	if _shake_timer <= 0.0:
		_camera.offset = Vector2.ZERO
		return
	_shake_timer = maxf(0.0, _shake_timer - delta)
	var ratio: float = _shake_timer / _shake_duration if _shake_duration > 0.0 else 0.0
	var mag: float = _shake_strength * ratio
	_camera.offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))
	if _shake_timer <= 0.0:
		_shake_strength = 0.0
		_shake_duration = 0.0
		_camera.offset = Vector2.ZERO
