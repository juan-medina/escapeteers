# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name GameError
extends RefCounted

enum Code { OK, TECHNICAL, LOBBY_NOT_FOUND, LOBBY_FULL, LOBBY_VERSION_MISMATCH, LOBBY_DISCONNECTED, NETWORK_ERROR, LOBBY_ALREADY_EXISTS }


static func string(error_code: Code) -> StringName:
	match error_code:
		Code.OK:
			return &"Ok"
		Code.TECHNICAL:
			return &"Technical error"
		Code.LOBBY_NOT_FOUND:
			return &"Can't find the game"
		Code.LOBBY_FULL:
			return &"The game is full"
		Code.LOBBY_VERSION_MISMATCH:
			return &"This game version is different from yours"
		Code.LOBBY_DISCONNECTED:
			return &"Disconnected from the game"
		Code.NETWORK_ERROR:
			return &"Communication error"
		Code.LOBBY_ALREADY_EXISTS:
			return &"A game with this name already exists"
		_:
			return &"Unknown Error"
