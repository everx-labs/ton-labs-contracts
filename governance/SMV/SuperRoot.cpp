#include "config.hpp"
#include "SuperRoot.hpp"
#include "ProposalRoot.hpp"
#include "MultiBallot.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

static constexpr unsigned SUPER_ROOT_TIMESTAMP_DELAY = 1800;

class SuperRoot final : public smart_interface<ISuperRoot>, public DSuperRoot {
public:
  using super_root_replay_protection_t = replay_attack_protection::timestamp<SUPER_ROOT_TIMESTAMP_DELAY>;

  static constexpr unsigned minimal_voting_time = 60;

  struct error_code : tvm::error_code {
    static constexpr unsigned duplicated_id           = 100;
    static constexpr unsigned zero_votes              = 101;
    static constexpr unsigned wrong_starttime         = 102;
    static constexpr unsigned wrong_endtime           = 103;
    static constexpr unsigned zero_vote_price         = 104;
    static constexpr unsigned not_enough_tons         = 105;
    static constexpr unsigned id_not_found            = 106;
    static constexpr unsigned bad_gas_price_fmt       = 107;
    static constexpr unsigned wrong_proposal_addr     = 108;
    static constexpr unsigned wrong_deployer_key      = 109;
    static constexpr unsigned not_fully_initialized   = 110;
  };

  static constexpr unsigned createProposalGas    = 40000;
  static constexpr unsigned deployProposalGas    = 40000;
  static constexpr unsigned createMultiBallotGas = 40000;
  static constexpr unsigned Stats_registerTransferGas = 40000;

  __always_inline
  void constructor(address budget, address stats, address depool) {
    budget_ = budget;
    stats_ = stats;
    depool_ = depool;

    auto myaddr = address{tvm_myaddr()};
    workchain_id_ = std::get<addr_std>(myaddr()).workchain_id;
    start_balance_ = tvm_balance();
    deployer_key_ = tvm_pubkey();
  }

  __always_inline
  void setProposalRootCode(cell code) {
    require(deployer_key_ && deployer_key_ == tvm_pubkey(), error_code::wrong_deployer_key);
    tvm_accept();
    proposal_root_code_ = code;
    // when the contract is fully initialized, deployer key will be nullified
    if (proposal_root_code_ && multi_ballot_code_)
      deployer_key_ = 0;
  }

  __always_inline
  void setMultiBallotCode(cell code) {
    require(deployer_key_ && deployer_key_ == tvm_pubkey(), error_code::wrong_deployer_key);
    tvm_accept();
    multi_ballot_code_ = code;
    // when the contract is fully initialized, deployer key will be nullified
    if (proposal_root_code_ && multi_ballot_code_)
      deployer_key_ = 0;
  }

  // Adds new proposal to m_proposals, prepares initial data for new Proposal Root contract,
  //  calculates it address and deploys it
  __always_inline
  bool_t createProposal(uint256 id, VotesType totalVotes,
                        uint32 startime, uint32 endtime, bytes desc,
                        bool_t super_majority, DepositType vote_price,
                        bool_t finalMsgEnabled,
                        cell finalMsg, uint256 finalMsgValue, uint256 finalMsgRequestValue,
                        bool_t whiteListEnabled, dict_array<uint256> whitePubkeys) {
    require(proposal_root_code_ && multi_ballot_code_, error_code::not_fully_initialized);
    require(!proposals_.contains(id.get()), error_code::duplicated_id);
    require(totalVotes != 0, error_code::zero_votes);

    auto cur_time = smart_contract_info::now();
    require(startime + 60 >= cur_time, error_code::wrong_starttime);
    require(endtime + 60 >= cur_time + minimal_voting_time, error_code::wrong_endtime);
    require(vote_price != 0, error_code::zero_vote_price);

    unsigned myExecTons = gastogram(createProposalGas);
    unsigned tonsToProposal = gastogram(deployProposalGas);

    auto [sender, value_gr] = int_sender_and_value();
    DepositType value(value_gr());
    require(value >= myExecTons + tonsToProposal + finalMsgValue.get(), error_code::not_enough_tons);

    tvm_rawreserve(std::max(start_balance_, tvm_balance() - value).get(), rawreserve_flag::none);

    std::optional<cell> finalMsgOpt = finalMsgEnabled ? finalMsg : std::optional<cell>{};

    auto [proposal_init, dest] = calc_proposal_init(id, totalVotes, startime, endtime, desc,
                                                    super_majority, vote_price,
                                                    whiteListEnabled, whitePubkeys,
                                                    finalMsgOpt, finalMsgValue, finalMsgRequestValue);
    handle<IProposalRoot> dest_handle(dest);
    dest_handle.deploy(proposal_init, Grams(tonsToProposal + finalMsgValue.get()), IGNORE_ACTION_ERRORS).
      deployProposal();

    proposals_.set_at(id.get(), Proposal{dest});

    set_int_return_flag(INT_RETURN_FLAG);
    return bool_t{true};
  }

