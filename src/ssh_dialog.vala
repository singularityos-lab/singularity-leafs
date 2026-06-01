using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    private class LeafsSshDialog : Singularity.Widgets.AppDialog {
        private Singularity.Widgets.EntryRow    name_row;
        private Singularity.Widgets.EntryRow    host_row;
        private Singularity.Widgets.SpinRow     port_row;
        private Singularity.Widgets.EntryRow    user_row;
        private Singularity.Widgets.PasswordRow pass_row;
        private Singularity.Widgets.EntryRow    key_row;
        private string?                         existing_id;

        public signal void session_saved (SshSession session);

        public LeafsSshDialog (Gtk.Window parent, SshSession? existing = null) {
            base ((Gtk.Application)parent.application, true);
            this.set_title (existing != null ? _("Edit SSH Session") : _("New SSH Session"));
            this.transient_for = parent;

            existing_id = existing?.id;
            set_default_size (420, -1);

            var group = new Singularity.Widgets.PreferencesGroup ();
            group.margin_start = 12; group.margin_end = 12;
            group.margin_top = 12;   group.margin_bottom = 12;

            name_row = new Singularity.Widgets.EntryRow ("Name");
            name_row.text = existing?.name ?? "";
            group.add_row (name_row);

            host_row = new Singularity.Widgets.EntryRow ("Host / IP");
            host_row.text = existing?.host ?? "";
            group.add_row (host_row);

            port_row = new Singularity.Widgets.SpinRow ("Port", "Default is 22", 1, 65535, 1,
                existing != null ? existing.port : 22);
            group.add_row (port_row);

            user_row = new Singularity.Widgets.EntryRow ("Username");
            user_row.text = existing?.user ?? "";
            group.add_row (user_row);

            pass_row = new Singularity.Widgets.PasswordRow ("Password");
            pass_row.text = existing?.password ?? "";
            group.add_row (pass_row);

            key_row = new Singularity.Widgets.EntryRow ("SSH Key Path");
            key_row.text = existing?.key_path ?? "";
            group.add_row (key_row);

            this.content_box.append (group);

            var footer = new Box (Orientation.HORIZONTAL, 12);
            footer.margin_start = 24; footer.margin_end = 24; footer.margin_bottom = 24;
            footer.halign = Gtk.Align.END;

            var cancel_btn = new Button.with_label (_("Cancel"));
            cancel_btn.add_css_class ("flat");
            cancel_btn.clicked.connect (() => close ());

            var save_btn = new Button.with_label (_("Save"));
            save_btn.add_css_class ("suggested-action");
            save_btn.clicked.connect (on_save_clicked);

            footer.append (cancel_btn);
            footer.append (save_btn);
            this.content_box.append (footer);
        }

        private void on_save_clicked () {
            string n = name_row.text.strip ();
            string h = host_row.text.strip ();
            string u = user_row.text.strip ();
            if (n == "" || h == "" || u == "") return;

            var s      = new SshSession ();
            s.id       = (existing_id != null) ? existing_id : GLib.Uuid.string_random ();
            s.name     = n;
            s.host     = h;
            s.port     = (int) port_row.value;
            s.user     = u;
            s.password = pass_row.text;
            s.key_path = key_row.text.strip ();

            session_saved (s);
            close ();
        }
    }

}
