extends Node
## Global logger (autoload "Log"). Writes to stdout and a size-bounded rotating file in the
## user data folder. Headless servers rely on this for diagnostics, so keep it dependency free.

enum Level { DEBUG, INFO, WARN, ERROR }

const MAX_FILE_BYTES := 2 * 1024 * 1024
const KEEP_FILES := 3

var level: int = Level.INFO
var _file: FileAccess = null
var _path := ""
var _written := 0
var _channel := "game"


func _ready() -> void:
	if OS.is_debug_build() and not OS.has_feature("dedicated_server"):
		level = Level.DEBUG


## Opens (and rotates) the log file. Called by App once the user/profile root is known.
func open(channel: String, dir_path: String) -> void:
	_channel = channel
	if _file:
		_file.close()
		_file = null
	DirAccess.make_dir_recursive_absolute(dir_path)
	_path = dir_path.path_join("%s.log" % channel)
	_rotate()
	_file = FileAccess.open(_path, FileAccess.WRITE)
	_written = 0
	if _file == null:
		push_warning("Log: cannot open %s" % _path)


## Keeps `KEEP_FILES` generations: name.log (current), name.log.1, name.log.2, ...
func _rotate() -> void:
	var oldest := "%s.%d" % [_path, KEEP_FILES - 1]
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for gen in range(KEEP_FILES - 2, 0, -1):
		var src := "%s.%d" % [_path, gen]
		if FileAccess.file_exists(src):
			DirAccess.rename_absolute(src, "%s.%d" % [_path, gen + 1])
	if FileAccess.file_exists(_path):
		DirAccess.rename_absolute(_path, "%s.1" % _path)


func log_path() -> String:
	return _path


## Writes buffered lines to disk now (INFO lines are otherwise flushed with the next WARN/ERROR;
## the dedicated server calls this every second so operators can tail the log).
func flush() -> void:
	if _file:
		_file.flush()


func d(tag: String, msg: String) -> void:
	_emit(Level.DEBUG, tag, msg)


func i(tag: String, msg: String) -> void:
	_emit(Level.INFO, tag, msg)


func w(tag: String, msg: String) -> void:
	_emit(Level.WARN, tag, msg)


func e(tag: String, msg: String) -> void:
	_emit(Level.ERROR, tag, msg)


func _emit(lv: int, tag: String, msg: String) -> void:
	if lv < level:
		return
	var names := ["DEBUG", "INFO", "WARN", "ERROR"]
	var line := "%s [%s] %s: %s" % [Time.get_datetime_string_from_system(false, true), names[lv], tag, msg]
	if lv >= Level.ERROR:
		printerr(line)
	else:
		print(line)
	if _file:
		_file.store_line(line)
		_written += line.length() + 1
		if lv >= Level.WARN:
			_file.flush()
		if _written > MAX_FILE_BYTES:
			_file.close()
			_rotate()
			_file = FileAccess.open(_path, FileAccess.WRITE)
			_written = 0


func _exit_tree() -> void:
	if _file:
		_file.flush()
		_file.close()
