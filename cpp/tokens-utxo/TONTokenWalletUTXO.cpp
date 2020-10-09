#include "TONTokenWalletUTXO.hpp"

#include <tvm/contract.hpp>
#include <tvm/contract_handle.hpp>
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
    static constexpr unsigned non_zero_remaining                = 106;
    static constexpr unsigned no_allowance_set                  = 107;
    static constexpr unsigned wrong_spender                     = 108;
    static constexpr unsigned not_enough_allowance              = 109;
    static constexpr unsigned utxo_already_received             = 110;
    static constexpr unsigned unexpected_bounced_msg            = 111;
  };

  __always_inline
  void constructor(bytes name, bytes symbol, uint8 decimals,
                   uint256 root_public_key, uint256 wallet_public_key,
                   lazy<MsgAddressInt> root_address, cell code) {
    utxo_received_ = false;
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
  void transferUTXO(int8 workchain_dest, uint256 pubkey_dest, int8 workchain_rest, uint256 pubkey_rest,
                    TokensType tokens, WalletGramsType grams_dest) {
    require(tvm_pubkey() == wallet_public_key_, error_code::message_sender_is_not_my_owner);

    // the function must complete successfully if token balance is less that transfer value.
    if (balance_ < tokens)
      return;

    tvm_accept();

    TokensType tokens_rest = balance_ - tokens;
    if (!tokens_rest || !tokens) { // all tokens to single destination
      int8 workchain = tokens ? workchain_dest : workchain_rest;
      uint256 pubkey = tokens ? pubkey_dest : pubkey_rest;
      TokensType cur_tokens = tokens ? tokens : tokens_rest;

      auto [init, addr] = calc_wallet_init(workchain, pubkey);
      contract_handle<ITONTokenWallet> handle(addr);
      handle.deploy(init, 0, SEND_ALL_GAS).
        call<&ITONTokenWallet::internalTransfer>(cur_tokens, pubkey);
    } else {
      // Deploy first wallet with
      auto [wallet_init_dest, dest] = calc_wallet_init(workchain_dest, pubkey_dest);
      contract_handle<ITONTokenWallet> dest_handle(dest);
      dest_handle.deploy(wallet_init_dest, Grams(grams_dest.get())).
        call<&ITONTokenWallet::internalTransfer>(tokens, wallet_public_key_);

      // Deploy second wallet with the rest of tokens and the rest of gas
      auto [wallet_init_rest, rest] = calc_wallet_init(workchain_rest, pubkey_rest);
      contract_handle<ITONTokenWallet> rest_handle(rest);
      rest_handle.deploy(wallet_init_rest, 0, SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY).
        call<&ITONTokenWallet::internalTransfer>(tokens_rest, wallet_public_key_);
    }
    balance_ = 0;
  }

  __always_inline
  void accept(TokensType tokens) {
    require(!utxo_received_, error_code::utxo_already_received);
    // the function must check that message sender is the RTW.
    require(root_address_.sl() == int_sender().sl(),
            error_code::message_sender_is_not_my_root);

    tvm_accept();

    utxo_received_ = true;
    balance_ += tokens;
  }

  __always_inline
  void internalTransfer(TokensType tokens, uint256 pubkey) {
    require(!utxo_received_, error_code::utxo_already_received);

    uint256 expected_address = expected_sender_address(pubkey);
    auto sender = int_sender();

    require(std::get<addr_std>(sender()).address == expected_address,
            error_code::message_sender_is_not_good_wallet);

    tvm_accept();

    utxo_received_ = true;
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

  // UTXO wallet sends only deploy-messages, so bounced messages not expected
  __always_inline static int _on_bounced(cell msg, slice msg_body) {
    tvm_throw(error_code::unexpected_bounced_msg);
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
      bool_t(false),
      name_, symbol_, decimals_,
      TokensType(0), root_public_key_, sender_public_key,
      root_address_, code_
    };
    return prepare_wallet_state_init_and_addr(wallet_data).second;
  }
  __always_inline
  std::pair<StateInit, lazy<MsgAddressInt>> calc_wallet_init(int8 workchain_id, uint256 pubkey) {
    DTONTokenWallet wallet_data {
      bool_t(false),
      name_, symbol_, decimals_,
      TokensType(0), root_public_key_, pubkey,
      root_address_, code_
    };
    auto [wallet_init, dest_addr] = prepare_wallet_state_init_and_addr(wallet_data);
    lazy<MsgAddressInt> dest{ MsgAddressInt{ addr_std { {}, {}, workchain_id, dest_addr } } };
    return { wallet_init, dest };
  }
};

DEFINE_JSON_ABI(ITONTokenWallet, DTONTokenWallet, ETONTokenWallet);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(TONTokenWallet, ITONTokenWallet, DTONTokenWallet, TOKEN_WALLET_TIMESTAMP_DELAY)

