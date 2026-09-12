#include "backend.h"
#include <algorithm>
#include <cstdlib>
#if defined(__APPLE__)
#include <CoreMIDI/CoreMIDI.h>
#include <mach/mach_time.h>
#elif defined(_WIN32)
#include <windows.h>
#include <mmsystem.h>
#endif

namespace drumx {
struct MIDI::Impl {
  Backend &owner;
  struct Connection {
    Backend *owner;
    uint64_t generation;
    std::atomic<bool> active{true};
    double origin = 0;
    uint8_t status = 0, first = 0;
    int used = 0;
    bool sysex = false;
    Connection(Backend &b, uint64_t g) : owner(&b), generation(g) {}
    void bytes(const uint8_t *data, size_t length, double captured) {
      for (size_t i=0;i<length;++i) {
        const uint8_t byte = data[i];
        if (byte >= 0xf8) continue;
        if (byte == 0xf0) { sysex = true; status = 0; continue; }
        if (byte == 0xf7) { sysex = false; continue; }
        if (sysex) continue;
        if (byte & 0x80) { status = byte < 0xf0 ? byte : 0; used = 0; continue; }
        if (!status) continue;
        const int size = (status & 0xf0) == 0xc0 || (status & 0xf0) == 0xd0 ? 1 : 2;
        if (used == 0) first = byte;
        if (++used == size) {
          if ((status & 0xf0) == 0x90 && byte > 0 && active.load()) owner->midi_hit(first, byte, captured, generation);
          used = 0;
        }
      }
    }
  };
  std::vector<std::unique_ptr<Connection>> connections;
  Connection *current = nullptr;
#if defined(__APPLE__)
  MIDIClientRef client = 0; MIDIPortRef port = 0; MIDIEndpointRef endpoint = 0;
  static void callback(const MIDIPacketList *packets, void *reference, void *) {
    auto &c = *static_cast<Connection*>(reference);
    if (!c.active.load()) return;
    static const double scale = [] { mach_timebase_info_data_t t{}; mach_timebase_info(&t); return double(t.numer)/double(t.denom)/1e9; }();
    const MIDIPacket *packet = &packets->packet[0];
    for (UInt32 i=0;i<packets->numPackets;++i) {
      const double captured = packet->timeStamp ? double(packet->timeStamp) * scale : host_time();
      c.bytes(packet->data, packet->length, captured);
      packet = MIDIPacketNext(packet);
    }
  }
  static std::string name(MIDIEndpointRef endpoint) {
    CFStringRef value = nullptr;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || !value) return "MIDI input";
    char buffer[1024]{}; CFStringGetCString(value, buffer, sizeof(buffer), kCFStringEncodingUTF8); CFRelease(value);
    return buffer;
  }
  static std::string id(MIDIEndpointRef endpoint) {
    SInt32 value = 0; MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &value); return "coremidi:" + std::to_string(value);
  }
#elif defined(_WIN32)
  HMIDIIN handle = nullptr;
  static void CALLBACK callback(HMIDIIN, UINT message, DWORD_PTR instance, DWORD_PTR data, DWORD_PTR timestamp) {
    auto &c = *reinterpret_cast<Connection*>(instance);
    if (message != MIM_DATA || !c.active.load()) return;
    const uint8_t bytes[] = {uint8_t(data & 0xff), uint8_t((data >> 8) & 0xff), uint8_t((data >> 16) & 0xff)};
    // WinMM gives driver capture milliseconds since midiInStart, not callback delivery time.
    c.bytes(bytes, 3, c.origin + double(uint32_t(timestamp)) / 1000.0);
  }
  static std::string utf8(const wchar_t *value) {
    int count = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    if (count <= 1) return "MIDI input";
    std::string result(size_t(count), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), count, nullptr, nullptr); result.pop_back(); return result;
  }
#endif
  explicit Impl(Backend &b) : owner(b) {
#if defined(__APPLE__)
    MIDIClientCreate(CFSTR("Drumx Shared Native"), nullptr, nullptr, &client);
#endif
  }
  ~Impl() {
#if defined(__APPLE__)
    if (client) MIDIClientDispose(client);
#endif
  }
};
MIDI::MIDI(Backend &owner) : p(std::make_unique<Impl>(owner)) {}
MIDI::~MIDI() { disconnect(); }
std::vector<Source> MIDI::sources() {
  std::vector<Source> result;
#if defined(__APPLE__)
  for (ItemCount i=0;i<MIDIGetNumberOfSources();++i) {
    const auto endpoint = MIDIGetSource(i); if (endpoint) result.push_back({Impl::id(endpoint), Impl::name(endpoint)});
  }
#elif defined(_WIN32)
  for (UINT i=0;i<midiInGetNumDevs();++i) {
    MIDIINCAPSW caps{};
    if (midiInGetDevCapsW(i, &caps, sizeof(caps)) == MMSYSERR_NOERROR) {
      auto name = Impl::utf8(caps.szPname);
      result.push_back({"winmm:" + std::to_string(i) + ":" + name, name});
    }
  }
#endif
  return result;
}
bool MIDI::connect(const std::string &id, uint64_t generation) {
  disconnect();
  auto context = std::make_unique<Impl::Connection>(p->owner, generation);
  p->current = context.get(); p->connections.push_back(std::move(context));
#if defined(__APPLE__)
  if (!p->client) return false;
  for (ItemCount i=0;i<MIDIGetNumberOfSources();++i) {
    auto endpoint = MIDIGetSource(i);
    if (Impl::id(endpoint) != id) continue;
    if (MIDIInputPortCreate(p->client, CFSTR("Drumx drum input"), Impl::callback, p->current, &p->port) != noErr) return false;
    p->endpoint = endpoint;
    if (MIDIPortConnectSource(p->port, endpoint, nullptr) == noErr) return true;
    disconnect(); return false;
  }
#elif defined(_WIN32)
  const auto available = sources();
  for (const auto &source : available) {
    if (source.id != id) continue;
    const UINT index = UINT(std::strtoul(id.c_str() + 6, nullptr, 10));
    if (midiInOpen(&p->handle, index, reinterpret_cast<DWORD_PTR>(&Impl::callback), reinterpret_cast<DWORD_PTR>(p->current), CALLBACK_FUNCTION) != MMSYSERR_NOERROR) return false;
    p->current->origin = host_time();
    if (midiInStart(p->handle) == MMSYSERR_NOERROR) return true;
    disconnect(); return false;
  }
#endif
  return false;
}
void MIDI::disconnect() {
  if (p->current) p->current->active.store(false);
#if defined(__APPLE__)
  if (p->port) {
    if (p->endpoint) MIDIPortDisconnectSource(p->port, p->endpoint);
    MIDIPortDispose(p->port); p->port = 0; p->endpoint = 0;
  }
#elif defined(_WIN32)
  if (p->handle) { midiInStop(p->handle); midiInReset(p->handle); midiInClose(p->handle); p->handle = nullptr; }
#endif
  p->current = nullptr;
}
}
