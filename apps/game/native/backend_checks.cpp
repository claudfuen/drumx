#include "backend.h"
#include <chrono>
#include <cmath>
#include <iostream>
#include <thread>

namespace drumx {
// Test-only friend supplies explicit capture/transport times and device state.
// The real worker is tested separately; these hooks are never exposed to Godot.
struct BackendTestAccess {
  static void pause_worker(Backend &b) {
    b.quitting.store(true);
    if (b.worker.joinable()) b.worker.join();
  }
  static void keyboard_hit_at(Backend &b, int pad, int velocity, double captured) {
    b.receive(-1, pad, velocity, captured, false);
  }
  static void stop_at(Backend &b, double now) {
    std::lock_guard<std::mutex> lock(b.mutex);
    b.stop_locked(now);
  }
  static uint64_t source(Backend &b) {
    std::lock_guard<std::mutex> lock(b.mutex);
    b.state.source_id = "test-only:driver";
    return b.generation.fetch_add(1) + 1;
  }
  static void phrase_boundary(Backend &b) {
    std::lock_guard<std::mutex> lock(b.mutex);
    b.state.practice_start = host_time() - dx_core_duration(b.core) - .01;
  }
  static void audio_opened(Backend &b) {
    auto &status=b.audio->device_status();
    status.begin_open(); status.confirm_started(true);
  }
  static void audio_notification(Backend &b, AudioDeviceEvent event) { b.audio->device_status().notify(event); }
  static void advance_now(Backend &b) { b.advance(host_time()); }
};
}

