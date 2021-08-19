#include "RootTokenContract.hpp"
#include "TONTokenWallet.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

template<bool Internal>
class RootTokenContract final : public smart_interface<IRootTokenContract>, public DRootTokenContract {
public:
  static constexpr unsigned wallet_hash = 0x5300be5b5c3b30c9d592f9816473d78721dfed025ca1c90c40aff60756fa468e;

  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner  = 100;
    static constexpr unsigned not_enough_balance              = 101;
    static constexpr unsigned wrong_bounced_header            = 102;
    static constexpr unsigned wrong_bounced_args              = 103;
    static constexpr unsigned internal_owner_enabled          = 104;
    static constexpr unsigned internal_owner_disabled         = 105;
    static constexpr unsigned define_pubkey_or_internal_owner = 106;
    static constexpr unsigned wrong_wallet_code_hash          = 107;
    static constexpr unsigned cant_override_wallet_code       = 108;
    static constexpr unsigned too_big_decimals                = 109;
  };

  __always_inline
  void constructor(
    string name,
    string symbol,
    uint8 decimals,
    uint256 root_public_key,
    address root_owner,
    uint128 total_supply
  ) {
    require((root_public_key != 0) or (std::get<addr_std>(root_owner()).address != 0),
            error_code::define_pubkey_or_internal_owner);
    require(decimals < 4, error_code::too_big_decimals);
    name_ = name;
    symbol_ = symbol;
    decimals_ = decimals;
    root_public_key_ = root_public_key;
    total_supply_ = total_supply;
    total_granted_ = uint128(0);
    owner_address_ = optional_owner(root_owner);
    start_balance_ = tvm_balance();
  }

  __always_inline
  bool_t setWalletCode(cell wallet_code) {
    check_owner();
    tvm_accept();
    require(!wallet_code_, error_code::cant_override_wallet_code);
    require(__builtin_tvm_hashcu(wallet_code) == wallet_hash,
            error_code::wrong_wallet_code_hash);
    wallet_code_ = wallet_code;

    if constexpr (Internal) {
      auto value_gr = int_value();
      tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
      set_int_return_flag(SEND_ALL_GAS);
    }
    return bool_t{true};
  }

  __always_inline
  address deployWallet(
    uint256 pubkey,
    address internal_owner,
    uint128 tokens,
    uint128 grams
  ) {
    check_owner();
    tvm_accept();
    require(total_granted_ + tokens <= total_supply_, error_code::not_enough_balance);

    address answer_addr;
    if constexpr (Internal) {
      auto value_gr = int_value();
      tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
      answer_addr = int_sender();
    } else {
      answer_addr = address{tvm_myaddr()};
    }

    auto [wallet_init, dest] = calc_wallet_init(pubkey, internal_owner);

    // performing `tail call` - requesting dest to answer to our caller
    temporary_data::setglob(global_id::answer_id, return_func_id()->get());
    ITONTokenWalletPtr dest_handle(dest);
    dest_handle.deploy(wallet_init, Grams(grams.get())).
      accept(tokens, answer_addr, grams);

    total_granted_ += tokens;

    set_int_return_flag(SEND_ALL_GAS);
    return dest;
  }

  __always_inline
  address deployEmptyWallet(
    uint256 pubkey,
    address internal_owner,
    uint128 grams
  ) {
    // This protects from spending root balance to deploy message
    auto value_gr = int_value();
    tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);

    auto [wallet_init, dest] = calc_wallet_init(pubkey, internal_owner);
    ITONTokenWalletPtr dest_handle(dest);
    dest_handle.deploy_noop(wallet_init, Grams(grams.get()));

    // sending all rest gas except reserved old balance, processing and deployment costs
    set_int_return_flag(SEND_ALL_GAS);
    return dest;
  }

  __always_inline
  void grant(
    address dest,
    uint128 tokens,
    uint128 grams
  ) {
    check_owner();
    require(total_granted_ + tokens <= total_supply_, error_code::not_enough_balance);

    tvm_accept();

    address answer_addr;
    unsigned msg_flags = 0;
    if constexpr (Internal) {
      auto value_gr = int_value();
      tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
      msg_flags = SEND_ALL_GAS;
      grams = 0;
      answer_addr = int_sender();
    } else {
      answer_addr = address{tvm_myaddr()};
    }

    ITONTokenWalletPtr dest_handle(dest);
    dest_handle(Grams(grams.get()), msg_flags).accept(tokens, answer_addr, uint128(0));

    total_granted_ += tokens;
  }

  __always_inline
  bool_t mint(uint128 tokens) {
    check_owner();

    tvm_accept();

    if constexpr (Internal) {
      auto value_gr = int_value();
      tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
    }

    total_supply_ += tokens;

    set_int_return_flag(SEND_ALL_GAS);
    return bool_t{true};
  }

  __always_inline
  uint128 requestTotalGranted() {
    auto value_gr = int_value();
    tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
    set_int_return_flag(SEND_ALL_GAS);
    return total_granted_;
  }

  // getters
  __always_inline string getName() {
    return name_;
  }

  __always_inline string getSymbol() {
    return symbol_;
  }

  __always_inline uint8 getDecimals() {
    return decimals_;
  }

  __always_inline uint256 getRootKey() {
    return root_public_key_;
  }

  __always_inline uint128 getTotalSupply() {
    return total_supply_;
  }

  __always_inline uint128 getTotalGranted() {
    return total_granted_;
  }

  __always_inline bool_t hasWalletCode() {
    return bool_t{!!wallet_code_};
  }

  __always_inline cell getWalletCode() {
    return wallet_code_.get();
  }

  __always_inline
  address getWalletAddress(uint256 pubkey, address owner) {
    return calc_wallet_init(pubkey, owner).second;
  }

  // received bounced message back
  __always_inline static int _on_bounced(cell /*msg*/, slice msg_body) {
    tvm_accept();

    using Args = args_struct_t<&ITONTokenWallet::accept>;
    parser p(msg_body);
    require(p.ldi(32) == -1, error_code::wrong_bounced_header);
    auto [opt_hdr, =p] = parse_continue<abiv2::internal_msg_header_with_answer_id>(p);
    require(opt_hdr && opt_hdr->function_id == id_v<&ITONTokenWallet::accept>,
            error_code::wrong_bounced_header);
    auto args = parse<Args>(p, error_code::wrong_bounced_args);
    auto bounced_val = args.tokens;

    auto [hdr, persist] = load_persistent_data<IRootTokenContract, root_replay_protection_t, DRootTokenContract>();
    require(bounced_val <= persist.total_granted_, error_code::wrong_bounced_args);
    persist.total_granted_ -= bounced_val;
    save_persistent_data<IRootTokenContract, root_replay_protection_t>(hdr, persist);
    return 0;
  }

  __always_inline
  uint256 getWalletCodeHash() {
    return uint256{__builtin_tvm_hashcu(wallet_code_.get())};
  }

  // default processing of unknown messages
  __always_inline static int _fallback(cell /*msg*/, slice /*msg_body*/) {
    return 0;
  }

  // =============== Support functions ==================
  DEFAULT_SUPPORT_FUNCTIONS(IRootTokenContract, root_replay_protection_t)
