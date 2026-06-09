using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    public class LeafPane : Box {
        public Vte.Terminal terminal;
        private Singularity.Widgets.HoverControls hover_controls;
        public  string      pane_id;
        public  Gtk.Button  ssh_btn;
        public int shell_pid = 0;
        public string? ssh_host = null;

        // Kept alive to prevent Vala from freeing popovers while GTK still uses them.
        private Singularity.Widgets.ContextMenu? _add_menu   = null;
        private Singularity.Widgets.ContextMenu? _close_menu = null;

        // Bug (sub-terminal) support
        private GLib.Settings                          _settings;
        private Singularity.Widgets.ChipBar            _chip_bar;
        private Gtk.Box                                _bug_host;
        private Gee.HashMap<string, Vte.Terminal>      _bugs;
        private string?                                _active_bug   = null;
        private int                                    _bug_counter  = 0;

        // Bug pane resize
        private int    _bug_height       = 200;
        private double _drag_start_height = 0;
        private const int BUG_MIN_HEIGHT = 60;
        private const int BUG_MAX_HEIGHT = 600;

        public signal void close_requested     (LeafPane pane);
        public signal void add_requested       (LeafPane pane);
        public signal void flower_requested    ();    
        public signal void detach_requested    (LeafPane pane); 
        public signal void settings_requested  ();
        public signal void close_all_requested ();
        public signal void reorder_requested    (LeafPane source, LeafPane target);
        public signal void lookup_reorder       (string source_id, LeafPane target);

        public LeafPane (GLib.Settings settings, string? cwd = null, string? id = null, string[]? spawn_cmd = null) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            hexpand = true;
            vexpand = true;
            pane_id   = id ?? GLib.Uuid.string_random ();
            _settings = settings;
            _bugs     = new Gee.HashMap<string, Vte.Terminal> ();

            terminal = new Vte.Terminal ();
            terminal.hexpand = true;
            terminal.vexpand = true;
            _apply_settings (settings);

            // History file per pane
            string hist_dir = GLib.Path.build_filename (
                GLib.Environment.get_home_dir (),
                ".local", "share", "singularity", "leafs");
            try { GLib.DirUtils.create_with_parents (hist_dir, 0755); } catch {}
            string hist_path = GLib.Path.build_filename (hist_dir, "history-%s.hist".printf (pane_id));

            // Seed pane history from user's shell history if not already created
            if (!FileUtils.test (hist_path, FileTest.EXISTS)) {
                string home = GLib.Environment.get_home_dir ();
                string[] candidates = {
                    GLib.Environment.get_variable ("HISTFILE") ?? "",
                    GLib.Path.build_filename (home, ".zsh_history"),
                    GLib.Path.build_filename (home, ".bash_history"),
                    GLib.Path.build_filename (home, ".history")
                };
                foreach (var candidate in candidates) {
                    if (candidate != "" && FileUtils.test (candidate, FileTest.EXISTS)) {
                        try {
                            string content;
                            FileUtils.get_contents (candidate, out content);
                            FileUtils.set_contents (hist_path, content);
                        } catch {}
                        break;
                    }
                }
            }

            string shell = GLib.Environment.get_variable ("SHELL") ?? "/bin/bash";
            // PROMPT_COMMAND flushes bash history after every command;
            // zsh/fish ignore it harmlessly. This keeps .hist files up to date
            // even if the app is killed instead of closed cleanly.
            string[] envv = {
                "HISTFILE=" + hist_path,
                "HISTSIZE=10000",
                "HISTFILESIZE=10000",
                "PROMPT_COMMAND=history -a"
            };
            string[] argv = spawn_cmd ?? new string[] { shell };

            terminal.spawn_async (
                Vte.PtyFlags.DEFAULT,
                cwd ?? GLib.Environment.get_home_dir (),
                argv,
                envv,
                GLib.SpawnFlags.DO_NOT_REAP_CHILD,
                null, -1, null,
                (t, pid, err) => {
                    if (err != null) warning ("LeafPane spawn: %s", err.message);
                    else shell_pid = (int) pid;
                }
            );

            // When the shell exits (e.g. the `exit` command), close this pane
            // instead of leaving a dead terminal hanging.
            terminal.child_exited.connect ((status) => {
                close_requested (this);
            });

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

            var add_btn = new Button.from_icon_name ("list-add-symbolic");
            add_btn.tooltip_text = _("New leaf / bug");
            add_btn.clicked.connect (() => {
                _add_menu = new Singularity.Widgets.ContextMenu (add_btn);
                Gdk.Rectangle rect = { 0, 0, 1, 1 };
                _add_menu.set_pointing_to (rect);
                _add_menu.add_item ("New Leaf",    "list-add-symbolic",    () => add_requested (this));
                _add_menu.add_item ("New Bug",     "go-down-symbolic",     () => _spawn_bug ());
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

            append (hover_controls);

            // Bug host - fixed height, resizable via drag on the separator.
            _bug_host = new Gtk.Box (Orientation.VERTICAL, 0);
            _bug_host.hexpand = true;
            _bug_host.vexpand = false;
            _bug_host.visible = false;

            var bug_sep = new Gtk.Separator (Orientation.HORIZONTAL);
            bug_sep.add_css_class ("leaf-sep");
            bug_sep.add_css_class ("leaf-bug-separator");
            bug_sep.set_size_request (-1, 12);
            bug_sep.margin_top = 6;
            bug_sep.margin_bottom = 6;
            bug_sep.cursor = new Gdk.Cursor.from_name ("row-resize", null);

            var sep_event = new Gtk.Box (Orientation.HORIZONTAL, 0);
            sep_event.set_size_request (-1, 24);
            sep_event.cursor = new Gdk.Cursor.from_name ("row-resize", null);
            sep_event.append (bug_sep);
            sep_event.valign = Gtk.Align.CENTER;

            var drag = new Gtk.GestureDrag ();
            drag.drag_begin.connect ((x, y) => {
                _drag_start_height = _bug_height;
            });
            drag.drag_update.connect ((dx, dy) => {
                int nh = (int)(_drag_start_height - dy);
                _bug_height = nh.clamp (BUG_MIN_HEIGHT, BUG_MAX_HEIGHT);
                _bug_host.set_size_request (-1, _bug_height);
            });
            drag.drag_end.connect ((dx, dy) => {
                _bug_host.set_size_request (-1, _bug_height);
            });
            sep_event.add_controller (drag);

            _bug_host.append (sep_event);
            append (_bug_host);

            // Chip bar - visible only when at least one bug exists.
            _chip_bar = new Singularity.Widgets.ChipBar ();
            _chip_bar.visible = false;
            // Session chips can be reordered by dragging them.
            _chip_bar.reorderable = true;
            _chip_bar.chip_activated.connect (_on_chip_activated);
            _chip_bar.chip_closed.connect    (_on_chip_closed);
            append (_chip_bar);

            // Right-click context menu
            var rclick = new GestureClick ();
            rclick.button = 3;
            rclick.pressed.connect ((n, x, y) => {
                var menu = new Singularity.Widgets.ContextMenu (terminal);
                Gdk.Rectangle rect = { (int) x, (int) y, 1, 1 };
                menu.set_pointing_to (rect);
                if (terminal.get_has_selection ())
                    menu.add_item ("Copy", "edit-copy-symbolic", () => terminal.copy_clipboard_format (Vte.Format.TEXT));
                menu.add_item ("Paste", "edit-paste-symbolic", () => smart_paste (terminal));
                menu.add_separator ();
                menu.add_item ("Clear", "edit-clear-symbolic", () => terminal.reset (true, true));
                menu.popup ();
            });
            terminal.add_controller (rclick);
        }

        public void apply_settings (GLib.Settings settings) {
            _settings = settings;
            _apply_settings_to (terminal, settings);
            foreach (var vte in _bugs.values)
                _apply_settings_to (vte, settings);
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
                        (int) GLib.get_real_time () / 1000000,
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

            var theme = Singularity.Core.TerminalThemes.get_by_id (s.get_string ("color-scheme"));
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

        private void _spawn_bug () {
            _bug_counter++;
            string bug_id    = "bug-%d".printf (_bug_counter);
            string bug_label = "#%d".printf (_bug_counter);

            var vte = new Vte.Terminal ();
            vte.hexpand = true;
            vte.vexpand = false;
            _apply_settings_to (vte, _settings);

            string shell = GLib.Environment.get_variable ("SHELL") ?? "/bin/bash";
            string cwd   = get_working_dir ();
            vte.spawn_async (
                Vte.PtyFlags.DEFAULT, cwd,
                new string[] { shell }, null,
                GLib.SpawnFlags.DO_NOT_REAP_CHILD,
                null, -1, null,
                (t, pid, err) => {
                    if (err != null) warning ("Bug spawn: %s", err.message);
                }
            );

            _bugs.set (bug_id, vte);
            _chip_bar.add_chip (bug_id, bug_label);
            _chip_bar.visible = true;

            // Track VTE title, chip label (truncate to 10 chars)
            string tracked_id = bug_id;
            vte.window_title_changed.connect (() => {
                string? t = vte.get_window_title ();
                if (t == null || t.length == 0) return;
                string display = t.char_count () > 10
                    ? t.substring (0, t.index_of_nth_char (10)) + "…"
                    : t;
                _chip_bar.update_chip_label (tracked_id, display);
            });

            // Right-click context menu for bug terminal (same as leaf)
            var bug_rclick = new GestureClick ();
            bug_rclick.button = 3;
            bug_rclick.pressed.connect ((n, x, y) => {
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
            vte.add_controller (bug_rclick);

            _activate_bug (bug_id);
        }

        private void _activate_bug (string id) {
            // Clicking the active chip again, deactivate (collapse)
            if (_active_bug == id) {
                _deactivate_bug ();
                return;
            }

            // Remove previous bug terminal from host
            if (_active_bug != null) {
                var prev = _bugs.get (_active_bug);
                if (prev != null) _bug_host.remove (prev);
            }

            var vte = _bugs.get (id);
            if (vte == null) return;

            _bug_host.append (vte);
            _bug_host.set_size_request (-1, _bug_height);
            _bug_host.visible = true;
            _active_bug = id;
            _chip_bar.set_active (id);
            vte.grab_focus ();
        }

        private void _deactivate_bug () {
            if (_active_bug != null) {
                var vte = _bugs.get (_active_bug);
                if (vte != null) _bug_host.remove (vte);
            }
            _active_bug = null;
            _bug_host.visible = false;
            _chip_bar.set_active (null);
            terminal.grab_focus ();
        }

        private void _on_chip_activated (string id) {
            _activate_bug (id);
        }

        private void _on_chip_closed (string id) {
            if (_active_bug == id) {
                var vte = _bugs.get (id);
                if (vte != null) _bug_host.remove (vte);
                _active_bug = null;
                _bug_host.visible = false;
            }
            _bugs.unset (id);
            _chip_bar.remove_chip (id);
            if (_chip_bar.chip_count == 0) _chip_bar.visible = false;
            _chip_bar.set_active (null);
            terminal.grab_focus ();
        }

        public string get_working_dir () {
            string? uri = terminal.get_current_directory_uri ();
            if (uri != null) {
                try { return GLib.Filename.from_uri (uri); } catch {}
            }
            return GLib.Environment.get_home_dir ();
        }

        /** Returns true if this leaf or any of its bug terminals has focus. */
        public bool has_focus () {
            if (terminal.is_focus ()) return true;
            if (_active_bug != null) {
                var bug_vte = _bugs.get (_active_bug);
                if (bug_vte != null && bug_vte.is_focus ()) return true;
            }
            return false;
        }

        /** Returns the active bug terminal, or null if none is active. */
        public Vte.Terminal? get_active_bug () {
            if (_active_bug == null) return null;
            return _bugs.get (_active_bug);
        }
    }

}
