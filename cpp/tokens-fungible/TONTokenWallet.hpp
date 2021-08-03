#pragma once

#include <tvm/schema/message.hpp>
#include <tvm/sequence.hpp>
#include <tvm/small_dict_map.hpp>

#include <tvm/replay_attack_protection/timestamp.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>

namespace tvm { inline namespace schema {

// #define TIP3_ENABLE_EXTERNAL
// #define TIP3_ENABLE_ALLOWANCE
// #define TIP3_ENABLE_LEND_OWNERSHIP
// #define TIP3_ENABLE_BURN
// #define TIP3_IMPROVED_TRANSFER

#ifdef TIP3_ENABLE_EXTERNAL
#define TIP3_EXTERNAL [[external, dyn_chain_parse]]
#else
#define TIP3_EXTERNAL
#endif

static constexpr unsigned TOKEN_WALLET_TIMESTAMP_DELAY = 1800;
using external_wallet_replay_protection_t = replay_attack_protection::timestamp<TOKEN_WALLET_TIMESTAMP_DELAY>;
#ifdef TIP3_ENABLE_EXTERNAL
using wallet_replay_protection_t = external_wallet_replay_protection_t;
#else
using wallet_replay_protection_t = void;
#endif

struct allowance_info {
  address spender;
  uint128 remainingTokens;
};

struct lend_record {
  uint128 lend_balance;
  uint32 lend_finish_time;
};
using lend_ownership_map = small_dict_map<addr_std_fixed, lend_record>;

struct lend_array_record {
  address lend_addr;
  uint128 lend_balance;
  uint32 lend_finish_time;
};
using lend_ownership_array = dict_array<lend_array_record>;

struct details_info {
  bytes name;
  bytes symbol;
  uint8 decimals;
  uint128 balance;
  uint256 root_public_key;
  uint256 wallet_public_key;
  address root_address;
  address owner_address;
  lend_ownership_array lend_ownership;
  uint128 lend_balance; // sum lend balance to all targets
  cell code;
  allowance_info allowance;
  int8 workchain_id;
};

// =========== TON Token wallet notification callback interface ============ //
__interface ITONTokenWalletNotify {

  [[internal, noaccept, answer_id]]
  bool_t onTip3LendOwnership(
    address answer_addr,
    uint128 balance,
    uint32  lend_finish_time,
    uint256 pubkey,
    address internal_owner,
    cell    payload
  ) = 201;

  [[internal, noaccept, answer_id]]
  bool_t onTip3Transfer(
    address answer_addr,
    uint128 balance,
    uint128 new_tokens,
    uint256 sender_pubkey,
    address sender_owner,
    cell    payload
  ) = 202;
};
using ITONTokenWalletNotifyPtr = handle<ITONTokenWalletNotify>;

// ====================== TON Token wallet interface ======================= //
__interface ITONTokenWallet {

  TIP3_EXTERNAL
  [[internal, noaccept]]
  void transfer(
    address answer_addr,
    address to,
    uint128 tokens,
    uint128 grams,
    bool_t  return_ownership
  );

  // Notify versions have answer_id to provide tail call answer
#ifdef TIP3_IMPROVED_TRANSFER
  TIP3_EXTERNAL
  [[internal, noaccept, answer_id]]
  void transferWithNotify(
    address answer_addr,
    address to,
    uint128 tokens,
    uint128 grams,
    bool_t  return_ownership,
    cell    payload
  );

  TIP3_EXTERNAL
  [[internal, noaccept]]
  void transferToRecipient(
    address answer_addr,
    uint256 recipient_public_key,
    address recipient_internal_owner,
    uint128 tokens,
    uint128 grams,
    bool_t  deploy,
    bool_t  return_ownership
  );

  TIP3_EXTERNAL
  [[internal, noaccept, answer_id]]
  void transferToRecipientWithNotify(
    address answer_addr,
    uint256 recipient_public_key,
    address recipient_internal_owner,
    uint128 tokens,
    uint128 grams,
    bool_t  deploy,
    bool_t  return_ownership,
    cell    payload
  );

  [[internal, noaccept, answer_id]]
  uint128 requestBalance();
#endif // TIP3_IMPROVED_TRANSFER

  // Receive tokens from root
  [[internal, noaccept, answer_id]]
  bool_t accept(uint128 tokens, address answer_addr, uint128 keep_grams);

  // Receive tokens from other wallet
  [[internal, noaccept, answer_id]]
  void internalTransfer(
    uint128 tokens,
    address answer_addr,
    uint256 sender_pubkey,
    address sender_owner,
    bool_t  notify_receiver,
    cell    payload
  );

#ifdef TIP3_IMPROVED_TRANSFER
  // Send rest !native! funds to `dest` and destroy the wallet.
  // balance must be zero. Not allowed for lend ownership.
  TIP3_EXTERNAL
  [[internal, noaccept]]
  void destroy(address dest);
#endif // TIP3_IMPROVED_TRANSFER

#ifdef TIP3_ENABLE_BURN
  [[internal, noaccept, answer_id]]
  void burn(uint256 out_pubkey, address out_internal_owner);
#endif

#ifdef TIP3_ENABLE_LEND_OWNERSHIP
  // lend ownership to some contract until 'lend_finish_time'
  // allowance is cleared and is not permited to set up by temporary owner.
  TIP3_EXTERNAL
  [[internal, noaccept, answer_id]]
  void lendOwnership(
    address answer_addr,
    uint128 grams,
    uint256 std_dest,
    uint128 lend_balance,
    uint32  lend_finish_time,
    cell    deploy_init_cl,
    cell    payload
  );

  // return ownership back to the original owner
  [[internal, noaccept]]
  void returnOwnership();
#endif // TIP3_ENABLE_LEND_OWNERSHIP

  // =============================== getters =============================== //
  [[getter]]
  details_info getDetails();

#ifdef TIP3_ENABLE_ALLOWANCE
  // ========================= allowance interface ========================= //
  TIP3_EXTERNAL
  [[internal, noaccept]]
  void approve(
    address spender,
    uint128 remainingTokens,
    uint128 tokens
  );

  TIP3_EXTERNAL
  [[internal, noaccept]]
  void transferFrom(
    address answer_addr,
    address from,
    address to,
    uint128 tokens,
    uint128 grams
  );

  TIP3_EXTERNAL
  [[internal, noaccept]]
  void transferFromWithNotify(
    address answer_addr,
    address from,
    address to,
    uint128 tokens,
    uint128 grams,
    cell    payload
  );

  TIP3_EXTERNAL
  [[internal]]
  void internalTransferFrom(
    address answer_addr,
    address to,
    uint128 tokens,
    bool_t  notify_receiver,
    cell    payload
  );

  TIP3_EXTERNAL
  [[internal, noaccept]]
  void disapprove();
#endif // TIP3_ENABLE_ALLOWANCE
};
using ITONTokenWalletPtr = handle<ITONTokenWallet>;

struct DTONTokenWallet {
  bytes name_;
  bytes symbol_;
  uint8 decimals_;
  uint128 balance_;
  uint256 root_public_key_;
  uint256 wallet_public_key_;
  address root_address_;
  std::optional<address> owner_address_;
#ifdef TIP3_ENABLE_LEND_OWNERSHIP
  lend_ownership_map lend_ownership_;
#endif
  cell code_;
#ifdef TIP3_ENABLE_ALLOWANCE
  std::optional<allowance_info> allowance_;
#endif
  int8 workchain_id_;
};

// TODO: implement filter reflection instead of code duplication
// struct [[disable("lend_ownership"), enable("allowance")]] ExternalCfg {};
// struct [[enable("lend_ownership"), disable("allowance")]] InternalCfg {};
// using DTONTokenWalletExternal = __reflect_filter<DTONTokenWallet, ExternalCfg>;
// using DTONTokenWalletInternal = __reflect_filter<DTONTokenWallet, InternalCfg>;
// using DTONTokenWalletExternal = __reflect_filter<DTONTokenWallet, [[disable("lend_ownership"), enable("allowance")]]>;

struct DTONTokenWalletExternal {
  bytes name_;
  bytes symbol_;
  uint8 decimals_;
  uint128 balance_;
  uint256 root_public_key_;
  uint256 wallet_public_key_;
  address root_address_;
  std::optional<address> owner_address_;
  cell code_;
  std::optional<allowance_info> allowance_;
  int8 workchain_id_;
};

struct DTONTokenWalletInternal {
  bytes name_;
  bytes symbol_;
  uint8 decimals_;
  uint128 balance_;
  uint256 root_public_key_;
  uint256 wallet_public_key_;
  address root_address_;
  std::optional<address> owner_address_;
  lend_ownership_map lend_ownership_;
  cell code_;
  int8 workchain_id_;
};

struct ETONTokenWallet {
};

inline
DTONTokenWallet prepare_wallet_data(
  bytes name, bytes symbol, uint8 decimals, uint256 root_public_key,
  uint256 wallet_public_key, address root_address, std::optional<address> owner_address,
  cell code, int8 workchain_id
) {
  return {
    name, symbol, decimals,
    uint128(0), root_public_key, wallet_public_key,
    root_address, owner_address,
#ifdef TIP3_ENABLE_LEND_OWNERSHIP
    {},
#endif
    code,
#ifdef TIP3_ENABLE_ALLOWANCE
    {},
#endif
    workchain_id
  };
}

// Prepare Token Wallet StateInit structure and expected contract address (hash from StateInit)
inline
std::pair<StateInit, uint256> prepare_wallet_state_init_and_addr(DTONTokenWallet wallet_data) {
  cell wallet_data_cl =
    prepare_persistent_data<ITONTokenWallet, wallet_replay_protection_t, DTONTokenWallet>(
#ifdef TIP3_ENABLE_EXTERNAL
      wallet_replay_protection_t::init(),
#else
      {},
#endif
      wallet_data);
  StateInit wallet_init {
    /*split_depth*/{}, /*special*/{},
    wallet_data.code_, wallet_data_cl, /*library*/{}
  };
  cell wallet_init_cl = build(wallet_init).make_cell();
  return { wallet_init, uint256(tvm_hash(wallet_init_cl)) };
}

inline
std::pair<StateInit, uint256> prepare_external_wallet_state_init_and_addr(
  bytes name, bytes symbol, uint8 decimals, uint256 root_public_key,
  uint256 wallet_public_key, address root_address, std::optional<address> owner_address,
  cell code, int8 workchain_id
) {
  DTONTokenWalletExternal wallet_data {
    name, symbol, decimals,
    uint128(0), root_public_key, wallet_public_key,
    root_address, owner_address,
    code, {}, workchain_id
  };
  cell wallet_data_cl =
    prepare_persistent_data<ITONTokenWallet, external_wallet_replay_protection_t, DTONTokenWalletExternal>(
      external_wallet_replay_protection_t::init(), wallet_data);
  StateInit wallet_init {
    /*split_depth*/{}, /*special*/{},
    code, wallet_data_cl, /*library*/{}
  };
  cell wallet_init_cl = build(wallet_init).make_cell();
  return { wallet_init, uint256(tvm_hash(wallet_init_cl)) };
}

inline
std::pair<StateInit, uint256> prepare_internal_wallet_state_init_and_addr(
  bytes name, bytes symbol, uint8 decimals, uint256 root_public_key,
  uint256 wallet_public_key, address root_address, std::optional<address> owner_address,
  cell code, int8 workchain_id
) {
  DTONTokenWalletInternal wallet_data {
    name, symbol, decimals,
    uint128(0), root_public_key, wallet_public_key,
    root_address, owner_address,
    {}, code, workchain_id
  };
  cell wallet_data_cl =
    prepare_persistent_data<ITONTokenWallet, void, DTONTokenWalletInternal>({}, wallet_data);
  StateInit wallet_init {
    /*split_depth*/{}, /*special*/{},
    code, wallet_data_cl, /*library*/{}
  };
  cell wallet_init_cl = build(wallet_init).make_cell();
  return { wallet_init, uint256(tvm_hash(wallet_init_cl)) };
}

}} // namespace tvm::schema

