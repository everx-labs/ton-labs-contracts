#include "TONTokenWallet.hpp"

#ifdef TIP3_ENABLE_BURN
#include "Wrapper.hpp"
#endif

#include <tvm/contract.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

template<bool Internal>
class TONTokenWallet final : public smart_interface<ITONTokenWallet>, public DTONTokenWallet {
public:
  static constexpr unsigned min_transfer_costs = 150000000;

  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner       = 100;
    static constexpr unsigned not_enough_balance                   = 101;
    static constexpr unsigned message_sender_is_not_my_root        = 102;
    static constexpr unsigned message_sender_is_not_good_wallet    = 103;
    static constexpr unsigned wrong_bounced_header                 = 104;
    static constexpr unsigned wrong_bounced_args                   = 105;
    static constexpr unsigned non_zero_remaining                   = 106;
    static constexpr unsigned no_allowance_set                     = 107;
    static constexpr unsigned wrong_spender                        = 108;
    static constexpr unsigned not_enough_allowance                 = 109;
    static constexpr unsigned internal_owner_enabled               = 110;
    static constexpr unsigned internal_owner_disabled              = 111;
    static constexpr unsigned destroy_non_empty_wallet             = 112;
    static constexpr unsigned only_original_owner_allowed          = 113;
    static constexpr unsigned wallet_in_lend_owneship              = 114;
    static constexpr unsigned finish_time_must_be_greater_than_now = 115;
    static constexpr unsigned not_enough_tons_to_process           = 116;
    static constexpr unsigned allowance_is_set                     = 117;
  };

  __always_inline
  void transfer(
    address answer_addr,
    address to,
    uint128 tokens,
    uint128 grams,
    bool_t  return_ownership
  ) {
    transfer_impl(answer_addr, to, tokens, grams, return_ownership.get(), false, builder().endc());
  }

  __always_inline
  void transferWithNotify(
    address answer_addr,
    address to,
    uint128 tokens,
    uint128 grams,
    bool_t  return_ownership,
    cell    payload
  ) {
    // performing `tail call` - requesting dest to answer to our caller
    temporary_data::setglob(global_id::answer_id, return_func_id()->get());
    transfer_impl(answer_addr, to, tokens, grams, return_ownership.get(), true, payload);
  }

  __always_inline
  void transferToRecipient(
    address answer_addr,
    uint256 recipient_public_key,
    address recipient_internal_owner,
    uint128 tokens,
    uint128 grams,
    bool_t  deploy,
    bool_t  return_ownership
  ) {
    transfer_to_recipient_impl(answer_addr, recipient_public_key, recipient_internal_owner,
                               tokens, grams, deploy.get(), return_ownership.get(), false, builder().endc());
  }

  __always_inline
  void transferToRecipientWithNotify(
    address answer_addr,
    uint256 recipient_public_key,
    address recipient_internal_owner,
    uint128 tokens,
    uint128 grams,
    bool_t  deploy,
    bool_t  return_ownership,
    cell    payload
  ) {
    // performing `tail call` - requesting dest to answer to our caller
    temporary_data::setglob(global_id::answer_id, return_func_id()->get());
    transfer_to_recipient_impl(answer_addr, recipient_public_key, recipient_internal_owner,
                               tokens, grams, deploy.get(), return_ownership.get(), true, payload);
  }

  __always_inline
  uint128 requestBalance() {
    check_internal_owner(/*original_owner_only*/false, /*allowed_for_original_owner_in_lend_state*/true);
    tvm_rawreserve(tvm_balance() - int_value().get(), rawreserve_flag::up_to);
    set_int_return_flag(SEND_ALL_GAS);
    return balance_;
  }

  __always_inline
  bool_t accept(uint128 tokens, address answer_addr, uint128 keep_grams) {
    auto [sender, value_gr] = int_sender_and_value();
    // the function must check that message sender is the RTW.
    require(root_address_ == sender, error_code::message_sender_is_not_my_root);
    tvm_accept();
    balance_ += tokens;

    tvm_rawreserve(tvm_balance() + keep_grams.get() - value_gr(), rawreserve_flag::up_to);

    set_int_sender(answer_addr);
    set_int_return_value(0);
    set_int_return_flag(SEND_ALL_GAS | IGNORE_ACTION_ERRORS);

    return bool_t{true};
  }

  __always_inline
  void internalTransfer(
    uint128 tokens,
    address answer_addr,
    uint256 sender_pubkey,
    address sender_owner,
    bool_t  notify_receiver,
    cell    payload
  ) {
    uint256 expected_address = expected_sender_address(sender_pubkey, sender_owner);
    auto [sender, value_gr] = int_sender_and_value();
    require(std::get<addr_std>(sender()).address == expected_address,
            error_code::message_sender_is_not_good_wallet);
    balance_ += tokens;

    tvm_rawreserve(tvm_balance() - value_gr(), rawreserve_flag::up_to);
    // If notify_receiver is specified, we send notification to the internal owner
    if (notify_receiver && owner_address_) {
      // performing `tail call` - requesting dest to answer to our caller
      temporary_data::setglob(global_id::answer_id, return_func_id()->get());
      ITONTokenWalletNotifyPtr(*owner_address_)(Grams(0), SEND_ALL_GAS).
        onTip3Transfer(answer_addr, balance_, tokens, sender_pubkey, sender_owner,
                       payload);
    } else {
      // In some cases (allowance request, for example) answer_addr may be this contract
      if (answer_addr != address{tvm_myaddr()})
        tvm_transfer(answer_addr, 0, false, SEND_ALL_GAS);
    }
  }

  __always_inline
  void destroy(address dest) {
    check_owner(/*original_owner_only*/true, /*allowed_for_original_owner_in_lend_state*/false);
    require(balance_ == 0, error_code::destroy_non_empty_wallet);
    tvm_accept();
    tvm_transfer(dest, 0, false,
      SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY | DELETE_ME_IF_I_AM_EMPTY | IGNORE_ACTION_ERRORS);
  }

