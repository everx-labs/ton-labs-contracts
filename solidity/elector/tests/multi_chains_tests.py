#!/usr/bin/env python3

import ed25519
import json
import os
import pprint
import secrets
import time

import ts4
from BaseContract import *
from core import set_trace_tvm, parse_config_param
from globals import status, time_set, time_get
from contracts import Config, DePoolHelper, DePool, Elector, Validator, Zero
from deployers import deploy_elector, deploy_config
from call_utils import stake, generate_query_id, make_elections, conduct_elections, make_stakes

core = globals.core
init('binaries/', verbose = True)

def deploy_network(max_validators, main_validators, min_validators, wc_ids: list[str]):
    work_chains: list[dict] = []
    for chain in wc_ids:
        wc = dict(wc_id=chain, validators=[], elect_id=None)
        work_chains.append(wc)
    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(
        max_validators  = max_validators,
        min_validators  = min_validators,
        main_validators = main_validators,
        min_stake       = 10 * GRAM,
        max_stake       = 10000 * GRAM,
        min_total_stake = 100 * GRAM,
    )

    e = deploy_elector()
    for wc in work_chains:
        c.add_new_wc(wc["wc_id"])

    configurations = [[3, 40]] * 6

    # for wc_id in wc_ids:
    #     v = make_elections(configurations, e, wc_id)
    #     conduct_elections(c, e, len(configurations), wc_id)
    for chain in work_chains[0:1]:
        wc_id = chain["wc_id"]
        assert eq(False, e.get_chain_election(wc_id)["open"])
        e.ticktock(False)  # announce_new_elections
        chain['validators'] = make_stakes(configurations, e, wc_id)
        e.ticktock(False)  # chain -1 update active vset_id

    for chain in work_chains[1:]:
        wc_id  = chain["wc_id"]
        assert eq(False, e.get_chain_election(wc_id)["open"])
        e.ticktock(False)  # chain 0 announce new election
        assert eq(True, e.get_chain_election(wc_id)["open"])
        chain['validators'] = make_stakes(configurations, e, wc_id)

    for chain in work_chains:
        wc_id = chain['wc_id']

        chain["elect_id"] = decode_int(e.get_chain_election(wc_id)['elect_at'])


    status('Conducting elections')
    for chain in work_chains:
        wc_id = chain['wc_id']

        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
        e.ticktock(False)  # conduct_elections

        assert eq(True, e.get_chain_election(wc_id)['open'])

    dispatch_messages()
    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    for _ in work_chains:
        e.ticktock(False) # validator_set_installed

    for wc_id in wc_ids:
        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 240 * len(wc_ids) * GRAM) # 240 grams of stake + 100 grams of own funds

    globals.time_shift(1)

    return (e, c, work_chains)
def test_identical_validators_1():

    globals.reset()
    showtime = 86400
    time_set(showtime)

    keypair = make_keypair()
    c = deploy_config(max_validators = 3, keypair = keypair)

    e = deploy_elector()

    for wc in ["-1", "0"]:
        c.add_new_wc(wc)
    return (showtime, e, c)

