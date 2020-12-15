#include "AuthWallet.hpp"

#include <tvm/contract.hpp>
#include <tvm/contract_handle.hpp>
#include <iterator>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

class AuthWallet final : public smart_interface<IAuthWallet>, public DAuthWallet {
public:
  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_root = 100;
  };

  __always_inline
  void constructor(bytes name, bytes symbol,
                   uint256 root_public_key, uint256 wallet_public_key,
                   address root_address, cell code) {
    name_ = name;
    symbol_ = symbol;
    root_public_key_ = root_public_key;
    wallet_public_key_ = wallet_public_key;
    root_address_ = root_address;
  }

  __always_inline
  void accept(RightId rightId) {
    require(root_address_ == int_sender(),
            error_code::message_sender_is_not_my_root);
    tvm_accept();

    if (rightId)
      rights_.insert(rightId);
  }

  __always_inline
  void deny(RightId rightId) {
    require(root_address_ == int_sender(),
            error_code::message_sender_is_not_my_root);
    tvm_accept();

    if (rightId)
      rights_.erase(rightId);
  }

  __always_inline
  void destroy() {
    require(root_address_ == int_sender(),
            error_code::message_sender_is_not_my_root);
    tvm_accept();
    auto empty_cell = builder().endc();
    tvm_transfer(root_address_, 0, false,
      SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY | DELETE_ME_IF_I_AM_EMPTY | IGNORE_ACTION_ERRORS,
      empty_cell);
  }

  // =============== getters ================== //
  __always_inline
  bytes getName() {
    return name_;
  }
  __always_inline
  bytes getSymbol() {
    return symbol_;
  }
  __always_inline
  uint256 getWalletKey() {
    return wallet_public_key_;
  }
  __always_inline
  address getRootAddress() {
    return root_address_;
  }
  __always_inline
  RightsType getRightsCount() {
    return RightsType(rights_.size().get());
  }
  __always_inline
  RightId getRightByIndex(RightsType index) {
    require(index < rights_.size(), error_code::iterator_overflow);
    return *std::next(rights_.begin(), index.get());
  }
  __always_inline
  dict_array<RightId> getRights() {
    return dict_array<RightId>(rights_.begin(), rights_.end());
  }

  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }

  // =============== Support functions ================== //
  DEFAULT_SUPPORT_FUNCTIONS(IAuthWallet, wallet_replay_protection_t)
};

DEFINE_JSON_ABI(IAuthWallet, DAuthWallet, EAuthWallet);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(AuthWallet, IAuthWallet, DAuthWallet, WALLET_TIMESTAMP_DELAY)