#ifdef TIP3_ENABLE_BURN
  __always_inline
  void burn(uint256 out_pubkey, address out_internal_owner) {
    check_owner(/*original_owner_only*/true, /*allowed_for_original_owner_in_lend_state*/false);
    tvm_accept();
    IWrapperPtr root_ptr(root_address_);
    unsigned flags = SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY | DELETE_ME_IF_I_AM_EMPTY |
                     IGNORE_ACTION_ERRORS;
    root_ptr(Grams(0), flags).
      burn(int_sender(), wallet_public_key_, get_owner_addr(), out_pubkey, out_internal_owner, getBalance());
  }
#endif

#ifdef TIP3_ENABLE_LEND_OWNERSHIP
  __always_inline
  void lendOwnership(
    address answer_addr,
    uint128 grams,
    uint256 std_dest,
    uint128 lend_balance,
    uint32  lend_finish_time,
    cell    deploy_init_cl,
    cell    payload
  ) {
    auto allowed_balance = check_owner(/*original_owner_only*/true, /*allowed_for_original_owner_in_lend_state*/true);
    // Current allocated lend balance plus new lend balance LEQ all wallet balance
    require(lend_balance > 0 && lend_balance <= allowed_balance, error_code::not_enough_balance);
    require(lend_finish_time > tvm_now(), error_code::finish_time_must_be_greater_than_now);
#ifdef TIP3_ENABLE_ALLOWANCE
    require(!allowance_, error_code::allowance_is_set);
#endif
    tvm_accept();

    fixup_answer_addr(answer_addr);
    auto dest = address::make_std(workchain_id_, std_dest);

    lend_ownership_.set_at(dest, {lend_balance, lend_finish_time});

    auto deploy_init = parse<StateInit>(deploy_init_cl.ctos());
    unsigned msg_flags = prepare_transfer_message_flags(grams);

    if (deploy_init.code && deploy_init.data) {
      // performing `tail call` - requesting dest to answer to our caller
      temporary_data::setglob(global_id::answer_id, return_func_id()->get());
      ITONTokenWalletNotifyPtr(dest).deploy(deploy_init, Grams(grams.get()), msg_flags, false).
        onTip3LendOwnership(answer_addr, lend_balance, lend_finish_time,
                            wallet_public_key_, get_owner_addr(), payload);
    } else {
      // performing `tail call` - requesting dest to answer to our caller
      temporary_data::setglob(global_id::answer_id, return_func_id()->get());
      ITONTokenWalletNotifyPtr(dest)(Grams(grams.get()), msg_flags, false).
        onTip3LendOwnership(answer_addr, lend_balance, lend_finish_time,
                            wallet_public_key_, get_owner_addr(), payload);
    }
  }

  __always_inline
  void returnOwnership() {
    check_owner(/*original_owner_only*/false, /*allowed_for_original_owner_in_lend_state*/false);
    lend_ownership_.erase(int_sender());
  }
