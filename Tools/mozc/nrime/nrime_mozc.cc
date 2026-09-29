// NRIME's C API over Mozc; see nrime_mozc.h. Follows ios/ios_engine.cc, Mozc's
// own in-process use of SessionHandler.
#include "nrime/nrime_mozc.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <utility>

#include "absl/status/statusor.h"
#include "absl/synchronization/mutex.h"
#include "base/system_util.h"
#include "base/version.h"
#include "data_manager/data_manager.h"
#include "engine/engine.h"
#include "protocol/commands.pb.h"
#include "session/session_handler.h"

struct NrimeMozc {
  std::unique_ptr<mozc::SessionHandler> handler;
  absl::Mutex mu;
};

extern "C" {

int32_t nrime_mozc_abi_version(void) { return NRIME_MOZC_ABI_VERSION; }

NrimeMozc* nrime_mozc_new(const char* data_path, const char* profile_dir) {
  if (data_path == nullptr || data_path[0] == '\0') return nullptr;
  if (profile_dir != nullptr && profile_dir[0] != '\0') {
    mozc::SystemUtil::SetUserProfileDirectory(profile_dir);
  }
  absl::StatusOr<std::unique_ptr<const mozc::DataManager>> data =
      mozc::DataManager::CreateFromFile(data_path);
  if (!data.ok()) return nullptr;
  absl::StatusOr<std::unique_ptr<mozc::Engine>> engine =
      mozc::Engine::CreateEngine(*std::move(data));
  if (!engine.ok()) return nullptr;

  auto* mozc = new NrimeMozc;
  mozc->handler = std::make_unique<mozc::SessionHandler>(*std::move(engine));
  return mozc;
}

void nrime_mozc_free(NrimeMozc* mozc) { delete mozc; }

int nrime_mozc_eval(NrimeMozc* mozc, const uint8_t* input, size_t input_size,
                    uint8_t** output, size_t* output_size) {
  if (mozc == nullptr || output == nullptr || output_size == nullptr) return 0;
  mozc::commands::Command command;
  if (!command.mutable_input()->ParseFromArray(input, static_cast<int>(input_size))) {
    return 0;
  }
  {
    absl::MutexLock lock(&mozc->mu);
    // A rejected command is reported in the output's error_code, as
    // mozc_server reports it; nothing to do with the return value here.
    mozc->handler->EvalCommand(&command);
  }
  std::string bytes;
  if (!command.output().SerializeToString(&bytes)) return 0;
  auto* buffer = static_cast<uint8_t*>(std::malloc(bytes.empty() ? 1 : bytes.size()));
  if (buffer == nullptr) return 0;
  std::memcpy(buffer, bytes.data(), bytes.size());
  *output = buffer;
  *output_size = bytes.size();
  return 1;
}

void nrime_mozc_free_buffer(uint8_t* buffer) { std::free(buffer); }

const char* nrime_mozc_version(void) {
  static const std::string* version = new std::string(mozc::Version::GetMozcVersion());
  return version->c_str();
}

}  // extern "C"
