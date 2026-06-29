using Gtk;
using Singularity;
using Singularity.Widgets;
using GLib;

namespace Singularity.Apps {

    private class LeafsBloomDialog : Singularity.Widgets.AppDialog {
        private Singularity.Widgets.EntryRow label_row;
        private Singularity.Widgets.EntryRow command_row;

        public signal void bloom_saved (BloomDef def, BloomDef? replacing);

        public LeafsBloomDialog (Gtk.Window parent, BloomDef? existing = null) {
            base ((Gtk.Application) parent.application, true);
            this.set_title (existing != null ? _("Edit Bloom") : _("New Bloom"));
            this.transient_for = parent;
            set_default_size (420, -1);

            var group = new Singularity.Widgets.PreferencesGroup ();
            group.margin_start = 12; group.margin_end = 12;
            group.margin_top = 12;   group.margin_bottom = 12;

            label_row = new Singularity.Widgets.EntryRow ("Label");
            label_row.text = existing?.label ?? "";
            group.add_row (label_row);

            command_row = new Singularity.Widgets.EntryRow ("Command");
            command_row.text = existing?.command ?? "";
            group.add_row (command_row);

            this.content_box.append (group);

            var footer = new Box (Orientation.HORIZONTAL, 12);
            footer.margin_start = 24; footer.margin_end = 24; footer.margin_bottom = 24;
            footer.halign = Gtk.Align.END;

            var cancel_btn = new Button.with_label (_("Cancel"));
            cancel_btn.add_css_class ("flat");
            cancel_btn.clicked.connect (() => close ());

            var save_btn = new Button.with_label (_("Save"));
            save_btn.add_css_class ("suggested-action");
            save_btn.clicked.connect (() => {
                string l = label_row.text.strip ();
                string c = command_row.text.strip ();
                if (l == "" || c == "") return;
                bloom_saved (new BloomDef (l, c), existing);
                close ();
            });

            footer.append (cancel_btn);
            footer.append (save_btn);
            this.content_box.append (footer);
        }
    }
}
