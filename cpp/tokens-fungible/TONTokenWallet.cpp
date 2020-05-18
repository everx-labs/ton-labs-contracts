#include "TONTokenWallet.hpp"

#include <tvm/contract.hpp>
#include <tvm/contract_handle.hpp>

using namespace tvm;
using namespace schema;

class TONTokenWallet final : public smart_interface<ITONTokenWallet>, public DTONTokenWallet {
public:
  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner    = 100;
    static constexpr unsigned not_enough_balance                = 101;
    static constexpr unsigned message_sender_is_not_my_root     = 102;
    static constexpr unsigned message_sender_is_not_good_wallet = 103;
    static constexpr unsigned wrong_bounced_header              = 104;
    static constexpr unsigned wrong_bounced_args                = 105;
    static constexpr unsigned non_zero_remaining                = 106;
    static constexpr unsigned no_allowance_set                  = 107;
    static constexpr unsigned wrong_spender                     = 108;
    static constexpr unsigned not_enough_allowance              = 109;
  };

  __always_inline
  void constructor(bytes name, bytes symbol, uint8 decimals,
                   uint256 root_public_key, uint256 wallet_public_key,
                   lazy<MsgAddressInt> root_address, cell code) {
    name_ = name;
    symbol_ = symbol;
    decimals_ = decimals;
    balance_ = TokensType(0);
    root_public_key_ = root_public_key;
    wallet_public_key_ = wallet_public_key;
    root_address_ = root_address;
    code_ = code;
  }

  __always_inline
  void transfer(lazy<MsgAddressInt> dest, TokensType tokens, WalletTONSType tons) {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);

    // the function must complete successfully if token balance is less that transfer value.
    require(tokens <= balance_, error_code::not_enough_balance);

    // Transfer to zero address is not allowed.
    require(std::get<addr_std>(dest()).address != 0, error_code::not_enough_balance);

    tvm_accept();

    contract_handle<ITONTokenWallet> dest_wallet(dest);
    dest_wallet(Grams(tons.get())).
      call<&ITONTokenWallet::internalTransfer>(tokens, wallet_public_key_);

    balance_ -= tokens;
  }

  __always_inline
  void accept(TokensType tokens) {
    // the function must check that message sender is the RTW.
    require(root_address_.raw_slice() == int_sender().raw_slice(),
            error_code::message_sender_is_not_my_root);

    tvm_accept();

    balance_ += tokens;
  }

  __always_inline
  void internalTransfer(TokensType tokens, uint256 pubkey) {
    uint256 expected_address = expected_sender_address(pubkey);
    auto sender = int_sender();

    require(std::get<addr_std>(sender()).address == expected_address,
            error_code::message_sender_is_not_good_wallet);

    tvm_accept();

    balance_ += tokens;
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
  __always_inline TokensType getBalance() {
    return balance_;
  }
  __always_inline uint256 getWalletKey() {
    return wallet_public_key_;
  }
  __always_inline lazy<MsgAddressInt> getRootAddress() {
    return root_address_;
  }
  __always_inline allowance_info allowance() {
    return allowance_ ? *allowance_ :
      allowance_info{lazy<MsgAddressInt>{addr_std{ {}, {}, int8(0), uint256(0) }}, TokensType(0)};
  }

  // allowance interface
  __always_inline
  void approve(lazy<MsgAddressInt> spender, TokensType remainingTokens, TokensType tokens) {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);
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
  void transferFrom(lazy<MsgAddressInt> dest, lazy<MsgAddressInt> to, TokensType tokens,
                    WalletTONSType tons) {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);
    tvm_accept();

    contract_handle<ITONTokenWallet> dest_wallet(dest);
    dest_wallet(Grams(tons.get())).
      call<&ITONTokenWallet::internalTransferFrom>(to, tokens);
  }

  __always_inline
  void internalTransferFrom(lazy<MsgAddressInt> to, TokensType tokens) {
    require(!!allowance_, error_code::no_allowance_set);
    require(int_sender().raw_slice() == allowance_->spender.raw_slice(), error_code::wrong_spender);
    require(tokens <= allowance_->remainingTokens, error_code::not_enough_allowance);
    require(tokens <= balance_, error_code::not_enough_balance);

    contract_handle<ITONTokenWallet> dest_wallet(to);
    dest_wallet(Grams(0), SEND_REST_GAS_FROM_INCOMING).
      call<&ITONTokenWallet::internalTransfer>(tokens, wallet_public_key_);

    allowance_->remainingTokens -= tokens;
    balance_ -= tokens;
  }

  __always_inline
  void disapprove() {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);
    tvm_accept();
    allowance_.reset();
  }

  // received bounced message back
  __always_inline static int _on_bounced(cell msg, slice msg_body) {
    tvm_accept();

    parser p(msg_body);
    require(p.ldi(32) == -1, error_code::wrong_bounced_header);
    auto [opt_hdr, =p] = parse_continue<abiv1::internal_msg_header>(p);
    require(!!opt_hdr, error_code::wrong_bounced_header);
    // If it is bounced internalTransferFrom, do nothing
    if (opt_hdr->function_id == id_v<&ITONTokenWallet::internalTransferFrom>)
      return 0;

    // Otherwise, it should be bounced internalTransfer
    require(opt_hdr->function_id == id_v<&ITONTokenWallet::internalTransfer>,
            error_code::wrong_bounced_header);
    using Args = args_struct_t<&ITONTokenWallet::internalTransfer>;
    static_assert(std::is_same_v<decltype(Args{}.tokens), TokensType>);

    // Parsing only first tokens variable internalTransfer pubkey argument won't fit into bounced response
    auto bounced_val = parse<TokensType>(p, error_code::wrong_bounced_args);

    auto [hdr, persist] = load_persistent_data<wallet_replay_protection_t, DTONTokenWallet>();
    persist.balance_ += bounced_val;
    save_persistent_data<wallet_replay_protection_t>(hdr, persist);
    return 0;
  }
  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }

  unsigned pubkey_ = 0;
  __always_inline void set_tvm_pubkey(unsigned pubkey) { pubkey_ = pubkey; }
  __always_inline unsigned tvm_pubkey() const { return pubkey_; }

  std::variant<cell, slice> msg_slice_;
  __always_inline void set_msg_slice(slice sl) { msg_slice_ = sl; }
  __always_inline void set_msg_slice(cell cl) { msg_slice_ = cl; }
  __always_inline slice msg_slice() {
    if (isa<cell>(msg_slice_))
      msg_slice_ = std::get_known<cell>(msg_slice_).ctos();
    return std::get_known<slice>(msg_slice_);
  }

  std::optional<lazy<MsgAddressInt>> int_sender_;
  __always_inline lazy<MsgAddressInt> int_sender() {
    if (!int_sender_) {
      auto parsed_msg = parse<schema::int_msg_info>(parser(msg_slice()), error_code::bad_incoming_msg);
      int_sender_ = incoming_msg(parsed_msg).int_sender();
    }
    return *int_sender_;
  }
  std::optional<lazy<MsgAddressExt>> ext_sender_;
  __always_inline lazy<MsgAddressExt> ext_sender() {
    if (!ext_sender_) {
      auto parsed_msg = parse<schema::ext_in_msg_info>(parser(msg_slice()), error_code::bad_incoming_msg);
      ext_sender_ = incoming_msg(parsed_msg).ext_sender();
    }
    return *ext_sender_;
  }
private:
  __always_inline uint256 expected_sender_address(uint256 sender_public_key) {
    DTONTokenWallet wallet_data {
      name_, symbol_, decimals_,
      TokensType(0), root_public_key_, sender_public_key,
      root_address_, code_
    };
    return prepare_wallet_state_init_and_addr(wallet_data).second;
  }
};

DEFINE_JSON_ABI(ITONTokenWallet, DTONTokenWallet, ETONTokenWallet);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(TONTokenWallet, ITONTokenWallet, DTONTokenWallet, TOKEN_WALLET_TIMESTAMP_DELAY)

