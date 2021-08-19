#pragma once

#include "TONTokenWallet.hpp"

namespace tvm { inline namespace schema {

static constexpr unsigned ROOT_TIMESTAMP_DELAY = 1800;
using root_replay_protection_t = replay_attack_protection::timestamp<ROOT_TIMESTAMP_DELAY>;

// ===== Root Token Contract ===== //
__interface IRootTokenContract {

  // expected offchain constructor execution
  [[internal, external, dyn_chain_parse]]
  void constructor(
    string name,
    string symbol,
    uint8 decimals,
    uint256 root_public_key,
    address root_owner,
    uint128 total_supply
  ) = 10;

  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  bool_t setWalletCode(cell wallet_code) = 11;

  // Should be provided pubkey (for external owned wallet) or std addr (for internal owned wallet).
  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  address deployWallet(
    uint256 pubkey,
    address internal_owner,
    uint128 tokens,
    uint128 grams
  ) = 12;

  // Anyone may request to deploy an empty wallet
  [[internal, noaccept, dyn_chain_parse, answer_id]]
  address deployEmptyWallet(
    uint256 pubkey,
    address internal_owner,
    uint128 grams
  ) = 13;

  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  void grant(
    address dest,
    uint128 tokens,
    uint128 grams
  ) = 14;

  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  bool_t mint(uint128 tokens) = 15;

  [[internal, noaccept, answer_id]]
  uint128 requestTotalGranted() = 16;

  [[getter]]
  string getName() = 17;

  [[getter]]
  string getSymbol() = 18;

  [[getter]]
  uint8 getDecimals() = 19;

  [[getter]]
  uint256 getRootKey() = 20;

  [[getter]]
  uint128 getTotalSupply() = 21;

  [[getter]]
  uint128 getTotalGranted() = 22;

  [[getter]]
  bool_t hasWalletCode() = 23;

  [[getter]]
  cell getWalletCode() = 24;

  [[getter, dyn_chain_parse]]
  address getWalletAddress(uint256 pubkey, address owner) = 25;

  [[getter]]
  uint256 getWalletCodeHash() = 26;
};
using IRootTokenContractPtr = handle<IRootTokenContract>;

struct DRootTokenContract {
  string   name_;
  string   symbol_;
  uint8   decimals_;
  uint256 root_public_key_;
  uint128 total_supply_;
  uint128 total_granted_;
  optcell wallet_code_;
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

