using Gtk;

namespace Singularity.Apps {

    private class CheatRow : ListBoxRow {
        public CheatPage? page;
        public CheatExample? example;
        public CheatShortcut? shortcut;
        public int order;

        public CheatRow.for_example (CheatPage page, CheatExample example, int order) {
            this.page = page;
            this.example = example;
            this.order = order;
            activatable = true;
            var box = new Box (Orientation.VERTICAL, 2);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 12;
            box.margin_end = 12;
            if (example.description != "") {
                var desc = new Label (example.description);
                desc.xalign = 0;
                desc.wrap = true;
                desc.wrap_mode = Pango.WrapMode.WORD_CHAR;
                desc.add_css_class ("caption");
                desc.add_css_class ("dim-label");
                box.append (desc);
            }
            var code = new Label (null);
            code.use_markup = true;
            code.set_markup (example.markup ());
            code.xalign = 0;
            code.wrap = true;
            code.wrap_mode = Pango.WrapMode.CHAR;
            code.add_css_class ("leafs-cheat-code");
            box.append (code);
            child = box;
            tooltip_text = _("Insert into the terminal");
            update_property (AccessibleProperty.LABEL, "%s: %s".printf (example.description, example.plain ()), -1);
        }

        public CheatRow.for_shortcut (CheatShortcut shortcut, int order) {
            this.shortcut = shortcut;
            this.order = order;
            activatable = false;
            var box = new Box (Orientation.HORIZONTAL, 12);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 12;
            box.margin_end = 12;
            var desc = new Label (shortcut.description);
            desc.xalign = 0;
            desc.hexpand = true;
            desc.wrap = true;
            box.append (desc);
            var keys = new Label (shortcut.keys);
            keys.add_css_class ("leafs-cheat-keys");
            keys.valign = Align.CENTER;
            box.append (keys);
            child = box;
        }

        public string group_name () {
            return page != null ? page.name : shortcut.section;
        }

        public bool matches (string[] terms) {
            if (example != null) return Cheatsheet.matches (terms, page.name, page.summary, example.description, example.command);
            return Cheatsheet.matches (terms, shortcut.section, "", shortcut.description, shortcut.keys);
        }
    }

    public class CheatsheetPanel : Box {
        private Cheatsheet sheet;
        private Singularity.Widgets.SearchEntry search;
        private ListBox list;
        private Stack stack;
        private string[] terms = {};

        public signal void insert_requested (string text);
        public signal void close_requested ();

        public static CheatShortcut[] shortcuts () {
            string leafs = _("Leafs");
            string shell = _("Command Line");
            return {
                new CheatShortcut (leafs, "Ctrl+Shift+N", _("New leaf beside this one")),
                new CheatShortcut (leafs, "Ctrl+Shift+T", _("New tab in this leaf")),
                new CheatShortcut (leafs, "Ctrl+Shift+B", _("New bloom, a floating terminal")),
                new CheatShortcut (leafs, "Ctrl+Shift+C", _("Copy the selection")),
                new CheatShortcut (leafs, "Ctrl+Shift+V", _("Paste")),
                new CheatShortcut (leafs, "Ctrl+Shift+W", _("Close the window")),
                new CheatShortcut (leafs, "Ctrl+Shift+H", _("Show or hide this cheatsheet")),
                new CheatShortcut (leafs, "Ctrl+Plus", _("Zoom in")),
                new CheatShortcut (leafs, "Ctrl+Minus", _("Zoom out")),
                new CheatShortcut (leafs, "Ctrl+0", _("Actual size")),
                new CheatShortcut (leafs, "Ctrl+Comma", _("Settings")),
                new CheatShortcut (leafs, "F11", _("Fullscreen")),
                new CheatShortcut (shell, "Tab", _("Complete a command or file name")),
                new CheatShortcut (shell, "Ctrl+R", _("Search the command history")),
                new CheatShortcut (shell, "Ctrl+C", _("Stop the running command")),
                new CheatShortcut (shell, "Ctrl+Z", _("Pause the running command")),
                new CheatShortcut (shell, "Ctrl+D", _("End input or close the shell")),
                new CheatShortcut (shell, "Ctrl+L", _("Clear the screen")),
                new CheatShortcut (shell, "Ctrl+A", _("Go to the start of the line")),
                new CheatShortcut (shell, "Ctrl+E", _("Go to the end of the line")),
                new CheatShortcut (shell, "Ctrl+U", _("Delete to the start of the line")),
                new CheatShortcut (shell, "Ctrl+K", _("Delete to the end of the line")),
                new CheatShortcut (shell, "Ctrl+W", _("Delete the previous word")),
                new CheatShortcut (shell, "Alt+.", _("Insert the last argument of the previous command"))
            };
        }

