#pragma once

#include "TONTokenWallet.hpp"

namespace tvm { namespace schema {

static constexpr unsigned ROOT_TIMESTAMP_DELAY = 1800;
using root_replay_protection_t = replay_attack_protection::timestamp<ROOT_TIMESTAMP_DELAY>;

// ===== Root Token Contract ===== //
__interface IRootTokenContract {

  // expected offchain constructor execution
  [[internal, external, dyn_chain_parse]]
  void constructor(bytes name, bytes symbol, uint8 decimals,
    uint256 root_public_key, uint256 root_owner, cell wallet_code, TokensType total_supply) = 11;

  // Should be provided pubkey (for external owned wallet) or std addr (for internal owned wallet).
  // The other value must be zero.
  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  address deployWallet(int8 workchain_id, uint256 pubkey, uint256 internal_owner,
                       TokensType tokens, WalletGramsType grams) = 12;

  // Anyone may request to deploy an empty wallet
  [[internal, noaccept, dyn_chain_parse, answer_id]]
  address deployEmptyWallet(int8 workchain_id, uint256 pubkey, uint256 internal_owner,
                            WalletGramsType grams) = 13;

  [[internal, external, noaccept, dyn_chain_parse]]
  void grant(address dest, TokensType tokens, WalletGramsType grams) = 14;

  [[internal, external, noaccept, dyn_chain_parse]]
  void mint(TokensType tokens) = 15;

  [[getter]]
  bytes getName() = 16;

  [[getter]]
  bytes getSymbol() = 17;

  [[getter]]
  uint8 getDecimals() = 18;

  [[getter]]
  uint256 getRootKey() = 19;

  [[getter]]
  TokensType getTotalSupply() = 20;

  [[getter]]
  TokensType getTotalGranted() = 21;

  [[getter]]
  cell getWalletCode() = 22;

  [[getter]]
  address getWalletAddress(int8 workchain_id, uint256 pubkey, uint256 owner_std_addr) = 23;

  [[getter]]
  uint256 getWalletCodeHash() = 24;
};

struct DRootTokenContract {
  bytes name_;
  bytes symbol_;
  uint8 decimals_;
  uint256 root_public_key_;
  TokensType total_supply_;
  TokensType total_granted_;
  cell wallet_code_;
  std::optional<address> owner_address_;
  Grams start_balance_;
};

struct ERootTokenContract {
};

// Prepare Root StateInit structure and expected contract address (hash from StateInit)
inline
std::pair<StateInit, uint256> prepare_root_state_init_and_addr(cell root_code, DRootTokenContract root_data) {
  cell root_data_cl =
    prepare_persistent_data<IRootTokenContract, root_replay_protection_t, DRootTokenContract>(
      root_replay_protection_t::init(), root_data);
  StateInit root_init {
    /*split_depth*/{}, /*special*/{},
    root_code, root_data_cl, /*library*/{}
  };
  cell root_init_cl = build(root_init).make_cell();
  return { root_init, uint256(tvm_hash(root_init_cl)) };
}

}} // namespace tvm::schema

