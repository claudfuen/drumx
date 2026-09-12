#include "progress_lock.h"
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace fs = std::filesystem;
namespace {
const char *path_variable = "DRUMX_ARCHIVE_LOCK_TEST_PATH";
std::string read_bytes(const fs::path &path) {
  std::ifstream input(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

// Probe through a separate process, then exit without C++ destructors. This
// checks both actual cross-process exclusion and OS cleanup after owner exit.
int probe(const char *mode) {
#if defined(_WIN32)
  const wchar_t *path = _wgetenv(L"DRUMX_ARCHIVE_LOCK_TEST_PATH");
  if (!path) return 120;
  const auto archive = fs::path(path).u8string();
#else
  const char *path = std::getenv(path_variable);
  if (!path) return 120;
  const std::string archive = path;
#endif
  drumx::ProgressLock owner;
  const bool acquired = owner.acquire(archive);
  const bool wanted = std::string(mode) == "--probe-free";
  std::_Exit(acquired == wanted ? 0 : 1);
}

bool run_probe(const char *executable, const fs::path &archive, bool expect_free) {
#if defined(_WIN32)
  const wchar_t *existing = _wgetenv(L"DRUMX_ARCHIVE_LOCK_TEST_PATH");
  const std::wstring previous = existing ? existing : L"";
  const bool had_previous = existing != nullptr;
  SetEnvironmentVariableW(L"DRUMX_ARCHIVE_LOCK_TEST_PATH", archive.c_str());
  std::wstring self(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, self.data(), DWORD(self.size()));
  if (!length || length >= self.size()) return false;
  self.resize(length);
  std::wstring command = L"\"" + self + (expect_free ? L"\" --probe-free" : L"\" --probe-held");
  STARTUPINFOW startup{}; startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  const bool launched = CreateProcessW(self.c_str(), command.data(), nullptr, nullptr,
    FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process) != 0;
  SetEnvironmentVariableW(L"DRUMX_ARCHIVE_LOCK_TEST_PATH", had_previous ? previous.c_str() : nullptr);
  if (!launched) return false;
  const DWORD wait = WaitForSingleObject(process.hProcess, 5000);
  DWORD code = 1;
  if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &code);
  else TerminateProcess(process.hProcess, 121); // Test-owned child only.
  CloseHandle(process.hThread); CloseHandle(process.hProcess);
  (void)executable;
  return wait == WAIT_OBJECT_0 && code == 0;
#else
  const char *existing = std::getenv(path_variable);
  const std::string previous = existing ? existing : "";
  const bool had_previous = existing != nullptr;
  setenv(path_variable, archive.c_str(), 1);
  const pid_t child = fork();
  if (child == 0) {
    execl(executable, executable, expect_free ? "--probe-free" : "--probe-held", nullptr);
    _exit(121);
  }
  if (had_previous) setenv(path_variable, previous.c_str(), 1); else unsetenv(path_variable);
  if (child < 0) return false;
  int status = 0;
  return waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0;
#endif
}
}

int main(int argc, char **argv) {
  if (argc == 2) return probe(argv[1]);
  int checks = 0, failures = 0;
  const auto check = [&](bool passed, const char *description) {
    ++checks;
    if (!passed) { ++failures; std::cerr << "FAIL " << description << '\n'; }
  };
  const auto serial = std::chrono::steady_clock::now().time_since_epoch().count();
  const auto directory = fs::temp_directory_path() / ("drumx-lock-check-" + std::to_string(serial));
  if (!fs::create_directory(directory)) { std::cerr << "Cannot create unique lock fixture\n"; return 1; }
  const auto archive = directory / "progress.json";
  const std::string original = "original archive bytes\n";
  { std::ofstream output(archive, std::ios::binary); output << original; }
  {
    drumx::ProgressLock first, second, independent;
    check(!first.owned() && first.archive_path().empty(), "new owner has no archive");
    check(first.acquire(archive.u8string()), "first owner acquires archive");
    check(first.owned() && first.error().empty(), "ownership is published only after acquisition");
    check(first.acquire(archive.u8string()), "same owner reacquisition is idempotent");
    check(!second.acquire(archive.u8string()) && !second.owned(), "second owner cannot acquire same archive");
    check(second.error().find("Another Drumx") != std::string::npos, "contention gives actionable separate lock error");
    check(read_bytes(archive) == original, "failed lock leaves original progress bytes untouched");
    check(run_probe(argv[0], archive, false), "separate process is excluded by held OS lock");
    const auto other = directory / "other" / "progress.json";
    check(independent.acquire(other.u8string()), "different archive directory is independent");
    check(!fs::exists(other), "locking does not create or replace progress archive itself");
    check(!first.acquire(other.u8string()) && first.archive_path() == fs::weakly_canonical(archive).u8string(), "failed reacquisition preserves original ownership");
    check(!second.acquire(archive.u8string()), "original lock remains held after failed move");
    const auto next = directory / "next" / "progress.json";
    check(first.acquire(next.u8string()), "owner can acquire new archive before releasing old handle");
    check(second.acquire(archive.u8string()) && second.error().empty(), "successful move releases previous archive for next owner");
    check(!first.acquire("relative-progress.json") && first.owned(), "relative path rejected without losing held ownership");
    check(!first.acquire(std::string("/invalid\0suffix", 15)), "embedded zero cannot truncate archive identity");
    check(!first.acquire(directory.u8string()), "directory cannot masquerade as an archive");
    const auto obstruction = directory / "not-a-directory";
    { std::ofstream output(obstruction); output << "preserve"; }
    check(!first.acquire((obstruction / "progress.json").u8string()), "unusable parent fails without acquiring unrelated archive");
    check(read_bytes(obstruction) == "preserve", "failed directory creation leaves obstruction untouched");
  }
  check(fs::exists(fs::u8path(archive.u8string() + ".lock")), "lock file persists after handle release");
  {
    drumx::ProgressLock next;
    check(next.acquire(archive.u8string()), "owner destruction permits next acquisition");
  }
  check(run_probe(argv[0], archive, true), "child process acquires and exits without destructor cleanup");
  {
    drumx::ProgressLock after_exit;
    check(after_exit.acquire(archive.u8string()), "OS releases ownership after abrupt owner process exit");
  }
  const auto unicode = directory / fs::u8path(u8"Dr\u00fcmx-\u8a66\u9a13") / fs::u8path(u8"pr\u00e1ctica.json");
  {
    drumx::ProgressLock first, second;
    check(first.acquire(unicode.u8string()), "Unicode archive path acquires through native wide Windows API");
    check(!second.acquire(unicode.u8string()), "Unicode identity still excludes another owner");
    check(run_probe(argv[0], unicode, false), "Unicode path is excluded across processes");
  }
  check(read_bytes(archive) == original, "all ownership operations preserve original archive bytes");
  // Every owner has exited its scope before deleting this test-only directory.
  fs::remove_all(directory);
  std::cout << checks << " archive ownership checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}