#endif // TIP3_ENABLE_LEND_OWNERSHIP

  // =============================== getters =============================== //
  __always_inline
  details_info getDetails() {
    auto [filtered_lend_array, lend_balance] = filter_lend_ownerhip_array();
    return { getName(), getSymbol(), getDecimals(),
             getBalance(), getRootKey(), getWalletKey(),
             getRootAddress(), getOwnerAddress(), filtered_lend_array, lend_balance,
             getCode(), allowance(), workchain_id_ };
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
  __always_inline uint128 getBalance() {
    return balance_;
  }
  __always_inline uint256 getRootKey() {
    return root_public_key_;
  }
  __always_inline uint256 getWalletKey() {
    return wallet_public_key_;
  }
  __always_inline address getRootAddress() {
    return root_address_;
  }
  __always_inline address getOwnerAddress() {
    return owner_address_ ? *owner_address_ : address::make_std(int8(0), uint256(0));
  }
  __always_inline cell getCode() {
    return code_;
  }
  __always_inline allowance_info allowance() {
#ifdef TIP3_ENABLE_ALLOWANCE
    if (allowance_) return *allowance_;
#endif
    return allowance_info{address::make_std(int8(0), uint256(0)), uint128(0)};
  }

  // ========================= allowance interface ========================= //
#ifdef TIP3_ENABLE_ALLOWANCE
  __always_inline
  void approve(
    address spender,
    uint128 remainingTokens,
    uint128 tokens
  ) {
    check_owner(/*original_owner_only*/true, /*allowed_for_original_owner_in_lend_state*/false);
    require(tokens <= balance_, error_code::not_enough_balance);
    tvm_accept();
    if (allowance_) {
      if (allowance_->remainingTokens == remainingTokens) {
        allowance_->remainingTokens = tokens;
        allowance_->spender = spender;
      }
    } else {
      require(remainingTokens == 0, error_code::non_zero_remaining);
      allowance_ = { spender, tokens };
    }
  }

  __always_inline
  void transferFrom(
    address answer_addr,
    address from,
    address to,
    uint128 tokens,
    uint128 grams
  ) {
    transfer_from_impl(answer_addr, from, to, tokens, grams, false, builder().endc());
  }

  __always_inline
  void transferFromWithNotify(
    address answer_addr,
    address from,
    address to,
    uint128 tokens,
    uint128 grams,
    cell    payload
  ) {
    transfer_from_impl(answer_addr, from, to, tokens, grams, true, payload);
  }

  __always_inline
  void internalTransferFrom(
    address answer_addr,
    address to,
    uint128 tokens,
    bool_t  notify_receiver,
    cell    payload
  ) {
    require(!!allowance_, error_code::no_allowance_set);
    require(int_sender() == allowance_->spender, error_code::wrong_spender);
    require(tokens <= allowance_->remainingTokens, error_code::not_enough_allowance);
    require(tokens <= balance_, error_code::not_enough_balance);

    ITONTokenWalletPtr dest_wallet(to);
    tvm_rawreserve(tvm_balance() - int_value().get(), rawreserve_flag::up_to);
    dest_wallet(Grams(0), SEND_ALL_GAS).
      internalTransfer(tokens, answer_addr, wallet_public_key_, get_owner_addr(), notify_receiver, payload);

    allowance_->remainingTokens -= tokens;
    balance_ -= tokens;
  }

  __always_inline
  void disapprove() {
    check_owner(/*original_owner_only*/true, /*allowed_for_original_owner_in_lend_state*/false);
    tvm_accept();
    allowance_.reset();
  }
#endif // TIP3_ENABLE_ALLOWANCE

  // received bounced message back
  __always_inline static int _on_bounced(cell msg, slice msg_body) {
    tvm_accept();

    parser p(msg_body);
    require(p.ldi(32) == -1, error_code::wrong_bounced_header);
    auto [opt_hdr, =p] = parse_continue<abiv2::internal_msg_header>(p);
    require(!!opt_hdr, error_code::wrong_bounced_header);
    // If it is bounced internalTransferFrom, do nothing
#ifdef TIP3_ENABLE_ALLOWANCE
    if (opt_hdr->function_id == id_v<&ITONTokenWallet::internalTransferFrom>)
      return 0;
#endif

    // other cases require load/store of persistent data
    auto [hdr, persist] = load_persistent_data<ITONTokenWallet, wallet_replay_protection_t, DTONTokenWallet>();

    // If it is bounced onTip3LendOwnership, then we need to reset lend ownership
#ifdef TIP3_ENABLE_LEND_OWNERSHIP
    if (opt_hdr->function_id == id_v<&ITONTokenWalletNotify::onTip3LendOwnership>) {
      auto parsed_msg = parse<int_msg_info>(parser(msg), error_code::bad_incoming_msg);
      persist.lend_ownership_.erase(incoming_msg(parsed_msg).int_sender());
#else
    if (false) {
#endif
    } else {
      // Otherwise, it should be bounced internalTransfer
      require(opt_hdr->function_id == id_v<&ITONTokenWallet::internalTransfer>,
              error_code::wrong_bounced_header);
      using Args = args_struct_t<&ITONTokenWallet::internalTransfer>;
      static_assert(std::is_same_v<decltype(Args{}.tokens), uint128>);

      auto [answer_id, =p] = parse_continue<uint32>(p);
      // Parsing only first tokens variable internalTransfer, other arguments won't fit into bounced response
      auto bounced_val = parse<uint128>(p, error_code::wrong_bounced_args);
      persist.balance_ += bounced_val;
    }
    save_persistent_data<ITONTokenWallet, wallet_replay_protection_t>(hdr, persist);
    return 0;
  }
  // default processing of unknown messages
  __always_inline static int _fallback(cell /*msg*/, slice msg_body) {
    require(parser(msg_body).ldu(32) == 0, error_code::wrong_public_call);
    return 0;
  }

  // =============== Support functions ==================
  DEFAULT_SUPPORT_FUNCTIONS(ITONTokenWallet, wallet_replay_protection_t)
private:
  __always_inline
  void transfer_impl(address answer_addr, address to, uint128 tokens, uint128 grams,
                     bool return_ownership, bool send_notify, cell payload) {
    auto active_balance = check_transfer_requires(tokens, grams);
    // Transfer to zero address is not allowed.
    require(std::get<addr_std>(to()).address != 0, error_code::not_enough_balance);
    tvm_accept();

    unsigned msg_flags = prepare_transfer_message_flags(grams);
    ITONTokenWalletPtr dest_wallet(to);
    dest_wallet(Grams(grams.get()), msg_flags).
      internalTransfer(tokens, answer_addr, wallet_public_key_, get_owner_addr(), bool_t{send_notify}, payload);
    update_spent_balance(tokens, return_ownership);
  }

  __always_inline
  void transfer_to_recipient_impl(address answer_addr,
                                  uint256 recipient_public_key, address recipient_internal_owner,
                                  uint128 tokens, uint128 grams, bool deploy,
                                  bool return_ownership, bool send_notify, cell payload) {
    auto active_balance = check_transfer_requires(tokens, grams);
    tvm_accept();

    unsigned msg_flags = prepare_transfer_message_flags(grams);
    auto [wallet_init, dest] = calc_wallet_init(recipient_public_key, recipient_internal_owner);
    ITONTokenWalletPtr dest_wallet(dest);
    if (deploy) {
      dest_wallet.deploy(wallet_init, Grams(grams.get()), msg_flags).
        internalTransfer(tokens, answer_addr, wallet_public_key_, get_owner_addr(), bool_t{send_notify}, payload);
    } else {
      dest_wallet(Grams(grams.get()), msg_flags).
        internalTransfer(tokens, answer_addr, wallet_public_key_, get_owner_addr(), bool_t{send_notify}, payload);
    }
    update_spent_balance(tokens, return_ownership);
  }

#ifdef TIP3_ENABLE_ALLOWANCE
  __always_inline
  void transfer_from_impl(address answer_addr, address from, address to,
                          uint128 tokens, uint128 grams, bool send_notify, cell payload) {
    check_owner(/*original_owner_only*/true, /*allowed_for_original_owner_in_lend_state*/false);
    tvm_accept();

    fixup_answer_addr(answer_addr);
    unsigned msg_flags = prepare_transfer_message_flags(grams);

    ITONTokenWalletPtr dest_wallet(from);
    dest_wallet(Grams(grams.get()), msg_flags).
      internalTransferFrom(answer_addr, to, tokens, bool_t{send_notify}, payload);
  }
#endif

  __always_inline
  address get_owner_addr() {
    return owner_address_ ? *owner_address_ :
                            address::make_std(int8(0), uint256(0));
  }

  // If zero answer_addr is specified, it is corrected to incoming sender (for internal message),
  // or this contract address (for external message)
  __always_inline
  void fixup_answer_addr(address &answer_addr) {
    if (std::get<addr_std>(answer_addr()).address == 0) {
      if constexpr (Internal)
        answer_addr = int_sender();
      else
        answer_addr = tvm_myaddr();
    }
  }

  __always_inline
  uint128 check_transfer_requires(uint128 tokens, uint128 grams) {
    auto active_balance = check_owner(/*original_owner_only*/false, /*allowed_for_original_owner_in_lend_state*/false);
    require(tokens <= active_balance, error_code::not_enough_balance);

    if constexpr (Internal)
      require(int_value().get() >= min_transfer_costs, error_code::not_enough_tons_to_process);
    else
      require(grams.get() >= min_transfer_costs && tvm_balance() > grams.get(),
              error_code::not_enough_tons_to_process);
    return active_balance;
  }

  __always_inline
  unsigned prepare_transfer_message_flags(uint128 &grams) {
    unsigned msg_flags = IGNORE_ACTION_ERRORS;
    if constexpr (Internal) {
      tvm_rawreserve(tvm_balance() - int_value().get(), rawreserve_flag::up_to);
      msg_flags = SEND_ALL_GAS;
      grams = 0;
    }
    return msg_flags;
  }

  __always_inline
  void update_spent_balance(uint128 tokens, bool return_ownership) {
    balance_ -= tokens;
#ifdef TIP3_ENABLE_LEND_OWNERSHIP
    if (lend_ownership_.empty())
      return;
    auto sender = int_sender();
    if (return_ownership) {
      lend_ownership_.erase(sender);
    } else {
      auto v = lend_ownership_[sender];
      v.lend_balance -= tokens;
      if (!v.lend_balance)
        lend_ownership_.erase(sender);
      else
        lend_ownership_.set_at(sender, v);
    }
#endif
  }

  // transform x:0000...0000 address into empty optional<address>
  __always_inline
  std::optional<address> optional_owner(address owner) {
    return std::get<addr_std>(owner()).address ?
      std::optional<address>(owner) : std::optional<address>();
  }

  __always_inline
  std::pair<StateInit, uint256> calc_wallet_init_hash(uint256 pubkey, address internal_owner) {
    DTONTokenWallet wallet_data =
      prepare_wallet_data(name_, symbol_, decimals_, root_public_key_, pubkey, root_address_,
                          optional_owner(internal_owner), code_, workchain_id_);
    return prepare_wallet_state_init_and_addr(wallet_data);
  }

  __always_inline
  uint256 expected_sender_address(uint256 sender_public_key, address sender_owner) {
    return calc_wallet_init_hash(sender_public_key, sender_owner).second;
  }

  __always_inline
  std::pair<StateInit, address> calc_wallet_init(uint256 pubkey, address internal_owner) {
    auto [wallet_init, dest_addr] = calc_wallet_init_hash(pubkey, internal_owner);
    address dest = address::make_std(workchain_id_, dest_addr);
    return { wallet_init, dest };
  }

  // Filter lend ownership map to keep only actual (unexpired) records and common lend balance
  __always_inline
  std::pair<lend_ownership_map, uint128> filter_lend_ownerhip_map() {
#ifdef TIP3_ENABLE_LEND_OWNERSHIP
    if (lend_ownership_.empty())
      return {};
    auto now_v = tvm_now();
    lend_ownership_map rv;
    uint128 lend_balance;
    for (auto v : lend_ownership_) {
      if (now_v < v.second.lend_finish_time) {
        rv.insert(v);
        lend_balance += v.second.lend_balance;
      }
    }
    lend_ownership_ = rv;
    return { rv, lend_balance };
#else
    return {};
#endif
  }

  __always_inline
  std::pair<lend_ownership_array, uint128> filter_lend_ownerhip_array() {
#ifdef TIP3_ENABLE_LEND_OWNERSHIP
    if (lend_ownership_.empty())
      return {};
    auto now_v = tvm_now();
    lend_ownership_array rv;
    uint128 lend_balance;
    for (auto v : lend_ownership_) {
      if (now_v < v.second.lend_finish_time) {
        rv.push_back({v.first, v.second.lend_balance, v.second.lend_finish_time});
        lend_balance += v.second.lend_balance;
      }
    }
    return { rv, lend_balance };
#else
    return {};
#endif
  }

  __always_inline bool is_internal_owner() const { return owner_address_.has_value(); }

  // original_owner_only - methods only allowed to call by original owner (no lend)
  // allowed_for_original_owner_in_lend_state - methods allowed to call by original owner in lend state
  __always_inline
  uint128 check_internal_owner(bool original_owner_only, bool allowed_for_original_owner_in_lend_state) {
    auto [filtered_map, actual_lend_balance] = filter_lend_ownerhip_map();
    if (actual_lend_balance > 0) {
      if (allowed_for_original_owner_in_lend_state) {
        require(is_internal_owner(), error_code::internal_owner_disabled);
        if (*owner_address_ == int_sender())
          return balance_ - actual_lend_balance;
      }
      require(!original_owner_only, error_code::only_original_owner_allowed);
      auto elem = filtered_map.lookup(int_sender());
      require(!!elem, error_code::message_sender_is_not_my_owner);
      return std::min(balance_, elem->lend_balance);
    } else {
      require(is_internal_owner(), error_code::internal_owner_disabled);
      require(*owner_address_ == int_sender(),
              error_code::message_sender_is_not_my_owner);
      return balance_;
    }
  }

  __always_inline
  uint128 check_external_owner() {
    require(!is_internal_owner(), error_code::internal_owner_enabled);
    require(msg_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);
    tvm_accept();
    auto [filtered_map, lend_balance] = filter_lend_ownerhip_map();
    require(filtered_map.empty(), error_code::wallet_in_lend_owneship);
    return balance_;
  }

  __always_inline
  uint128 check_owner(bool original_owner_only, bool allowed_in_lend_state) {
    if constexpr (Internal)
      return check_internal_owner(original_owner_only, allowed_in_lend_state);
    else
      return check_external_owner();
  }
};

DEFINE_JSON_ABI(ITONTokenWallet, DTONTokenWallet, ETONTokenWallet);

// ----------------------------- Main entry functions ---------------------- //
#ifdef TIP3_ENABLE_EXTERNAL
DEFAULT_MAIN_ENTRY_FUNCTIONS_TMPL(TONTokenWallet, ITONTokenWallet, DTONTokenWallet, TOKEN_WALLET_TIMESTAMP_DELAY)
#else
MAIN_ENTRY_FUNCTIONS_NO_REPLAY_TMPL(TONTokenWallet, ITONTokenWallet, DTONTokenWallet)
#endif

