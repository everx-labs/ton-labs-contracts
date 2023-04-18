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



    chains_array = [master_chain, work_chain]

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



test_identical_validators()
test_seven_validators()