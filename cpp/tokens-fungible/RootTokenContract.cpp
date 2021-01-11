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
  static constexpr unsigned wallet_hash = 0xdfdd2547c0e4fcf05aae09a4689c6945395f4fbf14ebc7b7e6b0cbd17c722b52;

  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner  = 100;
    static constexpr unsigned not_enough_balance              = 101;
    static constexpr unsigned wrong_bounced_header            = 102;
    static constexpr unsigned wrong_bounced_args              = 103;
    static constexpr unsigned internal_owner_enabled          = 104;
    static constexpr unsigned internal_owner_disabled         = 105;
    static constexpr unsigned define_pubkey_or_internal_owner = 106;
    static constexpr unsigned wrong_wallet_code_hash          = 107;
  };

  __always_inline
  void constructor(bytes name, bytes symbol, uint8 decimals,
                   uint256 root_public_key, uint256 root_owner,
                   cell wallet_code, TokensType total_supply) {
    require((root_public_key != 0 and root_owner == 0) or (root_public_key == 0 and root_owner != 0),
            error_code::define_pubkey_or_internal_owner);
    require(__builtin_tvm_hashcu(wallet_code) == wallet_hash,
            error_code::wrong_wallet_code_hash);

    name_ = name;
    symbol_ = symbol;
    decimals_ = decimals;
    root_public_key_ = root_public_key;
    wallet_code_ = wallet_code;
    total_supply_ = total_supply;
    total_granted_ = TokensType(0);
    if (root_owner) {
      auto workchain_id = std::get<addr_std>(address{tvm_myaddr()}.val()).workchain_id;
      owner_address_ = address::make_std(workchain_id, root_owner);
    }
    start_balance_ = tvm_balance();
  }

  __always_inline
  address deployWallet(int8 workchain_id, uint256 pubkey, uint256 internal_owner,
                       TokensType tokens, WalletGramsType grams) {
    check_owner();
    require(total_granted_ + tokens <= total_supply_, error_code::not_enough_balance);
    require((pubkey == 0 and internal_owner != 0) or (pubkey != 0 and internal_owner == 0),
            error_code::define_pubkey_or_internal_owner);

    tvm_accept();

    // Gathering some funds from internal message value to keep balance for storage payments
    //  (up to start balance of the contract)
    if constexpr (Internal) {
      auto value_gr = int_value();
      tvm_rawreserve(std::max(start_balance_.get(), tvm_balance() - value_gr()), rawreserve_flag::up_to);
    }

    std::optional<address> owner_addr;
    if (internal_owner)
      owner_addr = address::make_std(workchain_id, internal_owner);
    auto [wallet_init, dest] = calc_wallet_init(workchain_id, pubkey, owner_addr);
    handle<ITONTokenWallet> dest_handle(dest);
    dest_handle.deploy(wallet_init, Grams(grams.get())).
      accept(tokens);

    total_granted_ += tokens;

    set_int_return_flag(SEND_ALL_GAS);
    return dest;
  }

  __always_inline
  address deployEmptyWallet(int8 workchain_id, uint256 pubkey, uint256 internal_owner,
                            WalletGramsType grams) {
    // This protects from spending root balance to deploy message
    auto value_gr = int_value();
    tvm_rawreserve(std::max(start_balance_.get(), tvm_balance() - value_gr()), rawreserve_flag::up_to);

    require((pubkey == 0 and internal_owner != 0) or (pubkey != 0 and internal_owner == 0),
            error_code::define_pubkey_or_internal_owner);

    std::optional<address> owner_addr;
    if (internal_owner)
      owner_addr = address::make_std(workchain_id, internal_owner);
    auto [wallet_init, dest] = calc_wallet_init(workchain_id, pubkey, owner_addr);
    handle<ITONTokenWallet> dest_handle(dest);
    dest_handle.deploy_noop(wallet_init, Grams(grams.get()));

    // sending all rest gas except reserved old balance, processing and deployment costs
    set_int_return_flag(SEND_ALL_GAS);
    return dest;
  }

  __always_inline
  void grant(address dest, TokensType tokens, WalletGramsType grams) {
    check_owner();
    require(total_granted_ + tokens <= total_supply_, error_code::not_enough_balance);

    tvm_accept();

    handle<ITONTokenWallet> dest_handle(dest);
    dest_handle(Grams(grams.get())).accept(tokens);

    total_granted_ += tokens;
  }

  __always_inline
  void mint(TokensType tokens) {
    check_owner();

    tvm_accept();

    total_supply_ += tokens;
  }

  // getters
  __always_inline bytes getName() {
    return name_;
  }

  __always_inline bytes getSymbol() {
    return symbol_;
  }

  __always_inline uint8 getDecimals() {
    return decimals_;
  }

  __always_inline uint256 getRootKey() {
    return root_public_key_;
  }

  __always_inline TokensType getTotalSupply() {
    return total_supply_;
  }

  __always_inline TokensType getTotalGranted() {
    return total_granted_;
  }

  __always_inline cell getWalletCode() {
    return wallet_code_;
  }

  __always_inline
  address getWalletAddress(int8 workchain_id, uint256 pubkey, uint256 owner_std_addr) {
    std::optional<address> owner_addr;
    if (owner_std_addr)
      owner_addr = address::make_std(workchain_id, owner_std_addr);
    return calc_wallet_init(workchain_id, pubkey, owner_addr).second;
  }

  // received bounced message back
  __always_inline static int _on_bounced(cell msg, slice msg_body) {
    tvm_accept();

    using Args = args_struct_t<&ITONTokenWallet::accept>;
    parser p(msg_body);
    require(p.ldi(32) == -1, error_code::wrong_bounced_header);
    auto [opt_hdr, =p] = parse_continue<abiv1::internal_msg_header>(p);
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
    return uint256{__builtin_tvm_hashcu(wallet_code_)};
  }

  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }

  // =============== Support functions ==================
  DEFAULT_SUPPORT_FUNCTIONS(IRootTokenContract, root_replay_protection_t)
private:
  __always_inline
  std::pair<StateInit, address> calc_wallet_init(int8 workchain_id, uint256 pubkey,
                                                 std::optional<address> owner_addr) {
    DTONTokenWallet wallet_data {
      name_, symbol_, decimals_,
      TokensType(0), root_public_key_, pubkey,
      address{tvm_myaddr()}, owner_addr, wallet_code_, {}, workchain_id
    };
    auto [wallet_init, dest_addr] = prepare_wallet_state_init_and_addr(wallet_data);
    address dest = address::make_std(workchain_id, dest_addr);
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

DEFINE_JSON_ABI(IRootTokenContract, DRootTokenContract, ERootTokenContract);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS_TMPL(RootTokenContract, IRootTokenContract, DRootTokenContract, ROOT_TIMESTAMP_DELAY)