def test_identical_validators_2(showtime, e: Elector, c: Config):
    master_chain = dict(wc_id ="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id ="0", validators=[], elect_id=None)

    chains_array = [master_chain, work_chain]

    configurations = [[3, 40]] * 6


    status('Announcing new elections')
    master_chain_state = e.get_chain_election(master_chain['wc_id'])
    assert eq(False, master_chain_state['open'])
    e.ticktock(False) # announce_new_elections
    # Make master chain stakes
    master_chain['validators'] = make_stakes(configurations, e, master_chain['wc_id'])

    e.ticktock(False) # chain -1 update active vset_id

    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(False, work_chain_state['open'])

    e.ticktock(False) # chain 0 announce new election
    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(True, work_chain_state['open'])
    # Make master work_chain stakes
    work_chain['validators'] = make_stakes(configurations, e, work_chain['wc_id'])

    # shift time until close state
    time_set(decode_int(e.get_chain_election(master_chain['wc_id'])['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections for master_chain

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    e.ticktock(False) # validator_set_installed for master_chain
    time_set(decode_int(e.get_chain_election(work_chain['wc_id'])['elect_close']))
    e.ticktock(False) # conduct_elections for work_chain
    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()


    globals.time_shift(c.elect_end_before)
    c.ticktock(False)

    set_config_param(100, c.get_config_param(100))

    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed
    e.ticktock(False) # validator_set_installed


    for chain in chains_array:
        state = e.get_chain_election(chain['wc_id'])
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])


    e.ensure_balance(globals.G_DEFAULT_BALANCE + 240 * 2 * GRAM) # 240 grams of stake + 100 grams of own funds

    for chain in chains_array:
        time_set(decode_int(c.get_current_vset(chain['wc_id'])['utime_until']) - c.elect_begin_before)

        status('Announcing new elections #2')
        e.ticktock(False) # announce_new_elections

        state = e.get_chain_election(chain['wc_id'])
        assert eq(True, state['open'])
        state = e.get_chain_election(chain['wc_id'])
        assert eq(True, state['open'])
        # elect_id = state['elect_at']
        chain_validators = chain['validators']

        status('Recovering the stakes from elections #1')
        stakes1 = [40, 40, 40, 0, 0, 0]
        for i in range(6):
            query_id = generate_query_id()
            chain_validators[i].recover(query_id)
            dispatch_one_message()  # validator: elector.recover_stake()
            dispatch_one_message()  # elector: validator.receive_stake_back()
            chain_validators[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes1[i] * GRAM)



    for chain in chains_array:
        state = e.get_chain_election(chain['wc_id'])
        elect_id = state['elect_at']
        chain['elect_id'] = elect_id
        chain_validators = chain["validators"]
        stakes2 = [80, 80, 80, 40, 40, 40]
        for i in range(6):
            stake(elect_id, 0x30000, 40 * GRAM, chain['wc_id'], chain_validators[i])
            chain_validators[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes2[i] * GRAM)



    for chain in chains_array:

        time_set(decode_int(e.get_chain_election(chain['wc_id'])['elect_close']))
        status('Conducting elections')
        e.ticktock(False)  # validator_set_installed
        e.ticktock(False)  # conduct_elections

        dispatch_one_message()  # elector: config.set_next_validator_set()
        set_config_param(100, c.get_config_param(100))
        dispatch_one_message()  # elector: config.set_next_validator_set()

        assert eq(True, e.get_chain_election(chain['wc_id'])['open'])



    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))

    status('Installing next validator set')
    for chain in chains_array:
        e.ticktock(False)  # validator_set_installed
        assert eq(False, e.get_chain_election(chain['wc_id'])['open'])
        state = e.get_chain_election(chain['wc_id'])
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])


    e.ensure_balance(globals.G_DEFAULT_BALANCE + (120 + 240)* 2 * GRAM)

    for chain in chains_array:
        time_set(decode_int(e.get_chain_past_elections(chain['wc_id'])[chain['elect_id']]['unfreeze_at']))
        status('Unfreezing the stakes')
        e.ticktock(False)
        e.ticktock(False)

    for chain in chains_array:

        stakes3 = [40, 40, 40, 0, 0, 0]
        status('Recovering the stakes from elections #1')
        print(e.get_chain_election(chain['wc_id']))
        validators = chain["validators"]
        for i in range(6):
            print(i)
            query_id = generate_query_id()
            validators[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            validators[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes3[i] * GRAM)

    status('All done')

def test_identical_validators():
    (showtime, e, c) = test_identical_validators_1()

    c.set_config_params()
    test_identical_validators_2(showtime, e, c)

def test_return_stake(ec, stake_at, max_factor, value,wc_id: str, bad_sign = False):

    v = Validator()
    query_id = generate_query_id()
    cell = v.stake_sign_helper(stake_at, max_factor)
    private_key = v.private_key
    if bad_sign:
        (private_key, unused) = make_keypair()
    signature = sign_cell(cell, private_key)
    v.stake(query_id, stake_at, max_factor, value + EVER, signature, wc_id)
    dispatch_one_message() # validator: elector.process_new_stake()
    dispatch_one_message() # elector: validator.return_stake()
    state = v.get()
    assert eq(decode_int(query_id), decode_int(state['returned_query_id']))
    assert eq(ec, decode_int(state['returned_body']))
    v.ensure_balance(globals.G_DEFAULT_BALANCE)
def test_return_simple_transfer(value):
    v = Validator()
    v.transfer(value)
    dispatch_one_message()
    v.ensure_balance(globals.G_DEFAULT_BALANCE - value)
    dispatch_one_message()
    v.ensure_balance(globals.G_DEFAULT_BALANCE)
def test_return_stake_same_pubkey(v, stake_at, wc_id: str):
    w = Validator()
    w.private_key      = v.private_key
    w.validator_pubkey = v.validator_pubkey
    w.adnl_addr        = v.adnl_addr
    query_id = generate_query_id()
    cell = w.stake_sign_helper(stake_at, 0x10000)
    signature = sign_cell(cell, v.private_key)
    w.stake(query_id, stake_at, 0x10000, 11 * GRAM, signature, wc_id)
    dispatch_one_message() # validator: elector.process_new_stake()
    dispatch_one_message() # elector: validator.return_stake()
    state = w.get()
    assert eq(decode_int(query_id), decode_int(state['returned_query_id']))
    assert eq(4, decode_int(state['returned_body']))
    w.ensure_balance(globals.G_DEFAULT_BALANCE)

configurations = [
    (2.0, 10), (2.0, 10), (3.0, 10), (3.0, 10), (3.0, 40),
    (3.0, 40), (2.0, 20), (3.0, 10), (2.0, 20), (2.0, 10),
    (2.0, 40), (3.0, 30), (3.0, 10), (3.0, 20), (2.0, 20),
    (2.0, 10), (2.0, 40), (3.0, 10), (2.0, 20), (2.0, 10),
    (3.0, 50), (3.0, 40), (3.0, 10), (3.0, 10), (3.0, 10),
    (2.0, 10), (3.0, 20), (3.0, 40), (3.0, 20), (3.0, 30)]

total_count = len(configurations)
def test_seven_validators():
    master_chain = dict(wc_id="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id="0", validators=[], elect_id=None)
    chains_array = [master_chain, work_chain]

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config()
    e = deploy_elector()
    for wc in chains_array:
        c.add_new_wc(wc["wc_id"])




    status('Announcing new elections')
    master_chain_state = e.get_chain_election(master_chain['wc_id'])
    assert eq(False, master_chain_state['open'])
    e.ticktock(False) # announce_new_elections
    # Make master chain stakes
    master_chain['validators'] = make_stakes(configurations, e, master_chain['wc_id'])

    e.ticktock(False) # chain -1 update active vset_id

    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(False, work_chain_state['open'])

    e.ticktock(False) # chain 0 announce new election
    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(True, work_chain_state['open'])
    # Make master work_chain stakes
    work_chain['validators'] = make_stakes(configurations, e, work_chain['wc_id'])




    for chain in chains_array:
        wc_id = chain['wc_id']
        total_stake = decode_int(e.get_chain_election(chain["wc_id"])['total_stake'])
        assert eq(globals.G_DEFAULT_BALANCE + (530 * EVER), total_stake)
        status('Checking stake with bad signature')
        status(green('total_stake: {}'.format(total_stake)))
        elect_id = decode_int(e.get_chain_election(wc_id)['elect_at'])
        chain["elect_id"] = elect_id
        test_return_stake(1, elect_id, 0x10000, 11 * EVER, wc_id, bad_sign = True)

        status('Checking stake with bad signature')
        test_return_stake(1, elect_id, 0x10000, 11 * EVER, wc_id, bad_sign = True)
        status('Checking stake less than 1/4096 of total_stake')
        test_return_stake(2, elect_id, 0x10000, total_stake >> 12, wc_id)

        status('Checking stake less than 1/4096 of total_stake')
        total_stake = decode_int(e.get_chain_election(wc_id)['total_stake'])
        test_return_stake(2, elect_id, 0x10000, ((total_stake + 1) >> 12), wc_id)
        status('Checking stake with bad election id')
        test_return_stake(3, elect_id + 1, 0x10000, 11 * EVER, wc_id)
        status('Checking stake from another address using the same pubkey')
        test_return_stake_same_pubkey(chain["validators"][0], elect_id, wc_id)
        status('Checking stake less than min_stake')
        test_return_stake(5, elect_id, 0x10000, 1 * EVER, wc_id)
        status('Checking stake with bad max factor')
        test_return_stake(6, elect_id, 0xffff, 11 * EVER, wc_id)
        status('Checking stake greater than max_stake')
        test_return_stake(7, elect_id, 0x10000, 60 * EVER, wc_id)
        status('Checking simple transfer not from -1:00..0 address')
        test_return_simple_transfer(10 * EVER)

    for chain in chains_array:
        wc_id = chain['wc_id']
        e.ticktock(False)
        conduct_elections(c, e, len(configurations), wc_id)


    elected = [20, 4, 5, 10, 16, 21, 27]
    for chain in chains_array:
        v = chain["validators"]
        wc_id = chain["wc_id"]
        elect_id = chain["elect_id"]

        status('Checking early stake recovery')
        for i in range(len(configurations)):
            validator  = v[i]
            orig_stake = configurations[i][1]

            balance = globals.G_DEFAULT_BALANCE - (orig_stake * EVER)
            validator.ensure_balance(balance)

            query_id = generate_query_id()
            validator.recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.error() or validator.receive_stake_back()
            state = validator.get()
            if i in elected:
                # elected validator's stake is freezed
                assert eq(decode_int(query_id), decode_int(state['error_query_id']))
                validator.ensure_balance(balance)
            else:
                # not elected validator gets back complete refund
                assert eq(decode_int(query_id), decode_int(state['refund_query_id']))
                validator.ensure_balance(globals.G_DEFAULT_BALANCE)

        status('Installing next validator set')
        e.ticktock(False) # validator_set_installed
        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])
        status('Checking stake after elections have finished')
        test_return_stake(0, elect_id, 0x10000, 11 * EVER, wc_id)

    globals.time_shift(600) # this line is here to prevent replay protection failure with exit code 52

    for chain in chains_array:

        wc_id = chain["wc_id"]
        v = chain["validators"]
        elect_id = chain["elect_id"]

        status('Checking next validator set')
        vset = c.get_next_vset(wc_id)
        for i in range(len(elected)):
            print(i)
            print(elected[i])
            print(v[elected[i]].validator_pubkey)
            print(vset)
            print(vset['vdict'])
            print(vset['vdict']['%d' % i])
            print(vset['vdict']['%d' % i]['pubkey'])
            assert eq(decode_int(v[elected[i]].validator_pubkey),
                      decode_int(vset['vdict']['%d' % i]['pubkey']))
        time_set(decode_int(e.get_chain_past_elections(wc_id)['%d' % elect_id]['unfreeze_at']))

    #
    status('Unfreezing the stakes')

    balances_before_unfreeze: dict[str,int] = dict() # calculate balances while it is available in the past_elections
    for chain in chains_array:
        wc_id = chain["wc_id"]
        elect_id = chain["elect_id"]
        stake = decode_int(e.get_chain_past_elections(wc_id)['%d' % elect_id]['total_stake'])
        balances_before_unfreeze[chain["wc_id"]] = stake

    for chain in chains_array:
        wc_id = chain["wc_id"]
        v = chain["validators"]
        e.ticktock(False) # check_unfreeze
        ensure_queue_empty()
        total_stake = 0
        for balance_wc in balances_before_unfreeze.keys(): # calculate remaining stake that should be included in elector
            total_stake += balances_before_unfreeze[balance_wc]

        e.ensure_balance(globals.G_DEFAULT_BALANCE + total_stake)

        status('Recovering the stakes')
        for i in range(len(configurations)):
            wallet_addr = v[i].hex_addr
            assert eq(100 * EVER - v[i].balance,
                        e.compute_returned_stake(wallet_addr))

            query_id = generate_query_id()
            v[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE)

        status('Triggering Config contract to update current vset')
        c.ticktock(False)
        c.set_config_params()

        status('Checking current validator set')
        vset = c.get_current_vset(wc_id)
        for i in range(len(elected)):
            assert eq(decode_int(v[elected[i]].validator_pubkey),
                      decode_int(vset['vdict']['%d' % i]['pubkey']))

        # decrease stake part that was withdrawn
        remaining_elector_balance = globals.G_DEFAULT_BALANCE + total_stake - balances_before_unfreeze[wc_id]
        e.ensure_balance(remaining_elector_balance)
        del balances_before_unfreeze[wc_id] # drop stake for excluding it in the next loop step
        c.ensure_balance(globals.G_DEFAULT_BALANCE, True)

    status('All done')
