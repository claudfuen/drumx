#include "backend.h"
#include <chrono>
#include <cmath>
#include <iostream>
#include <thread>

namespace drumx {
// Test-only friend manipulates connection identity, never exposed through Godot.
struct BackendTestAccess {
  static uint64_t source(Backend &b) {
    std::lock_guard<std::mutex> lock(b.mutex);
    b.state.source_id = "test-only:driver";
    return b.generation.fetch_add(1) + 1;
  }
};
}

int main(int argc, char **argv) {
  int checks=0, failures=0;
  auto check=[&](bool ok,const char *name){++checks;if(!ok){++failures;std::cerr<<"FAIL "<<name<<"\n";}};
  drumx::Backend backend(false);
  check(std::isfinite(drumx::host_time()) && drumx::host_time()>0,"native monotonic clock");
  check(backend.load_chart(240,1,{{0,0},{2,0},{1,1},{0,1.5},{2,2},{1,3}}),"authored simultaneous chart");
  auto before=backend.events();
  check(!backend.load_chart(240,1,{{0,0},{0,0}}),"duplicate targets rejected");
  check(backend.events().size()==before.size(),"invalid chart preserves prior chart");
  check(!backend.load_chart(240,0,{{0,0}}),"zero bars rejected");
  auto mapping=backend.mapping(); auto invalid=mapping; invalid[1].push_back(42);
  check(!backend.set_mapping(invalid),"overlapping maps rejected atomically");
  check(backend.mapping()==mapping,"invalid map does not alter kit");
  invalid=mapping; invalid[0].push_back(128); check(!backend.set_mapping(invalid),"out of range mapping rejected");
  check(!backend.learn_pad(0),"keyboard cannot arm MIDI learning");
  check(!backend.connect_source("unavailable"),"unknown source cannot appear connected");
  check(backend.snapshot().source_id.empty(),"failed input selection clears source identity");
  check(backend.start(-1)<0,"invalid count-in rejected");
  double first=backend.start(0); check(first>drumx::host_time(),"native start is scheduled in future");
  check(!backend.load_chart(72,1,{{0,0}}),"cannot replace playing chart");
  check(!backend.set_mapping(mapping),"cannot remap during take");
  check(backend.start(0)<0,"cannot restart active take");
  std::this_thread::sleep_until(std::chrono::steady_clock::now()+std::chrono::duration<double>(std::max(0.0,first-drumx::host_time())));
  backend.keyboard_hit(0,100); backend.keyboard_hit(2,100);
  auto score=backend.snapshot(); check(score.score.total.matched==2,"same-beat chord preserves two inputs");
  auto hits=backend.poll_hits(); check(hits.size()==2,"per-hit observations preserve chord");
  check(backend.poll_hits().empty(),"poll drains once");
  check(hits.size()==2 && hits[0].source_id.empty() && hits[0].note==-1,"keyboard receipt is labeled separately");
  backend.stop(); check(!backend.snapshot().running && backend.snapshot().completed,"manual stop closes take");
  check(!backend.snapshot().naturally_completed,"partial take not called complete");
  auto matched=backend.snapshot().score.total.matched; backend.keyboard_hit(1,100);
  check(backend.snapshot().score.total.matched==matched,"post-stop keyboard cannot alter grade");
  check(backend.load_chart(240,1,{{0,0}}),"replace stopped chart");
  first=backend.start(0); (void)first;
  std::this_thread::sleep_for(std::chrono::milliseconds(1350));
  score=backend.snapshot();
  check(!score.running && score.completed && score.naturally_completed,"native worker finishes with no UI polling");
  check(score.score.total.missed==1,"native worker resolves unplayed targets");
  for(int i=0;i<300;++i) backend.keyboard_hit(0,90);
  check(backend.poll_hits().size()==256 && backend.snapshot().dropped_hits==44,"observation queue bounded with explicit drop count");
  if(argc>1) {
    check(backend.load_samples(argv[1],false),"all 24 original FLAC decode without audio hardware");
    check(backend.snapshot().samples_ready && !backend.snapshot().audio_ready,"decoded samples do not imply output ready");
    check(!backend.load_samples("/path/that/does/not/exist",false),"missing bank rejected");
    check(backend.snapshot().samples_ready,"bad reload preserves already decoded bank");
    check(backend.load_samples(argv[1],false),"valid bank reload succeeds");
    check(backend.snapshot().error.empty(),"successful reload clears stale error");
  }
  drumx::Backend input(false);
  const auto epoch=drumx::BackendTestAccess::source(input);
  input.midi_hit(80,0,drumx::host_time(),epoch);
  check(input.poll_hits().empty(),"note-off velocity cannot count as strike");
  input.midi_hit(80,95,drumx::host_time(),epoch);
  hits=input.poll_hits(); check(hits.size()==1 && hits[0].pad==-1 && hits[0].note==80,"unmapped raw MIDI remains visible");
  check(input.learn_pad(0),"selected MIDI can arm mapping");
  input.midi_hit(80,90,drumx::host_time()-1,epoch);
  check(input.snapshot().pending_pad==0,"pre-arm queued timestamp cannot learn note");
  input.poll_hits();
  input.midi_hit(80,90,drumx::host_time(),epoch);
  hits=input.poll_hits();
  check(hits.size()==1 && hits[0].mapping_changed && hits[0].result.judgment==DX_IGNORED,"learned hit is explicitly unscored");
  auto learned=input.mapping();
  check(learned[0].size()==4 && learned[0][0]==42 && learned[0][1]==44 && learned[0][2]==46,"learn preserves hi-hat articulations");
  input.learn_pad(1); input.midi_hit(80,90,drumx::host_time(),epoch);
  learned=input.mapping();
  check(learned[0].size()==3 && learned[1].size()==3,"reassign removes conflicting alias only");
  input.learn_pad(0); input.cancel_learning();
  check(input.snapshot().pending_pad==-1,"learning cancellation clears target");
  input.poll_hits(); input.midi_hit(42,100,drumx::host_time(),epoch-1);
  check(input.poll_hits().empty(),"old source generation cannot enter new connection");
  input.load_chart(240,1,{{0,0},{2,0}});
  first=input.start(0);
  std::this_thread::sleep_for(std::chrono::milliseconds(180));
  input.stop();
  input.midi_hit(42,100,first,epoch); input.midi_hit(36,100,first,epoch);
  check(input.snapshot().score.total.matched==2,"original captured chord corrects a stopped take despite late delivery");
  input.keyboard_hit(1,100);
  check(input.snapshot().score.total.extra==0,"keyboard preview cannot contaminate MIDI take");
  input.midi_hit(38,100,drumx::host_time(),epoch);
  check(input.snapshot().score.total.extra==0,"post-stop MIDI does not add new scores");
  input.connect_source("");
  check(input.snapshot().source_id.empty() && input.snapshot().pending_pad==-1,"disconnect clears input and learn identity");
  std::cout<<checks<<" native backend checks, "<<failures<<" failures\n";
  return failures?1:0;
}
