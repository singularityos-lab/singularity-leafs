using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    public static int main (string[] args) {
        var app = new LeafsApp ();
        return app.run (args);
    }

}
