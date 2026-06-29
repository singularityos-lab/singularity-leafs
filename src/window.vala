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
        public Gtk.Overlay bloom_overlay;

        public LeafsWindow (Gtk.Application app) {
            Object (application: app);
#if DEVEL
            set_title (_("Leafs (Devel)"));
#else
            set_title (_("Leafs"));
#endif
            set_default_size (600, 600);
            toolbar.is_static = false;
            toolbar.visible = false;

            bloom_overlay = new Gtk.Overlay ();
            bloom_overlay.set_child (leaves_box);
            set_content (bloom_overlay);
        }
    }

}
