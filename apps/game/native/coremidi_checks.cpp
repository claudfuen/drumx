#include "backend.h"
#include <CoreMIDI/CoreMIDI.h>
#include <mach/mach_time.h>
#include <chrono>
#include <cmath>
#include <iostream>
#include <thread>

int main() {
  MIDIClientRef client=0; MIDIEndpointRef source=0;
  if (MIDIClientCreate(CFSTR("Drumx native test"),nullptr,nullptr,&client)!=noErr ||
      MIDISourceCreate(client,CFSTR("Drumx Native CTest"),&source)!=noErr) {
    if(client)MIDIClientDispose(client);
    std::cout<<"SKIP: CoreMIDI service unavailable on this host\n";return 77;
  }
  int failures=0, checks=0;
  auto check=[&](bool ok,const char *name){++checks;if(!ok){++failures;std::cerr<<"FAIL "<<name<<"\n";}};
  {
    drumx::Backend backend;
    SInt32 uid=0;MIDIObjectGetIntegerProperty(source,kMIDIPropertyUniqueID,&uid);
    const std::string id="coremidi:"+std::to_string(uid);
    check(backend.connect_source(id),"connect actual virtual CoreMIDI endpoint");
    mach_timebase_info_data_t base{};mach_timebase_info(&base);
    const double scale=double(base.numer)/double(base.denom)/1e9;
    const uint64_t timestamp=mach_absolute_time()-uint64_t(.04/scale);
    MIDIPacketList packets;auto packet=MIDIPacketListInit(&packets);
    const Byte bytes[]={0x99,80,93};
    MIDIPacketListAdd(&packets,sizeof(packets),packet,timestamp,3,bytes);
    check(MIDIReceived(source,&packets)==noErr,"deliver original timestamp packet through CoreMIDI");
    std::vector<drumx::Hit> hits;
    for(int i=0;i<100&&hits.empty();++i){std::this_thread::sleep_for(std::chrono::milliseconds(2));hits=backend.poll_hits();}
    check(hits.size()==1,"one raw MIDI receipt from native callback");
    if(hits.size()==1) {
      check(hits[0].note==80&&hits[0].pad==-1&&hits[0].velocity==93,"unmapped raw note and velocity retained");
      check(hits[0].source_id==id,"receipt includes selected source identity");
      check(std::abs(hits[0].host_time-double(timestamp)*scale)<.000001,"original packet timestamp preserved despite delayed delivery");
    }
    backend.learn_pad(0);
    packet=MIDIPacketListInit(&packets);
    MIDIPacketListAdd(&packets,sizeof(packets),packet,mach_absolute_time(),3,bytes);
    MIDIReceived(source,&packets);hits.clear();
    for(int i=0;i<100&&hits.empty();++i){std::this_thread::sleep_for(std::chrono::milliseconds(2));hits=backend.poll_hits();}
    check(hits.size()==1&&hits[0].mapping_changed,"native MIDI callback learns added alias");
    check(backend.mapping()[0].size()==4,"CoreMIDI learning preserves default hi-hat aliases");
    backend.connect_source("");
    packet=MIDIPacketListInit(&packets);MIDIPacketListAdd(&packets,sizeof(packets),packet,mach_absolute_time(),3,bytes);MIDIReceived(source,&packets);
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    check(backend.poll_hits().empty(),"disconnected source no longer delivers observations");
  }
  MIDIEndpointDispose(source);MIDIClientDispose(client);
  std::cout<<checks<<" CoreMIDI loopback checks, "<<failures<<" failures (software endpoint, no hardware latency measurement)\n";
  return failures?1:0;
}
