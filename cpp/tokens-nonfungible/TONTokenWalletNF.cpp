#include "TONTokenWalletNF.hpp"

#include <tvm/contract.hpp>
#include <tvm/contract_handle.hpp>
#include <iterator>
#include <tvm/default_support_functions.hpp>

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
    static constexpr unsigned no_allowance_set                  = 106;
    static constexpr unsigned wrong_spender                     = 107;
    static constexpr unsigned not_enough_allowance              = 108;
    static constexpr unsigned already_have_this_token           = 109;
    static constexpr unsigned zero_token_id                     = 110;
    static constexpr unsigned zero_dest_addr                    = 111;
  };

  __always_inline
  void constructor(bytes name, bytes symbol, uint8 decimals,
                   uint256 root_public_key, uint256 wallet_public_key,
                   lazy<MsgAddressInt> root_address, cell code) {
    name_ = name;
    symbol_ = symbol;
    decimals_ = decimals;
    root_public_key_ = root_public_key;
    wallet_public_key_ = wallet_public_key;
    root_address_ = root_address;
    code_ = code;
  }

  __always_inline
  void transfer(lazy<MsgAddressInt> dest, TokenId tokenId, WalletGramsType grams) {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);

    // Transfer to zero address is not allowed.
    require(std::get<addr_std>(dest()).address != 0, error_code::zero_dest_addr);

    tvm_accept();
    tvm_commit();
    require(tokens_.contains(tokenId), error_code::not_enough_balance);

    contract_handle<ITONTokenWallet> dest_wallet(dest);
    dest_wallet(Grams(grams.get())).
      call<&ITONTokenWallet::internalTransfer>(tokenId, wallet_public_key_);

    tokens_.erase(tokenId);
  }

  __always_inline
  void accept(TokenId tokenId) {
    // the function must check that message sender is the RTW.
    require(root_address_.sl() == int_sender().sl(),
            error_code::message_sender_is_not_my_root);

    tvm_accept();
    tvm_commit();
    require(!tokenId || !tokens_.contains(tokenId), error_code::already_have_this_token);

    if (tokenId)
      tokens_.insert(tokenId);
  }

  __always_inline
  void internalTransfer(TokenId tokenId, uint256 pubkey) {
    uint256 expected_address = expected_sender_address(pubkey);
    auto sender = int_sender();

    require(std::get<addr_std>(sender()).address == expected_address,
            error_code::message_sender_is_not_good_wallet);
    require(tokenId > 0, error_code::zero_token_id);

    tvm_accept();
    tvm_commit();
    require(!tokens_.contains(tokenId), error_code::already_have_this_token);

    tokens_.insert(tokenId);
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
    return TokensType(tokens_.size().get());
  }
  __always_inline uint256 getWalletKey() {
    return wallet_public_key_;
  }
  __always_inline lazy<MsgAddressInt> getRootAddress() {
    return root_address_;
  }
  __always_inline allowance_info allowance() {
    return allowance_ ? *allowance_ :
      allowance_info{lazy<MsgAddressInt>{addr_std{ {}, {}, int8(0), uint256(0) }}, TokenId(0)};
  }
  __always_inline TokenId getTokenByIndex(TokensType index) {
    require(index < tokens_.size(), error_code::iterator_overflow);
    return *std::next(tokens_.begin(), index.get());
  }
  __always_inline lazy<MsgAddressInt> getApproved(TokenId tokenId) {
    return (allowance_ && allowance_->allowedToken == tokenId) ? allowance_->spender :
      lazy<MsgAddressInt>{addr_std{ {}, {}, int8(0), uint256(0) }};
  }

  // allowance interface
  __always_inline
  void approve(lazy<MsgAddressInt> spender, TokenId tokenId) {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);
    require(tokenId > 0, error_code::zero_token_id);
    tvm_accept();
    tvm_commit();
    require(tokens_.contains(tokenId), error_code::not_enough_balance);

    allowance_ = { spender, tokenId };
  }

  __always_inline
  void transferFrom(lazy<MsgAddressInt> dest, lazy<MsgAddressInt> to, TokenId tokenId,
                    WalletGramsType grams) {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);
    require(tokenId > 0, error_code::zero_token_id);
    tvm_accept();

    contract_handle<ITONTokenWallet> dest_wallet(dest);
    dest_wallet(Grams(grams.get())).
      call<&ITONTokenWallet::internalTransferFrom>(to, tokenId);
  }

  __always_inline
  void internalTransferFrom(lazy<MsgAddressInt> to, TokenId tokenId) {
    require(!!allowance_, error_code::no_allowance_set);
    require(int_sender().sl() == allowance_->spender.sl(), error_code::wrong_spender);
    require(tokenId > 0, error_code::zero_token_id);
    require(tokenId == allowance_->allowedToken, error_code::not_enough_allowance);
    require(tokens_.contains(tokenId), error_code::not_enough_balance);

    contract_handle<ITONTokenWallet> dest_wallet(to);
    dest_wallet(Grams(0), SEND_REST_GAS_FROM_INCOMING).
      call<&ITONTokenWallet::internalTransfer>(tokenId, wallet_public_key_);

    allowance_.reset();
    tokens_.erase(tokenId);
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
    static_assert(std::is_same_v<decltype(Args{}.tokenId), TokenId>);

    // Parsing only first tokens variable internalTransfer pubkey argument won't fit into bounced response
    auto bounced_id = parse<TokenId>(p, error_code::wrong_bounced_args);
    require(bounced_id > 0, error_code::wrong_bounced_args);

    auto [hdr, persist] = load_persistent_data<ITONTokenWallet, wallet_replay_protection_t, DTONTokenWallet>();
    persist.tokens_.insert(bounced_id);
    save_persistent_data<ITONTokenWallet, wallet_replay_protection_t>(hdr, persist);
    return 0;
  }
  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }

  // =============== Support functions ==================
  DEFAULT_SUPPORT_FUNCTIONS(ITONTokenWallet, wallet_replay_protection_t)
private:
  __always_inline uint256 expected_sender_address(uint256 sender_public_key) {
    DTONTokenWallet wallet_data {
      name_, symbol_, decimals_,
      root_public_key_, sender_public_key,
      root_address_, code_, {}, {}
    };
    return prepare_wallet_state_init_and_addr(wallet_data).second;
  }
};

DEFINE_JSON_ABI(ITONTokenWallet, DTONTokenWallet, ETONTokenWallet);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(TONTokenWallet, ITONTokenWallet, DTONTokenWallet, TOKEN_WALLET_TIMESTAMP_DELAY)

