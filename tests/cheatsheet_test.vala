using Singularity.Apps;

private string bundled_path;

private void test_parse () {
    string text = "# tar\n\n> Archiving utility.\n> More information: <https://example.com>.\n\n- Extract an archive:\n\n`tar xf {{source.tar}}`\n\n- List:\n\n`tar tf {{a.tar}}`\n\n# empty\n\n> Nothing here.\n";
    var pages = Cheatsheet.parse (text, "tldr");
    assert (pages.size == 1);
    assert (pages[0].name == "tar");
    assert (pages[0].summary == "Archiving utility.");
    assert (pages[0].examples.size == 2);
    assert (pages[0].examples[0].description == "Extract an archive");
    assert (pages[0].examples[0].command == "tar xf {{source.tar}}");
    assert (pages[0].examples[0].plain () == "tar xf source.tar");
}

private void test_markup () {
    assert (Cheatsheet.placeholder_markup ("ls {{a<b}} && x") == "ls <i>a&lt;b</i> &amp;&amp; x");
    assert (Cheatsheet.placeholder_markup ("plain") == "plain");
    assert (Cheatsheet.placeholder_markup ("open {{x") == "open x");
    assert (Cheatsheet.strip_placeholders ("cp {{a}} {{b}}") == "cp a b");
}

private void test_search () {
    string[] t = Cheatsheet.terms ("  Tar  EXTRACT ");
    assert (t.length == 2 && t[0] == "tar" && t[1] == "extract");
    assert (Cheatsheet.matches (t, "tar", "", "Extract an archive", "tar xf {{f}}"));
    assert (!Cheatsheet.matches (t, "zip", "", "Extract an archive", "unzip {{f}}"));
    assert (Cheatsheet.matches ({}, "x", "", "", ""));
    assert (Cheatsheet.rank ({ "tar" }, "tar") == 0);
    assert (Cheatsheet.rank ({ "ta" }, "tar") == 1);
    assert (Cheatsheet.rank ({ "archive" }, "tar") == 2);
}

private void test_merge () {
    var sheet = new Cheatsheet ();
    sheet.add_pages (Cheatsheet.parse ("# ls\n\n- a:\n\n`ls`\n", Cheatsheet.OWN_SOURCE));
    sheet.add_pages (Cheatsheet.parse ("# ls\n\n- b:\n\n`ls -l`\n", Cheatsheet.OWN_SOURCE));
    assert (sheet.pages.size == 1 && sheet.pages[0].examples.size == 2);
    assert (!sheet.has_tldr);
    sheet.add_pages (Cheatsheet.parse ("# ls\n\n- c:\n\n`ls -a`\n", Cheatsheet.TLDR_SOURCE));
    assert (sheet.pages.size == 1 && sheet.pages[0].source == Cheatsheet.TLDR_SOURCE);
    assert (sheet.pages[0].examples.size == 1);
    assert (sheet.has_tldr);
}

private void test_dir () {
    string root = DirUtils.make_tmp ("cheat-XXXXXX");
    string dir = Path.build_filename (root, "tldr", "pages", "common");
    DirUtils.create_with_parents (dir, 0700);
    FileUtils.set_contents (Path.build_filename (dir, "jq.md"), "# jq\n\n> JSON processor.\n\n- Pretty print:\n\n`jq . {{file.json}}`\n");
    FileUtils.set_contents (Path.build_filename (dir, "notes.txt"), "# nope\n\n- x:\n\n`x`\n");
    var sheet = new Cheatsheet ();
    sheet.load_dir (dir);
    assert (sheet.pages.size == 1 && sheet.pages[0].name == "jq" && sheet.has_tldr);
    FileUtils.unlink (Path.build_filename (dir, "jq.md"));
    FileUtils.unlink (Path.build_filename (dir, "notes.txt"));
}

private void test_bundled () {
    string text;
    FileUtils.get_contents (bundled_path, out text);
    var pages = Cheatsheet.parse (text, Cheatsheet.OWN_SOURCE);
    assert (pages.size >= 60);
    var names = new Gee.HashSet<string> ();
    int examples = 0;
    foreach (var p in pages) {
        assert (!names.contains (p.name));
        names.add (p.name);
        assert (p.summary != "");
        foreach (var ex in p.examples) {
            assert (ex.description != "");
            assert (!ex.plain ().contains ("{{") && !ex.plain ().contains ("}}"));
            examples++;
        }
    }
    assert (examples >= 150);
    assert (names.contains ("tar") && names.contains ("grep") && names.contains ("ssh"));
}

public static int main (string[] args) {
    Test.init (ref args);
    bundled_path = args.length > 1 ? args[1] : "data/cheatsheet/commands.md";
    Test.add_func ("/cheatsheet/parse", test_parse);
    Test.add_func ("/cheatsheet/markup", test_markup);
    Test.add_func ("/cheatsheet/search", test_search);
    Test.add_func ("/cheatsheet/merge", test_merge);
    Test.add_func ("/cheatsheet/dir", test_dir);
    Test.add_func ("/cheatsheet/bundled", test_bundled);
    return Test.run ();
}
