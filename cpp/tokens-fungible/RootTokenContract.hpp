#pragma once

#include "TONTokenWallet.hpp"

namespace tvm { namespace schema {

// ===== Root Token Contract ===== //
__interface IRootTokenContract {

  // expected offchain constructor execution
  __attribute__((internal, external, dyn_chain_parse))
  void constructor(bytes name, bytes symbol, uint8 decimals,
    uint256 root_public_key, cell wallet_code, TokensType total_supply) = 1;

  __attribute__((external, noaccept, dyn_chain_parse))
  lazy<MsgAddressInt> deployWallet(int8 workchain_id, uint256 pubkey, TokensType tokens, WalletTONSType tons) = 2;

  __attribute__((external, noaccept, dyn_chain_parse))
  void grant(lazy<MsgAddressInt> dest, TokensType tokens, WalletTONSType tons) = 3;

  __attribute__((external, noaccept))
  void mint(TokensType tokens) = 4;

  __attribute__((getter))
  bytes getName() = 5;

  __attribute__((getter))
  bytes getSymbol() = 6;

  __attribute__((getter))
  uint8 getDecimals() = 7;

  __attribute__((getter))
  uint256 getRootKey() = 8;

  __attribute__((getter))
  TokensType getTotalSupply() = 9;

  __attribute__((getter))
  TokensType getTotalGranted() = 10;

  __attribute__((getter))
  cell getWalletCode() = 11;

  __attribute__((getter))
  lazy<MsgAddressInt> getWalletAddress(int8 workchain_id, uint256 pubkey) = 12;
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