  __always_inline
  address createMultiBallot(uint256 pubkey, DepositType tonsToBallot) {
    require(proposal_root_code_ && multi_ballot_code_, error_code::not_fully_initialized);

    unsigned myExecTons = gastogram(createMultiBallotGas);

    auto value_gr = int_value();
    DepositType value(value_gr());
    require(value >= myExecTons + tonsToBallot, error_code::not_enough_tons);

    tvm_rawreserve(std::max(start_balance_, tvm_balance() - value).get(), rawreserve_flag::none);

    auto [ballot_init, dest] = calc_ballot_init(pubkey);
    handle<IMultiBallot> dest_handle(dest);
    dest_handle.deploy(ballot_init, Grams(tonsToBallot.get()), IGNORE_ACTION_ERRORS).
      deployBallot();
    set_int_return_flag(INT_RETURN_FLAG);
    return dest;
  }

  __always_inline
  void contestApproved(uint256 id, address contest_addr, uint256 requestValue) {
    require(proposal_root_code_ && multi_ballot_code_, error_code::not_fully_initialized);
    address sender = int_sender();
    require(proposals_.contains(id.get()), error_code::id_not_found);
    require(proposals_.get_at(id.get()).root == sender, error_code::wrong_proposal_addr);

    Grams statsTons(gastogram(Stats_registerTransferGas));

    stats_(statsTons).registerTransfer(id, contest_addr, requestValue);

    budget_(Grams(0), SEND_REST_GAS_FROM_INCOMING).
      request(id, contest_addr, requestValue);
  }

  // ============== getters ==============
  __always_inline
  address getBudget() {
    return budget_.get();
  }

  __always_inline
  address getStats() {
    return stats_.get();
  }

  __always_inline
  address getDepool() {
    return depool_;
  }

  __always_inline
  address getMultiBallotAddress(uint256 pubkey) {
    return calc_ballot_init(pubkey).second;
  }

  // Returns code of Proposal Root smart contract
  __always_inline
  cell getProposalRootCode() {
    return *proposal_root_code_;
  }

  // Returns code of Voting Wallet smart contract
  __always_inline
  cell getMultiBallotCode() {
    return *multi_ballot_code_;
  }

  __always_inline
  int8 getWorkchainId() {
    return workchain_id_;
  }

  __always_inline
  DepositType getStartBalance() {
    return start_balance_;
  }

  __always_inline
  Proposal getProposalById(uint256 id) {
    require(proposals_.contains(id.get()), error_code::id_not_found);
    return proposals_.get_at(id.get());
  }

  __always_inline
  dict_array<uint256> getProposalIds() {
    dict_array<uint256> rv;
    for (auto pair : proposals_) {
      rv.push_back(pair.first);
    }
    return rv;
  }

  __always_inline
  address getProposalAddress(uint256 id) {
    return getProposalById(id).root;
  }

  __always_inline
  bool_t isFullyInitialized() {
    return bool_t{ proposal_root_code_ && multi_ballot_code_ };
  }

  __always_inline
  uint32 getNow() {
    return uint32(smart_contract_info::now());
  }

  __always_inline
  DepositType getCreateProposalGasPrice() {
    return DepositType(gastogram(createProposalGas));
  }

  __always_inline
  DepositType getDeployProposalGasPrice() {
    return DepositType(gastogram(deployProposalGas));
  }

  __always_inline
  DepositType getCreateMultiBallotGasPrice() {
    return DepositType(gastogram(createMultiBallotGas));
  }
private:
  __always_inline
  std::pair<StateInit, address> calc_proposal_init(
      uint256 id, VotesType totalVotes, uint32 startime, uint32 endtime, bytes desc,
      bool_t super_majority, DepositType vote_price,
      bool_t whiteListEnabled, const dict_array<uint256> whitePubkeys,
      std::optional<cell> finalMsg, uint256 finalMsgValue, uint256 finalMsgRequestValue) {
    dict_set<uint256> white_list(whitePubkeys.begin(), whitePubkeys.end());

    auto myaddr = address{tvm_myaddr()};
    auto my_std_addr = std::get<addr_std>(myaddr()).address;
    DProposalRoot proposal_data {
      super_majority, workchain_id_, my_std_addr, depool_, vote_price, *multi_ballot_code_, finalMsg,
      Grams(finalMsgValue.get()), Grams(finalMsgRequestValue.get()), id, startime, endtime, desc,
      totalVotes, VotesType(0), VotesType(0), bool_t{false}, whiteListEnabled, white_list
    };
    auto [proposal_init, dest_addr] = prepare_proposal_state_init_and_addr(proposal_data, *proposal_root_code_);
    auto dest = address::make_std(workchain_id_, dest_addr);
    return { proposal_init, dest };
  }
  __always_inline
  std::pair<StateInit, address> calc_ballot_init(uint256 pubkey) const {
    auto myaddr = address{tvm_myaddr()};
    auto my_std_addr = std::get<addr_std>(myaddr()).address;
    DMultiBallot ballot_data {
      pubkey, workchain_id_, my_std_addr, depool_, DepositType{0}, DepositType{0}, {}
    };
    auto [wallet_init, dest_addr] = prepare_ballot_state_init_and_addr(ballot_data, *multi_ballot_code_);
    auto dest = address::make_std(workchain_id_, dest_addr);
    return { wallet_init, dest };
  }
public:
  // ==================== Support methods =========================== //

  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }
  DEFAULT_SUPPORT_FUNCTIONS(ISuperRoot, super_root_replay_protection_t);
};

DEFINE_JSON_ABI(ISuperRoot, DSuperRoot, ESuperRoot);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(SuperRoot, ISuperRoot, DSuperRoot, SUPER_ROOT_TIMESTAMP_DELAY)