        public CheatsheetPanel (Cheatsheet sheet) {
            Object (orientation: Orientation.VERTICAL, spacing: 8);
            this.sheet = sheet;
            add_css_class ("leafs-cheatsheet");
            margin_top = 40;
            margin_start = 8;
            margin_end = 8;
            margin_bottom = 8;

            search = new Singularity.Widgets.SearchEntry ();
            search.placeholder_text = _("Search commands and shortcuts");
            search.search_changed.connect (() => {
                terms = Cheatsheet.terms (search.text);
                list.invalidate_filter ();
                list.invalidate_sort ();
                list.invalidate_headers ();
                update_empty ();
            });
            search.entry.activate.connect (activate_first);
            append (search);

            list = new ListBox ();
            list.selection_mode = SelectionMode.NONE;
            list.add_css_class ("leafs-cheat-list");
            list.set_filter_func ((row) => ((CheatRow) row).matches (terms));
            list.set_sort_func ((a, b) => {
                var ra = (CheatRow) a;
                var rb = (CheatRow) b;
                int ka = ra.page != null ? Cheatsheet.rank (terms, ra.page.name) : 3;
                int kb = rb.page != null ? Cheatsheet.rank (terms, rb.page.name) : 3;
                if (ka != kb) return ka - kb;
                return ra.order - rb.order;
            });
            list.set_header_func (update_header);
            list.row_activated.connect ((row) => {
                var r = (CheatRow) row;
                if (r.example != null) insert_requested (r.example.plain ());
            });
            int order = 0;
            foreach (var page in sheet.pages) {
                foreach (var ex in page.examples) list.append (new CheatRow.for_example (page, ex, order++));
            }
            foreach (var sc in shortcuts ()) list.append (new CheatRow.for_shortcut (sc, order++));

            var scroller = new ScrolledWindow ();
            scroller.hscrollbar_policy = PolicyType.NEVER;
            scroller.vexpand = true;
            scroller.child = list;

            var empty = new Singularity.Widgets.StatusPage ();
            empty.compact = true;
            empty.icon_name = "system-search";
            empty.title = _("No Results");
            empty.description = _("Try another command name or a word from what you want to do.");

            stack = new Stack ();
            stack.vexpand = true;
            stack.add_named (scroller, "list");
            stack.add_named (empty, "empty");
            append (stack);

            var credit = new Label (null);
            credit.wrap = true;
            credit.xalign = 0;
            credit.add_css_class ("caption");
            credit.add_css_class ("dim-label");
            if (sheet.has_tldr) {
                credit.set_markup (_("Command pages from <a href=\"https://tldr.sh\">tldr-pages</a>, licensed under <a href=\"https://creativecommons.org/licenses/by/4.0/\">CC BY 4.0</a>."));
            } else {
                credit.label = _("Click a command to insert it. Words in italics are placeholders to replace.");
            }
            append (credit);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (keyval == Gdk.Key.Escape) {
                    close_requested ();
                    return true;
                }
                return false;
            });
            add_controller (keys);
        }

        public override bool grab_focus () {
            return search.grab_focus ();
        }

        public void focus_search () {
            search.grab_focus ();
        }

        private void update_header (ListBoxRow row, ListBoxRow? before) {
            var r = (CheatRow) row;
            var b = (CheatRow?) before;
            if (b != null && b.group_name () == r.group_name () && (b.page == null) == (r.page == null)) {
                row.set_header (null);
                return;
            }
            var box = new Box (Orientation.VERTICAL, 2);
            box.margin_top = b == null ? 4 : 14;
            box.margin_bottom = 2;
            box.margin_start = 12;
            box.margin_end = 12;
            var title = new Label (r.group_name ());
            title.xalign = 0;
            title.add_css_class ("heading");
            if (r.page != null) title.add_css_class ("leafs-cheat-name");
            box.append (title);
            if (r.page != null && r.page.summary != "") {
                var summary = new Label (r.page.summary);
                summary.xalign = 0;
                summary.wrap = true;
                summary.add_css_class ("caption");
                box.append (summary);
            }
            row.set_header (box);
        }

        private void update_empty () {
            bool any = false;
            for (var child = list.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var row = child as CheatRow;
                if (row != null && row.matches (terms)) {
                    any = true;
                    break;
                }
            }
            stack.visible_child_name = any ? "list" : "empty";
        }

        private void activate_first () {
            CheatRow? best = null;
            for (var child = list.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var row = child as CheatRow;
                if (row == null || !row.get_child_visible () || row.example == null) continue;
                best = row;
                break;
            }
            if (best != null) insert_requested (best.example.plain ());
        }
    }
}
