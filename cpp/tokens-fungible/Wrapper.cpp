#include "Wrapper.hpp"
#include "TONTokenWallet.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

template<bool Internal>
class Wrapper final : public smart_interface<IWrapper>, public DWrapper {
public:
  static constexpr unsigned internal_wallet_hash = 0x79c9ee7e8afd15a8c45d03836db58a3439d199e9c3ab96427bee2a593b64fe3;

  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner    = 100;
    static constexpr unsigned not_enough_balance                = 101;
    static constexpr unsigned wrong_bounced_header              = 102;
    static constexpr unsigned wrong_bounced_args                = 103;
    static constexpr unsigned internal_owner_enabled            = 104;
    static constexpr unsigned internal_owner_disabled           = 105;
    static constexpr unsigned define_pubkey_or_internal_owner   = 106;
    static constexpr unsigned wrong_wallet_code_hash            = 107;
    static constexpr unsigned cant_override_wallet_code         = 108;
    static constexpr unsigned too_big_decimals                  = 109;
    static constexpr unsigned not_my_wallet_notifies            = 110;
    static constexpr unsigned burn_unallocated                  = 111;
    static constexpr unsigned message_sender_is_not_good_wallet = 112;
    static constexpr unsigned cant_override_external_wallet     = 113;
  };

  __always_inline
  bool_t init(address external_wallet) {
    require(!external_wallet_, error_code::cant_override_external_wallet);
    check_owner();
    tvm_accept();
    external_wallet_ = external_wallet;

    tvm_rawreserve(start_balance_.get(), rawreserve_flag::up_to);
    set_int_return_flag(SEND_ALL_GAS);
    return bool_t{true};
  }

  __always_inline
  bool_t setInternalWalletCode(cell wallet_code) {
    check_owner();
    tvm_accept();
    require(!internal_wallet_code_, error_code::cant_override_wallet_code);
    //require(__builtin_tvm_hashcu(wallet_code) == internal_wallet_hash,
    //        error_code::wrong_wallet_code_hash);
    internal_wallet_code_ = wallet_code;

    if constexpr (Internal) {
      auto value_gr = int_value();
      tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
      set_int_return_flag(SEND_ALL_GAS);
    }
    return bool_t{true};
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

    auto [wallet_init, dest] = calc_internal_wallet_init(pubkey, internal_owner);
    ITONTokenWalletPtr dest_handle(dest);
    dest_handle.deploy_noop(wallet_init, Grams(grams.get()));

    // sending all rest gas except reserved old balance, processing and deployment costs
    set_int_return_flag(SEND_ALL_GAS);
    return dest;
  }

  // Notification about incoming tokens from Wrapper owned external wallet
  __always_inline
  WrapperRet onTip3Transfer(
    address answer_addr,
    uint128 balance,
    uint128 new_tokens,
    uint256 sender_pubkey,
    address sender_owner,
    cell    payload
  ) {
    require(int_sender() == external_wallet_->get(), error_code::not_my_wallet_notifies);

    // to send answer to the original caller (caller->tip3wallet->wrapper->caller)
    set_int_sender(answer_addr);
    set_int_return_value(0);
    set_int_return_flag(SEND_ALL_GAS);

    auto args = parse<FLeXDeployWalletArgs>(payload.ctos());

    auto value_gr = int_value();
    tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);

    auto [wallet_init, dest] = calc_internal_wallet_init(args.pubkey, args.internal_owner);
    ITONTokenWalletPtr dest_handle(dest);
    dest_handle.deploy(wallet_init, Grams(args.grams.get())).accept(new_tokens, int_sender(), args.grams);
    total_granted_ += new_tokens;

    return { uint32(0), dest_handle.get() };
  }

  __always_inline
  void burn(
    address answer_addr,
    uint256 sender_pubkey,
    address sender_owner,
    uint256 out_pubkey,
    address out_internal_owner,
    uint128 tokens
  ) {
    require(total_granted_ >= tokens, error_code::burn_unallocated);
    auto [sender, value_gr] = int_sender_and_value();
    require(sender == expected_internal_address(sender_pubkey, sender_owner),
            error_code::message_sender_is_not_good_wallet);
    tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
    (*external_wallet_)(Grams(0), SEND_ALL_GAS).
      transferToRecipient(answer_addr, out_pubkey, out_internal_owner, tokens, uint128(0),
                          bool_t{true}, bool_t{false});
    total_granted_ -= tokens;
  }

  __always_inline
  uint128 requestTotalGranted() {
    auto value_gr = int_value();
    tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
    set_int_return_flag(SEND_ALL_GAS);
    return total_granted_;
  }

  // getters
  __always_inline
  wrapper_details_info getDetails() {
    return { getName(), getSymbol(), getDecimals(),
             getRootKey(), getTotalGranted(), getInternalWalletCode(),
             getOwnerAddress(), getExternalWallet() };
  }

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

  __always_inline uint128 getTotalGranted() {
    return total_granted_;
  }

  __always_inline bool_t hasInternalWalletCode() {
    return bool_t{!!internal_wallet_code_};
  }

  __always_inline cell getInternalWalletCode() {
    return internal_wallet_code_.get();
  }

  __always_inline address getOwnerAddress() {
    return owner_address_ ? *owner_address_ : address::make_std(int8(0), uint256(0));
  }

  __always_inline address getExternalWallet() {
    return external_wallet_->get();
  }

  __always_inline
  address getWalletAddress(uint256 pubkey, address owner) {
    return calc_internal_wallet_init(pubkey, owner).second;
  }

  // received bounced message back
  __always_inline static int _on_bounced(cell /*msg*/, slice msg_body) {
    tvm_accept();

    using Args = args_struct_t<&ITONTokenWallet::accept>;
    parser p(msg_body);
    require(p.ldi(32) == -1, error_code::wrong_bounced_header);
    auto [opt_hdr, =p] = parse_continue<abiv1::internal_msg_header>(p);
    require(opt_hdr && opt_hdr->function_id == id_v<&ITONTokenWallet::accept>,
            error_code::wrong_bounced_header);
    auto args = parse<Args>(p, error_code::wrong_bounced_args);
    auto bounced_val = args.tokens;

    auto [hdr, persist] = load_persistent_data<IWrapper, wrapper_replay_protection_t, DWrapper>();
    require(bounced_val <= persist.total_granted_, error_code::wrong_bounced_args);
    persist.total_granted_ -= bounced_val;
    save_persistent_data<IWrapper, wrapper_replay_protection_t>(hdr, persist);
    return 0;
  }

  __always_inline
  uint256 getInternalWalletCodeHash() {
    return uint256{__builtin_tvm_hashcu(internal_wallet_code_.get())};
  }

  // default processing of unknown messages
  __always_inline static int _fallback(cell /*msg*/, slice /*msg_body*/) {
    return 0;
  }

  // =============== Support functions ==================
  DEFAULT_SUPPORT_FUNCTIONS(IWrapper, wrapper_replay_protection_t)
