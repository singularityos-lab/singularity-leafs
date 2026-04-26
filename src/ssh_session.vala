using Gtk;
using Vte;
using Singularity;
using Singularity.Widgets;
using GLib;
using Gee;

namespace Singularity.Apps {

    public class SshSession : Object {
        public string id          { get; set; default = ""; }
        public string name        { get; set; default = ""; }
        public string host        { get; set; default = ""; }
        public int    port        { get; set; default = 22; }
        public string user        { get; set; default = ""; }
        public string password    { get; set; default = ""; }
        public string key_path    { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public bool   favorite    { get; set; default = false; }

        public static SshSession? from_json (string json_str) {
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (json_str);
                var root = parser.get_root ();
                if (root == null) return null;
                var obj = root.get_object ();
                if (obj == null) return null;
                var s = new SshSession ();
                s.id          = obj.has_member ("id")          ? obj.get_string_member ("id")          : GLib.Uuid.string_random ();
                s.name        = obj.has_member ("name")        ? obj.get_string_member ("name")        : "";
                s.host        = obj.has_member ("host")        ? obj.get_string_member ("host")        : "";
                s.port        = obj.has_member ("port")        ? (int) obj.get_int_member ("port")     : 22;
                s.user        = obj.has_member ("user")        ? obj.get_string_member ("user")        : "";
                s.password    = obj.has_member ("password")    ? obj.get_string_member ("password")    : "";
                s.key_path    = obj.has_member ("key_path")    ? obj.get_string_member ("key_path")    : "";
                s.description = obj.has_member ("description") ? obj.get_string_member ("description") : "";
                s.favorite    = obj.has_member ("favorite")    ? obj.get_boolean_member ("favorite")   : false;
                return s;
            } catch {
                return null;
            }
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("id");          b.add_string_value (id);
            b.set_member_name ("name");        b.add_string_value (name);
            b.set_member_name ("host");        b.add_string_value (host);
            b.set_member_name ("port");        b.add_int_value (port);
            b.set_member_name ("user");        b.add_string_value (user);
            b.set_member_name ("password");    b.add_string_value (password);
            b.set_member_name ("key_path");    b.add_string_value (key_path);
            b.set_member_name ("description"); b.add_string_value (description);
            b.set_member_name ("favorite");    b.add_boolean_value (favorite);
            b.end_object ();
            var g = new Json.Generator ();
            g.set_root (b.get_root ());
            return g.to_data (null);
        }
    }

}
