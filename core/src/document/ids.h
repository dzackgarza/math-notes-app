// Element ids (FORMAT.md, Page SVG): a prefix plus lowercase base32 (RFC 4648
// alphabet) from a seedable generator. std::mt19937_64 is fully specified by
// the C++ standard, so a seed gives the same ids on every host.
#pragma once

#include <cstdint>
#include <random>
#include <string>

namespace ink_engine {

class IdGenerator {
 public:
  explicit IdGenerator(uint64_t seed) : engine_(seed) {}

  std::string PageId() { return Make("p-", 6); }
  std::string LayerId() { return Make("l-", 6); }
  std::string StrokeId() { return Make("s-", 12); }
  std::string BookmarkId() { return Make("b-", 12); }
  std::string FigureId() { return Make("f-", 12); }

 private:
  std::string Make(const char *prefix, int length) {
    static constexpr char kAlphabet[] = "abcdefghijklmnopqrstuvwxyz234567";
    std::string id = prefix;
    for (int i = 0; i < length; ++i) id += kAlphabet[engine_() % 32];
    return id;
  }

  std::mt19937_64 engine_;
};

}  // namespace ink_engine