def test_rich_validator():
    master_chain = dict(wc_id="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id="0", validators=[], elect_id=None)
    chains_array = [master_chain, work_chain]
    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config()
    e = deploy_elector()

    for wc in chains_array:
        c.add_new_wc(wc["wc_id"])

    big_stake = 50
    common_stake = 2
    max_factor = 3
    common_count = 14
    configurations = [[3, big_stake]] + [[3, common_stake]] * common_count
    status('Announcing new elections')
    master_chain_state = e.get_chain_election(master_chain['wc_id'])
    assert eq(False, master_chain_state['open'])
    e.ticktock(False)  # announce_new_elections
    # Make master chain stakes
    master_chain['validators'] = make_stakes(configurations, e, master_chain['wc_id'])

    e.ticktock(False)  # chain -1 update active vset_id

    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(False, work_chain_state['open'])

    e.ticktock(False)  # chain 0 announce new election
    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(True, work_chain_state['open'])
    # Make master work_chain stakes
    work_chain['validators'] = make_stakes(configurations, e, work_chain['wc_id'])
    for chain in chains_array:
        wc_id = chain['wc_id']
        v = chain["validators"]

        chain["elect_id"] = decode_int(e.get_chain_election(wc_id)['elect_at'])
        elect_id = chain["elect_id"]
        assert eq(chain['elect_id'], e.active_election_id(wc_id))
        total_stake = decode_int(e.get_chain_election(wc_id)['total_stake'])
        status(green('total_stake: {}'.format(total_stake)))
        assert eq((big_stake + common_stake * common_count) * EVER, total_stake)
        status('Checking stake with bad signature')
        test_return_stake(1, elect_id, 0x10000, 11 * EVER, wc_id, bad_sign = True)
        status('Checking stake less than 1/4096 of total_stake')
        test_return_stake(2, elect_id, 0x10000, total_stake >> 12, wc_id)
        status('Checking stake with bad election id')
        test_return_stake(3, elect_id + 1, 0x10000, 11 * EVER, wc_id)
        status('Checking stake from another address using the same pubkey')
        test_return_stake_same_pubkey(v[0], elect_id, wc_id)
        status('Checking stake less than min_stake')
        test_return_stake(5, elect_id, 0x10000, 1 * EVER, wc_id)
        status('Checking stake with bad max factor')
        test_return_stake(6, elect_id, 0xffff, 11 * EVER, wc_id)
        status('Checking stake greater than max_stake')
        test_return_stake(7, elect_id, 0x10000, total_stake + EVER, wc_id)
        status('Checking simple transfer not from -1:00..0 address')
        test_return_simple_transfer(10 * EVER)


    #
    balance_before_conduct_elections = e.balance
    for chain in chains_array:
        wc_id = chain['wc_id']
        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
        status('Conducting elections')
        e.ticktock(False) # conduct_elections

    # it must be decreased because of new validator set was sent to config
    e.ensure_balance(balance_before_conduct_elections - (1 << 30) * len(chains_array))
    #
    for _ in chains_array:
        dispatch_one_message()  # elector: config.set_next_validator_set()
        set_config_param(100, c.get_config_param(100))

        dispatch_one_message()  # config: elector.config_set_confirmed_ok()

    #
    e.ensure_balance(balance_before_conduct_elections)
    for chain in chains_array:
        wc_id = chain['wc_id']
        assert eq(True, e.get_chain_election(wc_id)['open'])
    #
    status('Checking early stake recovery')
    for chain in chains_array:
        v = chain["validators"]

        for i in range(1 + common_count):
            orig_stake = common_stake if i != 0 else big_stake
            validator: Validator = v[i]

            balance = globals.G_DEFAULT_BALANCE - (orig_stake * GRAM)
            validator.ensure_balance(balance)

            query_id = generate_query_id()
            validator.recover(query_id)
            try:
                dispatch_one_message() # validator: elector.recover_stake()
            except Exception as err:
                print(i)
                raise translate_exception(err)

            dispatch_one_message() # elector: validator.error() or validator.receive_stake_back()
            state = validator.get()
            if i == 0:
                # not elected validator gets back complete refund
                assert eq(decode_int(query_id), decode_int(state['refund_query_id']))
                validator.ensure_balance(globals.G_DEFAULT_BALANCE - common_stake * max_factor * EVER)
            elif i < 7:
                # elected validator's stake is freezed
                assert eq(decode_int(query_id), decode_int(state['error_query_id']))
                validator.ensure_balance(balance)
            else:
                # not elected validator gets back complete refund
                assert eq(decode_int(query_id), decode_int(state['refund_query_id']))
                validator.ensure_balance(globals.G_DEFAULT_BALANCE)

    for chain in chains_array:
        wc_id = chain['wc_id']
        elect_id = chain["elect_id"]

        status('Installing next validator set')
        e.ticktock(False) # validator_set_installed
        e.ticktock(False)
        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])
        status('Checking stake after elections have finished')
        test_return_stake(0, elect_id, 0x10000, 10 * GRAM, wc_id)


    globals.time_shift(600) # this line is here to prevent replay protection failure with exit code 52
    #
    status('Checking next validator set')
    for chain in chains_array:
        wc_id = chain['wc_id']
        v = chain["validators"]
        elect_id = chain["elect_id"]

        vset = c.get_next_vset(wc_id)
        extra = None
        try:
            extra = vset['vdict']['7']
        except:
            extra = None
        assert eq(extra, None)

        for i in range(7):
            assert eq(decode_int(v[i].validator_pubkey),
                      decode_int(vset['vdict']['%d' % i]['pubkey']))

        time_set(decode_int(e.get_chain_past_elections(wc_id)['%d' % elect_id]['unfreeze_at']))

    status('Unfreezing the stakes')
    for chain in chains_array:
        e.ticktock(False) # check_unfreeze
    #
    e.ensure_balance(globals.G_DEFAULT_BALANCE + (common_stake * (max_factor + 6))*2 * EVER) # 2 * 3 + 2 * 6 + 100 grams of own funds

    status('Recovering the stakes')
    for chain in chains_array:
        wc_id = chain['wc_id']
        v = chain["validators"]
        for i in range(len(v)):
            wallet_addr = v[i].hex_addr
            assert eq(globals.G_DEFAULT_BALANCE - v[i].balance,
                        e.compute_returned_stake(wallet_addr))

            query_id = generate_query_id()
            v[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE)

    status('Triggering Config contract to update current vset')

    for chain in chains_array:
        wc_id = chain['wc_id']
        v = chain["validators"]
        c.ticktock(False)
        c.set_config_params()

        status('Checking current validator set')
        vset = c.get_current_vset(wc_id)
        for i in range(7):
            assert eq(decode_int(v[i].validator_pubkey),
                      decode_int(vset['vdict']['%d' % i]['pubkey']))

        e.ensure_balance(globals.G_DEFAULT_BALANCE)
        c.ensure_balance(globals.G_DEFAULT_BALANCE, True)
    #
    status('All done')

