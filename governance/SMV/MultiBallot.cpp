#include "MultiBallot.hpp"
#include "ProposalRoot.hpp"
#include "DePool.hpp"

#include <tvm/contract.hpp>
#include <tvm/smart_switcher.hpp>
#include <tvm/contract_handle.hpp>
#include <tvm/default_support_functions.hpp>

using namespace tvm;
using namespace schema;

class MultiBallot final : public smart_interface<IMultiBallot>, public DMultiBallot {
public:
  struct error_code : tvm::error_code {
    static constexpr unsigned message_sender_is_not_my_owner    = 100;
    static constexpr unsigned not_enough_balance                = 101;
    static constexpr unsigned call_deploy_ballot_instead        = 103;
    static constexpr unsigned deposit_already_requested         = 104;
    static constexpr unsigned deposit_not_requested_yet         = 105;
    static constexpr unsigned wrong_workchain                   = 106;
    static constexpr unsigned message_sender_is_not_depool      = 107;
  };
  static constexpr unsigned ProposalRoot_Vote_Gas                          = 20000;
  static constexpr unsigned ProposalRoot_ReturnDeposit_Gas                 = 20000;
  static constexpr unsigned ProposalRoot_IsFinished_Gas                    = 20000;
  static constexpr unsigned DePool_transferStake_Gas                       = 20000;
  static constexpr unsigned MultiBallot_receiveNativeTransfer_Gas          = 20000;
  static constexpr unsigned MultiBallot_receiveStakeTransfer_Gas           = 20000;

  // Initializes ballot variables
  __always_inline
  void deployBallot() {
    auto myaddr = address{tvm_myaddr()};
    auto workchain = std::get<addr_std>(myaddr()).workchain_id;
    require(workchain_id_ == workchain, error_code::wrong_workchain);
  }

  // Receive native funds transfer and keep it in deposit, and update votes
  __always_inline
  void receiveNativeTransfer(DepositType amount) {
    auto exec_grams = gastogram(MultiBallot_receiveNativeTransfer_Gas);
    require(int_value() > amount.get() + exec_grams, error_code::not_enough_balance);
    native_deposit_ += amount;
  }

  // Receive stake transfer notify, and update stake deposit
  __always_inline
  void receiveStakeTransfer(address source, uint128 amount) {
    auto sender = int_sender();
    require(sender.sl() == depool_.sl(), error_code::message_sender_is_not_depool);
    stake_deposit_ += amount.get();
  }

  // Sends votes for all deposit to Proposal Root contract
  __always_inline
  sendVotesResult sendVote(address proposal, bool_t yesOrNo) {
    require(tvm_pubkey() == ballot_public_key_, error_code::message_sender_is_not_my_owner);
    require(native_deposit_ || stake_deposit_, error_code::not_enough_balance);

    tvm_accept();

    auto proposal_std = std::get<addr_std>(proposal());
    require(proposal_std.workchain_id == workchain_id_, error_code::wrong_workchain);
    auto proposal_addr = proposal_std.address;

    auto deposit_sum = native_deposit_ + stake_deposit_;

    if (auto opt_elem = proposals_.lookup(proposal_addr.get())) {
      // already sent some deposit to this proposal
      auto already_sent_deposit = *opt_elem;
      if (already_sent_deposit >= deposit_sum) {
        return { deposit_sum, already_sent_deposit, DepositType{0} };
      } else {
        auto new_deposit = deposit_sum - already_sent_deposit;
        proposals_.set_at(proposal_addr.get(), new_deposit);
        sendVotesImpl(proposal, new_deposit, yesOrNo);
        return { deposit_sum, already_sent_deposit, new_deposit };
      }
    } else {
      proposals_.set_at(proposal_addr.get(), deposit_sum);
      sendVotesImpl(proposal, deposit_sum, yesOrNo);
      return { deposit_sum, DepositType{0}, deposit_sum };
    }
  }

