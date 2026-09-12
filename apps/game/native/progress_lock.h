#pragma once
#include <memory>
#include <string>

namespace drumx {
// Serial UI-thread use. The separate lock file is persistent and is never
// removed here: replacing an inode while it is locked would admit two writers.
class ProgressLock {
public:
  ProgressLock();
  ~ProgressLock();
  ProgressLock(const ProgressLock &) = delete;
  ProgressLock &operator=(const ProgressLock &) = delete;
  bool acquire(const std::string &absolute_archive_path);
  bool owned() const;
  const std::string &archive_path() const;
  const std::string &error() const;
private:
  struct Impl;
  std::unique_ptr<Impl> p;
};
}