def test_thirty_validators():
    master_chain = dict(wc_id="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id="0", validators=[], elect_id=None)
    chains_array = [master_chain, work_chain]

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(max_validators=100, min_validators=13)
    e = deploy_elector()
    for wc in chains_array:
        c.add_new_wc(wc["wc_id"])

    status('Announcing new elections')
    master_chain_state = e.get_chain_election(master_chain['wc_id'])
    assert eq(False, master_chain_state['open'])
    e.ticktock(False)  # announce_new_elections
    # Make master chain stakes
    master_chain['validators'] = make_stakes(configurations, e, master_chain['wc_id'])

    e.ticktock(False)  # chain -1 update active vset_id

    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(False, work_chain_state['open'])

    e.ticktock(False)  # chain 0 announce new election
    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(True, work_chain_state['open'])
    # Make master work_chain stakes
    work_chain['validators'] = make_stakes(configurations, e, work_chain['wc_id'])
    for chain in chains_array:
        wc_id = chain['wc_id']

        chain["elect_id"] = decode_int(e.get_chain_election(wc_id)['elect_at'])

    status('Conducting elections')
    for chain in chains_array:
        wc_id = chain['wc_id']

        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
        e.ticktock(False) # conduct_elections

        assert eq(True, e.get_chain_election(wc_id)['open'])

    for _ in chains_array:
        dispatch_one_message()  # elector: config.set_next_validator_set()
        set_config_param(100, c.get_config_param(100))

        dispatch_one_message()  # config: elector.config_set_confirmed_ok()
        status('Installing next validator set')

        e.ticktock(False) # validator_set_installed


    for chain in chains_array:
        wc_id = chain['wc_id']
        v = chain["validators"]
        elect_id = chain["elect_id"]

        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])

        status('Checking next validator set')
        vset = c.get_next_vset(wc_id)
        elected = [20,  4,  5, 10, 16, 21, 27, 11, 29,  6,  8, 13, 14, 18, 26,
                   28,  0,  1,  2,  3,  7,  9, 12, 15, 17, 19, 22, 23, 24, 25]
        for i in range(len(elected)):
            assert eq(decode_int(v[elected[i]].validator_pubkey),
                      decode_int(vset['vdict']['%d' % i]['pubkey']))

        status('Collecting refunds due to max_factor clipping')
        globals.time_shift(600)  # this line is here to prevent replay protection failure with exit code 52

        min_stake = 10
        for i in range(total_count):

            validator  = v[i]
            orig_stake = configurations[i][1]
            max_factor = configurations[i][0]

            balance = globals.G_DEFAULT_BALANCE - (orig_stake * GRAM)
            validator.ensure_balance(balance)

            refund = orig_stake - max_factor * min_stake
            if refund > 0:
                query_id = generate_query_id()
                validator.recover(query_id)
                dispatch_one_message() # validator: elector.recover_stake()
                dispatch_one_message() # elector: validator.receive_stake_back()
                validator.ensure_balance(balance + refund * GRAM)

    # Move time to the last chain `unfreeze_at`
    time_set(decode_int(e.get_chain_past_elections(work_chain["wc_id"])['%d' % work_chain["elect_id"]]['unfreeze_at']))
    status('Unfreezing the stakes')

    for chain in chains_array:
        v = chain["validators"]
        e.ticktock(False) # check_unfreeze

        status('Recovering the stakes')
        for i in range(total_count):
            query_id = generate_query_id()
            v[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE)

    e.ensure_balance(globals.G_DEFAULT_BALANCE)
    c.ensure_balance(globals.G_DEFAULT_BALANCE, True)

    status('All done')

