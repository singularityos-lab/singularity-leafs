namespace Singularity.Apps {

    public class CheatExample : Object {
        public string description { get; construct; }
        public string command { get; construct; }

        public CheatExample (string description, string command) {
            Object (description: description, command: command);
        }

        public string plain () {
            return Cheatsheet.strip_placeholders (command);
        }

        public string markup () {
            return Cheatsheet.placeholder_markup (command);
        }
    }

    public class CheatPage : Object {
        public string name { get; construct; }
        public string summary { get; set; default = ""; }
        public string source { get; construct; }
        public Gee.ArrayList<CheatExample> examples { get; default = new Gee.ArrayList<CheatExample> (); }

        public CheatPage (string name, string source) {
            Object (name: name, source: source);
        }
    }

    public class CheatShortcut : Object {
        public string keys { get; construct; }
        public string description { get; construct; }
        public string section { get; construct; }

        public CheatShortcut (string section, string keys, string description) {
            Object (section: section, keys: keys, description: description);
        }
    }

    public class Cheatsheet : Object {
        public const string BUNDLED = "/dev/sinty/leafs/cheatsheet/commands.md";
        public const string TLDR_SOURCE = "tldr";
        public const string OWN_SOURCE = "singularity";

        public Gee.ArrayList<CheatPage> pages { get; default = new Gee.ArrayList<CheatPage> (); }
        public bool has_tldr { get; private set; default = false; }

        public static Gee.ArrayList<CheatPage> parse (string text, string source) {
            var result = new Gee.ArrayList<CheatPage> ();
            CheatPage? page = null;
            string pending = "";
            foreach (string raw in text.split ("\n")) {
                string line = raw.strip ();
                if (line.has_prefix ("# ")) {
                    page = new CheatPage (line.substring (2).strip (), source);
                    result.add (page);
                    pending = "";
                } else if (page == null) {
                    continue;
                } else if (line.has_prefix ("> ")) {
                    string part = line.substring (2).strip ();
                    if (part.has_prefix ("More information") || part.has_prefix ("See also")) continue;
                    page.summary = page.summary == "" ? part : page.summary + " " + part;
                } else if (line.has_prefix ("- ")) {
                    pending = line.substring (2).strip ();
                    if (pending.has_suffix (":")) pending = pending.substring (0, pending.length - 1);
                } else if (line.has_prefix ("`") && line.has_suffix ("`") && line.length > 2) {
                    page.examples.add (new CheatExample (pending, line.substring (1, line.length - 2)));
                    pending = "";
                }
            }
            var cleaned = new Gee.ArrayList<CheatPage> ();
            foreach (var p in result) {
                if (p.examples.size > 0) cleaned.add (p);
            }
            return cleaned;
        }

        public void add_pages (Gee.List<CheatPage> incoming) {
            foreach (var p in incoming) {
                int existing = -1;
                for (int i = 0; i < pages.size; i++) {
                    if (pages[i].name == p.name) {
                        existing = i;
                        break;
                    }
                }
                if (existing >= 0) {
                    if (p.source == TLDR_SOURCE && pages[existing].source != TLDR_SOURCE) pages[existing] = p;
                    else if (p.source == pages[existing].source) pages[existing].examples.add_all (p.examples);
                } else {
                    pages.add (p);
                }
                if (p.source == TLDR_SOURCE) has_tldr = true;
            }
        }

        public static string[] extra_dirs () {
            string[] dirs = {};
            var bases = new Gee.ArrayList<string> ();
            bases.add (Environment.get_user_data_dir ());
            foreach (unowned string d in Environment.get_system_data_dirs ()) bases.add (d);
            foreach (string b in bases) {
                dirs += Path.build_filename (b, "singularity-leafs", "cheatsheet");
                dirs += Path.build_filename (b, "tldr", "pages", "common");
                dirs += Path.build_filename (b, "tldr", "pages", "linux");
            }
            return dirs;
        }

        public void load_dir (string dir) {
            Dir handle;
            try {
                handle = Dir.open (dir);
            } catch (Error e) {
                return;
            }
            string source = dir.contains (Path.DIR_SEPARATOR_S + "tldr" + Path.DIR_SEPARATOR_S) ? TLDR_SOURCE : OWN_SOURCE;
            var names = new Gee.ArrayList<string> ();
            string? name;
            while ((name = handle.read_name ()) != null) {
                if (name.has_suffix (".md")) names.add (name);
            }
            names.sort ();
            foreach (string n in names) {
                try {
                    string text;
                    FileUtils.get_contents (Path.build_filename (dir, n), out text);
                    add_pages (parse (text, source));
                } catch (Error e) {
                    warning ("Leafs: cannot read %s: %s", n, e.message);
                }
            }
        }

        public void load_default () {
            try {
                var bytes = resources_lookup_data (BUNDLED, ResourceLookupFlags.NONE);
                add_pages (parse ((string) bytes.get_data (), OWN_SOURCE));
            } catch (Error e) {
                warning ("Leafs: bundled cheatsheet missing: %s", e.message);
            }
            foreach (string dir in extra_dirs ()) load_dir (dir);
            pages.sort ((a, b) => strcmp (a.name, b.name));
        }

        public static string strip_placeholders (string command) {
            return command.replace ("{{", "").replace ("}}", "");
        }

        public static string placeholder_markup (string command) {
            var sb = new StringBuilder ();
            string rest = command;
            while (true) {
                int open = rest.index_of ("{{");
                if (open < 0) break;
                int close = rest.index_of ("}}", open + 2);
                if (close < 0) break;
                sb.append (Markup.escape_text (rest.substring (0, open)));
                sb.append ("<i>");
                sb.append (Markup.escape_text (rest.substring (open + 2, close - open - 2)));
                sb.append ("</i>");
                rest = rest.substring (close + 2);
            }
            sb.append (Markup.escape_text (strip_placeholders (rest)));
            return sb.str;
        }

        public static string[] terms (string query) {
            string[] result = {};
            foreach (string t in query.strip ().down ().split (" ")) {
                if (t != "") result += t;
            }
            return result;
        }

        public static bool matches (string[] terms, string name, string summary, string description, string command) {
            if (terms.length == 0) return true;
            string hay = (name + "\n" + summary + "\n" + description + "\n" + strip_placeholders (command)).down ();
            foreach (string t in terms) {
                if (!hay.contains (t)) return false;
            }
            return true;
        }

        public static int rank (string[] terms, string name) {
            if (terms.length == 0) return 2;
            string n = name.down ();
            if (n == terms[0]) return 0;
            if (n.has_prefix (terms[0])) return 1;
            return 2;
        }
    }
}
