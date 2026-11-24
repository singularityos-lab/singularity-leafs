using Gee;

namespace Singularity.Apps {

    public class LeafScreen : Object {
        public string before { get; private set; default = ""; }
        public string line { get; private set; default = ""; }

        private StringBuilder _lines = new StringBuilder ();
        private StringBuilder _current = new StringBuilder ();
        private StringBuilder _plain = new StringBuilder ();
        private ArrayList<string> _attributes = new ArrayList<string> ();
        private string _applied = "";

        public LeafScreen (Vte.Terminal terminal) {
            var adjustment = terminal.get_vadjustment ();
            long column, row;
            terminal.get_cursor_position (out column, out row);
            long first = adjustment != null ? (long) adjustment.lower : 0;
            size_t length;
            string? html = terminal.get_text_range_format (
                Vte.Format.HTML, first, 0, row, column, out length);
            parse (html ?? "");
            before = _lines.str;
            line = _plain.str;
        }

        private void parse (string html) {
            int i = 0;
            while (i < html.length) {
                char c = html[i];
                if (c == '<') {
                    int end = html.index_of_char ('>', i);
                    if (end < 0) break;
                    open_tag (html.substring (i + 1, end - i - 1));
                    i = end + 1;
                } else if (c == '&') {
                    int end = html.index_of_char (';', i);
                    if (end < 0) break;
                    append_text (entity (html.substring (i + 1, end - i - 1)));
                    i = end + 1;
                } else if (c == '\n') {
                    end_line ();
                    i++;
                } else {
                    int next = i;
                    while (next < html.length && html[next] != '<' && html[next] != '&' && html[next] != '\n')
                        next++;
                    append_text (html.substring (i, next - i));
                    i = next;
                }
            }
        }

        private void open_tag (string tag) {
            if (tag == "pre" || tag == "/pre") return;
            if (tag.has_prefix ("/")) {
                if (!_attributes.is_empty)
                    _attributes.remove_at (_attributes.size - 1);
                return;
            }
            _attributes.add (sgr (tag));
        }

        private void append_text (string text) {
            if (text == "") return;
            var wanted = new StringBuilder ();
            foreach (var a in _attributes) {
                if (a == "") continue;
                if (wanted.len > 0) wanted.append_c (';');
                wanted.append (a);
            }
            if (wanted.str != _applied) {
                _current.append ("\x1b[0m");
                if (wanted.len > 0) _current.append ("\x1b[%sm".printf (wanted.str));
                _applied = wanted.str;
            }
            _current.append (text);
            _plain.append (text);
        }

        private void end_line () {
            if (_applied != "") {
                _current.append ("\x1b[0m");
                _applied = "";
            }
            _lines.append (_current.str);
            _lines.append ("\r\n");
            _current.truncate (0);
            _plain.truncate (0);
        }

        private static string sgr (string tag) {
            switch (tag) {
                case "b": return "1";
                case "i": return "3";
                case "blink": return "5";
                case "strike": return "9";
            }
            if (tag.has_prefix ("font color=\"#"))
                return "38;2;" + rgb (tag.substring (13));
            if (tag.has_prefix ("span style=\"background-color:#"))
                return "48;2;" + rgb (tag.substring (30));
            if (tag.has_prefix ("span style=\"text-decoration-line:overline"))
                return "53";
            if (tag.has_prefix ("u")) {
                string style = "4";
                if (tag.contains ("double")) style = "4:2";
                else if (tag.contains ("wavy")) style = "4:3";
                else if (tag.contains ("dotted")) style = "4:4";
                else if (tag.contains ("dashed")) style = "4:5";
                int color = tag.index_of ("text-decoration-color:#");
                if (color >= 0)
                    style += ";58:2::" + rgb (tag.substring (color + 23)).replace (";", ":");
                return style;
            }
            return "";
        }

        private static string rgb (string hex) {
            if (hex.length < 6) return "0;0;0";
            return "%lu;%lu;%lu".printf (
                ulong.parse (hex.substring (0, 2), 16),
                ulong.parse (hex.substring (2, 2), 16),
                ulong.parse (hex.substring (4, 2), 16));
        }

        private static string entity (string name) {
            switch (name) {
                case "amp": return "&";
                case "lt": return "<";
                case "gt": return ">";
                case "quot": return "\"";
                case "apos": return "'";
            }
            if (name.has_prefix ("#x") || name.has_prefix ("#X"))
                return ((unichar) ulong.parse (name.substring (2), 16)).to_string ();
            if (name.has_prefix ("#"))
                return ((unichar) ulong.parse (name.substring (1), 10)).to_string ();
            return "&" + name + ";";
        }
    }
}
