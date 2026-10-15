extends Node
## Autoload "Paths": the user-data root and its subfolders. Nothing is ever written next to the
## executable. Tests (and the paranoid) can redirect everything with `--user-root <dir>`, which
## is how paths with spaces and non-ASCII characters are verified (SAV-04).

const SUBDIRS := ["profiles", "mods", "arenas", "presets", "policies", "playlists", "runs", "logs",
	"lab", "captures", "replays", "server", "packages", "downloads"]

var root := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--user-root")
	if i >= 0 and i + 1 < args.size():
		root = args[i + 1].replace("\\", "/")
	elif args.has("--test"):
		# the automated suite never touches the player's real profiles, settings or mods
		root = OS.get_user_data_dir().replace("\\", "/").path_join("_test_root")
	else:
		root = OS.get_user_data_dir().replace("\\", "/")
	for d in SUBDIRS:
		DirAccess.make_dir_recursive_absolute(root.path_join(d))


func _ready() -> void:
	var channel := "server" if OS.get_cmdline_user_args().has("--server") else ("lab" if OS.get_cmdline_user_args().has("--lab-worker") else "game")
	Log.open(channel, dir("logs"))
	Log.i("paths", "user data root: %s" % root)


func dir(kind: String) -> String:
	var p := root.path_join(kind)
	if not DirAccess.dir_exists_absolute(p):
		DirAccess.make_dir_recursive_absolute(p)
	return p


func file(kind: String, name_: String) -> String:
	return dir(kind).path_join(name_)


## Filesystem-safe slug for user-provided names (keeps unicode letters; strips separators).
static func slug(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"]:
			out += "_"
		else:
			out += ch
	out = out.substr(0, 64).strip_edges()
	if out == "" or out == "." or out == "..":
		out = "unnamed"
	return out


func open_in_os(kind: String) -> void:
	OS.shell_open("file://" + dir(kind))
