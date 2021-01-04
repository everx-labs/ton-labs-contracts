#include "ProposalRoot.hpp"
#include "MultiBallot.hpp"
#include "SuperRoot.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/emit.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

// #define CONTEST_HAS_PUBKEY
#define CONTEST_HAS_EXPIRE_AT

class ProposalRoot final : public smart_interface<IProposalRoot>, public DProposalRoot {
public:
  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_good_ballot = 100;
    static constexpr unsigned out_of_time                       = 101;
    static constexpr unsigned not_enough_tons                   = 102;
    static constexpr unsigned call_deploy_proposal_instead      = 103;
    static constexpr unsigned pubkey_not_allowed                = 104;
    static constexpr unsigned approve_not_awaited               = 105;
  };

  __always_inline
  void deployProposal() {
    auto myaddr = address{tvm_myaddr()};
    workchain_id_ = std::get<addr_std>(myaddr()).workchain_id;
  }

  // Allows a multi ballot to vote for proposal
  __always_inline
  VotesInfo vote(uint256 pubkey, DepositType deposit, bool_t yes) {
    require(!white_list_enabled_ || white_list_.contains(pubkey), error_code::pubkey_not_allowed);

    uint256 expected_address = expected_sender_address(pubkey);
    auto sender = int_sender();
    auto addr_std_v = std::get<addr_std>(sender());
    require(addr_std_v.address == expected_address && addr_std_v.workchain_id == workchain_id_,
            error_code::message_sender_is_not_good_ballot);
    require(deposit > votePrice_, error_code::not_enough_tons);

    auto cur_time = smart_contract_info::now();
    require(cur_time >= start_, error_code::out_of_time);
    require(cur_time <= end_, error_code::out_of_time);

    auto votes = deposit / votePrice_;
    if (yes)
      yesVotes_ += votes;
    else
      noVotes_ += votes;

    emit<&EProposalRoot::VotesChanged>(yesVotes_, noVotes_);
    if (isEarlyFinished())
      sendResultsImpl(bool_t{checkSureApproved()});

    set_int_return_flag(SEND_REST_GAS_FROM_INCOMING);
    return { yesVotes_, noVotes_ };
  }

  // Returns true if voting is already finished
  // Also generates external message with voting results at first request after voting finish
  __always_inline
  bool_t checkFinished() {
    set_int_return_flag(SEND_REST_GAS_FROM_INCOMING);
    if (isFinished()) {
      sendResultsImpl(isApproved());
      return bool_t{true};
    }
    return bool_t{false};
  }

  // Returns true if voting is already finished and approved
  // Also generates external message with voting results at first request after voting finish
  __always_inline
  bool_t checkApproved() {
    set_int_return_flag(SEND_REST_GAS_FROM_INCOMING);
    bool_t approved = isApproved();
    if (isFinished())
      sendResultsImpl(approved);
    return approved;
  }

  // Returns VoteResults with details
  // Also generates external message with voting results at first request after voting finish
  __always_inline
  VoteResults checkResults() {
    set_int_return_flag(SEND_REST_GAS_FROM_INCOMING);
    bool_t finished = isFinished();
    bool_t approved = isApproved();
    if (finished)
      sendResultsImpl(approved);
    return { yesVotes_, noVotes_, finished, approved };
  }

  __always_inline
  void contestApproved() {
    require(final_dest_ && *final_dest_ == int_sender(), error_code::approve_not_awaited);
    tvm_accept();

    handle<ISuperRoot> super_root(address::make_std(workchain_id_, super_root_));
    super_root(Grams(0), SEND_REST_GAS_FROM_INCOMING).
      contestApproved(id_, *final_dest_, uint256(final_msg_request_value_.get()));
  }

  // ========== getters ==========

  __always_inline
  bool_t getSuperMajority() {
    return super_majority_;
  }

  __always_inline
  int8 getWorkchainId() {
    return workchain_id_;
  }

  __always_inline
  address getDepool() {
    return depool_;
  }

  __always_inline
  DepositType getVotePrice() {
    return votePrice_;
  }

  __always_inline
  cell getBallotCode() {
    return ballot_code_;
  }

  __always_inline
  ProposalInfo getProposal() {
    return ProposalInfo { id_, start_, end_, desc_, isFinished(), isApproved(), result_sent_,
                          isEarlyFinished(), white_list_enabled_, totalVotes_,
                          yesVotes_ + noVotes_, yesVotes_, noVotes_, votePrice_ };
  }

  __always_inline
  bool_t isFinished() {
    return bool_t{isEarlyFinished() || (smart_contract_info::now() > end_)};
  }

  __always_inline
  bool_t isApproved() {
    if (!isFinished())
      return bool_t{false};
    if (checkSureApproved())
      return bool_t{true};
    if (checkSureDisapproved())
      return bool_t{false};
    return bool_t{super_majority_ ? checkSoftSuperMajority() : checkSoftSimpleMajority()};
  }

  __always_inline
  bool_t isResultSent() {
    return result_sent_;
  }

  __always_inline
  bool_t isEarlyFinished() {
    return bool_t{checkSureApproved() || checkSureDisapproved()};
  }

  __always_inline
  bool_t isWhiteListEnabled() {
    return white_list_enabled_;
  }

  __always_inline
  dict_array<uint256> getWhiteList() {
    dict_array<uint256> rv;
    for (auto pubkey : white_list_) {
      rv.push_back(pubkey);
    }
    return rv;
  }
