#include "Budget.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/replay_attack_protection/timestamp.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

static constexpr unsigned TIMESTAMP_DELAY = 1800;

class Budget final : public smart_interface<IBudget>, public DBudget {
public:
  using replay_protection_t = replay_attack_protection::timestamp<TIMESTAMP_DELAY>;

  struct error_code : tvm::error_code {
    static constexpr unsigned wrong_sender_address = 100;
  };

  __always_inline
  void constructor(address SMV_root) {
    SMV_root_ = SMV_root;
  }

  __always_inline
  void request(uint256 proposalId, address contestAddr, uint256 requestValue) {
    require(int_sender() == SMV_root_, error_code::wrong_sender_address);

    tvm_transfer(contestAddr, requestValue.get(), /*bounce*/true);
  }

  // ==================== Support methods =========================== //

  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }
  DEFAULT_SUPPORT_FUNCTIONS(IBudget, replay_protection_t);
};

DEFINE_JSON_ABI(IBudget, DBudget, EBudget);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(Budget, IBudget, DBudget, TIMESTAMP_DELAY)

