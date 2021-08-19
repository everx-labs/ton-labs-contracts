#pragma once

#include "TONTokenWallet.hpp"

namespace tvm { inline namespace schema {

static constexpr unsigned WRAPPER_TIMESTAMP_DELAY = 1800;
using wrapper_replay_protection_t = replay_attack_protection::timestamp<WRAPPER_TIMESTAMP_DELAY>;

struct WrapperRet {
  uint32 err_code;
  address flex_wallet;
};

struct FLeXDeployWalletArgs {
  uint256 pubkey;
  address internal_owner;
  uint128 grams;
};

struct wrapper_details_info {
  string   name;
  string   symbol;
  uint8   decimals;
  uint256 root_public_key;
  uint128 total_granted;
  cell    wallet_code;
  address owner_address;
  address external_wallet;
};

// ===== FLeX Wrapper Contract ===== //
__interface IWrapper {

  [[internal, external, dyn_chain_parse, answer_id]]
  bool_t init(address external_wallet);

  [[internal, external, noaccept, answer_id]]
  bool_t setInternalWalletCode(cell wallet_code);

  [[internal, noaccept, dyn_chain_parse, answer_id]]
  address deployEmptyWallet(
    uint256 pubkey,
    address internal_owner,
    uint128 grams
  );

  // Notification about incoming tokens from Wrapper owned external wallet
  [[internal, noaccept, answer_id]]
  WrapperRet onTip3Transfer(
    address answer_addr,
    uint128 balance,
    uint128 new_tokens,
    uint256 pubkey,
    address internal_owner,
    cell    payload
  ) = 202;

  [[internal, noaccept]]
  void burn(
    address answer_addr,
    uint256 sender_pubkey,
    address sender_owner,
    uint256 out_pubkey,
    address out_internal_owner,
    uint128 tokens
  );

  [[internal, noaccept, answer_id]]
  uint128 requestTotalGranted();

  [[getter]]
  wrapper_details_info getDetails();

  [[getter]]
  bool_t hasInternalWalletCode();

  [[getter, dyn_chain_parse]]
  address getWalletAddress(uint256 pubkey, address owner);
};
using IWrapperPtr = handle<IWrapper>;

struct DWrapper {
  string   name_;
  string   symbol_;
  uint8   decimals_;
  int8    workchain_id_;
  uint256 root_public_key_;
  uint128 total_granted_;
  optcell internal_wallet_code_;
  std::optional<address> owner_address_;
  Grams start_balance_;
  std::optional<ITONTokenWalletPtr> external_wallet_;
};

struct EWrapper {
};

// Prepare Wrapper StateInit structure and expected contract address (hash from StateInit)
inline
std::pair<StateInit, uint256> prepare_wrapper_state_init_and_addr(cell wrapper_code, DWrapper wrapper_data) {
  cell wrapper_data_cl =
    prepare_persistent_data<IWrapper, wrapper_replay_protection_t, DWrapper>(
      wrapper_replay_protection_t::init(), wrapper_data);
  StateInit wrapper_init {
    /*split_depth*/{}, /*special*/{},
    wrapper_code, wrapper_data_cl, /*library*/{}
  };
  cell wrapper_init_cl = build(wrapper_init).make_cell();
  return { wrapper_init, uint256(tvm_hash(wrapper_init_cl)) };
}

}} // namespace tvm::schema

