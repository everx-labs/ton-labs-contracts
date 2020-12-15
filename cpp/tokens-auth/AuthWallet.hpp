#pragma once

#include <tvm/schema/message.hpp>
#include <tvm/sequence.hpp>

#include <tvm/replay_attack_protection/timestamp.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/dict_set.hpp>

namespace tvm { namespace schema {

using WalletGramsType = uint256;
using RightsType = uint256;
using RightId = uint256;

static constexpr unsigned WALLET_TIMESTAMP_DELAY = 1800;
using wallet_replay_protection_t = replay_attack_protection::timestamp<WALLET_TIMESTAMP_DELAY>;

// ===== Auth wallet ===== //
__interface IAuthWallet {

  // expected offchain constructor execution
  [[internal, external, dyn_chain_parse]]
  void constructor(bytes name, bytes symbol,
                   uint256 root_public_key, uint256 wallet_public_key,
                   address root_address, cell code) = 10;

  // Receive right id from root
  [[internal, noaccept]]
  void accept(RightId rightId) = 11;

  // Remove right id command from root
  [[internal, noaccept]]
  void deny(RightId rightId) = 12;

  // Destroy wallet and return all rest funds back to root
  [[internal, noaccept]]
  void destroy() = 13;

  // ===== getters ===== //
  [[getter]]
  bytes getName() = 14;

  [[getter]]
  bytes getSymbol() = 15;

  [[getter]]
  uint256 getWalletKey() = 16;

  [[getter]]
  address getRootAddress() = 17;

  [[getter]]
  RightsType getRightsCount() = 18;

  [[getter]]
  RightId getRightByIndex(RightsType index) = 19;

  [[getter]]
  dict_array<RightId> getRights() = 20;
};

struct DAuthWallet {
  bytes name_;
  bytes symbol_;
  uint256 root_public_key_;
  uint256 wallet_public_key_;
  address root_address_;
  dict_set<RightId> rights_;
};

struct EAuthWallet {
};

// Prepare Auth Wallet StateInit structure and expected contract address (hash from StateInit)
inline
std::pair<StateInit, uint256> prepare_wallet_state_init_and_addr(DAuthWallet wallet_data, cell wallet_code) {
  cell wallet_data_cl =
    prepare_persistent_data<IAuthWallet, wallet_replay_protection_t, DAuthWallet>(
      wallet_replay_protection_t::init(), wallet_data);
  StateInit wallet_init {
    /*split_depth*/{}, /*special*/{},
    wallet_code, wallet_data_cl, /*library*/{}
  };
  cell wallet_init_cl = build(wallet_init).make_cell();
  return { wallet_init, uint256(tvm_hash(wallet_init_cl)) };
}

}} // namespace tvm::schema