  __always_inline
  resumable<void> requestDeposit(address user_wallet) {
    require(tvm_pubkey() == ballot_public_key_, error_code::message_sender_is_not_my_owner);
    require(native_deposit_ || stake_deposit_, error_code::deposit_already_requested);
    tvm_accept();

    for (auto proposal : proposals_) {
      address dest{ MsgAddressInt{ addr_std{ {}, {}, workchain_id_, proposal.first } } };
      IProposalRootPtr proposal_root(dest);
      unsigned isFinishedTons = gastogram(ProposalRoot_IsFinished_Gas);
      bool_t finished =
        co_await proposal_root(Grams(isFinishedTons)).checkFinished();
      if (!finished)
        co_return ; //{ bool_t{false}, proposal.first };
    }

    if (stake_deposit_ != 0) {
      IDePoolPtr depool_h(depool_);
      unsigned transferStakeTons = gastogram(DePool_transferStake_Gas);
      depool_h(Grams(transferStakeTons)).transferStake(user_wallet, uint64{0});
    }
    if (native_deposit_ != 0) {
      tvm_transfer(user_wallet, native_deposit_.get(), true, DEFAULT_MSG_FLAGS);
    }
    native_deposit_ = 0;
    stake_deposit_ = 0;

    co_return;// { bool_t{true}, {} };
  }

  __always_inline
  void finalize(address user_wallet) {
    require(tvm_pubkey() == ballot_public_key_, error_code::message_sender_is_not_my_owner);
    require(native_deposit_ == 0 && stake_deposit_ == 0, error_code::deposit_not_requested_yet);
    tvm_accept();
    tvm_transfer(user_wallet, 0, true, SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY);
  }

  // ==================== Getter methods =========================== //

  __always_inline
  address getDepool() {
    return depool_;
  }

  __always_inline
  DepositType getNativeDeposit() {
    return native_deposit_;
  }

  __always_inline
  DepositType getStakeDeposit() {
    return stake_deposit_;
  }

  __always_inline
  dict_array<uint256> getProposals() {
    dict_array<uint256> rv;
    for (auto proposal : proposals_) {
      rv.push_back(proposal.first);
    }
    return rv;
  }

  __always_inline
  dict_array<DepositType> getProposalVoteDeposits() {
    dict_array<DepositType> rv;
    for (auto proposal : proposals_) {
      rv.push_back(proposal.second);
    }
    return rv;
  }

  __always_inline
  DepositType getProposalRoot_Vote_GasPrice() {
    return DepositType(gastogram(ProposalRoot_Vote_Gas));
  }

  __always_inline
  DepositType getProposalRoot_ReturnDeposit_GasPrice() {
    return DepositType(gastogram(ProposalRoot_ReturnDeposit_Gas));
  }

  __always_inline
  DepositType getMultiBallot_receiveNativeTransfer_GasPrice() {
    return DepositType(gastogram(MultiBallot_receiveNativeTransfer_Gas));
  }

  __always_inline
  DepositType getMultiBallot_receiveStakeTransfer_GasPrice() {
    return DepositType(gastogram(MultiBallot_receiveStakeTransfer_Gas));
  }

private:
  void sendVotesImpl(address proposal, DepositType deposit, bool_t yesOrNo) {
    IProposalRootPtr proposal_root(proposal);
    unsigned voteTons = gastogram(ProposalRoot_Vote_Gas);
    proposal_root(Grams(voteTons)).vote(ballot_public_key_, deposit, yesOrNo);
  }
public:
  // ==================== Support methods =========================== //
  // default processing of unknown messages
  __always_inline static int _fallback(cell msg, slice msg_body) {
    return 0;
  }
  DEFAULT_SUPPORT_FUNCTIONS(IMultiBallot, multi_ballot_replay_protection_t);
};

DEFINE_JSON_ABI(IMultiBallot, DMultiBallot, EMultiBallot);

// ----------------------------- Main entry functions ---------------------- //
DEFAULT_MAIN_ENTRY_FUNCTIONS(MultiBallot, IMultiBallot, DMultiBallot, MULTI_BALLOT_TIMESTAMP_DELAY)

