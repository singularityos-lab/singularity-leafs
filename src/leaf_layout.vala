namespace Singularity.Apps {

    public class LeafLayout : Object {

        public static Gtk.Orientation first_orientation (int width, int height) {
            return height > width ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL;
        }

        public static Singularity.TileTree? rebalanced (string[] cells, int width, int height) {
            if (cells.length == 0) return null;
            return Singularity.TileTree.balanced (cells, first_orientation (width, height));
        }

        public static Singularity.TileTree place (Singularity.TileTree? tree, string[] cells,
                                                  string target, string inserted,
                                                  Singularity.TileZone zone) {
            if (tree == null || tree.is_empty) {
                var single = new Singularity.TileTree ();
                single.add (inserted);
                return single;
            }
            if (tree.contains (target) && tree.split (target, inserted, zone))
                return tree;
            return Singularity.TileTree.balanced (cells, zone.orientation ());
        }

        public static double position_ratio (Singularity.TileNode node) {
            int total = node.count ();
            if (total <= 0 || node.start == null) return 0.5;
            return (double) node.start.count () / (double) total;
        }

        public static void write (Json.Builder builder, Singularity.TileNode node, string[] cells) {
            builder.begin_object ();
            if (node.tile != null) {
                builder.set_member_name ("cell");
                builder.add_int_value (index_of (cells, node.tile));
            } else {
                builder.set_member_name ("orientation");
                builder.add_string_value (node.orientation == Gtk.Orientation.HORIZONTAL
                    ? "horizontal"
                    : "vertical");
                builder.set_member_name ("start");
                write (builder, node.start, cells);
                builder.set_member_name ("end");
                write (builder, node.end, cells);
            }
            builder.end_object ();
        }

        public static Singularity.TileTree? read (Json.Object? saved, string[] cells) {
            var root = read_node (saved, cells);
            if (root == null) return null;
            var tree = new Singularity.TileTree ();
            tree.replace_root (root);
            var found = tree.tiles ();
            if (found.length != cells.length) return null;
            var seen = new GenericSet<string> (str_hash, str_equal);
            foreach (string id in found) {
                if (seen.contains (id)) return null;
                seen.add (id);
            }
            foreach (string id in cells)
                if (!seen.contains (id)) return null;
            return tree;
        }

        private static Singularity.TileNode? read_node (Json.Object? saved, string[] cells) {
            if (saved == null) return null;
            if (saved.has_member ("cell")) {
                int index = (int) saved.get_int_member ("cell");
                return index >= 0 && index < cells.length
                    ? new Singularity.TileNode.leaf (cells[index])
                    : null;
            }
            if (!saved.has_member ("orientation") ||
                !saved.has_member ("start") || !saved.has_member ("end"))
                return null;

            string orientation = saved.get_string_member ("orientation");
            if (orientation != "horizontal" && orientation != "vertical")
                return null;
            var start = read_node (saved.get_object_member ("start"), cells);
            var end = read_node (saved.get_object_member ("end"), cells);
            if (start == null || end == null) return null;
            var node = new Singularity.TileNode.split (
                orientation == "horizontal" ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL,
                start, end);
            node.ratio = position_ratio (node);
            return node;
        }

        private static int index_of (string[] cells, string id) {
            for (int i = 0; i < cells.length; i++)
                if (cells[i] == id) return i;
            return -1;
        }
    }
}
