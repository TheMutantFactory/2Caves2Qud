# Autoload: the game's sound effects and music from qud/sfx and qud/music.
# play("hit_enemy") and music("battle_3"); silent when the files are missing.
extends Node

const SFX_ROOT := "res://qud/sfx/"
const MUSIC_ROOT := "res://qud/music/"
const POOL := 10

var players: Array = []
var music_player: AudioStreamPlayer
var streams := {}
var current_music := ""
var sfx_db := -6.0
var music_db := -10.0
var muted := false


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)
	music_player.finished.connect(func(): if current_music != "": music_player.play())
	muted = "--mute" in OS.get_cmdline_user_args() or OS.has_feature("headless")


# Clips live in the Qud asset store OUTSIDE the project (godot/qud is a link into it),
# so they are never imported: OGG and WAV load straight from the file at runtime.
func _stream(path: String) -> AudioStream:
	if streams.has(path):
		return streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	else:
		var gp := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(gp):
			if path.ends_with(".ogg"):
				s = AudioStreamOggVorbis.load_from_file(gp)
			elif path.ends_with(".wav"):
				s = AudioStreamWAV.load_from_file(gp)
	streams[path] = s
	return s


func play(name: String, volume_db := 0.0) -> void:
	if muted:
		return
	var s := _stream(SFX_ROOT + name + ".ogg")
	if s == null:
		s = _stream(SFX_ROOT + name + ".wav")
	if s == null:
		return
	for p in players:
		if not p.playing:
			p.stream = s
			p.volume_db = sfx_db + volume_db
			p.play()
			return
	players[0].stream = s
	players[0].volume_db = sfx_db + volume_db
	players[0].play()


func music(name: String) -> void:
	if muted or name == current_music:
		return
	var s := _stream(MUSIC_ROOT + name + ".mp3")
	if s == null:
		s = _stream(MUSIC_ROOT + name + ".ogg")
	current_music = name
	if s == null:
		return
	music_player.stream = s
	music_player.volume_db = music_db
	music_player.play()


func stop_music() -> void:
	current_music = ""
	music_player.stop()
