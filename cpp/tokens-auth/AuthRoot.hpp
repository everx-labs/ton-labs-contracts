#pragma once

#include "AuthWallet.hpp"

namespace tvm { namespace schema {

// ===== Auth Root Contract ===== //
__interface IAuthRoot {

  // expected offchain constructor execution
  [[external, dyn_chain_parse]]
  void constructor(bytes name, bytes symbol,
    uint256 root_public_key, uint256 root_owner, cell wallet_code) = 10;

  [[internal, external, noaccept, dyn_chain_parse, answer_id]]
  address deployWallet(int8 workchain_id, uint256 pubkey,
                       RightId rightId, WalletGramsType grams) = 11;

  [[internal, noaccept, dyn_chain_parse, answer_id]]
  address deployEmptyWallet(int8 workchain_id, uint256 pubkey,
                            WalletGramsType grams) = 12;

  [[internal, external, noaccept, dyn_chain_parse]]
  void grant(address dest, RightId rightId, WalletGramsType grams) = 13;

  [[internal, external, noaccept, dyn_chain_parse]]
  void deny(address dest, RightId rightId, WalletGramsType grams) = 14;

  [[internal, external, noaccept, dyn_chain_parse]]
  void destroyWallet(address dest, WalletGramsType grams) = 15;

  // Destroy root and return all rest funds to dest
  [[internal, external, noaccept, dyn_chain_parse]]
  void destroyRoot(address dest) = 16;

  [[getter]]
  bytes getName() = 17;

  [[getter]]
  bytes getSymbol() = 18;

  [[getter]]
  uint256 getRootKey() = 19;

  [[getter]]
  cell getWalletCode() = 20;

  [[getter]]
  address getWalletAddress(int8 workchain_id, uint256 pubkey) = 21;
};

struct DAuthRoot {
  bytes name_;
  bytes symbol_;
  uint256 root_public_key_;
  std::optional<address> owner_address_;
  cell wallet_code_;
  Grams start_balance_;
};

struct EAuthRoot {
};

}} // namespace tvm::schema

