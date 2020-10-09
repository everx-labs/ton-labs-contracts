#include "RootTokenContractNF.hpp"
#include "TONTokenWalletNF.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

static constexpr unsigned ROOT_TIMESTAMP_DELAY = 100;

class RootTokenContract final : public smart_interface<IRootTokenContract>, public DRootTokenContract {
public:
  using root_replay_protection_t = replay_attack_protection::timestamp<ROOT_TIMESTAMP_DELAY>;

  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner = 100;
    static constexpr unsigned token_not_minted               = 101;
    static constexpr unsigned wrong_bounced_header           = 102;
    static constexpr unsigned wrong_bounced_args             = 103;
    static constexpr unsigned wrong_mint_token_id            = 104;
  };

  __always_inline
  void constructor(bytes name, bytes symbol, uint8 decimals, uint256 root_public_key, cell wallet_code) {
    name_ = name;
    symbol_ = symbol;
    decimals_ = decimals;
    root_public_key_ = root_public_key;
    wallet_code_ = wallet_code;
    total_supply_ = TokensType(0);
    total_granted_ = TokensType(0);
  }

  __always_inline
  lazy<MsgAddressInt> deployWallet(int8 workchain_id, uint256 pubkey, TokenId tokenId, WalletGramsType grams) {
    require(root_public_key_ == tvm_pubkey(), error_code::message_sender_is_not_my_owner);
    require(!tokenId || tokens_.contains(tokenId), error_code::token_not_minted);

    tvm_accept();

    auto [wallet_init, dest] = calc_wallet_init(workchain_id, pubkey);
    contract_handle<ITONTokenWallet> dest_handle(dest);
    dest_handle.deploy(wallet_init, Grams(grams.get())).
      call<&ITONTokenWallet::accept>(tokenId);

    if (tokenId)
      ++total_granted_;
    return dest;
  }

  __always_inline
  void grant(lazy<MsgAddressInt> dest, TokenId tokenId, WalletGramsType grams) {
    require(root_public_key_ == tvm_pubkey(), error_code::message_sender_is_not_my_owner);
    require(tokens_.contains(tokenId), error_code::token_not_minted);

    tvm_accept();

    contract_handle<ITONTokenWallet> dest_handle(dest);
    dest_handle(Grams(grams.get())).call<&ITONTokenWallet::accept>(tokenId);

    ++total_granted_;
  }

  __always_inline
  TokenId mint(TokenId tokenId) {
    require(root_public_key_ == tvm_pubkey(), error_code::message_sender_is_not_my_owner);
    require(tokenId == total_supply_ + 1, error_code::wrong_mint_token_id);

    tvm_accept();

    tokens_.insert(tokenId);
    ++total_supply_;
    return tokenId;
  }

  // getters
  __always_inline bytes getName() {
    return name_;
  }

  __always_inline bytes getSymbol() {
    return symbol_;
  }

  __always_inline uint8 getDecimals() {
    return decimals_;
  }

  __always_inline uint256 getRootKey() {
    return root_public_key_;
  }

  __always_inline TokensType getTotalSupply() {
    return total_supply_;
  }

  __always_inline TokensType getTotalGranted() {
    return total_granted_;
  }

  __always_inline cell getWalletCode() {
    return wallet_code_;
  }

  __always_inline TokenId getLastMintedToken() {
    return total_supply_;
  }

  __always_inline
  lazy<MsgAddressInt> getWalletAddress(int8 workchain_id, uint256 pubkey) {
    return calc_wallet_init(workchain_id, pubkey).second;
  }

  // received bounced message back
  __always_inline static int _on_bounced(cell msg, slice msg_body) {
    tvm_accept();

    using Args = args_struct_t<&ITONTokenWallet::accept>;
    parser p(msg_body);
    require(p.ldi(32) == -1, error_code::wrong_bounced_header);
    auto [opt_hdr, =p] = parse_continue<abiv1::internal_msg_header>(p);
    require(opt_hdr && opt_hdr->function_id == id_v<&ITONTokenWallet::accept>,
            error_code::wrong_bounced_header);
    auto args = parse<Args>(p, error_code::wrong_bounced_args);
    auto bounced_id = args.tokenId;

    auto [hdr, persist] = load_persistent_data<IRootTokenContract, root_replay_protection_t, DRootTokenContract>();
    require(bounced_id > 0, error_code::wrong_bounced_args);
    require(bounced_id <= persist.total_supply_, error_code::wrong_bounced_args);
    require(persist.total_granted_ > 0, error_code::wrong_bounced_args);
    --persist.total_granted_;
    persist.tokens_.insert(bounced_id);
    save_persistent_data<IRootTokenContract, root_replay_protection_t>(hdr, persist);
    return 0;
  }
  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }

  // =============== Support functions ==================
  DEFAULT_SUPPORT_FUNCTIONS(IRootTokenContract, root_replay_protection_t)
private:
  __always_inline
  std::pair<StateInit, lazy<MsgAddressInt>> calc_wallet_init(int8 workchain_id, uint256 pubkey) {
    DTONTokenWallet wallet_data {
      name_, symbol_, decimals_,
      root_public_key_, pubkey,
      lazy<MsgAddressInt>{tvm_myaddr()}, wallet_code_, {}, {}
    };
    auto [wallet_init, dest_addr] = prepare_wallet_state_init_and_addr(wallet_data);
    lazy<MsgAddressInt> dest{ MsgAddressInt{ addr_std { {}, {}, workchain_id, dest_addr } } };
    return { wallet_init, dest };
  }
};

DEFINE_JSON_ABI(IRootTokenContract, DRootTokenContract, ERootTokenContract);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(RootTokenContract, IRootTokenContract, DRootTokenContract, ROOT_TIMESTAMP_DELAY)

