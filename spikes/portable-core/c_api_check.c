#include "drumx_core.h"
#include <stdio.h>

int main(void) {
    DXCore* core = dx_core_create();
    DXChartEvent chart[] = {{DX_HIHAT, 0.0}, {DX_KICK, 0.0}, {DX_SNARE, 1.0}};
    DXSnapshot snapshot = {0};
    if (!core || !dx_core_load_chart(core, 60.0, 4.0, chart, 3)) return 1;
    DXHitResult hat = dx_core_input(core, DX_HIHAT, 0.0, 0.8);
    DXHitResult kick = dx_core_input(core, DX_KICK, 0.0, 0.8);
    dx_core_finish(core, 4.0);
    dx_core_snapshot(core, &snapshot);
    const int valid = hat.judgment == DX_CENTERED && kick.judgment == DX_CENTERED
        && hat.event_id != kick.event_id && snapshot.finished
        && snapshot.total.expected == 3 && snapshot.total.matched == 2
        && snapshot.total.missed == 1 && snapshot.total.extra == 0;
    dx_core_destroy(core);
    if (!valid) { fputs("C API contract failed\n", stderr); return 1; }
    puts("C consumer linked and verified chord/miss snapshot through the public API.");
    return 0;
}
