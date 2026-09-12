#include "progress_lock.h"
#include <filesystem>
#include <system_error>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <cerrno>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace drumx {
namespace fs = std::filesystem;
struct ProgressLock::Impl {
#if defined(_WIN32)
  HANDLE handle = INVALID_HANDLE_VALUE;
  static bool valid(HANDLE value) { return value != INVALID_HANDLE_VALUE; }
  static void close(HANDLE value) { if (valid(value)) CloseHandle(value); }
#else
  int handle = -1;
  static bool valid(int value) { return value >= 0; }
  static void close(int value) { if (valid(value)) ::close(value); }
#endif
  std::string archive, failure;
  ~Impl() { close(handle); }
};

ProgressLock::ProgressLock() : p(std::make_unique<Impl>()) {}
ProgressLock::~ProgressLock() = default;
bool ProgressLock::owned() const { return Impl::valid(p->handle); }
const std::string &ProgressLock::archive_path() const { return p->archive; }
const std::string &ProgressLock::error() const { return p->failure; }

bool ProgressLock::acquire(const std::string &absolute_archive_path) {
  const auto unavailable = [&] {
    p->failure = "Drumx could not reserve its progress archive. Check the data folder's permissions, then reopen Drumx.";
    return false;
  };
  if (absolute_archive_path.empty() || absolute_archive_path.find('\0') != std::string::npos) return unavailable();
  try {
    auto archive = fs::u8path(absolute_archive_path);
    if (!archive.is_absolute() || archive.filename().empty()) return unavailable();
    std::error_code ec;
    fs::create_directories(archive.parent_path(), ec);
    if (ec) return unavailable();
    if (fs::is_symlink(fs::symlink_status(archive, ec))) return unavailable();
    if (ec && ec != std::errc::no_such_file_or_directory) return unavailable();
    ec.clear();
    archive = fs::weakly_canonical(archive, ec);
    if (ec || archive.filename().empty()) return unavailable();
    const bool exists = fs::exists(archive, ec);
    if (ec || (exists && !fs::is_regular_file(archive, ec)) || ec) return unavailable();
    auto normalized = archive.u8string();
    auto lock_path = archive;
    lock_path += ".lock";
    if (owned()) {
      const auto previous_lock = fs::u8path(p->archive + ".lock");
      if (normalized == p->archive || fs::equivalent(lock_path, previous_lock, ec)) {
        p->failure.clear(); return true;
      }
    }
#if defined(_WIN32)
    const HANDLE candidate = CreateFileW(lock_path.c_str(), GENERIC_READ | GENERIC_WRITE,
      0, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (!Impl::valid(candidate)) {
      const DWORD code = GetLastError();
      if (code != ERROR_SHARING_VIOLATION && code != ERROR_LOCK_VIOLATION) return unavailable();
      p->failure = "Another Drumx window owns this progress archive. Close that instance, then reopen Drumx here.";
      return false;
    }
#else
    const int candidate = ::open(lock_path.c_str(), O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (!Impl::valid(candidate)) return unavailable();
    struct stat info{};
    if (fstat(candidate, &info) != 0 || !S_ISREG(info.st_mode)) { Impl::close(candidate); return unavailable(); }
    if (flock(candidate, LOCK_EX | LOCK_NB) != 0) {
      const int code = errno;
      Impl::close(candidate);
      if (code != EWOULDBLOCK && code != EAGAIN) return unavailable();
      p->failure = "Another Drumx window owns this progress archive. Close that instance, then reopen Drumx here.";
      return false;
    }
#endif
    // Reserve the new archive first. Failure above never releases the old one.
    Impl::close(p->handle);
    p->handle = candidate;
    p->archive.swap(normalized);
    p->failure.clear();
    return true;
  } catch (const fs::filesystem_error &) {
    return unavailable();
  } catch (const std::exception &) {
    return unavailable();
  }
}
}