private:
  __always_inline
  uint256 expected_sender_address(uint256 pubkey) const {
    DMultiBallot ballot_data {
      pubkey, workchain_id_, super_root_, depool_,
      DepositType(0), DepositType(0), {}
    };
    return prepare_ballot_state_init_and_addr(ballot_data, ballot_code_).second;
  }

  __always_inline
  void sendResultsImpl(bool_t approve) {
    if (!result_sent_) {
      emit<&EProposalRoot::VotingFinished>(yesVotes_, noVotes_, approve);
      if (final_msg_) {
        // TODO: remove this fix when SDK will be able to prepare internal deploy messages
        cell fixed_msg = convertExternalDeployIntoInternal(*final_msg_, final_msg_value_);
        tvm_sendmsg(fixed_msg, DEFAULT_MSG_FLAGS);
      }
      result_sent_ = true;
    }
  }

  __always_inline
  bool checkSoftSimpleMajority() const {
    // Ymax = T/2 + 1; Nmax = T/2
    // Ymin = T/10;    Nmin = 0
    // Y = Ymin + k * N
    // T/2 + 1 = T/10 + k * (T/2)
    // k = (T/2 + 1 - T/10) / (T/2) = (T + 2 - T/5) / T = 4/5 + 2/T
    // Y >= T/10 + (4/5 + 2/T) * N
    // 10*T*Y >= T*T + (8*T + 20) * N
    auto T = totalVotes_.get();
    auto Y = yesVotes_.get();
    auto N = noVotes_.get();
    return 10*T*Y >= T*T + (8*T + 20) * N;
  }
  __always_inline
  bool checkSoftSuperMajority() const {
    // Ymax = T/2 + 1; Nmax = T/2
    // Ymin = T/3;     Nmin = 0
    // Y = Ymin + k * N
    // T/2 + 1 = T/3 + k * (T/2)
    // k = (T/2 + 1 - T/3) / (T/2) = (T + 2 - 2*T/3) / T = 1 - 2/3 + 2/T = 1/3 + 2/T
    // Y >= T/3 + (1/3 + 2/T) * N
    // 3*T*Y >= T*T + (T + 6) * N
    auto T = totalVotes_.get();
    auto Y = yesVotes_.get();
    auto N = noVotes_.get();
    return 3*T*Y >= T*T + (T + 6) * N;
  }
  __always_inline
  bool checkSureApproved() const {
    return super_majority_ ? checkSureApprovedSuper() : checkSureApprovedSimple();
  }
  __always_inline
  bool checkSureDisapproved() const {
    return super_majority_ ? checkSureDisapprovedSuper() : checkSureDisapprovedSimple();
  }
  __always_inline
  bool checkSureApprovedSimple() const {
    auto T = totalVotes_.get();
    auto Y = yesVotes_.get();
    return 2*Y > T;
  }
  __always_inline
  bool checkSureDisapprovedSimple() const {
    auto T = totalVotes_.get();
    auto N = noVotes_.get();
    return 2*N > T;
  }
  __always_inline
  bool checkSureApprovedSuper() const {
    auto T = totalVotes_.get();
    auto Y = yesVotes_.get();
    return 3*Y > 2*T;
  }
  __always_inline
  bool checkSureDisapprovedSuper() const {
    auto T = totalVotes_.get();
    auto N = noVotes_.get();
    return 3*N > 2*T;
  }

  // TODO: Remove when SDK will support internal deploy messages
  // Remember to keep `final_dest_` set
  __always_inline
  cell convertExternalDeployIntoInternal(cell orig_msg, Grams value) {
    using msg_t = message_relaxed<anyval>;
    auto in_msg = parse<msg_t>(parser(orig_msg.ctos()));
    if (!std::holds_alternative<ext_in_msg_info>(in_msg.info))
      return orig_msg;
    auto in_info = std::get<ext_in_msg_info>(in_msg.info);
    auto addr = in_info.dest;
    final_dest_ = addr;
    int_msg_info_relaxed out_info = { {},
      /*ihr_disabled*/bool_t{true}, /*bounce*/bool_t{false}, bool_t{false},
      MsgAddress{MsgAddressExt{addr_none{}}}, addr, { value, {} }, Grams(0), Grams(0),
      uint64{0}, uint32{0}
    };
    in_msg.info = out_info;
    auto state_init = *in_msg.init;
    if (state_init.isa<StateInit>())
      in_msg.init = Either<StateInit, ref<StateInit>>{ ref<StateInit>{state_init.get<StateInit>()} };
    if (in_msg.body.isa<anyval>())
      in_msg.body = ref<anyval>{in_msg.body.get<anyval>()};
    slice body_sl = in_msg.body.get<ref<anyval>>().val_.val_;
    parser p(body_sl);
    if (p.ldu(1)) {
      p.skip(512); // signature
    }
#ifdef CONTEST_HAS_PUBKEY
    if (p.ldu(1)) {
      p.ldu(256); // pubkey
    }
#endif
    unsigned timestamp = p.ldu(64);
#ifdef CONTEST_HAS_EXPIRE_AT
    unsigned expire_at = p.ldu(32);
#endif
    unsigned func_id = p.ldu(32);
    require(func_id == 777, 77);
    slice args = p.sl();
    slice fixed_sl = builder().stu(func_id, 32).stslice(args).make_slice();
    in_msg.body = ref<anyval>{anyval{fixed_sl}};
    return build(in_msg).endc();
  }
public:
  // ==================== Support methods =========================== //
  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }
  DEFAULT_SUPPORT_FUNCTIONS(IProposalRoot, proposal_root_replay_protection_t);
};

DEFINE_JSON_ABI(IProposalRoot, DProposalRoot, EProposalRoot);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(ProposalRoot, IProposalRoot, DProposalRoot, PROPOSAL_ROOT_TIMESTAMP_DELAY)

