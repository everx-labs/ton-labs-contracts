#include "AuthRoot.hpp"
#include "AuthWallet.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

static constexpr unsigned ROOT_TIMESTAMP_DELAY = 1800;

// For node SE testing:
//#define INT_RETURN_FLAG (SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY)
// For dev/main-net:
#define INT_RETURN_FLAG SEND_ALL_GAS

template<bool Internal>
class AuthRoot final : public smart_interface<IAuthRoot>, public DAuthRoot {
public:
  using root_replay_protection_t = replay_attack_protection::timestamp<ROOT_TIMESTAMP_DELAY>;

  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner  = 100;
    static constexpr unsigned internal_owner_enabled          = 101;
    static constexpr unsigned internal_owner_disabled         = 102;
    static constexpr unsigned define_pubkey_or_internal_owner = 103;
  };

  __always_inline
  void constructor(bytes name, bytes symbol,
                   uint256 root_public_key, uint256 root_owner, cell wallet_code) {
    require((root_public_key != 0 and root_owner == 0) or (root_public_key == 0 and root_owner != 0),
            error_code::define_pubkey_or_internal_owner);

    name_ = name;
    symbol_ = symbol;
    root_public_key_ = root_public_key;
    wallet_code_ = wallet_code;
    if (root_owner) {
      auto workchain_id = std::get<addr_std>(address{tvm_myaddr()}.val()).workchain_id;
      owner_address_ = address::make_std(workchain_id, root_owner);
    }
    start_balance_ = tvm_balance();
  }

  __always_inline
  address deployWallet(int8 workchain_id, uint256 pubkey,
                       RightId rightId, WalletGramsType grams) {
    check_owner();
    tvm_accept();

    // Gathering some funds from internal message value to keep balance for storage payments
    //  (up to start balance of the contract)
    if constexpr (Internal) {
      auto value_gr = int_value();
      tvm_rawreserve(std::max(start_balance_.get(), tvm_balance() - value_gr()), rawreserve_flag::up_to);
    }

    auto [wallet_init, dest] = calc_wallet_init(workchain_id, pubkey);
    handle<IAuthWallet> dest_handle(dest);
    dest_handle.deploy(wallet_init, Grams(grams.get())).
      accept(rightId);

    set_int_return_flag(INT_RETURN_FLAG);
    return dest;
  }

  __always_inline
  address deployEmptyWallet(int8 workchain_id, uint256 pubkey, WalletGramsType grams) {
    // This protects from spending root balance to deploy message
    auto value_gr = int_value();
    tvm_rawreserve(std::max(start_balance_.get(), tvm_balance() - value_gr()), rawreserve_flag::up_to);

    auto [wallet_init, dest] = calc_wallet_init(workchain_id, pubkey);
    handle<IAuthWallet> dest_handle(dest);
    dest_handle.deploy(wallet_init, Grams(grams.get())).
      accept(RightId(0));

    // sending all rest gas except reserved old balance, processing and deployment costs
    set_int_return_flag(INT_RETURN_FLAG);
    return dest;
  }

  __always_inline
  void grant(address dest, RightId rightId, WalletGramsType grams) {
    check_owner();

    tvm_accept();

    handle<IAuthWallet> dest_handle(dest);
    dest_handle(Grams(grams.get())).accept(rightId);
  }

  __always_inline
  void deny(address dest, RightId rightId, WalletGramsType grams) {
    check_owner();

    tvm_accept();

    handle<IAuthWallet> dest_handle(dest);
    dest_handle(Grams(grams.get())).deny(rightId);
  }

  __always_inline
  void destroyWallet(address dest, WalletGramsType grams) {
    check_owner();

    tvm_accept();

    handle<IAuthWallet> dest_handle(dest);
    dest_handle(Grams(grams.get())).destroy();
  }

  __always_inline
  void destroyRoot(address dest) {
    check_owner();

    tvm_accept();

    auto empty_cell = builder().endc();
    tvm_transfer(dest, 0, false,
      SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY | DELETE_ME_IF_I_AM_EMPTY | IGNORE_ACTION_ERRORS,
      empty_cell);
  }

  // ================ getters ================ //
  __always_inline bytes getName() {
    return name_;
  }

  __always_inline bytes getSymbol() {
    return symbol_;
  }

  __always_inline uint256 getRootKey() {
    return root_public_key_;
  }

  __always_inline cell getWalletCode() {
    return wallet_code_;
  }

  __always_inline
  address getWalletAddress(int8 workchain_id, uint256 pubkey) {
    return calc_wallet_init(workchain_id, pubkey).second;
  }

  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }

  // =============== Support functions ==================
  DEFAULT_SUPPORT_FUNCTIONS(IAuthRoot, root_replay_protection_t)
private:
  __always_inline
  std::pair<StateInit, address> calc_wallet_init(int8 workchain_id, uint256 pubkey) {
    DAuthWallet wallet_data {
      name_, symbol_,
      root_public_key_, pubkey,
      address{tvm_myaddr()}, {}
    };
    auto [wallet_init, dest_addr] = prepare_wallet_state_init_and_addr(wallet_data, wallet_code_);
    address dest{ MsgAddressInt{ addr_std { {}, {}, workchain_id, dest_addr } } };
    return { wallet_init, dest };
  }

  __always_inline bool is_internal_owner() const { return owner_address_.has_value(); }

  __always_inline
  void check_internal_owner() {
    require(is_internal_owner(), error_code::internal_owner_disabled);
    require(*owner_address_ == int_sender(),
            error_code::message_sender_is_not_my_owner);
  }

  __always_inline
  void check_external_owner() {
    require(!is_internal_owner(), error_code::internal_owner_enabled);
    require(tvm_pubkey() == root_public_key_, error_code::message_sender_is_not_my_owner);
  }

  __always_inline
  void check_owner() {
    if constexpr (Internal)
      check_internal_owner();
    else
      check_external_owner();
  }
};

DEFINE_JSON_ABI(IAuthRoot, DAuthRoot, EAuthRoot);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS_TMPL(AuthRoot, IAuthRoot, DAuthRoot, ROOT_TIMESTAMP_DELAY)

