using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    public class LeafsApp : Singularity.Application {
        private LeafsWindow main_window;
        private ArrayList<LeafPane> leaves;
        private GLib.Settings settings;
        private GLib.Settings desktop_settings;
        private ArrayList<SshSession> ssh_sessions;

        public LeafsApp () {
            Object (application_id: "dev.sinty.leafs",
                    flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        protected override void startup () {
            base.startup ();
            setup_styles ();

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
            settings.changed["color-scheme"].connect ((_k) => apply_settings_to_all ());
            settings.changed["scrollback-lines"].connect ((_k) => apply_settings_to_all ());

            // When "auto" theme is active, re-apply whenever system accent or dark-mode changes
            try {
                desktop_settings = new GLib.Settings ("dev.sinty.desktop");
            } catch (Error e) {
                warning ("Leafs: dev.sinty.desktop settings unavailable: %s", e.message);
                desktop_settings = null;
            }
            if (desktop_settings != null) {
                desktop_settings.changed["accent-color"].connect ((_k) => {
                    if (settings.get_string ("color-scheme") == "auto")
                        apply_settings_to_all ();
                });
                desktop_settings.changed["custom-accent-color"].connect ((_k) => {
                    if (settings.get_string ("color-scheme") == "auto")
                        apply_settings_to_all ();
                });
                desktop_settings.changed["dark-mode"].connect ((_k) => {
                    if (settings.get_string ("color-scheme") == "auto")
                        apply_settings_to_all ();
                });
            }
        }

        protected override void activate () {
            if (main_window != null) {
                main_window.present ();
                return;
            }
            build_window ();
            leaves       = new ArrayList<LeafPane> ();
            ssh_sessions = new ArrayList<SshSession> ();
            load_ssh_sessions ();
            restore_session ();
            if (leaves.is_empty) add_leaf (null, null);
            main_window.present ();
        }

        private void build_window () {
            main_window = new LeafsWindow (this);

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
                    case Gdk.Key.c:
                        var t = get_focused_terminal ();
                        if (t != null && t.get_has_selection ()) {
                            t.copy_clipboard_format (Vte.Format.TEXT);
                            return true;
                        }
                        return false;
                    case Gdk.Key.v:
                        var t = get_focused_terminal ();
                        if (t != null) { t.paste_clipboard (); return true; }
                        return false;
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

            if (after == null) {
                leaves.add (leaf);
                main_window.leaves_box.append (leaf);
            } else {
                int idx = leaves.index_of (after);
                if (idx < 0 || idx >= leaves.size - 1) {
                    leaves.add (leaf);
                    main_window.leaves_box.append (leaf);
                } else {
                    leaves.insert (idx + 1, leaf);
                    main_window.leaves_box.insert_child_after (leaf, after);
                }
            }

            add_separator_if_needed ();
            leaf.terminal.grab_focus ();
        }

        private void connect_leaf_signals (LeafPane leaf) {
            leaf.close_requested.connect (on_close_leaf);
            leaf.add_requested.connect   ((pane) => insert_leaf_after (pane, null, null));
            leaf.settings_requested.connect (show_settings);
            leaf.ssh_btn.clicked.connect (() => show_ssh_popover (leaf.ssh_btn));
            leaf.close_all_requested.connect (() => {
                save_session ();
                main_window.close ();
            });
            leaf.reorder_requested.connect (on_reorder_leaf);
            leaf.lookup_reorder.connect (on_lookup_reorder);
        }

        private void on_reorder_leaf (LeafPane source, LeafPane target) {
            if (source == target) return;
            int src_idx = leaves.index_of (source);
            int dst_idx = leaves.index_of (target);
            if (src_idx < 0 || dst_idx < 0) return;

            leaves.remove (source);
            if (dst_idx > src_idx) dst_idx--;
            leaves.insert (dst_idx, source);
            main_window.leaves_box.insert_child_after (source, target);
            rebuild_separators ();
        }

        private void on_lookup_reorder (string source_id, LeafPane target) {
            foreach (var leaf in leaves) {
                if (leaf.pane_id == source_id) {
                    on_reorder_leaf (leaf, target);
                    return;
                }
            }
        }

        private void on_close_leaf (LeafPane pane) {
            if (leaves.size == 1) {
                save_session ();
                main_window.close ();
                return;
            }
            leaves.remove (pane);
            main_window.leaves_box.remove (pane);
            rebuild_separators ();
        }

        private void add_leaf_after_focused () {
            LeafPane? focused = get_focused_leaf ();
            insert_leaf_after (focused, null, null);
        }

        private LeafPane? get_focused_leaf () {
            foreach (var leaf in leaves) {
                if (leaf.has_focus ()) return leaf;
            }
            return leaves.size > 0 ? leaves.last () : null;
        }

        private Vte.Terminal? get_focused_terminal () {
            var leaf = get_focused_leaf ();
            if (leaf == null) return null;
            // If a bug terminal is active in this leaf, return that instead
            var bug = leaf.get_active_bug ();
            return bug ?? leaf.terminal;
        }

        // Thin 1px dividers between leaves (rebuilt on add/remove)

        private void add_separator_if_needed () {
            rebuild_separators ();
        }

        private void rebuild_separators () {
            // Remove all current separators
            Gtk.Widget? child = main_window.leaves_box.get_first_child ();
            var to_remove = new ArrayList<Gtk.Widget> ();
            while (child != null) {
                if (child.has_css_class ("leaf-sep")) to_remove.add (child);
                child = child.get_next_sibling ();
            }
            foreach (var w in to_remove) main_window.leaves_box.remove (w);

            // Re-insert separators between each pair of leaves
            for (int i = 0; i < leaves.size - 1; i++) {
                var sep = new Gtk.Separator (Orientation.VERTICAL);
                sep.add_css_class ("leaf-sep");
                main_window.leaves_box.insert_child_after (sep, leaves.get (i));
            }
        }

        private void show_settings () {
            try {
                Singularity.Shell.ShellService shell = Bus.get_proxy_sync (
                    BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                shell.open_app_settings ("dev.sinty.leafs");
            } catch (Error e) {
                warning ("Leafs: failed to open settings: %s", e.message);
            }
        }

        private void apply_settings_to_all () {
            foreach (var leaf in leaves)
                leaf.apply_settings (settings);
        }

        private void save_session () {
            var builder = new Json.Builder ();
            builder.begin_array ();
            foreach (var leaf in leaves) {
                builder.begin_object ();
                builder.set_member_name ("id");  builder.add_string_value (leaf.pane_id);
                builder.set_member_name ("cwd"); builder.add_string_value (leaf.get_working_dir ());
                builder.end_object ();
            }
            builder.end_array ();
            var gen = new Json.Generator ();
            gen.set_root (builder.get_root ());
            settings.set_string ("session", gen.to_data (null));
            // Force GSettings to flush to disk before exit
            GLib.Settings.sync ();
        }

        private void restore_session () {
            string json = settings.get_string ("session");
            if (json == null || json == "") return;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json);
                var root = parser.get_root ();
                if (root == null) return;
                var arr = root.get_array ();
                if (arr == null) return;
                arr.foreach_element ((a, i, node) => {
                    var obj = node.get_object ();
                    if (obj == null) return;
                    string cwd = obj.has_member ("cwd")
                        ? obj.get_string_member ("cwd")
                        : GLib.Environment.get_home_dir ();
                    string id = obj.has_member ("id")
                        ? obj.get_string_member ("id")
                        : GLib.Uuid.string_random ();
                    if (!FileUtils.test (cwd, FileTest.IS_DIR))
                        cwd = GLib.Environment.get_home_dir ();
                    add_leaf (cwd, id);
                });
            } catch (Error e) {
                warning ("Leafs: failed to restore session: %s", e.message);
            }
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

            var title_lbl = new Gtk.Label ("SSH Sessions");
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
                var empty_lbl = new Gtk.Label ("No sessions - click + to add one");
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
                overflow: hidden;
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
            .terminal-paned separator {
                background-color: transparent;
                min-width: 8px;
                min-height: 8px;
            }
            /* Bug terminal separator - draggable resize handle */
            .leaf-bug-separator {
                min-height: 4px;
                min-width: 4px;
                background-color: alpha(@text_color, 0.12);
                border-radius: 2px;
                margin: 4px 8px;
            }
            .leaf-bug-separator:hover {
                background-color: alpha(@accent_color, 0.5);
            }
        """;
    }

}