def test_insufficient_number_of_validators():
    master_chain = dict(wc_id="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id="0", validators=[], elect_id=None)
    chains_array = [master_chain, work_chain]

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(max_validators  = 100,
                      min_validators  = 21,
                      min_stake       = 9 * GRAM,
                      max_stake       = 50 * GRAM,
                      min_total_stake = 100 * GRAM)
    e = deploy_elector()

    for wc in chains_array:
        c.add_new_wc(wc["wc_id"])

    master_chain_state = e.get_chain_election(master_chain['wc_id'])
    assert eq(False, master_chain_state['open'])
    e.ticktock(False)  # announce_new_elections
    # Make master chain stakes
    master_chain['validators'] = make_stakes(configurations[:10], e, master_chain['wc_id'])

    e.ticktock(False)  # chain -1 update active vset_id

    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(False, work_chain_state['open'])

    e.ticktock(False)  # chain 0 announce new election
    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(True, work_chain_state['open'])
    # Make master work_chain stakes
    work_chain['validators'] = make_stakes(configurations[:10], e, work_chain['wc_id'])

    for chain in chains_array:
        wc_id = chain['wc_id']

        chain["elect_id"] = e.get_chain_election(wc_id)['elect_at']

        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))

        assert eq(False, e.get_chain_election(wc_id)['finished'])

    status('Trying to conduct elections for the first time')
    for chain in chains_array:

        e.ticktock(False)  # conduct_elections, validator_set_installed, update_active_vset_id

        wc_id = chain['wc_id']
        assert eq(False, e.get_chain_election(wc_id)['finished'])

    globals.time_shift(600)

    status('Trying to conduct elections for the second time')
    for chain in chains_array:
        wc_id = chain['wc_id']

        w = make_stakes(configurations[10:20], e, wc_id)
        chain["validators"] += w

        e.ticktock(False) # conduct_elections, validator_set_installed, update_active_vset_id

        assert eq(False, e.get_chain_election(wc_id)['finished'])

    globals.time_shift(600)

    status('Trying to conduct elections for the third time')
    for chain in chains_array:
        wc_id = chain['wc_id']
        w = make_stakes(configurations[20:], e, wc_id)
        chain["validators"] += w

    for chain in chains_array:
        e.ticktock(False)  # success conduct elections


    for _ in chains_array:
        dispatch_one_message()  # elector: config.set_next_validator_set()
        set_config_param(100, c.get_config_param(100))
        dispatch_one_message()  # config: elector.config_set_confirmed_ok()

    ensure_queue_empty()

    for chain in chains_array:
        wc_id = chain['wc_id']
        v = chain["validators"]

        time_of_elections = globals.time_get()


        assert eq(True, e.get_chain_election(wc_id)['open'])

        status('Installing next validator set')
        e.ticktock(False) # validator_set_installed

        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])

        status('Checking next validator set')
        vset = c.get_next_vset(wc_id)
        elected = [20,  4,  5, 10, 16, 21, 27, 11, 29,  6,  8, 13, 14, 18, 26,
                   28,  0,  1,  2,  3,  7,  9, 12, 15, 17, 19, 22, 23, 24, 25]
        for i in range(len(elected)):
            assert eq(decode_int(v[elected[i]].validator_pubkey),
                      decode_int(vset['vdict']['%d' % i]['pubkey']))

        status('Checking validator set validity period')
        assert eq(time_of_elections + c.elect_end_before - 60, decode_int(vset['utime_since']))
        assert eq(c.elect_for, decode_int(vset['utime_until']) - decode_int(vset['utime_since']))

    status('All done')
