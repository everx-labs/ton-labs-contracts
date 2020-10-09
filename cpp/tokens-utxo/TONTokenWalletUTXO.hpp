#pragma once

#include <tvm/schema/message.hpp>
#include <tvm/sequence.hpp>

#include <tvm/replay_attack_protection/timestamp.hpp>
#include <tvm/smart_switcher.hpp>

namespace tvm { namespace schema {

using WalletGramsType = uint128;
using TokensType = uint128;

static constexpr unsigned TOKEN_WALLET_TIMESTAMP_DELAY = 100;
using wallet_replay_protection_t = replay_attack_protection::timestamp<TOKEN_WALLET_TIMESTAMP_DELAY>;

// ===== TON Token wallet ===== //
__interface ITONTokenWallet {

  // expected offchain constructor execution
  __attribute__((internal, external, dyn_chain_parse))
  void constructor(bytes name, bytes symbol, uint8 decimals,
                   uint256 root_public_key, uint256 wallet_public_key,
                   lazy<MsgAddressInt> root_address, cell code) = 11;

  // tokens and grams_dest will be sent to a new deployed {workchain_dest, pubkey_dest} wallet
  //   and the rest of tokens and the rest of gas will be sent to new {workchain_rest, pubkey_rest} wallet
  __attribute__((external, noaccept, dyn_chain_parse))
  void transferUTXO(int8 workchain_dest, uint256 pubkey_dest, int8 workchain_rest, uint256 pubkey_rest,
                    TokensType tokens, WalletGramsType grams_dest) = 12;

  // TODO: eliminate workaround when bounced message problem will be solved
  // https://www.notion.so/tonlabs/Bounced-message-problem-333cf800e789421d87acd9cb401dca4f

  // Receive tokens from root
  __attribute__((internal, noaccept))
  void accept(TokensType tokens) = 13;

  // Receive tokens from other wallet
  __attribute__((internal, noaccept))
  void internalTransfer(TokensType tokens, uint256 pubkey) = 14;

  // getters
  __attribute__((getter))
  bytes getName() = 15;

  __attribute__((getter))
  bytes getSymbol() = 16;

  __attribute__((getter))
  uint8 getDecimals() = 17;

  __attribute__((getter))
  TokensType getBalance() = 18;

  __attribute__((getter))
  uint256 getWalletKey() = 19;

  __attribute__((getter))
  lazy<MsgAddressInt> getRootAddress() = 20;
};

struct DTONTokenWallet {
  bool_t utxo_received_;
  bytes name_;
  bytes symbol_;
  uint8 decimals_;
  TokensType balance_;
  uint256 root_public_key_;
  uint256 wallet_public_key_;
  lazy<MsgAddressInt> root_address_;
  cell code_;
};

struct ETONTokenWallet {
};

// Prepare Token Wallet StateInit structure and expected contract address (hash from StateInit)
inline
std::pair<StateInit, uint256> prepare_wallet_state_init_and_addr(DTONTokenWallet wallet_data) {
  cell wallet_data_cl =
    prepare_persistent_data<ITONTokenWallet, wallet_replay_protection_t, DTONTokenWallet>(
      wallet_replay_protection_t::init(), wallet_data);
  StateInit wallet_init {
    /*split_depth*/{}, /*special*/{},
    wallet_data.code_, wallet_data_cl, /*library*/{}
  };
  cell wallet_init_cl = build(wallet_init).make_cell();
  return { wallet_init, uint256(tvm_hash(wallet_init_cl)) };
}

}} // namespace tvm::schema

