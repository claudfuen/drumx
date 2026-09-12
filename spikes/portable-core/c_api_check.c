#include "drumx_core.h"
#include "drumx_tempo.h"
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
    const DXTempoContext tempo_context = {1, DX_TEMPO_POLICY_VERSION, 72, 16, DX_FOLLOW, 1};
    const DXTempoAttempt takes[] = {
        {1, 1, DX_TEMPO_POLICY_VERSION, 72, 16, DX_FOLLOW, 1, 64, 64, 64, 0, 0, 1, 1},
        {2, 1, DX_TEMPO_POLICY_VERSION, 72, 16, DX_FOLLOW, 1, 64, 64, 64, 0, 0, 1, 1}
    };
    DXTempoDecision decision = {0};
    if (!dx_tempo_evaluate(takes, 2, &tempo_context, &decision)
        || !decision.checkpoint_earned || decision.action != DX_TEMPO_HIDE_NOTES
        || decision.next_bpm != 72 || decision.next_guidance != DX_FADE
        || decision.next_live_feedback != 1) {
        fputs("C guided-tempo contract failed\n", stderr);
        return 1;
    }
    puts("C consumer linked and verified chord/miss snapshot through the public API.");
    puts("C consumer verified the versioned guided-tempo checkpoint decision.");
    return 0;
}