private:
  // transform x:0000...0000 address into empty optional<address>
  __always_inline
  std::optional<address> optional_owner(address owner) {
    return std::get<addr_std>(owner()).address ?
      std::optional<address>(owner) : std::optional<address>();
  }

  __always_inline
  int8 workchain_id() {
    return std::get<addr_std>(address{tvm_myaddr()}()).workchain_id;
  }

  __always_inline
  std::pair<StateInit, address> calc_wallet_init(uint256 pubkey,
                                                 address owner_addr) {
    DTONTokenWallet wallet_data =
      prepare_wallet_data(name_, symbol_, decimals_, root_public_key_, pubkey,
                          address{tvm_myaddr()}, optional_owner(owner_addr), wallet_code_.get(), workchain_id());
    auto [wallet_init, dest_addr] = prepare_wallet_state_init_and_addr(wallet_data);
    address dest = address::make_std(workchain_id(), dest_addr);
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
    require(msg_pubkey() == root_public_key_, error_code::message_sender_is_not_my_owner);
  }

  __always_inline
  void check_owner() {
    if constexpr (Internal)
      check_internal_owner();
    else
      check_external_owner();
  }
};

DEFINE_JSON_ABI(IRootTokenContract, DRootTokenContract, ERootTokenContract);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS_TMPL(RootTokenContract, IRootTokenContract, DRootTokenContract, ROOT_TIMESTAMP_DELAY)

