using Singularity.Apps;

private string shape (Singularity.TileNode? node) {
    if (node == null) return "-";
    if (node.tile != null) return node.tile;
    return "%s(%s,%s)".printf (node.orientation == Gtk.Orientation.HORIZONTAL ? "H" : "V",
                               shape (node.start), shape (node.end));
}

private string ratios (Singularity.TileNode? node) {
    if (node == null || node.tile != null) return "";
    string inner = ratios (node.start) + ratios (node.end);
    return "%.2f;".printf (LeafLayout.position_ratio (node)) + inner;
}

private Json.Object parse (string json) {
    var parser = new Json.Parser ();
    try {
        parser.load_from_data (json);
    } catch (Error e) {
        assert_not_reached ();
    }
    return parser.get_root ().get_object ();
}

private string saved (Singularity.TileTree tree, string[] cells) {
    var builder = new Json.Builder ();
    LeafLayout.write (builder, tree.root, cells);
    var gen = new Json.Generator ();
    gen.set_root (builder.get_root ());
    return gen.to_data (null);
}

private void test_orientation () {
    assert (LeafLayout.first_orientation (800, 600) == Gtk.Orientation.HORIZONTAL);
    assert (LeafLayout.first_orientation (600, 800) == Gtk.Orientation.VERTICAL);
    assert (LeafLayout.first_orientation (600, 600) == Gtk.Orientation.HORIZONTAL);
    assert (LeafLayout.first_orientation (0, 0) == Gtk.Orientation.HORIZONTAL);
}

private void test_rebalanced () {
    assert (LeafLayout.rebalanced ({}, 800, 600) == null);
    assert (shape (LeafLayout.rebalanced ({ "a" }, 800, 600).root) == "a");
    assert (shape (LeafLayout.rebalanced ({ "a", "b" }, 800, 600).root) == "H(a,b)");
    assert (shape (LeafLayout.rebalanced ({ "a", "b" }, 600, 800).root) == "V(a,b)");
    var three = LeafLayout.rebalanced ({ "a", "b", "c" }, 800, 600);
    assert (shape (three.root) == "H(a,V(b,c))");
    assert (ratios (three.root) == "0.33;0.50;");
    var four = LeafLayout.rebalanced ({ "a", "b", "c", "d" }, 800, 600);
    assert (shape (four.root) == "H(V(a,b),V(c,d))");
    assert (ratios (four.root) == "0.50;0.50;0.50;");
    var five = LeafLayout.rebalanced ({ "a", "b", "c", "d", "e" }, 600, 800);
    assert (shape (five.root) == "V(H(a,b),H(c,V(d,e)))");
    assert (ratios (five.root) == "0.40;0.50;0.33;0.50;");
    string[] order = five.tiles ();
    assert (string.joinv (",", order) == "a,b,c,d,e");
}

private void test_place () {
    var tree = LeafLayout.rebalanced ({ "a", "b" }, 800, 600);
    tree = LeafLayout.place (tree, { "a", "b", "c" }, "b", "c", Singularity.TileZone.BOTTOM);
    assert (shape (tree.root) == "H(a,V(b,c))");
    tree = LeafLayout.place (tree, { "d", "a", "b", "c" }, "a", "d", Singularity.TileZone.TOP);
    assert (shape (tree.root) == "H(V(d,a),V(b,c))");
    tree = LeafLayout.place (tree, { "d", "a", "e", "b", "c" }, "b", "e", Singularity.TileZone.LEFT);
    assert (shape (tree.root) == "H(V(d,a),V(H(e,b),c))");
    tree = LeafLayout.place (tree, { "d", "a", "e", "b", "f", "c" }, "c", "f", Singularity.TileZone.RIGHT);
    assert (shape (tree.root) == "H(V(d,a),V(H(e,b),H(c,f)))");
    assert (ratios (tree.root) == "0.33;0.50;0.50;0.50;0.50;");

    var empty = LeafLayout.place (null, { "x" }, "missing", "x", Singularity.TileZone.RIGHT);
    assert (shape (empty.root) == "x");

    var lost = LeafLayout.rebalanced ({ "a", "b" }, 800, 600);
    var fallback = LeafLayout.place (lost, { "a", "b", "c" }, "gone", "c", Singularity.TileZone.BOTTOM);
    assert (shape (fallback.root) == "V(a,H(b,c))");

    var center = LeafLayout.rebalanced ({ "a", "b" }, 800, 600);
    var centered = LeafLayout.place (center, { "a", "b", "c" }, "a", "c", Singularity.TileZone.CENTER);
    assert (centered.size == 3);
}

