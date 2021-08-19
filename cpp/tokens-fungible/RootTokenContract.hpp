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
    bytes name,
    bytes symbol,
    uint8 decimals,
    uint256 root_public_key,
    address root_owner,
    uint128 total_supply
  );

  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  bool_t setWalletCode(cell wallet_code);

  // Should be provided pubkey (for external owned wallet) or std addr (for internal owned wallet).
  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  address deployWallet(
    uint256 pubkey,
    address internal_owner,
    uint128 tokens,
    uint128 grams
  );

  // Anyone may request to deploy an empty wallet
  [[internal, noaccept, dyn_chain_parse, answer_id]]
  address deployEmptyWallet(
    uint256 pubkey,
    address internal_owner,
    uint128 grams
  );

  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  void grant(
    address dest,
    uint128 tokens,
    uint128 grams
  );

  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  bool_t mint(uint128 tokens);

  [[internal, noaccept, answer_id]]
  uint128 requestTotalGranted();

  [[getter]]
  bytes getName();

  [[getter]]
  bytes getSymbol();

  [[getter]]
  uint8 getDecimals();

  [[getter]]
  uint256 getRootKey();

  [[getter]]
  uint128 getTotalSupply();

  [[getter]]
  uint128 getTotalGranted();

  [[getter]]
  bool_t hasWalletCode();

  [[getter]]
  cell getWalletCode();

  [[getter, dyn_chain_parse]]
  address getWalletAddress(uint256 pubkey, address owner);

  [[getter]]
  uint256 getWalletCodeHash();
};
using IRootTokenContractPtr = handle<IRootTokenContract>;

struct DRootTokenContract {
  bytes   name_;
  bytes   symbol_;
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