int main(int argc, char **argv) {
  int checks=0, failures=0;
  auto check=[&](bool ok,const char *name){++checks;if(!ok){++failures;std::cerr<<"FAIL "<<name<<"\n";}};
  drumx::Backend backend(false);
  drumx::BackendTestAccess::pause_worker(backend);
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
  check(backend.snapshot().source_lost&&backend.snapshot().lost_source_id=="unavailable"&&backend.start(0)<0,"failed first MIDI choice cannot silently start a keyboard take");
  check(backend.connect_source("")&&!backend.snapshot().source_lost,"explicit keyboard choice recovers failed first MIDI selection");
  check(backend.start(-1)<0,"invalid count-in rejected");
  const double before_start=drumx::host_time();
  double first=backend.start(0); check(first>=before_start+.15,"native start schedules its lead-in from the monotonic clock");
  check(!backend.load_chart(72,1,{{0,0}}),"cannot replace playing chart");
  check(!backend.set_mapping(mapping),"cannot remap during take");
  check(backend.start(0)<0,"cannot restart active take");
  // sleep_until cannot guarantee waking inside the 125 ms grading window on a
  // loaded runner. Exercise the production receive path with two captures on the
  // exact same beat instead of turning this chord check into a scheduler test.
  drumx::BackendTestAccess::keyboard_hit_at(backend,0,100,first);
  drumx::BackendTestAccess::keyboard_hit_at(backend,2,100,first);
  auto score=backend.snapshot(); check(score.score.total.matched==2,"same-beat chord preserves two inputs");
  auto hits=backend.poll_hits(); check(hits.size()==2,"per-hit observations preserve chord");
  check(hits.size()==2 && hits[0].pad==0 && hits[1].pad==2 &&
        hits[0].host_time==first && hits[1].host_time==first &&
        hits[0].result.judgment==DX_CENTERED && hits[1].result.judgment==DX_CENTERED &&
        hits[0].result.event_id!=hits[1].result.event_id,
        "simultaneous captures match distinct centered targets");
  check(backend.poll_hits().empty(),"poll drains once");
  check(hits.size()==2 && hits[0].source_id.empty() && hits[0].note==-1,"keyboard receipt is labeled separately");
  drumx::BackendTestAccess::stop_at(backend,first+.01);
  check(!backend.snapshot().running && backend.snapshot().completed,"manual stop closes take");
  check(!backend.snapshot().naturally_completed,"partial take not called complete");
  auto matched=backend.snapshot().score.total.matched;
  drumx::BackendTestAccess::keyboard_hit_at(backend,1,100,first+.02);
  check(backend.snapshot().score.total.matched==matched,"post-stop keyboard cannot alter grade");
  check(backend.load_chart(240,1,{{0,0}}),"replace stopped chart");
  const double before_key=drumx::host_time();
  backend.keyboard_hit(1,100);
  const double after_key=drumx::host_time();
  hits=backend.poll_hits();
  check(hits.size()==1 && hits[0].pad==1 && hits[0].velocity==100 &&
        hits[0].note==-1 && hits[0].source_id.empty() &&
        hits[0].host_time>=before_key && hits[0].host_time<=after_key,
        "public keyboard input preserves pad and native receipt timestamp");
  drumx::Backend autonomous(false);
  check(autonomous.load_chart(240,1,{{0,0}}),"live worker completion chart");
  first=autonomous.start(0); (void)first;
  std::this_thread::sleep_for(std::chrono::milliseconds(1350));
  score=autonomous.snapshot();
  check(!score.running && score.completed && score.naturally_completed,"native worker finishes with no UI polling");
  check(score.score.total.missed==1,"native worker resolves unplayed targets");
  for(int i=0;i<300;++i) backend.keyboard_hit(0,90);
  check(backend.poll_hits().size()==256 && backend.snapshot().dropped_hits==44,"observation queue bounded with explicit drop count");
  if(argc>1) {
    check(backend.load_samples(argv[1],false),"all 80 original full-kit FLAC decode without audio hardware");
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

  drumx::Backend count_in_loss(false);
  const auto count_in_epoch=drumx::BackendTestAccess::source(count_in_loss);
  check(count_in_loss.start(4)>drumx::host_time(),"MIDI loss fixture starts in count-in");
  check(count_in_loss.sources().empty(),"source enumeration detects vanished input");
  auto lost=count_in_loss.snapshot();
  check(lost.source_lost&&lost.lost_source_id=="test-only:driver"&&lost.source_id.empty(),"loss preserves intended source separately from connection");
  check(lost.completed&&!lost.running&&!lost.naturally_completed&&lost.score.total.missed==0,"count-in unplug stops without missed notes or completion evidence");
  check(!lost.error.empty()&&count_in_loss.start(4)<0,"unresolved loss explains why restart is blocked");
  count_in_loss.sources();
  check(count_in_loss.snapshot().lost_source_id==lost.lost_source_id,"repeated enumeration retains recovery identity");
  count_in_loss.midi_hit(42,100,drumx::host_time(),count_in_epoch);
  check(count_in_loss.poll_hits().empty(),"packets from lost source generation are rejected");
  check(count_in_loss.set_mapping(mapping)&&!count_in_loss.snapshot().error.empty(),"mapping update cannot clear unresolved input-loss message");
  check(!count_in_loss.connect_source("still-unavailable"),"failed reconnect remains explicit failure");
  check(count_in_loss.snapshot().source_lost&&count_in_loss.snapshot().lost_source_id==lost.lost_source_id,"failed reconnect preserves intended lost device");
  check(count_in_loss.load_chart(240,1,{{0,0}})&&count_in_loss.start(0)<0,"loading a new chart cannot bypass source-loss gate");
  check(count_in_loss.connect_source(""),"explicit keyboard choice acknowledges disconnected kit");
  lost=count_in_loss.snapshot();
  check(!lost.source_lost&&lost.lost_source_id.empty()&&lost.error.empty()&&!lost.running,"explicit keyboard recovery clears loss without transport start");
  check(count_in_loss.start(4)>0,"acknowledged keyboard mode can start a fresh count-in");
  count_in_loss.stop();

  drumx::Backend midphrase_loss(false);
  const auto mid_epoch=drumx::BackendTestAccess::source(midphrase_loss);
  midphrase_loss.load_chart(240,1,{{0,0},{1,1},{2,2}});
  first=midphrase_loss.start(0);
  std::this_thread::sleep_for(std::chrono::milliseconds(180));
  midphrase_loss.midi_hit(42,100,first,mid_epoch);
  midphrase_loss.sources(); lost=midphrase_loss.snapshot();
  check(lost.source_lost&&!lost.running&&lost.completed&&!lost.naturally_completed&&lost.score.total.matched==1,"midphrase unplug preserves hits but excludes completion");
  const auto loss_matched=lost.score.total.matched, loss_extra=lost.score.total.extra;
  midphrase_loss.keyboard_hit(0,100);
  check(midphrase_loss.snapshot().score.total.matched==loss_matched&&midphrase_loss.snapshot().score.total.extra==loss_extra,"keyboard preview cannot grade an unresolved lost MIDI take");

  drumx::Backend boundary_loss(false);
  drumx::BackendTestAccess::source(boundary_loss);
  boundary_loss.load_chart(240,1,{{0,0}}); boundary_loss.start(4);
  drumx::BackendTestAccess::phrase_boundary(boundary_loss);
  boundary_loss.sources();
  check(boundary_loss.snapshot().source_lost&&!boundary_loss.snapshot().naturally_completed,"loss detected in completion grace cannot become a natural take");
  drumx::BackendTestAccess::source(autonomous); autonomous.sources();
  check(autonomous.snapshot().source_lost&&autonomous.snapshot().naturally_completed,"later input loss does not revoke an already completed take");

  drumx::AudioDeviceStatus lifecycle;
  check(!lifecycle.ready()&&!lifecycle.interrupted(),"audio lifecycle starts unopened without interruption");
  lifecycle.notify(drumx::AudioDeviceEvent::stopped);
  check(!lifecycle.interrupted(),"intentional unopened device stop does not latch recovery");
  lifecycle.begin_open(); lifecycle.notify(drumx::AudioDeviceEvent::started); lifecycle.confirm_started(true);
  check(lifecycle.ready()&&!lifecycle.interrupted(),"confirmed started output establishes readiness");
  lifecycle.notify(drumx::AudioDeviceEvent::stopped);
  check(!lifecycle.ready()&&lifecycle.interrupted(),"unexpected device stop invalidates readiness");
  lifecycle.notify(drumx::AudioDeviceEvent::started);
  check(!lifecycle.ready()&&lifecycle.interrupted(),"automatic device restart cannot clear interruption evidence");
  lifecycle.begin_open(); lifecycle.confirm_started(true);
  check(lifecycle.ready()&&!lifecycle.interrupted(),"explicit successful reopen clears audio recovery gate");
  lifecycle.notify(drumx::AudioDeviceEvent::rerouted);
  check(!lifecycle.ready()&&lifecycle.interrupted(),"changed output route requires fresh phrase and explicit retry");
  lifecycle.confirm_started(true);
  check(lifecycle.interrupted(),"late start confirmation cannot erase a concurrent route interruption");
  lifecycle.begin_open(); lifecycle.confirm_started(false);
  check(!lifecycle.ready()&&lifecycle.interrupted(),"failed start confirmation never advertises usable output");

  drumx::Backend audio_loss(false);
  drumx::BackendTestAccess::audio_opened(audio_loss);
  audio_loss.load_chart(240,1,{{0,0}}); audio_loss.start(4);
  drumx::BackendTestAccess::audio_notification(audio_loss,drumx::AudioDeviceEvent::stopped);
  drumx::BackendTestAccess::advance_now(audio_loss);
  auto interrupted=audio_loss.snapshot();
  check(interrupted.audio_interrupted&&!interrupted.audio_ready&&!interrupted.running&&interrupted.completed&&!interrupted.naturally_completed,"count-in device stop interrupts native transport without completion");
  check(interrupted.score.total.missed==0&&!interrupted.error.empty(),"count-in audio loss has recoverable message and no omissions");
  check(audio_loss.start(4)<0,"audio interruption blocks restart even when no physical devices are used by fixture");
  drumx::BackendTestAccess::audio_notification(audio_loss,drumx::AudioDeviceEvent::started);
  check(audio_loss.start(4)<0,"automatic audio restart does not resume scored practice");
  drumx::BackendTestAccess::audio_opened(audio_loss);
  check(!audio_loss.snapshot().running&&audio_loss.start(4)>0,"explicit successful audio reopen allows fresh count-in only");
  drumx::BackendTestAccess::phrase_boundary(audio_loss);
  drumx::BackendTestAccess::audio_notification(audio_loss,drumx::AudioDeviceEvent::rerouted);
  drumx::BackendTestAccess::advance_now(audio_loss);
  check(audio_loss.snapshot().audio_interrupted&&!audio_loss.snapshot().naturally_completed,"output change in completion grace cannot acquire natural completion");
  drumx::BackendTestAccess::source(audio_loss); audio_loss.sources();
  audio_loss.connect_source("");
  check(audio_loss.snapshot().audio_interrupted&&audio_loss.start(4)<0,"explicit keyboard choice cannot clear independent audio-loss gate");
  std::cout<<checks<<" native backend checks, "<<failures<<" failures\n";
  return failures?1:0;
}
