using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    public enum LeafDropZone {
        LEFT,
        RIGHT,
        TOP,
        BOTTOM,
        CENTER
    }

    private class LeafDragPayload : Object {
        public string id;

        public LeafDragPayload (string id) {
            this.id = id;
        }
    }

    public class LeafPane : Box {
        public Vte.Terminal terminal;
        private Singularity.Widgets.HoverControls hover_controls;
        public  string      pane_id;
        public  Gtk.Button  ssh_btn;
        public  Gtk.Button  bloom_btn;
        public int shell_pid = 0;
        public string? ssh_host = null;

        private string _state_dir;
        private string _history_path;
        private string _snapshot_path;
        private string _command_state_path;
        private uint _snapshot_source = 0;
        private bool _closing = false;
        private bool _direct_command = false;

        private const int SNAPSHOT_MAX_LINES = 200;
        private const int SNAPSHOT_MAX_CHARS = 65536;
        private const string SNAPSHOT_SEPARATOR = "------------------------------------------------";

        // Kept alive to prevent Vala from freeing popovers while GTK still uses them.
        private Singularity.Widgets.ContextMenu? _add_menu   = null;
        private Singularity.Widgets.ContextMenu? _close_menu = null;

        private GLib.Settings _settings;
        private Gtk.DrawingArea _tile_drop_overlay;
        private LeafDropZone _tile_drop_zone = LeafDropZone.CENTER;

        public signal void close_requested     (LeafPane pane);
        public signal void add_requested       (LeafPane pane);
        public signal void tab_requested       (LeafPane pane);
        public signal void flower_requested    ();    
        public signal void detach_requested    (LeafPane pane); 
        public signal void settings_requested  ();
        public signal void close_all_requested ();
        public signal void tile_drop_requested  (string source_id, LeafPane target,
                                                 LeafDropZone zone);
        public signal void state_changed        ();

        public LeafPane (GLib.Settings settings, string? cwd = null, string? id = null,
                         string[]? spawn_cmd = null) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            hexpand = true;
            vexpand = true;
            pane_id   = id ?? GLib.Uuid.string_random ();
            _settings = settings;
            _direct_command = spawn_cmd != null;

            _state_dir = GLib.Path.build_filename (
                GLib.Environment.get_user_data_dir (), "singularity", "leafs");
            _history_path = GLib.Path.build_filename (
                _state_dir, "history-%s.hist".printf (pane_id));
            _snapshot_path = GLib.Path.build_filename (
                _state_dir, "snapshot-%s.txt".printf (pane_id));
            _command_state_path = GLib.Path.build_filename (
                _state_dir, "command-%s.state".printf (pane_id));
            ensure_state_dir ();

            terminal = new Vte.Terminal ();
            terminal.hexpand = true;
            terminal.vexpand = true;
            _apply_settings (settings);

            string shell = resolve_login_shell ();
            string[] envv = build_shell_environment ();
            string[] argv = spawn_cmd ?? shell_argv (shell);

            show_previous_context ();

            terminal.spawn_async (
                Vte.PtyFlags.DEFAULT,
                cwd ?? GLib.Environment.get_home_dir (),
                argv,
                envv,
                (GLib.SpawnFlags) 0,
                null, -1, null,
                (t, pid, err) => {
                    if (err != null) warning ("LeafPane spawn: %s", err.message);
                    else shell_pid = (int) pid;
                }
            );

            // When the shell exits (e.g. the `exit` command), close this pane
            // instead of leaving a dead terminal hanging.
            terminal.child_exited.connect ((status) => {
                if (!_closing)
                    close_requested (this);
            });
            terminal.contents_changed.connect (queue_snapshot);
            terminal.current_directory_uri_changed.connect (() => state_changed ());

            if (spawn_cmd != null && spawn_cmd.length > 0 &&
                (spawn_cmd[0] == "ssh" || spawn_cmd[0].has_suffix ("/ssh") ||
                 spawn_cmd[0] == "mosh" || spawn_cmd[0].has_suffix ("/mosh"))) {
                for (int i = spawn_cmd.length - 1; i >= 1; i--) {
                    string a = spawn_cmd[i];
                    if (a.length == 0 || a.has_prefix ("-")) continue;
                    int at = a.index_of ("@");
                    ssh_host = at >= 0 ? a.substring (at + 1) : a;
                    break;
                }
            }

            hover_controls = new Singularity.Widgets.HoverControls ();
            hover_controls.add_css_class ("singularity-hover-on-content");
            hover_controls.hexpand = true;
            hover_controls.vexpand = true;
            hover_controls.set_content (terminal);

            // Drag grip for window moving
            var grip_btn = new Button ();
            grip_btn.add_css_class ("flat");
            grip_btn.set_size_request (28, 28);
            grip_btn.tooltip_text = _("Drag Window");
            var grip_icon = new Gtk.Image.from_icon_name ("list-drag-handle-symbolic");
            grip_icon.pixel_size = 14;
            grip_btn.set_child (grip_icon);

            var grip_drag = new Gtk.GestureDrag ();
            grip_drag.drag_begin.connect ((x, y) => {
                var win = (Gtk.Window) get_native ();
                if (win != null) {
                    var surface = win.get_surface ();
                    if (surface is Gdk.Toplevel) {
                        ((Gdk.Toplevel) surface).begin_move (
                            grip_drag.get_device (),
                            1,
                            x, y,
                            Gdk.CURRENT_TIME);
                    }
                }
            });
            grip_btn.add_controller (grip_drag);
            hover_controls.add_control (grip_btn);

            var tile_drag_btn = new Button ();
            tile_drag_btn.add_css_class ("flat");
            tile_drag_btn.add_css_class ("leaf-tile-drag-handle");
            tile_drag_btn.set_size_request (28, 28);
            tile_drag_btn.tooltip_text = _("Move Tile");
            var tile_drag_icon = new Gtk.Image.from_icon_name (
                "leaf-tile-drag-symbolic");
            tile_drag_icon.pixel_size = 14;
            tile_drag_btn.set_child (tile_drag_icon);

            var tile_drag = new Gtk.DragSource ();
            tile_drag.set_actions (Gdk.DragAction.MOVE);
            tile_drag.prepare.connect ((x, y) => {
                return new Gdk.ContentProvider.for_value (
                    new LeafDragPayload (pane_id));
            });
            tile_drag.drag_begin.connect ((drag) => {
                var paintable = new Gtk.WidgetPaintable (tile_drag_btn);
                tile_drag.set_icon (paintable,
                    tile_drag_btn.get_width () / 2,
                    tile_drag_btn.get_height () / 2);
                tile_drag_btn.add_css_class ("dragging");
            });
            tile_drag.drag_end.connect ((drag, delete_data) => {
                tile_drag_btn.remove_css_class ("dragging");
            });
            tile_drag_btn.add_controller (tile_drag);
            hover_controls.add_control (tile_drag_btn);

            var add_btn = new Button.from_icon_name ("list-add-symbolic");
            add_btn.tooltip_text = _("New leaf / tab");
            add_btn.clicked.connect (() => {
                _add_menu = new Singularity.Widgets.ContextMenu (add_btn);
                Gdk.Rectangle rect = { 0, 0, 1, 1 };
                _add_menu.set_pointing_to (rect);
                _add_menu.add_item ("New Leaf",    "list-add-symbolic",    () => add_requested (this));
                _add_menu.add_item ("New Tab",     "tab-new-symbolic",     () => tab_requested (this));
                _add_menu.add_item ("New Flower",  "window-new-symbolic",  () => flower_requested ());
                _add_menu.add_separator ();
                _add_menu.add_item ("Detach Leaf to Flower", "window-restore-symbolic",
                    () => detach_requested (this));
                _add_menu.closed.connect (() => { _add_menu.unparent (); _add_menu = null; });
                _add_menu.popup ();
            });
            hover_controls.add_control (add_btn);

            ssh_btn = new Button.from_icon_name ("network-server-symbolic");
            ssh_btn.tooltip_text = _("SSH Sessions");
            hover_controls.add_control (ssh_btn);

            bloom_btn = new Button.from_icon_name ("window-restore-symbolic");
            bloom_btn.tooltip_text = _("Blooms");
            hover_controls.add_control (bloom_btn);

            var settings_btn = new Button.from_icon_name ("emblem-system-symbolic");
            settings_btn.tooltip_text = _("Settings");
            settings_btn.clicked.connect (() => settings_requested ());
            hover_controls.add_control (settings_btn);

            var close_btn = new Button.from_icon_name ("window-close-symbolic");
            close_btn.tooltip_text = _("Close");
            close_btn.clicked.connect (() => {
                _close_menu = new Singularity.Widgets.ContextMenu (close_btn);
                Gdk.Rectangle rect = { 0, 0, 1, 1 };
                _close_menu.set_pointing_to (rect);
                _close_menu.add_item ("Close Leaf", "window-close-symbolic", () => close_requested (this));
                _close_menu.add_separator ();
                _close_menu.add_item ("Close All Leafs", "application-exit-symbolic", () => close_all_requested ());
                _close_menu.closed.connect (() => { _close_menu.unparent (); _close_menu = null; });
                _close_menu.popup ();
            });
            hover_controls.add_control (close_btn);

            var tile_overlay = new Gtk.Overlay ();
            tile_overlay.hexpand = true;
            tile_overlay.vexpand = true;
            tile_overlay.set_child (hover_controls);

            _tile_drop_overlay = new Gtk.DrawingArea ();
            _tile_drop_overlay.hexpand = true;
            _tile_drop_overlay.vexpand = true;
            _tile_drop_overlay.can_target = false;
            _tile_drop_overlay.visible = false;
            _tile_drop_overlay.set_draw_func (draw_tile_drop_zone);
            tile_overlay.add_overlay (_tile_drop_overlay);
            append (tile_overlay);

            var tile_target = new Gtk.DropTarget (
                typeof (LeafDragPayload), Gdk.DragAction.MOVE);
            tile_target.motion.connect ((x, y) => {
                _tile_drop_zone = drop_zone_at (x, y);
                _tile_drop_overlay.visible = true;
                _tile_drop_overlay.queue_draw ();
                return Gdk.DragAction.MOVE;
            });
            tile_target.leave.connect (() => {
                _tile_drop_overlay.visible = false;
            });
            tile_target.drop.connect ((value, x, y) => {
                _tile_drop_overlay.visible = false;
                var payload = value.get_object () as LeafDragPayload;
                if (payload == null || payload.id == pane_id) return false;
                tile_drop_requested (payload.id, this, drop_zone_at (x, y));
                return true;
            });
            add_controller (tile_target);

            _install_context_menu (terminal);
        }

        private LeafDropZone drop_zone_at (double x, double y) {
            double width = double.max (1.0, get_width ());
            double height = double.max (1.0, get_height ());
            double nx = x / width;
            double ny = y / height;
            if (nx >= 0.25 && nx <= 0.75 && ny >= 0.25 && ny <= 0.75)
                return LeafDropZone.CENTER;

            double edge = nx;
            LeafDropZone zone = LeafDropZone.LEFT;
            if (1.0 - nx < edge) {
                edge = 1.0 - nx;
                zone = LeafDropZone.RIGHT;
            }
            if (ny < edge) {
                edge = ny;
                zone = LeafDropZone.TOP;
            }
            if (1.0 - ny < edge)
                zone = LeafDropZone.BOTTOM;
            return zone;
        }

        private void draw_tile_drop_zone (Gtk.DrawingArea area, Cairo.Context cr,
                                           int width, int height) {
            double x = 0;
            double y = 0;
            double w = width;
            double h = height;
            switch (_tile_drop_zone) {
                case LeafDropZone.LEFT:
                    w /= 2;
                    break;
                case LeafDropZone.RIGHT:
                    x = width / 2.0;
                    w /= 2;
                    break;
                case LeafDropZone.TOP:
                    h /= 2;
                    break;
                case LeafDropZone.BOTTOM:
                    y = height / 2.0;
                    h /= 2;
                    break;
                case LeafDropZone.CENTER:
                    x = width * 0.2;
                    y = height * 0.2;
                    w = width * 0.6;
                    h = height * 0.6;
                    break;
            }

            Gdk.RGBA accent = Gdk.RGBA ();
            if (!accent.parse (
                    Singularity.Style.StyleManager.get_default ().accent_hex))
                accent.parse ("#3584e4");
            cr.rectangle (x + 3, y + 3, double.max (0, w - 6), double.max (0, h - 6));
            cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.24);
            cr.fill_preserve ();
            cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.9);
            cr.set_line_width (2);
            cr.stroke ();
        }

        private void ensure_state_dir () {
            if (GLib.DirUtils.create_with_parents (_state_dir, 0700) != 0)
                warning ("LeafPane state directory: %s", _state_dir);
            Posix.chmod (_state_dir, 0700);
        }

        private string[] build_shell_environment () {
            if (!FileUtils.test (_history_path, FileTest.EXISTS))
                write_private_file (_history_path, "");
            else
                Posix.chmod (_history_path, 0600);

            string[] envv = GLib.Environ.get ();
            envv = GLib.Environ.set_variable ((owned) envv, "HISTFILE", _history_path, true);
            envv = GLib.Environ.set_variable ((owned) envv, "HISTSIZE", "10000", true);
            envv = GLib.Environ.set_variable ((owned) envv, "HISTFILESIZE", "10000", true);
            envv = GLib.Environ.set_variable (
                (owned) envv, "LEAFS_COMMAND_STATE_FILE", _command_state_path, true);
            return envv;
        }

        private string[] shell_argv (string shell) {
            if (GLib.Path.get_basename (shell) != "bash")
                return new string[] { shell };

            string rc_path = GLib.Path.build_filename (
                _state_dir, "bashrc-%s.sh".printf (pane_id));
            string rc = """
if [ -r "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

shopt -s histappend

__leafs_history_sync() {
    local status=$?
    local command=""
    if [ "${__leafs_history_ready:-0}" = 1 ]; then
        command="$(builtin history 1 2>/dev/null)"
        command="${command#"${command%%[![:space:]]*}"}"
        command="${command#* }"
        command="${command#"${command%%[![:space:]]*}"}"
    fi
    builtin history -a
    if [ "${__leafs_history_ready:-0}" = 1 ]; then
        local tmp
        tmp="${LEAFS_COMMAND_STATE_FILE}.tmp.$$"
        {
            printf '%s\n' "$status"
            printf '%s\n' "$command"
        } > "$tmp"
        chmod 600 "$tmp"
        mv -f "$tmp" "$LEAFS_COMMAND_STATE_FILE"
    else
        __leafs_history_ready=1
    fi
    return "$status"
}

case "$(declare -p PROMPT_COMMAND 2>/dev/null)" in
    "declare -a"*) PROMPT_COMMAND=(__leafs_history_sync "${PROMPT_COMMAND[@]}") ;;
    *) PROMPT_COMMAND="__leafs_history_sync${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
""";
            write_private_file (rc_path, rc);
            return new string[] { shell, "--rcfile", rc_path, "-i" };
        }

        private void show_previous_context () {
            string context = "";
            try {
                FileUtils.get_contents (_snapshot_path, out context);
            } catch (Error e) {
                context = load_command_context ();
            }
            context = context.strip ();
            if (context == "")
                context = load_command_context ();
            if (context == "") return;

            context = sanitize_context (context);
            string display = context.replace ("\r", "").replace ("\n", "\r\n");
            display += "\r\n" + SNAPSHOT_SEPARATOR + "\r\n";
            terminal.feed (display.data);
        }

        private string sanitize_context (string context) {
            try {
                var controls = new GLib.Regex (
                    "[\\x{0000}-\\x{0008}\\x{000B}\\x{000C}\\x{000E}-\\x{001F}\\x{007F}]",
                    GLib.RegexCompileFlags.OPTIMIZE);
                return controls.replace (context, -1, 0, "");
            } catch (Error e) {
                return "";
            }
        }

        private string load_command_context () {
            try {
                string state;
                FileUtils.get_contents (_command_state_path, out state);
                int newline = state.index_of_char ('\n');
                if (newline < 0) return "";
                string status = state.substring (0, newline).strip ();
                string command = state.substring (newline + 1).strip ();
                if (command == "") return "";
                return "Last command: %s\nExit status: %s".printf (command, status);
            } catch (Error e) {
                return "";
            }
        }

        private void queue_snapshot () {
            if (_closing || _snapshot_source != 0) return;
            _snapshot_source = GLib.Timeout.add (350, () => {
                _snapshot_source = 0;
                persist_state ();
                return GLib.Source.REMOVE;
            });
        }

        public void persist_state () {
            string? text = terminal.get_text_format (Vte.Format.TEXT);
            if (text == null) return;

            bool had_previous_context = false;
            int separator = text.last_index_of (SNAPSHOT_SEPARATOR);
            if (separator >= 0) {
                had_previous_context = true;
                text = text.substring (separator + SNAPSHOT_SEPARATOR.length);
            }
            text = text.strip ();
            if (text == "") return;

            string[] lines = text.split ("\n");
            if (had_previous_context && lines.length < 2) return;
            if (!had_previous_context && lines.length < 2 && !_direct_command
                && !FileUtils.test (_command_state_path, FileTest.EXISTS)) return;

            int first = int.max (0, lines.length - SNAPSHOT_MAX_LINES);
            var saved = new StringBuilder ();
            for (int i = first; i < lines.length; i++) {
                if (saved.len > 0) saved.append_c ('\n');
                saved.append (lines[i]);
            }

            string snapshot = saved.str;
            int chars = snapshot.char_count ();
            if (chars > SNAPSHOT_MAX_CHARS) {
                int offset = snapshot.index_of_nth_char (chars - SNAPSHOT_MAX_CHARS);
                snapshot = snapshot.substring (offset);
            }
            write_private_file (_snapshot_path, snapshot);
        }

        public void prepare_close () {
            if (_closing) return;
            _closing = true;
            if (_snapshot_source != 0) {
                GLib.Source.remove (_snapshot_source);
                _snapshot_source = 0;
            }
            persist_state ();
            if (shell_pid > 0)
                Posix.kill (shell_pid, Posix.Signal.HUP);
        }

        private void write_private_file (string path, string contents) {
            string tmp = path + ".tmp";
            try {
                FileUtils.set_contents (tmp, contents);
                Posix.chmod (tmp, 0600);
                if (FileUtils.rename (tmp, path) != 0)
                    warning ("LeafPane state rename failed: %s", path);
            } catch (Error e) {
                warning ("LeafPane state write: %s", e.message);
            }
        }

        public void apply_settings (GLib.Settings settings) {
            _settings = settings;
            _apply_settings_to (terminal, settings);
        }

        // Counter for tmp filenames; doesn't need to be persisted.
        private static int _paste_counter = 0;

        /**
         * Paste from the clipboard, but if the clipboard contains an image
         * instead of text, save it to /tmp/leafs-paste-<n>.png and feed the
         * path to the terminal. This is what other "modern" terminals
         * (kitty, wezterm, ghostty, claude-code) do.
         *
         * For plain-text clipboards we just call paste_clipboard as before.
         */
        public static void smart_paste (Vte.Terminal vte) {
            var display = Gdk.Display.get_default ();
            if (display == null) { vte.paste_clipboard (); return; }
            var clip = display.get_clipboard ();
            var formats = clip.get_formats ();

            // Heuristic: text takes precedence over image (covers the common
            // case of copy-pasting URLs / paths from a file manager that
            // also expose a thumbnail). Only divert to image when there's
            // NO usable text but there IS image data.
            bool has_text = formats.contain_mime_type ("text/plain")
                         || formats.contain_mime_type ("text/plain;charset=utf-8")
                         || formats.contain_mime_type ("UTF8_STRING")
                         || formats.contain_gtype (typeof (string));
            bool has_image = formats.contain_mime_type ("image/png")
                          || formats.contain_mime_type ("image/jpeg")
                          || formats.contain_mime_type ("image/bmp")
                          || formats.contain_gtype (typeof (Gdk.Texture))
                          || formats.contain_gtype (typeof (Gdk.Pixbuf));

            if (!has_image || has_text) {
                vte.paste_clipboard ();
                return;
            }

            // Async-read the texture, then save + feed the path.
            clip.read_texture_async.begin (null, (obj, res) => {
                try {
                    var tex = clip.read_texture_async.end (res);
                    if (tex == null) { vte.paste_clipboard (); return; }
                    string dir = "%s/leafs-pasted".printf (GLib.Environment.get_tmp_dir ());
                    GLib.DirUtils.create_with_parents (dir, 0700);
                    string path = "%s/img-%d-%d.png".printf (dir,
                        (int) (GLib.get_real_time () / 1000000),
                        ++_paste_counter);
                    tex.save_to_png (path);
                    // Feed quoted path into the shell. Quoting protects spaces
                    // and special chars; trailing space lets the user keep typing.
                    string quoted = GLib.Shell.quote (path);
                    vte.feed_child ((quoted + " ").data);
                } catch (Error e) {
                    warning ("leafs smart_paste: %s; falling back to text paste", e.message);
                    vte.paste_clipboard ();
                }
            });
        }

        private void _apply_settings (GLib.Settings settings) {
            _apply_settings_to (terminal, settings);
        }

        private void _apply_settings_to (Vte.Terminal vte, GLib.Settings s) {
            var font_desc = new Pango.FontDescription ();
            font_desc.set_family (s.get_string ("font-family"));
            font_desc.set_size (s.get_int ("font-size") * Pango.SCALE);
            vte.set_font (font_desc);
            vte.set_scrollback_lines (s.get_int ("scrollback-lines"));

            string scheme = s.get_string ("color-scheme");
            var theme = (scheme == "auto")
                ? Singularity.Core.TerminalThemes.make_auto_theme (auto_is_dark ())
                : Singularity.Core.TerminalThemes.get_by_id (scheme);
            if (theme == null)
                theme = Singularity.Core.TerminalThemes.get_by_id ("onedark");
            if (theme != null) {
                Gdk.RGBA bg = Gdk.RGBA (), fg = Gdk.RGBA ();
                bg.parse (theme.background);
                fg.parse (theme.foreground);
                Gdk.RGBA[] palette = new Gdk.RGBA[16];
                for (int i = 0; i < 16; i++) {
                    palette[i] = Gdk.RGBA ();
                    palette[i].parse (theme.palette[i]);
                }
                vte.set_colors (fg, bg, palette);
            }
        }

        private bool auto_is_dark () {
            return Singularity.Style.ThemeMode.get_default ().app_dark ();
        }

        private void _install_context_menu (Vte.Terminal vte) {
            if (vte.get_data<bool> ("leafs-context-menu-installed")) return;
            vte.set_data<bool> ("leafs-context-menu-installed", true);
            var click = new GestureClick ();
            click.button = 3;
            click.pressed.connect ((n, x, y) => {
                var menu = new Singularity.Widgets.ContextMenu (vte);
                Gdk.Rectangle rect = { (int) x, (int) y, 1, 1 };
                menu.set_pointing_to (rect);
                if (vte.get_has_selection ())
                    menu.add_item ("Copy", "edit-copy-symbolic", () => vte.copy_clipboard_format (Vte.Format.TEXT));
                menu.add_item ("Paste", "edit-paste-symbolic", () => smart_paste (vte));
                menu.add_separator ();
                menu.add_item ("Clear", "edit-clear-symbolic", () => vte.reset (true, true));
                menu.popup ();
            });
            vte.add_controller (click);
        }

        public string get_working_dir () {
            string? uri = terminal.get_current_directory_uri ();
            if (uri != null) {
                try { return GLib.Filename.from_uri (uri); } catch {}
            }
            return GLib.Environment.get_home_dir ();
        }

        public bool has_focus () {
            return terminal.is_focus ();
        }

        public void redraw_terminals () {
            terminal.queue_resize ();
            terminal.queue_draw ();
        }
    }

}
