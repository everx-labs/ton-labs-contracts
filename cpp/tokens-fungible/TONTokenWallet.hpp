#pragma once

#include <tvm/schema/message.hpp>
#include <tvm/sequence.hpp>

#include <tvm/replay_attack_protection/timestamp.hpp>
#include <tvm/smart_switcher.hpp>

namespace tvm { namespace schema {

using WalletTONSType = uint128;
using TokensType = uint128;

static constexpr unsigned TOKEN_WALLET_TIMESTAMP_DELAY = 100;
using wallet_replay_protection_t = replay_attack_protection::timestamp<TOKEN_WALLET_TIMESTAMP_DELAY>;

struct allowance_info {
  lazy<MsgAddressInt> spender;
  TokensType remainingTokens;
};

// ===== TON Token wallet ===== //
__interface ITONTokenWallet {

  // expected offchain constructor execution
  __attribute__((internal, external, dyn_chain_parse))
  void constructor(bytes name, bytes symbol, uint8 decimals,
                   uint256 root_public_key, uint256 wallet_public_key,
                   lazy<MsgAddressInt> root_address, cell code) = 1;

  __attribute__((external, noaccept, dyn_chain_parse))
  void transfer(lazy<MsgAddressInt> dest, TokensType tokens, WalletTONSType tons) = 2;

  // Receive tokens from root
  __attribute__((internal, noaccept))
  void accept(TokensType tokens) = 3;

  // Receive tokens from other wallet
  __attribute__((internal, noaccept))
  void internalTransfer(TokensType tokens, uint256 pubkey) = 4;

  // getters
  __attribute__((getter))
  bytes getName() = 5;

  __attribute__((getter))
  bytes getSymbol() = 6;

  __attribute__((getter))
  uint8 getDecimals() = 7;

  __attribute__((getter))
  TokensType getBalance() = 8;

  __attribute__((getter))
  uint256 getWalletKey() = 9;

  __attribute__((getter))
  lazy<MsgAddressInt> getRootAddress() = 10;

  __attribute__((getter))
  allowance_info allowance() = 11;

  // allowance interface
  __attribute__((external, noaccept, dyn_chain_parse))
  void approve(lazy<MsgAddressInt> spender, TokensType remainingTokens, TokensType tokens) = 12;

  __attribute__((external, noaccept, dyn_chain_parse))
  void transferFrom(lazy<MsgAddressInt> dest, lazy<MsgAddressInt> to, TokensType tokens,
                    WalletTONSType tons) = 13;

  __attribute__((internal))
  void internalTransferFrom(lazy<MsgAddressInt> to, TokensType tokens) = 14;

  __attribute__((external, noaccept))
  void disapprove() = 15;
};

struct DTONTokenWallet {
  bytes name_;
  bytes symbol_;
  uint8 decimals_;
  TokensType balance_;
  uint256 root_public_key_;
  uint256 wallet_public_key_;
  lazy<MsgAddressInt> root_address_;
  cell code_;
  std::optional<allowance_info> allowance_;
};

struct ETONTokenWallet {
};

// Prepare Token Wallet StateInit structure and expected contract address (hash from StateInit)
inline
std::pair<StateInit, uint256> prepare_wallet_state_init_and_addr(DTONTokenWallet wallet_data) {
  cell wallet_data_cl =
    prepare_persistent_data<wallet_replay_protection_t, DTONTokenWallet>(
      wallet_replay_protection_t::init(), wallet_data);
  StateInit wallet_init {
    /*split_depth*/{}, /*special*/{},
    wallet_data.code_, wallet_data_cl, /*library*/{}
  };
  cell wallet_init_cl = build(wallet_init).make_cell();
  return { wallet_init, uint256(tvm_hash(wallet_init_cl)) };
}

}} // namespace tvm::schema

