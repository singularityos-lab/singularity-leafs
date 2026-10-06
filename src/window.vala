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

            var act_close = new SimpleAction ("close", null);
            act_close.activate.connect (() => close ());
            add_action (act_close);

            var act_fullscreen = new SimpleAction.stateful ("fullscreen", null, new Variant.boolean (false));
            act_fullscreen.activate.connect (() => {
                if (fullscreened) unfullscreen ();
                else fullscreen ();
            });
            notify["fullscreened"].connect (() => act_fullscreen.set_state (new Variant.boolean (fullscreened)));
            add_action (act_fullscreen);
        }
    }

}
