namespace Singularity.Apps {

    public class LeafTerminal : Vte.Terminal {
        private const uint SETTLE_MS = 180;

        private long columns = -1;
        private long rows = -1;
        private uint settle_id = 0;

        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            long c = get_column_count ();
            long r = get_row_count ();
            if (c == columns && r == rows) return;
            bool first = columns < 0;
            columns = c;
            rows = r;
            if (first) return;
            if (settle_id != 0) Source.remove (settle_id);
            settle_id = Timeout.add (SETTLE_MS, () => {
                settle_id = 0;
                redraw_foreground ();
                return Source.REMOVE;
            });
        }

        private void redraw_foreground () {
            var pty = get_pty ();
            if (pty == null) return;
            Posix.pid_t group = Posix.tcgetpgrp (pty.get_fd ());
            if (group > 0) Posix.killpg (group, Posix.Signal.WINCH);
        }

        public override void dispose () {
            if (settle_id != 0) {
                Source.remove (settle_id);
                settle_id = 0;
            }
            base.dispose ();
        }
    }
}
