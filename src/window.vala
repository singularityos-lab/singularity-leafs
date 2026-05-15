using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    [GtkTemplate (ui = "/dev/sinty/leafs/ui/main.ui")]
    public class LeafsWindow : Singularity.Widgets.Window {

        [GtkChild] public unowned Box leaves_box;

        public LeafsWindow (Gtk.Application app) {
            Object (application: app);
            set_title ("Leafs");
            set_default_size (600, 600);
            toolbar.is_static = false;
            toolbar.visible = false;
            leaves_box.homogeneous = true;
            set_content (leaves_box);
        }
    }

}