def test_insufficient_number_of_validators_in_one_chain():
    master_chain = dict(wc_id="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id="0", validators=[], elect_id=None)
    chains_array = [master_chain, work_chain]

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(max_validators  = 100,
                      min_validators  = 21,
                      min_stake       = 9 * GRAM,
                      max_stake       = 50 * GRAM,
                      min_total_stake = 100 * GRAM)
    e = deploy_elector()

    for wc in chains_array:
        c.add_new_wc(wc["wc_id"])

    master_chain_state = e.get_chain_election(master_chain['wc_id'])
    assert eq(False, master_chain_state['open'])
    e.ticktock(False)  # announce_new_elections
    # Make master chain stakes, only 10 validators
    master_chain['validators'] = make_stakes(configurations[:10], e, master_chain['wc_id'])

    e.ticktock(False)  # chain -1 update active vset_id

    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(False, work_chain_state['open'])

    e.ticktock(False)  # chain 0 announce new election
    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(True, work_chain_state['open'])
    # Make master work_chain stakes with all validators
    work_chain['validators'] = make_stakes(configurations, e, work_chain['wc_id'])

    for chain in chains_array:
        wc_id = chain['wc_id']

        chain["elect_id"] = e.get_chain_election(wc_id)['elect_at']

        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))

        assert eq(False, e.get_chain_election(wc_id)['finished'])

    status('Trying to conduct elections for the first time, master_chain will fail, wc_0 will success')
    e.ticktock(False)  # conduct_elections, validator_set_installed, update_active_vset_id

    assert eq(False, e.get_chain_election(master_chain["wc_id"])['finished'])
    assert eq(True, e.get_chain_election(work_chain["wc_id"])['finished'])

    status('Completing wc_0')

    dispatch_one_message()  # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message()  # config: elector.config_set_confirmed_ok()
    ensure_queue_empty()

    # globals.time_shift(600)

    wc_id = work_chain['wc_id']
    v = work_chain["validators"]

    time_of_elections = globals.time_get()

    assert eq(True, e.get_chain_election(wc_id)['open'])

    status('Installing next validator set')
    e.ticktock(False)  # validator_set_installed


    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    status('Checking next validator set')
    vset = c.get_next_vset(wc_id)
    elected = [20, 4, 5, 10, 16, 21, 27, 11, 29, 6, 8, 13, 14, 18, 26,
               28, 0, 1, 2, 3, 7, 9, 12, 15, 17, 19, 22, 23, 24, 25]
    for i in range(len(elected)):
        assert eq(decode_int(v[elected[i]].validator_pubkey),
                  decode_int(vset['vdict']['%d' % i]['pubkey']))

    status('Checking validator set validity period')
    assert eq(time_of_elections + c.elect_end_before, decode_int(vset['utime_since']))
    assert eq(c.elect_for, decode_int(vset['utime_until']) - decode_int(vset['utime_since']))


    status('Completing master_chain')
    globals.time_shift(600)
    master_chain['validators'] += make_stakes(configurations[10:], e, master_chain['wc_id'])
    e.ticktock(False)  # success conduct election for master_chain
    dispatch_one_message()  # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message()  # config: elector.config_set_confirmed_ok()
    ensure_queue_empty()

    master_chain_id = master_chain['wc_id']
    v = master_chain["validators"]

    time_of_elections = globals.time_get()

    assert eq(True, e.get_chain_election(master_chain_id)['open'])

    status('Installing next validator set')
    e.ticktock(False)  # validator_set_installed


    state = e.get_chain_election(master_chain_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    status('Checking next validator set')
    vset = c.get_next_vset(master_chain_id)
    elected = [20, 4, 5, 10, 16, 21, 27, 11, 29, 6, 8, 13, 14, 18, 26,
               28, 0, 1, 2, 3, 7, 9, 12, 15, 17, 19, 22, 23, 24, 25]
    for i in range(len(elected)):
        assert eq(decode_int(v[elected[i]].validator_pubkey),
                  decode_int(vset['vdict']['%d' % i]['pubkey']))

    status('Checking validator set validity period')
    assert eq(time_of_elections + c.elect_end_before - 60, decode_int(vset['utime_since']))
    assert eq(c.elect_for, decode_int(vset['utime_until']) - decode_int(vset['utime_since']))


def test_bonuses():
    master_chain = dict(wc_id="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id="0", validators=[], elect_id=None)
    chains_array = [master_chain, work_chain]

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(min_validators=13, max_validators=1000, min_stake=10 * EVER, max_stake=100 * EVER)
    e = deploy_elector()
    for wc in chains_array:
        c.add_new_wc(wc["wc_id"])
    configurations = [[3, 50]] * 13

    status('Announcing new elections')
    master_chain_state = e.get_chain_election(master_chain['wc_id'])
    assert eq(False, master_chain_state['open'])
    e.ticktock(False)  # announce_new_elections
    # Make master chain stakes
    master_chain['validators'] = make_stakes(configurations, e, master_chain['wc_id'])

    e.ticktock(False)  # chain -1 update active vset_id

    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(False, work_chain_state['open'])

    e.ticktock(False)  # chain 0 announce new election
    work_chain_state = e.get_chain_election(work_chain['wc_id'])
    assert eq(True, work_chain_state['open'])
    # Make master work_chain stakes
    work_chain['validators'] = make_stakes(configurations, e, work_chain['wc_id'])
    for chain in chains_array:
        wc_id = chain['wc_id']
        chain["elect_id"] = decode_int(e.get_chain_election(wc_id)['elect_at'])


    status('Conducting elections')
    for chain in chains_array:
        wc_id = chain['wc_id']

        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
        e.ticktock(False)  # conduct_elections
        assert eq(True, e.get_chain_election(wc_id)['open'])


    for _ in chains_array:
        dispatch_one_message()  # elector: config.set_next_validator_set()

    set_config_param(100, c.get_config_param(100))

    for chain in chains_array:
        wc_id = chain['wc_id']

        dispatch_one_message()  # config: elector.config_set_confirmed_ok()
        assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))

    for _ in chains_array:
        e.ticktock(False) # validator_set_installed

    set_config_param(100, c.get_config_param(100))

    ensure_queue_empty()
    e.ensure_balance(globals.G_DEFAULT_BALANCE + 650 * len(chains_array) * GRAM)  # 650 grams of stake + 100 grams of own funds
    time_set(decode_int(c.get_current_vset(work_chain["wc_id"])['utime_until']) - c.elect_begin_before)
    for chain in chains_array:
        wc_id = chain['wc_id']

        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])

        configurations = [[3, 20]] * 13
        make_elections(configurations, e, wc_id)

        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
        status('Conducting elections')
        e.ticktock(False) # conduct_elections

    z = Zero()
    for chain in chains_array:
        wc_id = chain['wc_id']

        z.grant_to_chain(50 * GRAM, wc_id)
        dispatch_one_message()


        set_config_param(100, c.get_config_param(100))
        dispatch_one_message() # config: elector.config_set_confirmed_ok()

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))

    for chain in chains_array:
        wc_id = chain['wc_id']

        assert eq(True, e.get_chain_election(wc_id)['open'])
        status('Installing next validator set')

        e.ticktock(False) # validator_set_installed

        assert eq(False, e.get_chain_election(wc_id)['open'])

        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])


    e.ensure_balance(globals.G_DEFAULT_BALANCE  + (960 * 2 ) * GRAM) # 910 grams of stake + 100 grams of own funds + 100 grams of bonuses

    time_set(decode_int(e.get_chain_past_elections(master_chain["wc_id"])['%d' % master_chain["elect_id"]]['unfreeze_at']))
    ensure_queue_empty()
    for chain in chains_array:
        v = chain["validators"]
        status('Unfreezing the stakes')
        e.ticktock(False)
        e.ticktock(False)

        status('Recovering the stakes from elections #1')
        for i in range(13):
            query_id = generate_query_id()
            v[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE + int((50 / 13) * GRAM))

    status('All done')

