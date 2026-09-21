using Gtk;
using Gee;

namespace Singularity.Apps {

    public class LeafCell : Object {
        public Singularity.Widgets.TabContainer tabs { get; private set; }
        public ArrayList<LeafPane> leaves { get; private set; }

        private Singularity.Widgets.ChipBar chips;
        private HashMap<LeafPane, ulong> title_handlers;
        private bool changing_pages = false;

        public signal void close_requested (LeafPane leaf);

        public LeafCell () {
            leaves = new ArrayList<LeafPane> ();
            title_handlers = new HashMap<LeafPane, ulong> ();
            tabs = new Singularity.Widgets.TabContainer ();
            tabs.hexpand = true;
            tabs.vexpand = true;
            tabs.tab_scroll.unparent ();
            tabs.tab_scroll.visible = false;
            tabs.notebook.show_tabs = false;

            chips = new Singularity.Widgets.ChipBar ();
            chips.hexpand = true;
            chips.visible = false;
            chips.reorderable = true;
            chips.chip_activated.connect (on_chip_activated);
            chips.chip_closed.connect (on_chip_closed);
            chips.chips_reordered.connect (on_chips_reordered);
            tabs.append (chips);

            tabs.page_removed.connect (on_page_removed);
            tabs.switch_page.connect ((page, page_num) => sync_active_chip ());
        }

        public void add_leaf (LeafPane leaf, bool activate = true) {
            leaves.add (leaf);
            tabs.add_tab (leaf, title_for (leaf));
            chips.add_chip (leaf.pane_id, title_for (leaf));
            title_handlers[leaf] = leaf.terminal.window_title_changed.connect (() => {
                string title = title_for (leaf);
                tabs.set_tab_title (leaf, title);
                chips.update_chip_label (leaf.pane_id, title);
            });
            if (activate)
                tabs.notebook.set_current_page (tabs.notebook.page_num (leaf));
            sync_chips ();
        }

        public void remove_leaf (LeafPane leaf) {
            disconnect_title (leaf);
            leaves.remove (leaf);
            chips.remove_chip (leaf.pane_id);
            if (tabs.notebook.page_num (leaf) != -1) {
                changing_pages = true;
                tabs.remove_tab (leaf);
                changing_pages = false;
            }
            sync_chips ();
        }

        public bool contains (LeafPane leaf) {
            return leaves.contains (leaf);
        }

        public LeafPane? active_leaf () {
            return tabs.get_current_page () as LeafPane;
        }

        private void on_page_removed (Gtk.Widget child, uint page_num) {
            if (changing_pages) return;
            var leaf = child as LeafPane;
            if (leaf == null || !leaves.contains (leaf)) return;
            disconnect_title (leaf);
            leaves.remove (leaf);
            chips.remove_chip (leaf.pane_id);
            sync_chips ();
            close_requested (leaf);
        }

        private void on_chip_activated (string id) {
            var leaf = leaf_for_id (id);
            if (leaf == null) return;
            int page = tabs.notebook.page_num (leaf);
            if (page >= 0)
                tabs.notebook.set_current_page (page);
        }

        private void on_chip_closed (string id) {
            var leaf = leaf_for_id (id);
            if (leaf != null)
                close_requested (leaf);
        }

        private void on_chips_reordered (string[] ids) {
            var reordered = new ArrayList<LeafPane> ();
            foreach (var id in ids) {
                var leaf = leaf_for_id (id);
                if (leaf != null)
                    reordered.add (leaf);
            }
            if (reordered.size != leaves.size) return;

            leaves.clear ();
            changing_pages = true;
            for (int i = 0; i < reordered.size; i++) {
                var leaf = reordered[i];
                leaves.add (leaf);
                tabs.notebook.reorder_child (leaf, i);
            }
            changing_pages = false;
            sync_active_chip ();
        }

        private LeafPane? leaf_for_id (string id) {
            foreach (var leaf in leaves)
                if (leaf.pane_id == id) return leaf;
            return null;
        }

        private void sync_chips () {
            chips.visible = leaves.size > 1;
            sync_active_chip ();
        }

        private void sync_active_chip () {
            var active = active_leaf ();
            chips.set_active (active != null ? active.pane_id : null);
        }

        private void disconnect_title (LeafPane leaf) {
            ulong handler = title_handlers.get (leaf);
            if (handler != 0)
                leaf.terminal.disconnect (handler);
            title_handlers.unset (leaf);
        }

        private string title_for (LeafPane leaf) {
            string? title = leaf.terminal.get_window_title ();
            return title != null && title.strip () != "" ? title.strip () : _("Terminal");
        }
    }
}
