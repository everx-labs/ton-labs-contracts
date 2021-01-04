#include "config.hpp"
#include "SMVStats.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

class SMVStats final : public smart_interface<ISMVStats>, public DSMVStats {
public:
  struct error_code : tvm::error_code {
    static constexpr unsigned wrong_sender_address = 100;
  };

  __always_inline
  void constructor(address SMV_root) {
    SMV_root_ = SMV_root;
    transfers_.reset();
    start_balance_ = tvm_balance();
  }

  __always_inline
  bool_t registerTransfer(uint256 proposalId, address contestAddr, uint256 requestValue) {
    require(int_sender() == SMV_root_, error_code::wrong_sender_address);

    auto [sender, value_gr] = int_sender_and_value();
    tvm_rawreserve(std::max(start_balance_.get(), tvm_balance() - value_gr()), rawreserve_flag::up_to);

    auto addr = std::get<addr_std>(contestAddr.val());

    transfers_.push_back(TransferRecord{proposalId, {addr.workchain_id, addr.address}, requestValue});

    set_int_return_flag(INT_RETURN_FLAG);
    return bool_t{true};
  }

  // ======= getters =======
  __always_inline
  dict_array<Transfer> getTransfers() {
    dict_array<Transfer> rv;
    for (auto it = transfers_.rbegin(); it != transfers_.rend(); ++it) {
      auto rec = *it;
      rv.push_back(
        Transfer{rec.proposalId,
                 address::make_std(rec.contestAddr.workchain_id, rec.contestAddr.address),
                 rec.requestValue});
    }
    return rv;
  }

  // ==================== Support methods =========================== //

  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }
  DEFAULT_SUPPORT_FUNCTIONS(ISMVStats, stats_replay_protection_t);
};

DEFINE_JSON_ABI(ISMVStats, DSMVStats, ESMVStats);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(SMVStats, ISMVStats, DSMVStats, STATS_TIMESTAMP_DELAY)