def test_reset_utime_until():
    master_chain = dict(wc_id ="-1", validators=[], elect_id=None)
    work_chain = dict(wc_id ="0", validators=[], elect_id=None)
    chains_array = [master_chain, work_chain]

    (showtime, e, c) = test_identical_validators_1()
    dispatch_one_message()
    status('Announcing new elections #1')
    for chain in chains_array:
        wc_id = chain['wc_id']

        e.ticktock(False) # announce_new_elections
        e.ticktock(False)
        state = e.get_chain_election(wc_id)
        assert eq(True, state['open'])

    time_set(decode_int(e.get_chain_election(master_chain["wc_id"])['elect_close']))

    for chain in chains_array:
        wc_id = chain['wc_id']
        chain["validators"] = make_stakes([(3.0, 40)] * 6, e, wc_id)


    status('Conducting elections')
    for _ in chains_array:
        e.ticktock(False) # conduct_elections

    for _ in chains_array:
        dispatch_one_message()  # elector: config.set_next_validator_set()

    set_config_param(100, c.get_config_param(100))
    for chain in chains_array:
        wc_id = chain['wc_id']

        dispatch_one_message()  # config: elector.config_set_confirmed_ok()
        assert eq(True, e.get_chain_election(wc_id)['open'])



    globals.time_shift(c.elect_end_before)
    c.ticktock(False)

    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')

    for chain in chains_array:
        wc_id = chain['wc_id']

        e.ticktock(False) # validator_set_installed

        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 240 * 2 * GRAM) # 240 grams of stake + 100 grams of own funds

    globals.time_shift(10000)
    status('Resetting utime_until')
    c.reset_utime_until()
    set_config_param(100, c.get_config_param(100))


    status('Announcing new out-of-order elections #2')
    for _ in chains_array:
        e.ticktock(False) # announce_new_elections

    for chain in chains_array:
        wc_id = chain['wc_id']
        v = chain['validators']
        state = e.get_chain_election(wc_id)
        assert eq(True, e.get_chain_election(wc_id)['open'])
        chain["elect_id"] = state['elect_at']


        status('Recovering the stakes from elections #1')
        stakes1 = [40, 40, 40, 0, 0, 0]
        for i in range(6):
            query_id = generate_query_id()
            v[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes1[i] * GRAM)

        stakes2 = [80, 80, 80, 40, 40, 40]
        for i in range(6):
            stake(chain["elect_id"], 0x30000, 40 * GRAM, wc_id, v[i])
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes2[i] * GRAM)


    time_set(decode_int(e.get_chain_election(work_chain["wc_id"])['elect_close']))
    status('Conducting elections')
    for _ in chains_array:
        e.ticktock(False) # conduct_elections

    for _ in chains_array:
        dispatch_one_message() # elector: config.set_next_validator_set()

    set_config_param(100, c.get_config_param(100))
    for chain in chains_array:
        wc_id = chain['wc_id']
        dispatch_one_message()  # config: elector.config_set_confirmed_ok()
        assert eq(True, e.get_chain_election(wc_id)['open'])



    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    for _ in chains_array:
        e.ticktock(False) # validator_set_installed

    for chain in chains_array:
        wc_id = chain['wc_id']
        elect_id = "%s" % chain["elect_id"]
        assert eq(False, e.get_chain_election(wc_id)['open'])
        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])
        time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))

    e.ensure_balance(globals.G_DEFAULT_BALANCE + (120*2 + 240*2) * GRAM)
    status('Unfreezing the stakes')
    for _ in chains_array:
        e.ticktock(False) # announce_new_elections, check_unfreeze
        e.ticktock(False) # announce_new_elections, check_unfreeze


    for chain in chains_array:
        v = chain["validators"]
        stakes3 = [40, 40, 40, 0, 0, 0]
        status('Recovering the stakes from elections #2')
        for i in range(6):
            query_id = generate_query_id()
            v[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes3[i] * GRAM)

    status('All done')

