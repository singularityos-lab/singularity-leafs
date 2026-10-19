namespace Singularity.Apps {

    internal bool host_shell_mode = false;

    internal const string HOST_SHELL_ACCENT = "#9b1c1c";

    private const string HOST_SHELL_GATE = """
marker="${XDG_CONFIG_HOME:-$HOME/.config}/singularity/leafs/host-shell-accepted"
if [ ! -e "$marker" ]; then
    cols=$(stty size 2>/dev/null | cut -d' ' -f2)
    [ -n "$cols" ] && [ "$cols" -gt 20 ] || cols=80
    printf '\033[1;31mHOST SHELL\033[0m\n\n'
    printf '%s\n\n%s\n' \
        'This shell runs directly on Sinty OS, outside the ush sandbox that normally protects your system and your files. Anything you run here can read, change or delete whatever your account can reach. A single mistyped command, such as rm -rf on the wrong folder, can erase your files for good.' \
        'Your home and personal folders cannot be deleted from here, and a program that deletes many files is paused until you allow it. That only limits the damage; it does not undo it. Continue only if you know what you are doing.' | fold -s -w "$cols"
    printf '\nType \033[1m"yes"\033[0m to continue, or \033[1m"yes, always"\033[0m to continue and never ask again. Anything else closes this terminal.\n' | fold -s -w "$cols"
    printf '\n> '
    IFS= read -r answer || exit 1
    answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$answer" in
        yes) ;;
        "yes, always"|"yes always"|"yes, always remember this")
            mkdir -p "${marker%/*}" && : > "$marker" ;;
        *) exit 1 ;;
    esac
    printf '\n'
fi
export PS1='\[\033[1;31m\]host\[\033[0m\] \w \$ '
[ -x /usr/bin/ush ] && exec /usr/bin/ush --guard -- "$1" -l
exec "$1" -l
""";

    internal string[] host_shell_argv () {
        string shell = GLib.FileUtils.test ("/bin/bash", GLib.FileTest.IS_EXECUTABLE) ? "/bin/bash" : "/bin/sh";
        return { "/bin/sh", "-c", HOST_SHELL_GATE, "leafs-host-shell", shell };
    }
}
