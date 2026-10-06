using GLib;

namespace Singularity.Apps {

    public class LeafsSearchProvider : Singularity.SearchProviderService {
        private const string PREFIX = "ssh";

        private weak LeafsApp app;

        public LeafsSearchProvider (LeafsApp app) {
            this.app = app;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            if (terms.length == 0 || terms[0].down () != PREFIX) return {};
            string query = "";
            for (int i = 1; i < terms.length; i++)
                query += (query == "" ? "" : " ") + terms[i].down ();
            string[] ids = {};
            foreach (var s in app.saved_ssh_sessions ()) {
                if (query == "" || s.name.down ().contains (query) || s.host.down ().contains (query))
                    ids += "session:" + s.id;
            }
            foreach (string host in config_hosts ()) {
                if (query == "" || host.down ().contains (query))
                    ids += "host:" + host;
            }
            if (query != "" && ids.length == 0 && is_plain_host (query))
                ids += "host:" + query;
            return ids;
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            Singularity.SearchResultMeta[] metas = {};
            var sessions = app.saved_ssh_sessions ();
            var known = config_hosts ();
            foreach (string id in ids) {
                if (id.has_prefix ("session:")) {
                    string sid = id.substring (8);
                    foreach (var s in sessions) {
                        if (s.id != sid) continue;
                        var meta = new Singularity.SearchResultMeta (id, s.name != "" ? s.name : s.host);
                        meta.description = _("Saved session, %s").printf (
                            s.user != "" ? "%s@%s".printf (s.user, s.host) : s.host);
                        meta.icon = new ThemedIcon ("network-server");
                        meta.score = 2;
                        metas += meta;
                    }
                } else if (id.has_prefix ("host:")) {
                    string host = id.substring (5);
                    var meta = new Singularity.SearchResultMeta (id, host);
                    meta.description = host in known ? _("Host from your SSH configuration") : _("Connect with SSH");
                    meta.icon = new ThemedIcon ("network-server");
                    meta.score = host in known ? 1 : 0;
                    metas += meta;
                }
            }
            return metas;
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            app.open_ssh_target (id);
            return null;
        }

        private static bool is_plain_host (string text) {
            if (text.length > 253) return false;
            for (int i = 0; i < text.length; i++) {
                char c = text[i];
                if (!(c.isalnum () || c == '.' || c == '-' || c == '_' || c == '@' || c == ':')) return false;
            }
            return !text.has_prefix ("-");
        }

        private static string[] config_hosts () {
            var hosts = new GenericArray<string> ();
            string path = Path.build_filename (Environment.get_home_dir (), ".ssh", "config");
            read_config (path, hosts, 0);
            string[] result = {};
            foreach (string h in hosts.data) result += h;
            return result;
        }

        private static void read_config (string path, GenericArray<string> hosts, int depth) {
            if (depth > 3) return;
            string contents;
            try {
                FileUtils.get_contents (path, out contents);
            } catch (Error e) {
                return;
            }
            foreach (string raw in contents.split ("\n")) {
                string line = raw.strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                string[] parts = Regex.split_simple ("[\\s=]+", line);
                if (parts.length < 2) continue;
                string key = parts[0].down ();
                if (key == "host") {
                    for (int i = 1; i < parts.length; i++) {
                        string h = parts[i];
                        if (h == "" || h.has_prefix ("!") || "*" in h || "?" in h) continue;
                        if (!hosts.find_with_equal_func (h, str_equal)) hosts.add (h);
                    }
                } else if (key == "include") {
                    for (int i = 1; i < parts.length; i++)
                        foreach (string included in expand_include (parts[i]))
                            read_config (included, hosts, depth + 1);
                }
            }
        }

        private static string[] expand_include (string pattern) {
            string p = pattern;
            if (p.has_prefix ("~/")) p = Path.build_filename (Environment.get_home_dir (), p.substring (2));
            else if (!Path.is_absolute (p)) p = Path.build_filename (Environment.get_home_dir (), ".ssh", p);
            string dir = Path.get_dirname (p);
            string glob = Path.get_basename (p);
            string[] result = {};
            if (!("*" in glob) && !("?" in glob)) {
                result += p;
                return result;
            }
            var spec = new PatternSpec (glob);
            try {
                var d = Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (spec.match_string (name)) result += Path.build_filename (dir, name);
                }
            } catch (FileError e) {
            }
            return result;
        }
    }
}
