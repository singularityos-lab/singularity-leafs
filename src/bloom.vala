using Gtk;
using Vte;
using Singularity;
using GLib;

namespace Singularity.Apps {

    public class BloomDef : Object {
        public string label;
        public string command;

        public BloomDef (string label, string command) {
            this.label = label;
            this.command = command;
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("label");   b.add_string_value (label);
            b.set_member_name ("command"); b.add_string_value (command);
            b.end_object ();
            var g = new Json.Generator ();
            g.set_root (b.get_root ());
            return g.to_data (null);
        }

        public static BloomDef? from_json (string json) {
            try {
                var p = new Json.Parser ();
                p.load_from_data (json);
                var o = p.get_root ().get_object ();
                if (o == null) return null;
                return new BloomDef (
                    o.has_member ("label")   ? o.get_string_member ("label")   : "",
                    o.has_member ("command") ? o.get_string_member ("command") : "");
            } catch (Error e) {
                return null;
            }
        }
    }

    public class Bloom : Object {

        public static void spawn (GLib.Settings settings, Gtk.Overlay overlay,
                                  string label, string command, string? cwd, int x, int y) {
            var terminal = new Vte.Terminal ();
            terminal.hexpand = true;
            terminal.vexpand = true;
            terminal.set_size (20, 4);
            terminal.add_css_class ("bloom-terminal");
            apply_theme (terminal, settings);

            string shell = GLib.Environment.get_variable ("SHELL") ?? "/bin/bash";
            terminal.spawn_async (
                Vte.PtyFlags.DEFAULT,
                cwd ?? GLib.Environment.get_home_dir (),
                new string[] { shell },
                null,
                (GLib.SpawnFlags) 0,
                null, -1, null,
                (t, pid, err) => {
                    if (err != null) { warning ("Bloom spawn: %s", err.message); return; }
                    if (command.length > 0)
                        terminal.feed_child ((command + "\n").data);
                }
            );

            var rclick = new Gtk.GestureClick ();
            rclick.button = 3;
            rclick.pressed.connect ((n, px, py) => {
                var menu = new Singularity.Widgets.ContextMenu (terminal);
                Gdk.Rectangle rect = { (int) px, (int) py, 1, 1 };
                menu.set_pointing_to (rect);
                if (terminal.get_has_selection ())
                    menu.add_item ("Copy", "edit-copy-symbolic", () => terminal.copy_clipboard_format (Vte.Format.TEXT));
                menu.add_item ("Paste", "edit-paste-symbolic", () => LeafPane.smart_paste (terminal));
                menu.add_separator ();
                menu.add_item ("Clear", "edit-clear-symbolic", () => terminal.reset (true, true));
                menu.popup ();
            });
            terminal.add_controller (rclick);

            var panel = new Singularity.Widgets.FloatingPanel (overlay);
            panel.title = label;
            panel.set_content (terminal);
            terminal.child_exited.connect ((status) => panel.dismiss ());
            panel.place (x, y);
        }

        private static void apply_theme (Vte.Terminal terminal, GLib.Settings s) {
            var font_desc = new Pango.FontDescription ();
            font_desc.set_family (s.get_string ("font-family"));
            font_desc.set_size (s.get_int ("font-size") * Pango.SCALE);
            terminal.set_font (font_desc);
            terminal.set_scrollback_lines (s.get_int ("scrollback-lines"));

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
                terminal.set_colors (fg, bg, palette);
            }
        }
    }
}