private void test_remove () {
    var tree = LeafLayout.rebalanced ({ "a", "b", "c", "d" }, 800, 600);
    assert (tree.remove ("b"));
    assert (shape (tree.root) == "H(a,V(c,d))");
    assert (ratios (tree.root) == "0.33;0.50;");
    assert (!tree.remove ("b"));
    assert (tree.remove ("a"));
    assert (shape (tree.root) == "V(c,d)");
    assert (tree.remove ("d"));
    assert (shape (tree.root) == "c");
    assert (tree.remove ("c"));
    assert (tree.is_empty);
}

private void test_move_between () {
    var tree = LeafLayout.rebalanced ({ "a", "b", "c" }, 800, 600);
    tree.remove ("a");
    tree = LeafLayout.place (tree, { "b", "c", "a" }, "c", "a", Singularity.TileZone.RIGHT);
    assert (shape (tree.root) == "V(b,H(c,a))");
}

private void test_save_load () {
    string[] cells = { "a", "b", "c", "d" };
    var tree = LeafLayout.rebalanced (cells, 800, 600);
    tree = LeafLayout.place (tree, { "a", "b", "c", "d", "e" }, "d", "e", Singularity.TileZone.LEFT);
    string[] after = { "a", "b", "c", "e", "d" };
    string json = saved (tree, after);
    assert (json == "{\"orientation\":\"horizontal\",\"start\":{\"orientation\":\"vertical\",\"start\":{\"cell\":0},\"end\":{\"cell\":1}},\"end\":{\"orientation\":\"vertical\",\"start\":{\"cell\":2},\"end\":{\"orientation\":\"horizontal\",\"start\":{\"cell\":3},\"end\":{\"cell\":4}}}}");

    string[] fresh = { "p", "q", "r", "s", "t" };
    var restored = LeafLayout.read (parse (json), fresh);
    assert (restored != null);
    assert (shape (restored.root) == "H(V(p,q),V(r,H(s,t)))");
    assert (ratios (restored.root) == "0.40;0.50;0.33;0.50;");
    assert (saved (restored, fresh) == json);

    string legacy = "{\"orientation\":\"vertical\",\"start\":{\"cell\":1},\"end\":{\"cell\":0}}";
    var old = LeafLayout.read (parse (legacy), { "x", "y" });
    assert (shape (old.root) == "V(y,x)");

    assert (LeafLayout.read (parse (legacy), { "x", "y", "z" }) == null);
    assert (LeafLayout.read (parse (legacy), { "x" }) == null);
    assert (LeafLayout.read (parse ("{\"orientation\":\"vertical\",\"start\":{\"cell\":0},\"end\":{\"cell\":0}}"), { "x", "y" }) == null);
    assert (LeafLayout.read (parse ("{\"orientation\":\"diagonal\",\"start\":{\"cell\":0},\"end\":{\"cell\":1}}"), { "x", "y" }) == null);
    assert (LeafLayout.read (parse ("{\"orientation\":\"vertical\",\"start\":{\"cell\":0}}"), { "x", "y" }) == null);
    assert (LeafLayout.read (parse ("{\"cell\":5}"), { "x" }) == null);
    assert (LeafLayout.read (null, { "x" }) == null);
}

private void test_shared_model () {
    var tree = LeafLayout.rebalanced ({ "a", "b", "c" }, 800, 600);
    var node = tree.to_json ();
    var copy = Singularity.TileTree.from_json (node, { "a", "b", "c" });
    assert (copy != null);
    assert (shape (copy.root) == shape (tree.root));
    assert (tree.neighbor ("a", Singularity.TileDirection.RIGHT) == "b");
    assert (tree.neighbor ("c", Singularity.TileDirection.UP) == "b");
    assert (tree.neighbor ("b", Singularity.TileDirection.LEFT) == "a");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/leafs/layout/orientation", test_orientation);
    Test.add_func ("/leafs/layout/rebalanced", test_rebalanced);
    Test.add_func ("/leafs/layout/place", test_place);
    Test.add_func ("/leafs/layout/remove", test_remove);
    Test.add_func ("/leafs/layout/move", test_move_between);
    Test.add_func ("/leafs/layout/save-load", test_save_load);
    Test.add_func ("/leafs/layout/shared-model", test_shared_model);
    return Test.run ();
}