def test_ban():
    (e, c, chains_array) = deploy_network(5, 3, 2, ["-1","0"])

    for chain in chains_array:
        wc_id = chain["wc_id"]
        chain["elect_id"] = e.get_chain(wc_id)['active_id']
    e.ticktock(False)

    status('Banning one validator')
    for chain in chains_array:
        v = chain["validators"]
        wc_id = chain["wc_id"]

        victim_idx = 2
        victim_pubkey = v[victim_idx].validator_pubkey
        chain['victim_pubkey'] = victim_pubkey
        assert eq(decode_int(victim_pubkey),
                  decode_int(c.get_current_vset(wc_id)['vdict'][str(victim_idx)]['pubkey']))
        for i in range(4):
            signature = v[i].report_signature(victim_pubkey, 13)
            e.report(
                '0x' + signature[:64],
                '0x' + signature[64:],
                v[i].validator_pubkey,
                victim_pubkey,
                13,
                wc_id
            )


    banned = e.get_banned()
    assert isinstance(banned, dict)
    assert eq(len(chains_array), len(banned))
    assert eq(Cell(EMPTY_CELL), c.get_config_param(35))

    for _ in chains_array:
        dispatch_one_message(src=e, dst=c)  # elector: config.set_slashed_validator_set()
        c.set_config_params() # todo check it

    # dispatch_one_message()
    for _ in chains_array:
        dispatch_one_message(src=c, dst=e)  # config: elector.config_slash_confirmed_ok()
    set_config_param(100, c.get_config_param(100))

    globals.time_shift(600)

    for chain in chains_array:
        wc_id = chain["wc_id"]
        vset = c.get_current_vset(wc_id)
        assert ne(Cell(EMPTY_CELL), vset)

    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))

    # dispatch_one_message()
    c.set_config_params()
    ensure_queue_empty()
    for chain in chains_array:
        wc_id = chain["wc_id"]
        victim_pubkey = chain['victim_pubkey']
        status('Checking current validator set after ban')
        vdict = c.get_current_vset(wc_id)['vdict']
        for i in range(len(vdict)):
            pubkey = vdict['%d' % i]['pubkey']
            assert decode_int(victim_pubkey) != decode_int(pubkey)


    time_set(decode_int(e.get_chain_past_elections(chains_array[0]["wc_id"])[chains_array[0]["elect_id"]]['unfreeze_at']))
    configurations = [[3, 35]] * 6
    for chain in chains_array:
        wc_id = chain["wc_id"]
        make_elections(configurations, e, wc_id)
        print("end of elect", decode_int(e.get_chain_election(wc_id)['elect_close']))
        time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
        e.ticktock(False)  # conduct_elections
        assert eq(True, e.get_chain_election(wc_id)['open'])

    dispatch_one_message()  # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message()  # config: elector.config_set_confirmed_ok()


    globals.time_shift(c.elect_end_before)

    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    for chain in chains_array:
        wc_id = chain["wc_id"]

        e.ticktock(False) # validator_set_installed

        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 450 * len(chains_array) * GRAM) # 450 grams of stake + 100 grams of own funds

    time_set(decode_int(e.get_chain_past_elections(chains_array[1]["wc_id"])[chains_array[1]["elect_id"]]['unfreeze_at']))

    status('Announce and Unfreezing the stakes')
    for _ in chains_array:
        e.ticktock(False)
        e.ticktock(False)

    status('Recovering the stakes')
    for chain in chains_array:
        v = chain["validators"]
        for i in range(6):
            query_id = generate_query_id()
            v[i].recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            if i < 2:
                exp_balance = globals.G_DEFAULT_BALANCE + 10 * EVER
            elif i == 2:
                exp_balance = globals.G_DEFAULT_BALANCE - 40 * EVER
            elif i < 5:
                exp_balance = globals.G_DEFAULT_BALANCE + 10 * EVER
            else:
                exp_balance = globals.G_DEFAULT_BALANCE
            v[i].ensure_balance(exp_balance)

    status('All done')



# test_identical_validators()
# test_seven_validators()
# test_rich_validator()
# test_thirty_validators()
# test_insufficient_number_of_validators()
# test_insufficient_number_of_validators_in_one_chain()
# test_bonuses()
# test_reset_utime_until()
test_ban()