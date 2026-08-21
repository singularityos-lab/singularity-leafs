using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    private class LeafLayoutNode : Object {
        public LeafCell? cell;
        public Orientation orientation;
        public LeafLayoutNode? start;
        public LeafLayoutNode? end;

        public LeafLayoutNode.for_cell (LeafCell cell) {
            this.cell = cell;
        }

        public LeafLayoutNode.for_split (Orientation orientation,
                                         LeafLayoutNode start,
                                         LeafLayoutNode end) {
            this.orientation = orientation;
            this.start = start;
            this.end = end;
        }

        public int leaf_count () {
            if (cell != null) return 1;
            int start_count = start != null ? start.leaf_count () : 0;
            int end_count = end != null ? end.leaf_count () : 0;
            return start_count + end_count;
        }
    }

    public class LeafsApp : Singularity.Application {
        // Primary window; "flowers" are additional LeafsWindow instances.
        private LeafsWindow main_window;
        private ArrayList<LeafPane> leaves;
        // Maps each leaf to the LeafsWindow currently hosting it.
        private HashMap<LeafPane, LeafsWindow> leaf_window = new HashMap<LeafPane, LeafsWindow>();
        private HashMap<LeafPane, LeafCell> leaf_cell = new HashMap<LeafPane, LeafCell>();
        private HashMap<LeafsWindow, ArrayList<LeafCell>> window_cells =
            new HashMap<LeafsWindow, ArrayList<LeafCell>> ();
        private HashMap<LeafsWindow, LeafLayoutNode> window_layout =
            new HashMap<LeafsWindow, LeafLayoutNode> ();
        // Extra "flower" windows beyond main_window.
        private ArrayList<LeafsWindow> flowers = new ArrayList<LeafsWindow>();
        private GLib.Settings settings;
        private GLib.Settings? desktop_settings;
        private ArrayList<SshSession> ssh_sessions;
        private ArrayList<BloomDef> blooms;
        private uint session_save_source = 0;
        private bool restoring_session = false;

        private LeafsWindow window_of(LeafPane leaf) {
            return leaf_window.has_key(leaf) ? leaf_window[leaf] : main_window;
        }

        // Command passed via `-e`/`--` on the command line, to run in the
        // first leaf instead of restoring the previous session. Lets Leafs act
        // as a terminal emulator target (e.g. for GAppInfo NEEDS_TERMINAL).
        private string[]? _startup_cmd = null;

        public LeafsApp () {
#if DEVEL
            Object (application_id: "dev.sinty.leafs-devel",
                    flags: ApplicationFlags.HANDLES_COMMAND_LINE);
            GLib.Environment.set_prgname ("dev.sinty.leafs-devel");
#else
            Object (application_id: "dev.sinty.leafs",
                    flags: ApplicationFlags.HANDLES_COMMAND_LINE);
            GLib.Environment.set_prgname ("dev.sinty.leafs");
#endif
        }

        // Pull the command to run out of a terminal-style argv: everything
        // after the first `-e`, `-x`, `--command` or `--` token. A single
        // remaining argument containing spaces is shell-split.
        private string[]? extract_exec_command (string[] argv) {
            for (int i = 1; i < argv.length; i++) {
                string a = argv[i];
                if (a == "-e" || a == "-x" || a == "--command" || a == "--") {
                    string[] rest = {};
                    for (int j = i + 1; j < argv.length; j++) rest += argv[j];
                    if (rest.length == 0) return null;
                    if (rest.length == 1 && (" " in rest[0])) {
                        try {
                            string[] parsed;
                            GLib.Shell.parse_argv (rest[0], out parsed);
                            return parsed;
                        } catch (Error e) { /* fall through to raw */ }
                    }
                    return rest;
                }
            }
            return null;
        }

        protected override int command_line (ApplicationCommandLine cmdline) {
            string[] argv = cmdline.get_arguments ();
            string[]? cmd = extract_exec_command (argv);
            if (cmd != null) _startup_cmd = cmd;
            activate ();
            return 0;
        }

        private void add_leaf_cmd (string[] cmd) {
            insert_leaf_after (null, null, null, cmd);
        }

        protected override void startup () {
            base.startup ();
            setup_styles ();

            var menu = new GLib.Menu ();
            var file_menu = new GLib.Menu ();
            file_menu.append ("Settings", "app.settings");
            file_menu.append ("Quit", "app.quit");
            menu.append_submenu ("File", file_menu);
            set_menubar (menu);

            var act_settings = new SimpleAction ("settings", null);
            act_settings.activate.connect (() => show_settings ());
            add_action (act_settings);

            var act_new_leaf = new SimpleAction ("new-leaf", null);
            act_new_leaf.activate.connect (() => add_leaf_after_focused ());
            add_action (act_new_leaf);

            var act_new_tab = new SimpleAction ("new-tab", null);
            act_new_tab.activate.connect (() => add_tab_after_focused ());
            add_action (act_new_tab);

            var act_quit = new SimpleAction ("quit", null);
            act_quit.activate.connect (() => quit ());
            add_action (act_quit);

            // Load settings schema
            var source = SettingsSchemaSource.get_default ();
            if (source.lookup ("dev.sinty.leafs", true) == null) {
                try {
                    string exe_path = FileUtils.read_link ("/proc/self/exe");
                    var exe_dir = File.new_for_path (exe_path).get_parent ();
                    var schema_file = exe_dir.get_child ("data").get_child ("gschemas.compiled");
                    if (schema_file.query_exists ()) {
                        var compiled = new SettingsSchemaSource.from_directory (
                            schema_file.get_parent ().get_path (), source, true);
                        var schema = compiled.lookup ("dev.sinty.leafs", true);
                        if (schema != null)
                            settings = new GLib.Settings.full (schema, null, null);
                    }
                } catch (Error e) {
                    warning ("Leafs: failed to load dev schemas: %s", e.message);
                }
            }
            if (settings == null)
                settings = new GLib.Settings ("dev.sinty.leafs");

            // React to font/theme changes live
            settings.changed["font-size"].connect    ((_k) => apply_settings_to_all ());
            settings.changed["font-family"].connect  ((_k) => apply_settings_to_all ());
            settings.changed["color-scheme"].connect ((_k) => sync_terminal_theme ());
            settings.changed["scrollback-lines"].connect ((_k) => apply_settings_to_all ());

            // When "auto" theme is active, re-apply whenever system accent or dark-mode changes
            desktop_settings = Singularity.Core.safe_settings ("dev.sinty.desktop");
            if (desktop_settings != null) {
                desktop_settings.changed["accent-color"].connect ((_k) => {
                    if (settings.get_string ("color-scheme") == "auto")
                        apply_settings_to_all ();
                });
                desktop_settings.changed["custom-accent-color"].connect ((_k) => {
                    if (settings.get_string ("color-scheme") == "auto")
                        apply_settings_to_all ();
                });
            }
            Singularity.Style.ThemeMode.get_default ().changed.connect (() => {
                sync_window_chrome ();
                if (settings.get_string ("color-scheme") == "auto")
                    apply_settings_to_all ();
            });
            Singularity.Style.StyleManager.get_default ().notify["accent-hex"].connect (() => {
                if (settings.get_string ("color-scheme") == "auto")
                    apply_settings_to_all ();
            });

            sync_window_chrome ();
        }

        protected override void activate () {
            if (main_window != null) {
                main_window.present ();
                if (_startup_cmd != null) {
                    add_leaf_cmd (_startup_cmd);
                    _startup_cmd = null;
                }
                return;
            }
            leaves       = new ArrayList<LeafPane> ();
            ssh_sessions = new ArrayList<SshSession> ();
            blooms       = new ArrayList<BloomDef> ();
            build_window ();
            load_ssh_sessions ();
            load_blooms ();
            if (_startup_cmd != null) {
                // Launched as a terminal for a specific command: skip session
                // restore and open just that command.
                add_leaf_cmd (_startup_cmd);
                _startup_cmd = null;
            } else {
                restore_session ();
                if (leaves.is_empty) add_leaf (null, null);
            }
            main_window.present ();
        }

        protected override void shutdown () {
            if (session_save_source != 0) {
                GLib.Source.remove (session_save_source);
                session_save_source = 0;
            }
            save_session ();
            if (leaves != null) {
                foreach (var leaf in leaves)
                    leaf.prepare_close ();
            }
            base.shutdown ();
        }


        private void build_window () {
            main_window = new LeafsWindow (this);
            window_cells[main_window] = new ArrayList<LeafCell> ();

            // Keyboard shortcuts
            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            key_ctrl.key_pressed.connect (on_key_pressed);
            ((Gtk.Widget) main_window).add_controller (key_ctrl);

            main_window.close_request.connect (() => {
                save_session ();
                return false;
            });
        }

        private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
            bool ctrl  = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

            if (ctrl && shift) {
                switch (Gdk.keyval_to_lower (keyval)) {
                    case Gdk.Key.n:
                        add_leaf_after_focused ();
                        return true;
                    case Gdk.Key.t:
                        add_tab_after_focused ();
                        return true;
                    case Gdk.Key.c:
                        var t = get_focused_terminal ();
                        if (t != null && t.get_has_selection ()) {
                            t.copy_clipboard_format (Vte.Format.TEXT);
                            return true;
                        }
                        return false;
                    case Gdk.Key.v:
                        var t = get_focused_terminal ();
                        if (t != null) { LeafPane.smart_paste (t); return true; }
                        return false;
                    case Gdk.Key.b:
                        spawn_bloom ("", "");
                        return true;
                }
            }
            // Ctrl+Q - save and close all
            if (ctrl && !shift && keyval == Gdk.Key.q) {
                save_session ();
                main_window.close ();
                return true;
            }
            return false;
        }

        private void add_leaf (string? cwd, string? id) {
            insert_leaf_after (null, cwd, id);
        }

        private void insert_leaf_after (LeafPane? after, string? cwd, string? id, string[]? spawn_cmd = null) {
            var leaf = new LeafPane (settings, cwd, id, spawn_cmd);
            connect_leaf_signals (leaf);
            LeafsWindow target = (after != null && leaf_window.has_key(after))
                ? leaf_window[after]
                : main_window;
            leaf_window[leaf] = target;

            insert_leaf_in_list (leaf, after);
            var cell = create_cell (leaf);
            leaf_cell[leaf] = cell;

            var cells = window_cells[target];
            int cell_index = after != null && leaf_cell.has_key (after)
                ? cells.index_of (leaf_cell[after])
                : cells.size - 1;
            if (cell_index < 0 || cell_index >= cells.size - 1)
                cells.add (cell);
            else
                cells.insert (cell_index + 1, cell);

            window_layout.unset (target);
            rebuild_separators_in (target);
            queue_save_session ();
            leaf.terminal.grab_focus ();
        }

        private void insert_tab_after (LeafPane? after, string? cwd, string? id,
                                       string[]? spawn_cmd = null) {
            if (after == null || !leaf_cell.has_key (after)) {
                insert_leaf_after (after, cwd, id, spawn_cmd);
                return;
            }

            var leaf = new LeafPane (settings, cwd, id, spawn_cmd);
            connect_leaf_signals (leaf);
            var target = window_of (after);
            var cell = leaf_cell[after];
            leaf_window[leaf] = target;
            leaf_cell[leaf] = cell;
            insert_leaf_in_list (leaf, after);
            cell.add_leaf (leaf);
            queue_save_session ();
            leaf.terminal.grab_focus ();
        }

        private void insert_leaf_in_list (LeafPane leaf, LeafPane? after) {
            if (after == null) {
                leaves.add (leaf);
                return;
            }
            int index = leaves.index_of (after);
            if (index < 0 || index >= leaves.size - 1)
                leaves.add (leaf);
            else
                leaves.insert (index + 1, leaf);
        }

        private LeafCell create_cell (LeafPane leaf) {
            var cell = new LeafCell ();
            cell.close_requested.connect (on_close_leaf);
            cell.add_leaf (leaf);
            return cell;
        }

        private void connect_leaf_signals (LeafPane leaf) {
            leaf.close_requested.connect (on_close_leaf);
            leaf.add_requested.connect   ((pane) => insert_leaf_after (pane, null, null));
            leaf.tab_requested.connect   ((pane) => insert_tab_after (pane, null, null));
            leaf.flower_requested.connect (() => open_flower (null));
            leaf.detach_requested.connect (detach_leaf_to_flower);
            leaf.settings_requested.connect (show_settings);
            leaf.ssh_btn.clicked.connect (() => show_ssh_popover (leaf.ssh_btn));
            leaf.bloom_btn.clicked.connect (() => show_bloom_popover (leaf.bloom_btn));
            leaf.close_all_requested.connect (() => {
                save_session ();
                close_all_windows ();
            });
            leaf.tile_drop_requested.connect (on_tile_drop);
            leaf.state_changed.connect (queue_save_session);
        }

        private void close_all_windows () {
            // Snapshot to avoid mutation-during-iteration when close_request fires.
            var snapshot = new ArrayList<LeafsWindow>();
            foreach (var w in flowers) snapshot.add (w);
            foreach (var w in snapshot) w.close ();
            main_window.close ();
        }

        /**
         * Create a new "flower" window with a fresh leaf inside it.
         */
        private void open_flower (string? cwd) {
            var win = create_flower_window ();

            var leaf = new LeafPane (settings, cwd, null, null);
            connect_leaf_signals (leaf);
            leaf_window[leaf] = win;
            var cell = create_cell (leaf);
            leaf_cell[leaf] = cell;
            window_cells[win].add (cell);
            leaves.add (leaf);
            rebuild_separators_in (win);
            queue_save_session ();

            win.present ();
            leaf.terminal.grab_focus ();
        }

        private LeafsWindow create_flower_window () {
            var win = new LeafsWindow (this);
            win.close_request.connect (() => {
                save_session ();
                return false;
            });
            flowers.add (win);
            window_cells[win] = new ArrayList<LeafCell> ();
            return win;
        }

        /**
         * Move an existing leaf into its own new flower window.
         */
        private void detach_leaf_to_flower (LeafPane leaf) {
            var src = window_of (leaf);
            // If this is the only leaf in its window, detach is a no-op.
            int siblings = 0;
            foreach (var l in leaves) if (leaf_window[l] == src) siblings++;
            if (siblings <= 1) return;

            var source_cell = leaf_cell[leaf];
            source_cell.remove_leaf (leaf);
            if (source_cell.leaves.is_empty) {
                remove_layout_cell (src, source_cell);
                window_cells[src].remove (source_cell);
            }

            var win = create_flower_window ();
            var target_cell = create_cell (leaf);
            leaf_window[leaf] = win;
            leaf_cell[leaf] = target_cell;
            window_cells[win].add (target_cell);
            rebuild_separators_in (src);
            rebuild_separators_in (win);
            queue_save_session ();
            win.present ();
            leaf.terminal.grab_focus ();
        }

        private void on_tile_drop (string source_id, LeafPane target,
                                   LeafDropZone zone) {
            var source = leaf_by_id (source_id);
            if (source == null || source == target) return;

            var src_win = window_of (source);
            var dst_win = window_of (target);
            if (src_win != dst_win && leaves_in_window (src_win) <= 1) return;

            var src_cell = leaf_cell[source];
            var dst_cell = leaf_cell[target];
            if (src_cell == dst_cell && zone == LeafDropZone.CENTER) {
                src_cell.tabs.notebook.set_current_page (
                    src_cell.tabs.notebook.page_num (source));
                source.terminal.grab_focus ();
                return;
            }

            ensure_window_layout (src_win);
            if (src_win != dst_win)
                ensure_window_layout (dst_win);

            src_cell.remove_leaf (source);
            if (src_cell.leaves.is_empty) {
                window_cells[src_win].remove (src_cell);
                remove_layout_cell (src_win, src_cell);
            }

            leaves.remove (source);
            int target_index = leaves.index_of (target);
            bool before = zone == LeafDropZone.LEFT || zone == LeafDropZone.TOP;
            int leaf_index = target_index < 0
                ? leaves.size
                : target_index + (before ? 0 : 1);
            leaves.insert (leaf_index.clamp (0, leaves.size), source);

            if (zone == LeafDropZone.CENTER) {
                dst_cell.add_leaf (source);
                leaf_cell[source] = dst_cell;
            } else {
                var moved_cell = create_cell (source);
                int cell_index = window_cells[dst_win].index_of (dst_cell);
                if (!before) cell_index++;
                window_cells[dst_win].insert (
                    cell_index.clamp (0, window_cells[dst_win].size), moved_cell);
                insert_layout_cell (dst_win, dst_cell, moved_cell, zone);
                leaf_cell[source] = moved_cell;
            }
            leaf_window[source] = dst_win;

            rebuild_separators_in (src_win);
            if (src_win != dst_win)
                rebuild_separators_in (dst_win);
            queue_save_session ();
            source.terminal.grab_focus ();
        }

        private LeafPane? leaf_by_id (string id) {
            foreach (var leaf in leaves)
                if (leaf.pane_id == id) return leaf;
            return null;
        }

        private int leaves_in_window (LeafsWindow win) {
            int count = 0;
            foreach (var leaf in leaves)
                if (window_of (leaf) == win) count++;
            return count;
        }

        private void on_close_leaf (LeafPane pane) {
            if (!leaves.contains (pane)) return;
            var win = window_of (pane);
            // Count siblings in the same window
            int siblings = 0;
            foreach (var l in leaves) if (leaf_window[l] == win) siblings++;


            if (win == main_window && leaves.size == 1) {
                // Last leaf in the only window → quit
                pane.persist_state ();
                save_session ();
                pane.prepare_close ();
                main_window.close ();
                return;
            }
            if (siblings == 1) {
                // Last leaf in this flower → close just the flower window
                remove_leaf_from_layout (pane, win);
                if (win != main_window) {
                    flowers.remove (win);
                    window_cells.unset (win);
                    window_layout.unset (win);
                    win.close ();
                } else {
                    rebuild_separators_in (win);
                }
                save_session ();
                return;
            }
            if (remove_leaf_from_layout (pane, win))
                rebuild_separators_in (win);
            save_session ();
        }

        private bool remove_leaf_from_layout (LeafPane pane, LeafsWindow win) {
            var cell = leaf_cell[pane];
            cell.remove_leaf (pane);
            bool removed_cell = cell.leaves.is_empty;
            if (removed_cell) {
                remove_layout_cell (win, cell);
                window_cells[win].remove (cell);
            }
            pane.prepare_close ();
            leaves.remove (pane);
            leaf_window.unset (pane);
            leaf_cell.unset (pane);
            return removed_cell;
        }

        private int _bloom_cascade = 0;

        private void spawn_bloom (string label, string command) {
            var leaf = get_focused_leaf ();
            var win  = leaf != null ? window_of (leaf) : main_window;
            string? cwd = leaf != null ? leaf.get_working_dir () : null;
            int off = 24 + (_bloom_cascade % 6) * 28;
            _bloom_cascade++;
            Bloom.spawn (settings, win.bloom_overlay, label, command, cwd, off, off);
        }

        private void load_blooms () {
            blooms.clear ();
            foreach (var js in settings.get_strv ("blooms")) {
                var d = BloomDef.from_json (js);
                if (d != null) blooms.add (d);
            }
        }

        private void save_blooms () {
            string[] arr = new string[blooms.size];
            for (int i = 0; i < blooms.size; i++)
                arr[i] = blooms[i].to_json ();
            settings.set_strv ("blooms", arr);
        }

        private void show_bloom_dialog (BloomDef? existing) {
            var dlg = new LeafsBloomDialog (main_window, existing);
            dlg.bloom_saved.connect ((def, replacing) => {
                if (replacing != null) {
                    int idx = blooms.index_of (replacing);
                    if (idx >= 0) blooms[idx] = def;
                    else blooms.add (def);
                } else {
                    blooms.add (def);
                }
                save_blooms ();
            });
            dlg.present ();
        }

        private void show_bloom_popover (Gtk.Button anchor) {
            var popover = new Gtk.Popover ();
            popover.set_parent (anchor);
            popover.has_arrow = true;

            var root_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            root_box.set_size_request (290, -1);

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            header.margin_start  = 14;
            header.margin_end    = 6;
            header.margin_top    = 10;
            header.margin_bottom = 8;

            var title_lbl = new Gtk.Label (_("Blooms"));
            title_lbl.add_css_class ("heading");
            title_lbl.hexpand = true;
            title_lbl.xalign  = 0;

            var add_btn = new Gtk.Button.from_icon_name ("list-add-symbolic");
            add_btn.add_css_class ("flat");
            add_btn.valign = Gtk.Align.CENTER;
            add_btn.clicked.connect (() => {
                popover.popdown ();
                show_bloom_dialog (null);
            });

            header.append (title_lbl);
            header.append (add_btn);
            root_box.append (header);
            root_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var list = new Gtk.ListBox ();
            list.selection_mode = Gtk.SelectionMode.NONE;
            list.add_css_class ("boxed-list");
            list.margin_top = 6; list.margin_bottom = 6;
            list.margin_start = 8; list.margin_end = 8;

            if (blooms.is_empty) {
                var empty_row = new Gtk.ListBoxRow ();
                empty_row.activatable = false;
                var empty_lbl = new Gtk.Label (_("No blooms - click + to add one"));
                empty_lbl.opacity = 0.5;
                empty_lbl.margin_top = 14; empty_lbl.margin_bottom = 14;
                empty_row.set_child (empty_lbl);
                list.append (empty_row);
            } else {
                foreach (var d in blooms) {
                    var row = new Gtk.ListBoxRow ();
                    var row_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                    row_box.margin_start = 8; row_box.margin_end = 4;
                    row_box.margin_top = 6; row_box.margin_bottom = 6;

                    var icon = new Gtk.Image.from_icon_name ("system-run-symbolic");
                    icon.pixel_size = 16;
                    icon.opacity = 0.7;

                    var labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                    labels.hexpand = true;
                    var name_lbl = new Gtk.Label (d.label);
                    name_lbl.xalign = 0;
                    name_lbl.halign = Gtk.Align.START;
                    var sub_lbl = new Gtk.Label (d.command);
                    sub_lbl.xalign = 0;
                    sub_lbl.halign = Gtk.Align.START;
                    sub_lbl.ellipsize = Pango.EllipsizeMode.END;
                    sub_lbl.add_css_class ("caption");
                    sub_lbl.opacity = 0.55;
                    labels.append (name_lbl);
                    labels.append (sub_lbl);

                    var edit_btn = new Gtk.Button.from_icon_name ("view-more-symbolic");
                    edit_btn.add_css_class ("flat");
                    edit_btn.valign = Gtk.Align.CENTER;
                    edit_btn.clicked.connect (() => {
                        popover.popdown ();
                        show_bloom_dialog (d);
                    });

                    var del_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                    del_btn.add_css_class ("flat");
                    del_btn.add_css_class ("destructive-action");
                    del_btn.valign = Gtk.Align.CENTER;
                    del_btn.clicked.connect (() => {
                        blooms.remove (d);
                        save_blooms ();
                        popover.popdown ();
                    });

                    row_box.append (icon);
                    row_box.append (labels);
                    row_box.append (edit_btn);
                    row_box.append (del_btn);
                    row.set_child (row_box);

                    row.activatable = true;
                    var gesture = new Gtk.GestureClick ();
                    gesture.released.connect ((n, x, y) => {
                        popover.popdown ();
                        spawn_bloom (d.label, d.command);
                    });
                    row.add_controller (gesture);

                    list.append (row);
                }
            }

            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.max_content_height = 320;
            scroll.propagate_natural_height = true;
            scroll.set_child (list);
            root_box.append (scroll);

            popover.set_child (root_box);
            popover.popup ();
        }

        private void add_leaf_after_focused () {
            LeafPane? focused = get_focused_leaf ();
            insert_leaf_after (focused, null, null);
        }

        private void add_tab_after_focused () {
            LeafPane? focused = get_focused_leaf ();
            insert_tab_after (focused, null, null);
        }

        private LeafPane? get_focused_leaf () {
            foreach (var leaf in leaves) {
                if (leaf.has_focus ()) return leaf;
            }
            foreach (var cells in window_cells.values) {
                for (int i = cells.size - 1; i >= 0; i--) {
                    var active = cells[i].active_leaf ();
                    if (active != null) return active;
                }
            }
            return leaves.size > 0 ? leaves.last () : null;
        }

        private Vte.Terminal? get_focused_terminal () {
            var leaf = get_focused_leaf ();
            return leaf != null ? leaf.terminal : null;
        }

        private void rebuild_separators_in (LeafsWindow win) {
            var cells = window_cells[win];
            foreach (var cell in cells)
                detach_cell_tabs (win, cell);

            var c = win.leaves_box.get_first_child ();
            while (c != null) { var nx = c.get_next_sibling (); win.leaves_box.remove (c); c = nx; }
            if (cells.is_empty) {
                window_layout.unset (win);
                return;
            }

            var root = ensure_window_layout (win);
            if (root != null)
                win.leaves_box.append (build_tiled_widget (root));

            foreach (var cell in cells)
                foreach (var leaf in cell.leaves)
                    leaf.redraw_terminals ();
        }

        private void detach_cell_tabs (LeafsWindow win, LeafCell cell) {
            var parent = cell.tabs.get_parent ();
            if (parent == null) return;
            if (parent == win.leaves_box) {
                win.leaves_box.remove (cell.tabs);
                return;
            }
            var paned = parent as Gtk.Paned;
            if (paned != null) {
                if (paned.get_start_child () == cell.tabs)
                    paned.set_start_child (null);
                else if (paned.get_end_child () == cell.tabs)
                    paned.set_end_child (null);
                return;
            }
            cell.tabs.unparent ();
        }

        private LeafLayoutNode? ensure_window_layout (LeafsWindow win) {
            if (window_layout.has_key (win))
                return window_layout[win];
            var cells = window_cells[win];
            if (cells.is_empty) return null;
            Orientation orientation = win.leaves_box.get_height () > win.leaves_box.get_width ()
                ? Orientation.VERTICAL
                : Orientation.HORIZONTAL;
            var root = build_balanced_layout (cells, 0, cells.size, orientation);
            window_layout[win] = root;
            return root;
        }

        private LeafLayoutNode build_balanced_layout (ArrayList<LeafCell> cells,
                                                       int first, int count,
                                                       Orientation orientation) {
            if (count == 1)
                return new LeafLayoutNode.for_cell (cells[first]);

            int first_count = count / 2;
            int second_count = count - first_count;
            Orientation next = orientation == Orientation.HORIZONTAL
                ? Orientation.VERTICAL
                : Orientation.HORIZONTAL;
            return new LeafLayoutNode.for_split (
                orientation,
                build_balanced_layout (cells, first, first_count, next),
                build_balanced_layout (cells, first + first_count, second_count, next));
        }

        private Gtk.Widget build_tiled_widget (LeafLayoutNode node) {
            if (node.cell != null)
                return node.cell.tabs;

            var start = node.start;
            var end = node.end;
            if (start == null || end == null)
                return start != null ? build_tiled_widget (start) : build_tiled_widget (end);

            var paned = new Gtk.Paned (node.orientation);
            paned.add_css_class ("leaf-paned");
            paned.resize_start_child = true;
            paned.resize_end_child = true;
            paned.shrink_start_child = false;
            paned.shrink_end_child = false;
            paned.set_start_child (build_tiled_widget (start));
            paned.set_end_child (build_tiled_widget (end));

            double ratio = (double) start.leaf_count () / (double) node.leaf_count ();
            GLib.Idle.add (() => {
                int span = node.orientation == Orientation.HORIZONTAL
                    ? paned.get_width ()
                    : paned.get_height ();
                if (span > 1)
                    paned.position = (int) Math.round (span * ratio);
                return GLib.Source.REMOVE;
            });
            return paned;
        }

        private void remove_layout_cell (LeafsWindow win, LeafCell cell) {
            var root = ensure_window_layout (win);
            if (root == null) return;
            bool removed;
            var updated = remove_layout_cell_from (root, cell, out removed);
            if (!removed) return;
            if (updated == null)
                window_layout.unset (win);
            else
                window_layout[win] = updated;
        }

        private LeafLayoutNode? remove_layout_cell_from (LeafLayoutNode node,
                                                         LeafCell cell,
                                                         out bool removed) {
            if (node.cell != null) {
                removed = node.cell == cell;
                return removed ? null : node;
            }

            bool child_removed;
            if (node.start != null) {
                var start = remove_layout_cell_from (node.start, cell, out child_removed);
                if (child_removed) {
                    removed = true;
                    if (start == null) return node.end;
                    node.start = start;
                    return node;
                }
            }
            if (node.end != null) {
                var end = remove_layout_cell_from (node.end, cell, out child_removed);
                if (child_removed) {
                    removed = true;
                    if (end == null) return node.start;
                    node.end = end;
                    return node;
                }
            }
            removed = false;
            return node;
        }

        private void insert_layout_cell (LeafsWindow win, LeafCell target,
                                         LeafCell inserted, LeafDropZone zone) {
            var root = ensure_window_layout (win);
            if (root == null) {
                window_layout[win] = new LeafLayoutNode.for_cell (inserted);
                return;
            }

            Orientation orientation = zone == LeafDropZone.LEFT || zone == LeafDropZone.RIGHT
                ? Orientation.HORIZONTAL
                : Orientation.VERTICAL;
            bool before = zone == LeafDropZone.LEFT || zone == LeafDropZone.TOP;
            var target_node = new LeafLayoutNode.for_cell (target);
            var inserted_node = new LeafLayoutNode.for_cell (inserted);
            var split = new LeafLayoutNode.for_split (
                orientation,
                before ? inserted_node : target_node,
                before ? target_node : inserted_node);
            bool replaced;
            var updated = replace_layout_cell (root, target, split, out replaced);
            window_layout[win] = replaced ? updated : build_balanced_layout (
                window_cells[win], 0, window_cells[win].size, orientation);
        }

        private LeafLayoutNode replace_layout_cell (LeafLayoutNode node,
                                                    LeafCell target,
                                                    LeafLayoutNode replacement,
                                                    out bool replaced) {
            if (node.cell != null) {
                replaced = node.cell == target;
                return replaced ? replacement : node;
            }

            if (node.start != null) {
                node.start = replace_layout_cell (
                    node.start, target, replacement, out replaced);
                if (replaced) return node;
            }
            if (node.end != null) {
                node.end = replace_layout_cell (
                    node.end, target, replacement, out replaced);
                if (replaced) return node;
            }
            replaced = false;
            return node;
        }

        private Singularity.Widgets.PreferencesWindow? prefs_win = null;

        private void show_settings () {
            if (Singularity.Runtime.is_shell_running ()) {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (
                        BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.leafs");
                    return;
                } catch (Error e) {
                    warning ("Leafs: failed to open shell settings: %s", e.message);
                }
            }
            show_local_settings ();
        }

        private void show_local_settings () {
            if (prefs_win != null) { prefs_win.present (); return; }

            var page = new Singularity.Widgets.PreferencesPage ();
            var group = new Singularity.Widgets.PreferencesGroup (_("Terminal"));

            var themes = Singularity.Core.TerminalThemes.get_all ();
            string[] names = {};
            foreach (var t in themes) names += t.name;
            string current = settings.get_string ("color-scheme");
            string current_name = "";
            foreach (var t in themes)
                if (t.id == current) current_name = t.name;

            var theme_row = new Singularity.Widgets.SelectionRow (_("Theme"), names, current_name);
            theme_row.selected.connect ((item) => {
                foreach (var t in themes) {
                    if (t.name == item) {
                        if (settings.get_string ("color-scheme") != t.id)
                            settings.set_string ("color-scheme", t.id);
                        break;
                    }
                }
            });
            group.add_row (theme_row);
            page.append_group (group);

            prefs_win = new Singularity.Widgets.PreferencesWindow (this, page, false);
            prefs_win.close_request.connect (() => { prefs_win = null; return false; });
            prefs_win.present ();
        }


        private bool terminal_is_dark () {
            string scheme = settings.get_string ("color-scheme");
            if (scheme == "auto")
                return Singularity.Style.ThemeMode.get_default ().app_dark ();
            var theme = Singularity.Core.TerminalThemes.get_by_id (scheme);
            if (theme == null)
                theme = Singularity.Core.TerminalThemes.get_by_id ("onedark");
            return theme != null
                && Singularity.Core.TerminalThemes.is_dark_background (theme.background);
        }

        private void sync_window_chrome () {
            bool dark = terminal_is_dark ();
            Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = dark;
            Singularity.Style.StyleManager.get_default ().apply_color_scheme (dark);
        }

        private void sync_terminal_theme () {
            sync_window_chrome ();
            apply_settings_to_all ();
        }

        private void apply_settings_to_all () {
            if (leaves == null)
                return;
            foreach (var leaf in leaves)
                leaf.apply_settings (settings);
        }

        private void queue_save_session () {
            if (restoring_session || session_save_source != 0) return;
            session_save_source = GLib.Timeout.add (250, () => {
                session_save_source = 0;
                save_session ();
                return GLib.Source.REMOVE;
            });
        }

        private void save_session () {
            if (leaves == null || main_window == null) return;
            foreach (var leaf in leaves)
                leaf.persist_state ();

            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("version");
            builder.add_int_value (3);
            builder.set_member_name ("windows");
            builder.begin_array ();
            append_window_session (builder, main_window, true);
            foreach (var win in flowers)
                append_window_session (builder, win, false);
            builder.end_array ();
            builder.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (builder.get_root ());
            settings.set_string ("session", gen.to_data (null));
            GLib.Settings.sync ();
        }

        private void append_window_session (Json.Builder builder, LeafsWindow win, bool is_main) {
            if (!window_cells.has_key (win)) return;
            builder.begin_object ();
            builder.set_member_name ("main");
            builder.add_boolean_value (is_main);
            builder.set_member_name ("cells");
            builder.begin_array ();
            foreach (var cell in window_cells[win]) {
                builder.begin_object ();
                builder.set_member_name ("active");
                builder.add_int_value (cell.tabs.notebook.get_current_page ());
                builder.set_member_name ("leaves");
                builder.begin_array ();
                foreach (var leaf in cell.leaves) {
                    builder.begin_object ();
                    builder.set_member_name ("id");
                    builder.add_string_value (leaf.pane_id);
                    builder.set_member_name ("cwd");
                    builder.add_string_value (leaf.get_working_dir ());
                    builder.end_object ();
                }
                builder.end_array ();
                builder.end_object ();
            }
            builder.end_array ();
            var layout = ensure_window_layout (win);
            if (layout != null) {
                builder.set_member_name ("layout");
                append_layout_session (builder, layout, window_cells[win]);
            }
            builder.end_object ();
        }

        private void append_layout_session (Json.Builder builder, LeafLayoutNode node,
                                            ArrayList<LeafCell> cells) {
            builder.begin_object ();
            if (node.cell != null) {
                builder.set_member_name ("cell");
                builder.add_int_value (cells.index_of (node.cell));
            } else {
                builder.set_member_name ("orientation");
                builder.add_string_value (node.orientation == Orientation.HORIZONTAL
                    ? "horizontal"
                    : "vertical");
                builder.set_member_name ("start");
                append_layout_session (builder, node.start, cells);
                builder.set_member_name ("end");
                append_layout_session (builder, node.end, cells);
            }
            builder.end_object ();
        }

        private void restore_session () {
            string json = settings.get_string ("session");
            if (json == null || json == "") return;
            restoring_session = true;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json);
                var root = parser.get_root ();
                if (root == null) return;
                if (root.get_node_type () == Json.NodeType.ARRAY)
                    restore_legacy_session (root.get_array ());
                else if (root.get_node_type () == Json.NodeType.OBJECT)
                    restore_tiled_session (root.get_object ());
            } catch (Error e) {
                warning ("Leafs: failed to restore session: %s", e.message);
            } finally {
                restoring_session = false;
            }
        }

        private void restore_legacy_session (Json.Array? panes) {
            if (panes == null) return;
            for (uint i = 0; i < panes.get_length (); i++) {
                var pane = panes.get_object_element (i);
                if (pane == null) continue;
                var cell = new LeafCell ();
                cell.close_requested.connect (on_close_leaf);
                restore_leaf (pane, main_window, cell);
                if (!cell.leaves.is_empty)
                    window_cells[main_window].add (cell);
            }
            rebuild_separators_in (main_window);
        }

        private void restore_tiled_session (Json.Object? session) {
            if (session == null || !session.has_member ("windows")) return;
            var windows = session.get_array_member ("windows");
            if (windows == null) return;
            bool restored_main = false;

            for (uint i = 0; i < windows.get_length (); i++) {
                var saved_window = windows.get_object_element (i);
                if (saved_window == null || !saved_window.has_member ("cells")) continue;
                bool wants_main = saved_window.has_member ("main")
                    && saved_window.get_boolean_member ("main");
                LeafsWindow win;
                if (wants_main && !restored_main) {
                    win = main_window;
                    restored_main = true;
                } else {
                    win = create_flower_window ();
                }

                var cells = saved_window.get_array_member ("cells");
                for (uint j = 0; j < cells.get_length (); j++) {
                    var saved_cell = cells.get_object_element (j);
                    if (saved_cell == null || !saved_cell.has_member ("leaves")) continue;
                    var cell = new LeafCell ();
                    cell.close_requested.connect (on_close_leaf);
                    var saved_leaves = saved_cell.get_array_member ("leaves");
                    for (uint k = 0; k < saved_leaves.get_length (); k++) {
                        var saved_leaf = saved_leaves.get_object_element (k);
                        if (saved_leaf != null)
                            restore_leaf (saved_leaf, win, cell);
                    }
                    if (cell.leaves.is_empty) continue;
                    window_cells[win].add (cell);
                    int active = saved_cell.has_member ("active")
                        ? (int) saved_cell.get_int_member ("active")
                        : 0;
                    cell.tabs.notebook.set_current_page (
                        active.clamp (0, cell.leaves.size - 1));
                }
                if (saved_window.has_member ("layout")) {
                    var layout = restore_layout_session (
                        saved_window.get_object_member ("layout"), window_cells[win]);
                    if (layout != null && layout_matches_cells (layout, window_cells[win]))
                        window_layout[win] = layout;
                }
                rebuild_separators_in (win);
                if (win != main_window)
                    win.present ();
            }
        }

        private LeafLayoutNode? restore_layout_session (Json.Object? saved,
                                                        ArrayList<LeafCell> cells) {
            if (saved == null) return null;
            if (saved.has_member ("cell")) {
                int index = (int) saved.get_int_member ("cell");
                return index >= 0 && index < cells.size
                    ? new LeafLayoutNode.for_cell (cells[index])
                    : null;
            }
            if (!saved.has_member ("orientation") ||
                !saved.has_member ("start") || !saved.has_member ("end"))
                return null;

            string orientation = saved.get_string_member ("orientation");
            if (orientation != "horizontal" && orientation != "vertical")
                return null;
            var start = restore_layout_session (
                saved.get_object_member ("start"), cells);
            var end = restore_layout_session (
                saved.get_object_member ("end"), cells);
            if (start == null || end == null) return null;
            return new LeafLayoutNode.for_split (
                orientation == "horizontal" ? Orientation.HORIZONTAL : Orientation.VERTICAL,
                start, end);
        }

        private bool layout_matches_cells (LeafLayoutNode layout,
                                           ArrayList<LeafCell> cells) {
            var found = new HashSet<LeafCell> ();
            if (!collect_layout_cells (layout, found) || found.size != cells.size)
                return false;
            foreach (var cell in cells)
                if (!found.contains (cell)) return false;
            return true;
        }

        private bool collect_layout_cells (LeafLayoutNode node,
                                           HashSet<LeafCell> found) {
            if (node.cell != null)
                return found.add (node.cell);
            return node.start != null && node.end != null
                && collect_layout_cells (node.start, found)
                && collect_layout_cells (node.end, found);
        }

        private void restore_leaf (Json.Object saved, LeafsWindow win, LeafCell cell) {
            string cwd = saved.has_member ("cwd")
                ? saved.get_string_member ("cwd")
                : GLib.Environment.get_home_dir ();
            string id = saved.has_member ("id")
                ? saved.get_string_member ("id")
                : GLib.Uuid.string_random ();
            if (!FileUtils.test (cwd, FileTest.IS_DIR))
                cwd = GLib.Environment.get_home_dir ();

            var leaf = new LeafPane (settings, cwd, id);
            connect_leaf_signals (leaf);
            leaves.add (leaf);
            leaf_window[leaf] = win;
            leaf_cell[leaf] = cell;
            cell.add_leaf (leaf, false);
        }

        private void load_ssh_sessions () {
            ssh_sessions.clear ();
            foreach (var js in settings.get_strv ("ssh-sessions")) {
                var s = SshSession.from_json (js);
                if (s != null) ssh_sessions.add (s);
            }
        }

        private void save_ssh_sessions () {
            string[] arr = new string[ssh_sessions.size];
            for (int i = 0; i < ssh_sessions.size; i++)
                arr[i] = ssh_sessions[i].to_json ();
            settings.set_strv ("ssh-sessions", arr);
        }

        private void connect_ssh (SshSession session) {
            string[] cmd = {};
            if (session.password != "") {
                cmd += "sshpass"; cmd += "-p"; cmd += session.password;
            }
            cmd += "ssh";
            if (session.key_path != "") { cmd += "-i"; cmd += session.key_path; }
            cmd += "-p"; cmd += session.port.to_string ();
            cmd += "%s@%s".printf (session.user, session.host);
            insert_leaf_after (get_focused_leaf (), null, null, cmd);
        }

        private void show_ssh_dialog (SshSession? existing, Gtk.Widget? anchor = null) {
            var dlg = new LeafsSshDialog (main_window, existing);
            dlg.session_saved.connect ((s) => {
                bool found = false;
                for (int i = 0; i < ssh_sessions.size; i++) {
                    if (ssh_sessions[i].id == s.id) {
                        ssh_sessions[i] = s;
                        found = true;
                        break;
                    }
                }
                if (!found) ssh_sessions.add (s);
                save_ssh_sessions ();
            });
            dlg.present ();
        }

        private void show_ssh_popover (Gtk.Button anchor) {
            var popover = new Gtk.Popover ();
            popover.set_parent (anchor);
            popover.has_arrow = true;

            var root_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            root_box.set_size_request (290, -1);

            // Header row: title + add button
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            header.margin_start  = 14;
            header.margin_end    = 6;
            header.margin_top    = 10;
            header.margin_bottom = 8;

            var title_lbl = new Gtk.Label (_("SSH Sessions"));
            title_lbl.add_css_class ("heading");
            title_lbl.hexpand = true;
            title_lbl.xalign  = 0;

            var add_btn = new Gtk.Button.from_icon_name ("list-add-symbolic");
            add_btn.add_css_class ("flat");
            add_btn.valign = Gtk.Align.CENTER;
            add_btn.clicked.connect (() => {
                popover.popdown ();
                show_ssh_dialog (null);
            });

            header.append (title_lbl);
            header.append (add_btn);
            root_box.append (header);
            root_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Session list
            var list = new Gtk.ListBox ();
            list.selection_mode = Gtk.SelectionMode.NONE;
            list.add_css_class ("boxed-list");
            list.margin_top = 6; list.margin_bottom = 6;
            list.margin_start = 8; list.margin_end = 8;

            if (ssh_sessions.is_empty) {
                var empty_row = new Gtk.ListBoxRow ();
                empty_row.activatable = false;
                var empty_lbl = new Gtk.Label (_("No sessions - click + to add one"));
                empty_lbl.opacity = 0.5;
                empty_lbl.margin_top = 14; empty_lbl.margin_bottom = 14;
                empty_row.set_child (empty_lbl);
                list.append (empty_row);
            } else {
                foreach (var s in ssh_sessions) {
                    var row = new Gtk.ListBoxRow ();
                    var row_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                    row_box.margin_start = 8; row_box.margin_end = 4;
                    row_box.margin_top = 6; row_box.margin_bottom = 6;

                    var icon = new Gtk.Image.from_icon_name ("network-server-symbolic");
                    icon.pixel_size = 16;
                    icon.opacity = 0.7;

                    var labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                    labels.hexpand = true;
                    var name_lbl = new Gtk.Label (s.name);
                    name_lbl.xalign = 0;
                    name_lbl.halign = Gtk.Align.START;
                    var sub_lbl = new Gtk.Label ("%s@%s:%d".printf (s.user, s.host, s.port));
                    sub_lbl.xalign = 0;
                    sub_lbl.halign = Gtk.Align.START;
                    sub_lbl.add_css_class ("caption");
                    sub_lbl.opacity = 0.55;
                    labels.append (name_lbl);
                    labels.append (sub_lbl);

                    var edit_btn = new Gtk.Button.from_icon_name ("document-edit-symbolic");
                    edit_btn.add_css_class ("flat");
                    edit_btn.valign = Gtk.Align.CENTER;
                    edit_btn.clicked.connect (() => {
                        popover.popdown ();
                        show_ssh_dialog (s);
                    });

                    var del_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                    del_btn.add_css_class ("flat");
                    del_btn.add_css_class ("destructive-action");
                    del_btn.valign = Gtk.Align.CENTER;
                    del_btn.clicked.connect (() => {
                        ssh_sessions.remove (s);
                        save_ssh_sessions ();
                        popover.popdown ();
                    });

                    row_box.append (icon);
                    row_box.append (labels);
                    row_box.append (edit_btn);
                    row_box.append (del_btn);
                    row.set_child (row_box);

                    row.activatable = true;
                    var gesture = new Gtk.GestureClick ();
                    gesture.released.connect ((n, x, y) => {
                        popover.popdown ();
                        connect_ssh (s);
                    });
                    row.add_controller (gesture);

                    list.append (row);
                }
            }

            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.max_content_height = 320;
            scroll.propagate_natural_height = true;
            scroll.set_child (list);
            root_box.append (scroll);

            popover.set_child (root_box);
            popover.popup ();
        }

        private void setup_styles () {
            var provider = new Gtk.CssProvider ();
            provider.load_from_data (LEAFS_CSS.data);
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        private const string LEAFS_CSS = """
            .leafs-window .singularity-app-frame {
                background-color: #1a1a1a;
            }
            /* Drag handle: fully transparent, no hover styling */
            .leafs-drag-handle,
            .leafs-drag-handle > box,
            .leafs-drag-handle:hover,
            .leafs-drag-handle:hover > box,
            .leafs-drag-handle:focus,
            .leafs-drag-handle > box:hover {
                background: transparent;
                background-color: transparent;
                border: none;
                box-shadow: none;
                outline: none;
            }
            /* VTE inner padding - space between text and window edges */
            vte-terminal {
                padding: 6px 12px;
            }
            /* Terminal App */
            .term-pane-focused {}
            .term-pane-unfocused {}
            .ssh-sidebar {
                border-right: 1px solid alpha(@text_color, 0.08);
                min-width: 200px;
            }
            .ssh-session-row {
                padding: 6px 10px;
                border-radius: 8px;
            }
            .ssh-session-row:hover {
                background-color: alpha(@text_color, 0.08);
            }
            .ssh-sidebar-title {
                font-size: 13px;
                font-weight: 700;
                padding: 12px 12px 4px 12px;
                opacity: 0.7;
            }
            .term-search-bar {
                background-color: alpha(@shadow_color, 0.4);
                border-top: 1px solid alpha(@text_color, 0.1);
            }
            /* Terminal Tiling Headers (Tilix-style) */
            .tile-header {
                min-height: 24px;
                padding: 0 4px;
                background-color: alpha(@shadow_color, 0.35);
                border-bottom: 1px solid alpha(@text_color, 0.07);
            }
            .tile-header-focused {
                background-color: alpha(@text_color, 0.06);
                border-bottom: 1px solid alpha(@accent_color, 0.4);
            }
            .tile-header-unfocused {
                background-color: alpha(@shadow_color, 0.3);
                border-bottom: 1px solid alpha(@text_color, 0.05);
            }
            .tile-header-title {
                font-size: 11px;
                opacity: 0.8;
                padding: 0 4px;
            }
            .tile-header-btn {
                min-width: 20px;
                min-height: 20px;
                padding: 1px;
                opacity: 0.6;
            }
            .tile-header-btn:hover {
                opacity: 1.0;
            }
            /* Tiled Terminals */
            .tiled-terminal {
                border-radius: 12px;
                border: 1px solid alpha(@text_color, 0.1);
                box-shadow: 0 4px 12px alpha(@shadow_color, 0.3);
                margin: 4px;
                background-color: @window_bg;
            }
            .terminal-overlay {
                border-radius: 12px;
            }
            .terminal-close-button {
                background-color: alpha(@text_color, 0.1);
                border-radius: 999px;
                padding: 0;
                margin: 8px;
                min-width: 24px;
                min-height: 24px;
                opacity: 0;
                transition: all 0.2s ease;
                color: white;
            }
            .terminal-overlay:hover .terminal-close-button {
                opacity: 1.0;
            }
            .terminal-close-button:hover {
                background-color: @destructive_color;
            }
            .leaf-paned > separator {
                background-color: transparent;
                min-width: 8px;
                min-height: 8px;
            }
            .leaf-paned > separator:hover {
                background-color: alpha(@accent_color, 0.5);
            }
            .bloom-terminal {
                padding: 30px 12px 8px 12px;
            }
        """;
    }

}