private:
  // transform x:0000...0000 address into empty optional<address>
  __always_inline
  std::optional<address> optional_owner(address owner) {
    return std::get<addr_std>(owner()).address ?
      std::optional<address>(owner) : std::optional<address>();
  }
  __always_inline
  address expected_internal_address(uint256 sender_public_key, address sender_owner_addr) {
    uint256 hash_addr =
      prepare_internal_wallet_state_init_and_addr(
        name_, symbol_, decimals_, root_public_key_,
        sender_public_key, address{tvm_myaddr()}, optional_owner(sender_owner_addr),
        internal_wallet_code_.get(), workchain_id_).second;
    return address::make_std(workchain_id_, hash_addr);
  }
  __always_inline
  std::pair<StateInit, address> calc_internal_wallet_init(uint256 pubkey,
                                                          address owner_addr) {
    auto [wallet_init, dest_addr] =
      prepare_internal_wallet_state_init_and_addr(
        name_, symbol_, decimals_, root_public_key_, pubkey,
        address{tvm_myaddr()}, optional_owner(owner_addr), internal_wallet_code_.get(), workchain_id_);
    address dest = address::make_std(workchain_id_, dest_addr);
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

DEFINE_JSON_ABI(IWrapper, DWrapper, EWrapper);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS_TMPL(Wrapper, IWrapper, DWrapper, WRAPPER_TIMESTAMP_DELAY)

