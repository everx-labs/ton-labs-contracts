#pragma once

#include "TONTokenWalletUTXO.hpp"

namespace tvm { namespace schema {

// ===== Root Token Contract ===== //
__interface IRootTokenContract {

  // expected offchain constructor execution
  __attribute__((internal, external, dyn_chain_parse))
  void constructor(bytes name, bytes symbol, uint8 decimals,
    uint256 root_public_key, cell wallet_code, TokensType total_supply) = 11;

  __attribute__((external, noaccept, dyn_chain_parse))
  lazy<MsgAddressInt> deployWallet(int8 workchain_id, uint256 pubkey, TokensType tokens, WalletGramsType grams) = 12;

  __attribute__((external, noaccept, dyn_chain_parse))
  void mint(TokensType tokens) = 13;

  __attribute__((getter))
  bytes getName() = 14;

  __attribute__((getter))
  bytes getSymbol() = 15;

  __attribute__((getter))
  uint8 getDecimals() = 16;

  __attribute__((getter))
  uint256 getRootKey() = 17;

  __attribute__((getter))
  TokensType getTotalSupply() = 18;

  __attribute__((getter))
  TokensType getTotalGranted() = 19;

  __attribute__((getter))
  cell getWalletCode() = 20;

  __attribute__((getter))
  lazy<MsgAddressInt> getWalletAddress(int8 workchain_id, uint256 pubkey) = 21;
};

struct DRootTokenContract {
  bytes name_;
  bytes symbol_;
  uint8 decimals_;
  uint256 root_public_key_;
  TokensType total_supply_;
  TokensType total_granted_;
  cell wallet_code_;
};

struct ERootTokenContract {
};

}} // namespace tvm::schema

