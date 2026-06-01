using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    public static int main (string[] args) {
        Intl.setlocale(GLib.LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = GLib.FileUtils.read_link("/proc/self/exe");
            locale_dir = GLib.Path.build_filename(GLib.Path.get_dirname(GLib.Path.get_dirname(exe)), "share", "locale");
        } catch (GLib.Error e) { }
        Intl.bindtextdomain("singularity-leafs", locale_dir);
        Intl.bind_textdomain_codeset("singularity-leafs", "UTF-8");
        Intl.textdomain("singularity-leafs");

        var app = new LeafsApp ();
        return app.run (args);
    }

}
