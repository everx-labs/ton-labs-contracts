#!/usr/bin/env python3

"""
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2023 (c) EverX
"""
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










#######################################################

def test_return_stake(ec, stake_at, max_factor, value, bad_sign = False):
    wc_id = "0"

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

def test_return_stake_same_pubkey(v, stake_at):
    wc_id = "0"


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

def test_return_simple_transfer(value):
    v = Validator()
    v.transfer(value)
    dispatch_one_message()
    v.ensure_balance(globals.G_DEFAULT_BALANCE - value)
    dispatch_one_message()
    v.ensure_balance(globals.G_DEFAULT_BALANCE)

configurations = [
    (2.0, 10), (2.0, 10), (3.0, 10), (3.0, 10), (3.0, 40),
    (3.0, 40), (2.0, 20), (3.0, 10), (2.0, 20), (2.0, 10),
    (2.0, 40), (3.0, 30), (3.0, 10), (3.0, 20), (2.0, 20),
    (2.0, 10), (2.0, 40), (3.0, 10), (2.0, 20), (2.0, 10),
    (3.0, 50), (3.0, 40), (3.0, 10), (3.0, 10), (3.0, 10),
    (2.0, 10), (3.0, 20), (3.0, 40), (3.0, 20), (3.0, 30)]

total_count = len(configurations)

def test_seven_validators():
    wc_id = "0"

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config()
    e = deploy_elector()
    c.add_new_wc("0")

    v = make_elections(configurations, e, wc_id)
    elect_id = decode_int(e.get_chain_election(wc_id)['elect_at'])

    total_stake = decode_int(e.get_chain_election(wc_id)['total_stake'])
    status(green('total_stake: {}'.format(total_stake)))
    assert eq(globals.G_DEFAULT_BALANCE + 530 * EVER, total_stake)

    status('Checking stake with bad signature')
    test_return_stake(1, elect_id, 0x10000, 11 * EVER, bad_sign = True)

    status('Checking stake with bad signature')
    test_return_stake(1, elect_id, 0x10000, 11 * EVER, bad_sign = True)
    status('Checking stake less than 1/4096 of total_stake')
    test_return_stake(2, elect_id, 0x10000, total_stake >> 12)

    status('Checking stake less than 1/4096 of total_stake')
    total_stake = decode_int(e.get_chain_election(wc_id)['total_stake'])
    test_return_stake(2, elect_id, 0x10000, ((total_stake + 1) >> 12))
    status('Checking stake with bad election id')
    test_return_stake(3, elect_id + 1, 0x10000, 11 * EVER)
    status('Checking stake from another address using the same pubkey')
    test_return_stake_same_pubkey(v[0], elect_id)
    status('Checking stake less than min_stake')
    test_return_stake(5, elect_id, 0x10000, 1 * EVER)
    status('Checking stake with bad max factor')
    test_return_stake(6, elect_id, 0xffff, 11 * EVER)
    status('Checking stake greater than max_stake')
    test_return_stake(7, elect_id, 0x10000, 60 * EVER)
    status('Checking simple transfer not from -1:00..0 address')
    test_return_simple_transfer(10 * EVER)

    conduct_elections(c, e, len(configurations), wc_id)

    elected = [20, 4, 5, 10, 16, 21, 27]
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
    test_return_stake(0, elect_id, 0x10000, 11 * EVER)
    globals.time_shift(600) # this line is here to prevent replay protection failure with exit code 52

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
    status('Unfreezing the stakes')
    e.ticktock(False) # check_unfreeze
    ensure_queue_empty()
    e.ensure_balance(globals.G_DEFAULT_BALANCE + 290 * EVER) # 290 evers of stake + 100 evers of own funds

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

    e.ensure_balance(globals.G_DEFAULT_BALANCE)
    c.ensure_balance(globals.G_DEFAULT_BALANCE, True)

    status('All done')

def test_rich_validator():
    wc_id = "0"
    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config()
    e = deploy_elector()
    c.add_new_wc("0")

    big_stake = 50
    common_stake = 2
    max_factor = 3
    common_count = 14
    configurations = [[3, big_stake]] + [[3, common_stake]] * common_count
    v = make_elections(configurations, e, wc_id)

    elect_id = decode_int(e.get_chain_election(wc_id)['elect_at'])
    assert eq(elect_id, e.active_election_id(wc_id))

    total_stake = decode_int(e.get_chain_election(wc_id)['total_stake'])
    status(green('total_stake: {}'.format(total_stake)))
    assert eq((big_stake + common_stake * common_count) * EVER, total_stake)

    status('Checking stake with bad signature')
    test_return_stake(1, elect_id, 0x10000, 11 * EVER, bad_sign = True)
    status('Checking stake less than 1/4096 of total_stake')
    test_return_stake(2, elect_id, 0x10000, total_stake >> 12)
    status('Checking stake with bad election id')
    test_return_stake(3, elect_id + 1, 0x10000, 11 * EVER)
    status('Checking stake from another address using the same pubkey')
    test_return_stake_same_pubkey(v[0], elect_id)
    status('Checking stake less than min_stake')
    test_return_stake(5, elect_id, 0x10000, 1 * EVER)
    status('Checking stake with bad max factor')
    test_return_stake(6, elect_id, 0xffff, 11 * EVER)
    status('Checking stake greater than max_stake')
    test_return_stake(7, elect_id, 0x10000, total_stake + EVER)
    status('Checking simple transfer not from -1:00..0 address')
    test_return_simple_transfer(10 * EVER)

    balance_before_conduct_elections = e.balance

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    # it must be decreased because of new validator set was sent to config
    e.ensure_balance(balance_before_conduct_elections - (1 << 30))

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))

    dispatch_one_message() # config: elector.config_set_confirmed_ok()

    e.ensure_balance(balance_before_conduct_elections)
    assert eq(True, e.get_chain_election(wc_id)['open'])

    status('Checking early stake recovery')
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

    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed
    e.ticktock(False)

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    status('Checking stake after elections have finished')
    test_return_stake(0, elect_id, 0x10000, 10 * GRAM)
    globals.time_shift(600) # this line is here to prevent replay protection failure with exit code 52

    status('Checking next validator set')
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
    e.ticktock(False) # check_unfreeze

    e.ensure_balance(globals.G_DEFAULT_BALANCE + (common_stake * (max_factor + 6)) * EVER) # 2 * 3 + 2 * 6 + 100 grams of own funds

    status('Recovering the stakes')
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
    c.ticktock(False)
    c.set_config_params()

    status('Checking current validator set')
    vset = c.get_current_vset(wc_id)
    for i in range(7):
        assert eq(decode_int(v[i].validator_pubkey),
                  decode_int(vset['vdict']['%d' % i]['pubkey']))

    e.ensure_balance(globals.G_DEFAULT_BALANCE)
    c.ensure_balance(globals.G_DEFAULT_BALANCE, True)

    status('All done')

def test_thirty_validators():
    wc_id = "0"

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(max_validators=100, min_validators=13)
    e = deploy_elector()
    c.add_new_wc("0")
    v = make_elections(configurations, e, wc_id)
    elect_id = e.get_chain_election(wc_id)['elect_at']

    status('Conducting elections')
    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()

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

    status('Collecting refunds due to max_factor clipping')
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

    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))
    status('Unfreezing the stakes')
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
    wc_id = "0"

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(max_validators  = 100,
                      min_validators  = 21,
                      min_stake       = 9 * GRAM,
                      max_stake       = 50 * GRAM,
                      min_total_stake = 100 * GRAM)
    e = deploy_elector()
    c.add_new_wc("0")

    v = make_elections(configurations[:10], e, wc_id)
    elect_id = e.get_chain_election(wc_id)['elect_at']

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Trying to conduct elections for the first time')
    e.ticktock(False) # conduct_elections, validator_set_installed, update_active_vset_id
    assert eq(False, e.get_chain_election(wc_id)['finished'])

    w = make_stakes(configurations[10:20], e, wc_id)
    v += w

    globals.time_shift(600)
    status('Trying to conduct elections for the second time')
    e.ticktock(False) # conduct_elections, validator_set_installed, update_active_vset_id
    assert eq(False, e.get_chain_election(wc_id)['finished'])
    # e.ticktock(False) # conduct_elections, validator_set_installed, update_active_vset_id
    # assert eq(False, e.get_chain_election(wc_id)['finished'])

    w = make_stakes(configurations[20:], e, wc_id)
    v += w

    globals.time_shift(600)
    status('Trying to conduct elections for the third time')
    time_of_elections = globals.time_get()
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()

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

def test_bonuses():
    wc_id = "0"

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(min_validators=13, max_validators=1000, min_stake=10 * EVER, max_stake=100 * EVER)
    e = deploy_elector()
    c.add_new_wc("0")
    configurations = [[3, 50]] * 13
    v = make_elections(configurations, e, wc_id)

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 650 * GRAM) # 650 grams of stake + 100 grams of own funds

    time_set(decode_int(c.get_current_vset(wc_id)['utime_until']) - c.elect_begin_before)
    configurations = [[3, 20]] * 13
    make_elections(configurations, e, wc_id)
    elect_id = e.get_chain_election(wc_id)['elect_at']

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    z = Zero()
    # set_trace_tvm(True)
    z.grant_to_chain(100 * GRAM, wc_id)
    dispatch_one_message()

    dispatch_one_message() # elector: config.set_next_validator_set()

    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    # dispatch_one_message()
    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)

    set_config_param(100, c.get_config_param(100))

    status('Installing next validator set')


    e.ticktock(False) # validator_set_installed

    assert eq(False, e.get_chain_election(wc_id)['open'])

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])


    e.ensure_balance(globals.G_DEFAULT_BALANCE + 1010 * GRAM) # 910 grams of stake + 100 grams of own funds + 100 grams of bonuses

    print(elect_id, e.get_chain_past_elections(wc_id))
    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))
    status('Unfreezing the stakes')
    e.ticktock(False)
    e.ticktock(False)

    status('Recovering the stakes from elections #1')
    for i in range(13):
        query_id = generate_query_id()
        v[i].recover(query_id)
        dispatch_one_message() # validator: elector.recover_stake()
        dispatch_one_message() # elector: validator.receive_stake_back()
        v[i].ensure_balance(globals.G_DEFAULT_BALANCE + int((100 / 13) * GRAM))

    status('All done')

def test_identical_validators_1():
    wc_id = "0"

    globals.reset()
    showtime = 86400
    time_set(showtime)

    keypair = make_keypair()
    c = deploy_config(max_validators = 3, keypair = keypair)

    c.set_config_params()
    e = deploy_elector()
    c.add_new_wc("0")

    c.set_config_params()

    return (showtime, e, c)


def test_identical_validators_2(showtime, e: Elector, c: Config):
    wc_id = "0"

    configurations = [[3, 40]] * 6
    v = make_elections(configurations, e, wc_id)

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()


    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)

    set_config_param(100, c.get_config_param(100))

    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 240 * GRAM) # 240 grams of stake + 100 grams of own funds

    time_set(decode_int(c.get_current_vset(wc_id)['utime_until']) - c.elect_begin_before)

    status('Announcing new elections #2')
    e.ticktock(False) # announce_new_elections

    state = e.get_chain_election(wc_id)
    assert eq(True, state['open'])
    elect_id = state['elect_at']

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
        stake(elect_id, 0x30000, 40 * GRAM,wc_id, v[i])
        v[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes2[i] * GRAM)

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)

    set_config_param(100, c.get_config_param(100))

    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed
    assert eq(False, e.get_chain_election(wc_id)['open'])

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + (120 + 240) * GRAM)

    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))
    status('Unfreezing the stakes')
    e.ticktock(False)
    e.ticktock(False)


    stakes3 = [40, 40, 40, 0, 0, 0]
    status('Recovering the stakes from elections #1')
    # set_trace_tvm(True)
    print(e.get_chain_election(wc_id))

    for i in range(6):
        print(i)
        query_id = generate_query_id()
        v[i].recover(query_id)
        dispatch_one_message() # validator: elector.recover_stake()
        dispatch_one_message() # elector: validator.receive_stake_back()
        v[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes3[i] * GRAM)

    status('All done')

def test_identical_validators():
    (showtime, e, c) = test_identical_validators_1()
    c.set_config_params()
    test_identical_validators_2(showtime, e, c)

def test_elector_code_upgrade():
    (showtime, e, c) = test_identical_validators_1()

    status('Testing setcode functionality')
    name = 'Elector.tvc'
    code = load_code_cell(name)
    c.set_elector_code(code, Cell(EMPTY_CELL))
    dispatch_one_message() # config: elector.upgrade_code()
    dispatch_one_message() # elector: config.setcode_confirmation()

    test_identical_validators_2(showtime, e, c)

def prepare_change_code_messages(msg_seqno):
    # u_c.boc
    # u_e.json
    # Config.abi.json
    # config-master.addr  - binary 0x3333...
    # config-master.pk    - binary secret key
    # config-master.json  - secret and public keys

    # first check hashes of contracts in blockchain and correct them in Elector.sol and Config.sol
    # check network capability 0x400 - GlobalCapabilities::CapMycode
    # prepare key files
    # copy Config.abi.json and Elector.abi.json
    # tonos-cli runget -1:5555555555555555555555555555555555555555555555555555555555555555 seqno
    # python test_elector.py
    # copy u_c.boc and u_e.json
    # tonos-cli sendfile u_c.boc
    # tonos-cli call --abi Config.abi.json --sign config-master.json -1:5555555555555555555555555555555555555555555555555555555555555555 set_elector_code u_e.json

    globals.reset()
    curtime = int(time.time())
    time_set(curtime)

    # input parameters
    private_key = "18ba321b20fd6df7e317623b7109bc0c30717d783a2ad54407dc116ff614cfcfd189e68c5465891838ef026302f97e28127a8bf72f6bf494991fe8c12e466180"
    pubkey = "d189e68c5465891838ef026302f97e28127a8bf72f6bf494991fe8c12e466180"
    keypair = (private_key, pubkey)
    valid_until = globals.time_get() + 1800

    name = 'Config.Update.tvc'
    code = load_code_cell(name)

    c = deploy_config(curtime, keypair)
    e = deploy_elector()

    cell = c.call_getter("upgrade_old_config_code_sign_helper", dict(
        msg_seqno = msg_seqno,
        valid_until = valid_until,
        code = code
    ))
    assert isinstance(cell, Cell)
    signature = sign_cell_hash(cell, private_key)

    cell = c.call_getter("upgrade_old_config_code_message_builder", dict(
        signature = signature,
        msg_seqno = msg_seqno,
        valid_until = valid_until,
        code = code
    ))
    assert isinstance(cell, Cell)
    msg = cell.raw_

    print("config code upgrade message")

    file = open("u_c.boc", "wb")
    data = base64.b64decode(msg)
    file.write(data)

    # Elector update

    name = 'Elector.Update.tvc'
    code = load_code_cell(name)
    params = '{{"code": "{}", "data": "{}"}}'.format(code, EMPTY_CELL)
    file = open("u_e.json", "w")
    file.write(params)
    print(
        'tonos-cli call --abi Config.abi.json --sign config_master.json',
        '-1:5555555555555555555555555555555555555555555555555555555555555555 set_elector_code u_e.json'
    )
    c.set_elector_code(code, Cell(EMPTY_CELL))

def test_old_config_code_upgrade():
    globals.reset()
    showtime = 86400
    time_set(showtime)

    status('Loading old config contract')
    private_key = "18ba321b20fd6df7e317623b7109bc0c30717d783a2ad54407dc116ff614cfcfd189e68c5465891838ef026302f97e28127a8bf72f6bf494991fe8c12e466180"
    old_c = BaseContract('Config.FunC', address = Address("-1:00" + "5" * 62))

    status('Testing setcode functionality')
    name = 'Config.Update.tvc'
    code = load_code_cell(name)
    msg_seqno = old_c.run_get("seqno")
    assert eq(0, msg_seqno)

    c = deploy_config()
    e = deploy_elector()
    v = Validator()

    cell = v.call_getter("upgrade_old_config_code_sign_helper", dict(
        msg_seqno = msg_seqno,
        valid_until = globals.time_get() + 1,
        code = code
    ))
    assert isinstance(cell, Cell)
    signature = sign_cell_hash(cell, private_key)

    cell = v.call_getter("upgrade_old_config_code_message_builder", dict(
        config_addr = old_c.hex_addr,
        signature = signature,
        msg_seqno = msg_seqno,
        valid_until = globals.time_get() + 1,
        code = code
    ))
    assert isinstance(cell, Cell)
    old_c.send_external_raw(cell)

    status('Config contract code is updated')

    old_c.ensure_balance(10000000000)

    status('Testing functionality after setcode')
    assert eq(0, old_c.call_getter('seqno')) # it is not working in new contract

    cell = old_c.call_getter("get_config_param", dict(index = 0))
    assert isinstance(cell, Cell)
    assert ne(Cell(EMPTY_CELL), cell)
    print(cell.raw_)
    # 55555555...
    assert eq(Cell("te6ccgEBAQEAIgAAQFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV"), cell)

    cell = old_c.call_getter("get_config_param", dict(index = 1))
    assert isinstance(cell, Cell)
    # 33333333...
    assert eq(Cell("te6ccgEBAQEAIgAAQDMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMz"), cell)

def old_elector_code_upgrade(time):
    globals.reset()
    showtime = 86400
    time_set(showtime)

    status('Testing elector code upgrade')

    old_e = BaseContract("Elector.FunC." + str(time), address = Address("-1:" + '3'*64))

    status('Setting config parameters')
    private_key = "18ba321b20fd6df7e317623b7109bc0c30717d783a2ad54407dc116ff614cfcfd189e68c5465891838ef026302f97e28127a8bf72f6bf494991fe8c12e466180"
    pubkey = "d189e68c5465891838ef026302f97e28127a8bf72f6bf494991fe8c12e466180"
    keypair = (private_key, pubkey)
    c = deploy_config(keypair = keypair, capabilities=0x42e)

    assert eq(94777034586717610846728020300470945782230364141182765844873697605755565662592, c.call_getter('public_key'))
    assert eq(0, c.call_getter('seqno'))

    name = 'Elector.Update.tvc'
    code = load_code_cell(name)
    c.set_elector_code(code, Cell(EMPTY_CELL))

    dispatch_one_message() # config: elector.upgrade_code()
    dispatch_one_message() # elector: config.setcode_confirmation()

    state = old_e.call_getter_raw('get')
    assert eq(time != 0, state['election_open'])
    elect_id = old_e.call_getter('active_election_id')
    assert eq(time, int(elect_id))

def test_old_elector_code_upgrade():
    old_elector_code_upgrade(0)
    old_elector_code_upgrade(1679637526)

def vote_for_complaint(k: Validator, idx, elect_id, chash):
    query_id = decode_int(generate_query_id())
    cell = k.vote_sign_helper(idx, elect_id, chash)
    assert isinstance(cell, Cell)
    signature = sign_cell(cell, k.private_key)
    assert eq(128, len(signature))
    k.vote(query_id, '0x' + signature[:64], '0x' + signature[64:], idx, elect_id, chash)
    dispatch_one_message() # validator: elector.proceed_register_vote()
    dispatch_one_message() # elector: validator.complain_answer()
    return decode_int(k.get()['complain_answers']['%d' % query_id])

def test_complaints():
    globals.reset()
    showtime = 86400

    globals.time_shift(600)

    c = deploy_config()
    e = deploy_elector()

    time_set(showtime)

    configurations = [[3, 50]] * 13
    v = make_elections(configurations, e)

    time_set(decode_int(e.get()['cur_elect']['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(36, c.get_config_param(36))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get()['election_open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(34, c.get_config_param(34))
    set_config_param(36, c.get_config_param(36))

    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    assert eq(False, e.get()['election_open'])
    assert eq(False, e.get()['cur_elect']['failed'])
    assert eq(False, e.get()['cur_elect']['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 650 * GRAM) # 650 grams of stake + 100 grams of own funds

    time_set(decode_int(c.get_current_vset()['utime_until']) - c.elect_begin_before)

    w = make_elections(configurations, e)
    elect_id2 = e.elect_id

    time_set(decode_int(e.get()['cur_elect']['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(36, c.get_config_param(36))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get()['election_open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(34, c.get_config_param(34))
    set_config_param(36, c.get_config_param(36))

    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    assert eq(False, e.get()['election_open'])
    assert eq(False, e.get()['cur_elect']['failed'])
    assert eq(False, e.get()['cur_elect']['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 1300 * GRAM) # 1300 grams of stake + 100 grams of own funds

    globals.time_shift(10000)
    status('Registering a complaint')

    victim         = 0
    complainer     = 12
    payment        = 5 * GRAM
    suggested_fine = 50 * GRAM

    query_id = decode_int(generate_query_id())
    v[complainer].complain(query_id, elect_id2, v[victim].validator_pubkey, payment, suggested_fine)
    dispatch_one_message() # complainer: elector.register_complaint()
    dispatch_one_message() # elector: complainer.complain_answer()
    assert eq(0, decode_int(v[complainer].get()['complain_answers']['%d' % query_id]))

    status('Voting for the complaint')
    complaints_hashes = list(e.get()['past_elections'][elect_id2]['complaints'].keys())
    chash = complaints_hashes[0]
    ec = 100
    for idx in range(4, 13):
        print(idx)
        globals.time_shift()
        ec = vote_for_complaint(v[idx], idx, elect_id2, chash)
        assert ec == 1 or (ec == 2 and idx == 12)
    assert ec == 2

    time_set(decode_int(c.get_current_vset()['utime_until']) - c.elect_begin_before)

    w = make_elections(configurations, e)
    elect_id3 = e.elect_id

    time_set(decode_int(e.get()['cur_elect']['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(36, c.get_config_param(36))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get()['election_open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(34, c.get_config_param(34))
    set_config_param(36, c.get_config_param(36))

    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    assert eq(False, e.get()['election_open'])
    assert eq(False, e.get()['cur_elect']['failed'])
    assert eq(False, e.get()['cur_elect']['finished'])

    if False: # elector_func:
        price = 1_378_920_448
    else:
        price = 1_277_194_240
    e.ensure_balance(globals.G_DEFAULT_BALANCE + 1950 * GRAM + price) # 1950 grams of stake + 100 grams of own funds
                                          # + complaint price

    time_set(decode_int(e.get()['past_elections'][elect_id3]['unfreeze_at']))
    status('Unfreezing the stakes')
    e.ticktock(False)
    e.ticktock(False)
    e.ticktock(False)

    status('Recovering the stakes')
    for i in range(13):
        query_id = generate_query_id()
        v[i].recover(query_id)
        dispatch_one_message() # validator: elector.recover_stake()
        dispatch_one_message() # elector: validator.receive_stake_back()
        if i == victim:
            balance = globals.G_DEFAULT_BALANCE - suggested_fine
        elif i == complainer:
            balance = globals.G_DEFAULT_BALANCE - price + (suggested_fine / 8)
        else:
            balance = globals.G_DEFAULT_BALANCE
        v[i].ensure_balance(balance)

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 1300 * GRAM + (suggested_fine / 8 * 7) + price)

    status('All done')

def test_reset_utime_until():
    wc_id = "0"

    (showtime, e, c) = test_identical_validators_1()

    status('Announcing new elections #1')
    e.ticktock(False) # announce_new_elections
    state = e.get_chain_election(wc_id)
    assert eq(True, state['open'])

    v = make_stakes([(3.0, 40)] * 6, e, wc_id)

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 240 * GRAM) # 240 grams of stake + 100 grams of own funds

    globals.time_shift(10000)
    status('Resetting utime_until')
    c.reset_utime_until()
    set_config_param(100, c.get_config_param(100))


    status('Announcing new out-of-order elections #2')
    e.ticktock(False) # announce_new_elections

    state = e.get_chain_election(wc_id)
    assert eq(True, e.get_chain_election(wc_id)['open'])
    elect_id = state['elect_at']

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
        stake(elect_id, 0x30000, 40 * GRAM, wc_id, v[i])
        v[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes2[i] * GRAM)

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))

    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed
    assert eq(False, e.get_chain_election(wc_id)['open'])

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + (120 + 240) * GRAM)

    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))
    status('Unfreezing the stakes')
    e.ticktock(False)
    e.ticktock(False)

    stakes3 = [40, 40, 40, 0, 0, 0]
    status('Recovering the stakes from elections #2')
    for i in range(6):
        query_id = generate_query_id()
        v[i].recover(query_id)
        dispatch_one_message() # validator: elector.recover_stake()
        dispatch_one_message() # elector: validator.receive_stake_back()
        v[i].ensure_balance(globals.G_DEFAULT_BALANCE - stakes3[i] * GRAM)

    status('All done')

def find_vtor(v, pubkey):
    for i in range(len(v)):
        if decode_int(v[i].validator_pubkey) == pubkey:
            return i
    return None

def ban(
        c: Config,
        e: Elector,
        v: list[Validator],
        victim_pubkey: str,
        wc_id: str,
        banned = [],
        expected_ec = 0,
        verbose = True,

):
    assert isinstance(victim_pubkey, str)

    state = dict()
    if verbose:
        state = c.get_slashed_vset(wc_id)
    else:
        state = c.get_current_vset(wc_id)

    current_vset = state['vdict']
    assert isinstance(current_vset, dict)
    assert ne(dict(), current_vset)

    index = 0
    total_weight = 0
    for i in current_vset:
        total_weight += decode_int(current_vset[i]['weight'])
        index += 1

    weight = 0
    for i in current_vset:
        reporter_pubkey = current_vset[i]['pubkey']
        if reporter_pubkey == victim_pubkey:
            continue
        if reporter_pubkey in banned:
            continue
        weight += decode_int(current_vset[i]['weight'])
        i = int(i)
        if verbose:
            status('Reporting %d' % i)
        for w in v:
            if w.validator_pubkey == reporter_pubkey:
                signature = w.report_signature(victim_pubkey, 13)
                break
        else:
            assert False, "validator's public key is not found is current validator set"
        banning = weight >= total_weight * 2 / 3
        e.report(
            '0x' + signature[:64], '0x' + signature[64:],
            reporter_pubkey, victim_pubkey,
            13,
            wc_id,
            expected_ec if banning else 0
        )
        if banning:
            if verbose:
                status('Threshold weight reached %d' % i)
            break
        else:
            ensure_queue_empty()
    else:
        assert False, "something gone wrong not enough weight to ban validator"

    if expected_ec == 0:

        dispatch_one_message(src = e, dst = c) # elector: config.set_slashed_validator_set()
        set_config_param(100, c.get_config_param(100))
        dispatch_one_message(src = c, dst = e) # config: elector.config_set_confirmed_ok()
        ensure_queue_empty()

        globals.time_shift(60) # to apply slashed validator set

        assert eq(len(banned) + 1, len(e.get_banned()))

def deploy_network(max_validators, main_validators, min_validators, wc_ids: list[str]):
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
    c.add_new_wc("0")
    configurations = [[3, 40]] * 6

    for wc_id in wc_ids:
        v = make_elections(configurations, e, wc_id)
        conduct_elections(c, e, len(configurations), wc_id)

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    for wc_id in wc_ids:
        state = e.get_chain_election(wc_id)
        assert eq(False, state['open'])
        assert eq(False, state['failed'])
        assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 240 * GRAM) # 240 grams of stake + 100 grams of own funds

    globals.time_shift(1)

    return (e, c, v)

def test_ban(wc_id: str):
    (e, c, v) = deploy_network(5, 3, 2, wc_id)
    elect_id = e.get_chain(wc_id)['active_id']

    status('Banning one validator')
    victim_idx = 2
    victim_pubkey = v[victim_idx].validator_pubkey
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
    e.ticktock(False)

    banned = e.get_banned()
    assert isinstance(banned, dict)
    assert eq(1, len(banned))
    assert eq(Cell(EMPTY_CELL), c.get_config_param(35))

    dispatch_one_message(src = e, dst = c) # elector: config.set_slashed_validator_set()
    # assert ne(Cell(EMPTY_CELL), c.get_config_param(35))
    set_config_param(100, c.get_config_param(100))
    # dispatch_one_message()
    dispatch_one_message(src = c, dst = e) # config: elector.config_slash_confirmed_ok()

    globals.time_shift(600)
    # assert eq(Cell(EMPTY_CELL), c.get_config_param(36))
    vset = c.get_current_vset(wc_id)
    assert ne(Cell(EMPTY_CELL), vset)
    c.ticktock(False)
    # assert eq(vset, c.get_current_vset(GLOBAL_DEFAULT_wc_id))
    set_config_param(100, c.get_config_param(100))
    # dispatch_one_message()
    c.ticktock(False)

    # set_config_param(35, c.get_config_param(35))

    status('Checking current validator set after ban')
    vdict = c.get_current_vset(wc_id)['vdict']
    for i in range(len(vdict)):
        pubkey = vdict['%d' % i]['pubkey']
        assert decode_int(victim_pubkey) != decode_int(pubkey)


    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))

    configurations = [[3, 35]] * 6
    make_elections(configurations, e, wc_id)
    elect_id = e.get_chain_election(wc_id)['elect_at']
    print("end of elect", decode_int(e.get_chain_election(wc_id)['elect_close']))
    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    assert eq(True, e.get_chain_election(wc_id)['open'])
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 450 * GRAM) # 450 grams of stake + 100 grams of own funds

    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))
    status('Unfreezing the stakes')
    e.ticktock(False)
    e.ticktock(False)

    status('Recovering the stakes')
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

def test_ban_multiple():
    wc_id = "0"

    (e, c, v) = deploy_network(6, 6, 4, list("0"))

    elect_id = e.get_chain(wc_id)['active_id']
    victim1_idx = 2
    status('Banning one validator %s' % v[victim1_idx].validator_pubkey)

    ban(c, e, v, v[victim1_idx].validator_pubkey, wc_id, [], 0, False)
    banned = [v[victim1_idx].validator_pubkey]
    victim2_idx = 1
    status('Banning second validator %s' % v[victim2_idx].validator_pubkey)
    ban(c, e, v, v[victim2_idx].validator_pubkey, wc_id, banned,0, True)
    banned.append(v[victim2_idx].validator_pubkey)
    # TODO check it!
    # victim3_idx = 0
    # status('Impossible banning third validator %s' % v[victim3_idx].validator_pubkey)
    # ban(c, e, v, v[victim3_idx].validator_pubkey, banned, 141)

    vdict = c.get_current_vset(wc_id)['vdict']
    assert eq(6, len(vdict))

    slashed = c.get_slashed_vset(wc_id)['vdict']
    assert eq(4, len(slashed))

    status('Early recovering the stakes')
    for i in [victim1_idx, victim2_idx]:
        balance = globals.G_DEFAULT_BALANCE - 40 * EVER # they lost stakes
        query_id = generate_query_id()
        v[i].recover(query_id)
        dispatch_one_message() # validator: elector.recover_stake()
        dispatch_one_message() # elector: validator.receive_stake_back()
        v[i].ensure_balance(balance)

    globals.time_shift(600)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))
    # set_config_param(35, c.get_config_param(35))

    status('Checking current validator set after ban')
    vdict = c.get_current_vset(wc_id)['vdict']
    assert eq(4, len(vdict))
    for i in vdict:
        pubkey = vdict[i]['pubkey']
        assert decode_int(v[victim1_idx].validator_pubkey) != decode_int(pubkey)
        assert decode_int(v[victim2_idx].validator_pubkey) != decode_int(pubkey)

    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))

    configurations = [[3, 30]] * 6
    make_elections(configurations, e, wc_id)
    elect_id = e.get_chain_election(wc_id)['elect_at']

    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    status('Conducting elections')
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()
    assert eq(True, e.get_chain_election(wc_id)['open'])

    globals.time_shift(c.elect_end_before)
    c.ticktock(False)
    set_config_param(100, c.get_config_param(100))


    status('Installing next validator set')
    e.ticktock(False) # validator_set_installed

    state = e.get_chain_election(wc_id)
    assert eq(False, state['open'])
    assert eq(False, state['failed'])
    assert eq(False, state['finished'])

    e.ensure_balance(globals.G_DEFAULT_BALANCE + 420 * GRAM) # 480 grams of stake + 100 grams of own funds

    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))
    status('Unfreezing the stakes')
    e.ticktock(False)
    e.ticktock(False)

    status('Recovering the stakes')
    for i in range(len(v)):
        if (i == victim1_idx) or (i == victim2_idx):
            balance = globals.G_DEFAULT_BALANCE - 40 * EVER # they lost stakes
        else:
            balance = globals.G_DEFAULT_BALANCE + 20 * EVER # they got stakes as bonus
        query_id = generate_query_id()
        v[i].recover(query_id)
        dispatch_one_message() # validator: elector.recover_stake()
        dispatch_one_message() # elector: validator.receive_stake_back()
        v[i].ensure_balance(balance)

    status('All done')

def test_on_bounce():
    wc_id = "0"

    globals.reset()
    showtime = 86400
    time_set(showtime)

    c = deploy_config(
        min_validators=13,
        max_validators=1000,
        min_stake=9 * EVER,
        max_stake=50 * EVER,
        min_total_stake=100 * EVER)
    e = deploy_elector()
    c.add_new_wc("0")
    v = make_elections(configurations, e, wc_id)
    elect_id = e.get_chain_election(wc_id)['elect_at']

    status('Conducting elections')
    time_set(decode_int(e.get_chain_election(wc_id)['elect_close']))
    e.ticktock(False) # conduct_elections

    dispatch_one_message() # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message() # config: elector.config_set_confirmed_ok()

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

    status('Collecting refunds due to max_factor clipping')
    min_stake = 10
    for i in range(total_count):
        validator  = v[i]
        orig_stake = configurations[i][1]
        max_factor = configurations[i][0]

        balance = globals.G_DEFAULT_BALANCE - orig_stake * GRAM
        validator.ensure_balance(balance)

        refund = orig_stake - max_factor * min_stake
        if refund > 0:
            query_id = generate_query_id()
            validator.recover(query_id)
            dispatch_one_message() # validator: elector.recover_stake()
            dispatch_one_message() # elector: validator.receive_stake_back()
            validator.ensure_balance(balance + refund * GRAM)

    time_set(decode_int(e.get_chain_past_elections(wc_id)[elect_id]['unfreeze_at']))
    status('Unfreezing the stakes')
    e.ticktock(False) # check_unfreeze

    defunct = 3
    v[defunct].toggle_defunct()

    status('Recovering the stakes')
    for i in range(total_count):
        query_id = generate_query_id()
        v[i].recover(query_id)
        dispatch_one_message() # validator: elector.recover_stake()
        if i == defunct:
            dispatch_one_message(expect_ec = 177)
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE - (configurations[defunct][1] + 1) * GRAM)
            dispatch_one_message() # bounced
        else:
            dispatch_one_message() # elector: validator.receive_stake_back()
            v[i].ensure_balance(globals.G_DEFAULT_BALANCE)

    v[defunct].toggle_defunct()
    query_id = generate_query_id()
    v[defunct].recover(query_id)
    dispatch_one_message() # validator: elector.recover_stake()
    dispatch_one_message() # elector: validator.receive_stake_back()
    v[defunct].ensure_balance(globals.G_DEFAULT_BALANCE)

    e.ensure_balance(globals.G_DEFAULT_BALANCE)
    c.ensure_balance(globals.G_DEFAULT_BALANCE, True)

    status('All done')

configurations2 = [
    [2.0, 10], [2.0, 10], [3.0, 10], [3.0, 10], [3.0, 40],
    [3.0, 40], [2.0, 20], [3.0, 10], [2.0, 20], [2.0, 10],
    [2.0, 40], [3.0, 30], [3.0, 10], [3.0, 20], [2.0, 20],
    [2.0, 10], [2.0, 40], [3.0, 10], [2.0, 20], [2.0, 10],
    [3.0, 50], [3.0, 40], [3.0, 10], [3.0, 10], [3.0, 10],
    [2.0, 10], [3.0, 20], [3.0, 40], [3.0, 20], [3.0, 30],
    [2.0, 10], [2.0, 10], [3.0, 10], [3.0, 10], [3.0, 40],
    [3.0, 40], [2.0, 20], [3.0, 10], [2.0, 20], [2.0, 10],
    [2.0, 40], [3.0, 30], [3.0, 10], [3.0, 20], [2.0, 20],
    [2.0, 10], [2.0, 40], [3.0, 10], [2.0, 20], [2.0, 10]]

def test_1000():
    wc_id = "0"

    count = 1000
    globals.reset()
    showtime = 86400
    time_set(showtime)

    e = deploy_elector()

    c = deploy_config(
        max_validators=count,
        min_validators=100,
        main_validators=count,
        min_stake=10*EVER,
        max_stake=50*EVER,
        min_total_stake=100*EVER)
    c.add_new_wc("0")
    status('Announcing new elections')
    e.ticktock(False) # announce_new_elections

    state = e.get_chain_election(wc_id)
    assert eq(True, state['open'])

    # now = time_get()
    max = decode_int(state['elect_close'])
    # assert False, max - now

    elect_id = decode_int(state['elect_at'])

    status('Making %d stakes'.format(count))
    for i in range(count):
        max_factor, value = configurations2[i % len(configurations2)]
        v = stake(elect_id, int(max_factor * 0x10000), value * GRAM, wc_id, None, False)
        v.ensure_balance(globals.G_DEFAULT_BALANCE - value * GRAM)
        assert time_get() < max

    start = time.time()
    conduct_elections(c, e, count, wc_id)
    end = time.time()
    status('{} elapsed'.format(end - start))

    status('All done')

def test_depool():
    # rebuild all
    assert os.system(". ~/.bash_aliases && cd ../ && ./tests/binaries/build.sh") == 0
    assert os.system("cd ../../depool && ./build_all.sh") == 0

    assert os.system("cp ../../depool/DePool.tvc            ./binaries/") == 0
    assert os.system("cp ../../depool/DePoolHelper.tvc      ./binaries/") == 0
    assert os.system("cp ../../depool/DePoolHelper.abi.json ./binaries/") == 0
    assert os.system("cp ../../depool/DePool.abi.json       ./binaries/") == 0
    assert os.system("cd ./binaries/ && /home/igor/src/tonlabs/tonos-cli/target/release/tonos-cli genaddr --save --genkey DePool.key.json  DePool.tvc DePool.abi.json") == 0

    with open('./binaries/DePool.key.json') as f:
        data = json.load(f)
        depool_private_key = data["secret"] + data["public"]


    globals.reset()
    start_time = 100_000
    elect_for = 1_000
    elect_begin_before = 600
    elect_end_before = 200
    time_set(start_time)

    e = deploy_elector()
    c = deploy_config()

    # status('Setting config parameters')
    # c = Config(elector_addr       = e.hex_addr,
    #            elect_for          = elect_for,
    #            elect_begin_before = elect_begin_before,
    #            elect_end_before   = elect_end_before,
    #            stake_held         = 350,
    #            max_validators     = 7,
    #            main_validators    = 100,
    #            min_validators     = 3,
    #            min_stake          = 10 * GRAM,
    #            max_stake          = 50 * GRAM,
    #            min_total_stake    = 100 * GRAM,
    #            max_stake_factor   = 0x30000,
    #            utime_since        = start_time,
    #            utime_until        = start_time + elect_for)
    # c.set_config_params()

    depool = None
    depool_helper = None

    for elect_at in[start_time, 2 * start_time]:
        time_set(elect_at + elect_for - elect_begin_before)
        status('Announcing new elections')
        e.ticktock(False) # announce_new_elections

        state = e.get()
        assert eq(True, state['election_open'])

        v = make_stakes(configurations, e)

        if elect_at == 2 * start_time:
            assert depool is not None
            rounds = depool.getRounds()
            assert rounds["2"]["supposedElectedAt"] == "0"

            # dispatch_one_message()
            assert depool_helper is not None
            depool_helper.sendTickTock()
            dispatch_messages()

            rounds = depool.getRounds()
            elector_state = e.get()
            assert rounds["2"]["supposedElectedAt"] == elector_state['cur_elect']['elect_at']
            pprint.pp(rounds)



        status('Conducting elections')
        time_set(decode_int(e.get()['cur_elect']['elect_close']))
        e.ticktock(False) # conduct_elections

        dispatch_one_message() # elector: config.set_next_validator_set()
        set_config_param(36, c.get_config_param(36))
        dispatch_one_message() # config: elector.config_set_confirmed_ok()

        assert eq(True, e.get()['election_open'])

        status('Installing next validator set')
        e.ticktock(False) # validator_set_installed

        state = e.get()
        assert eq(False, state['election_open'])

        time_set(elect_at + elect_for)
        c.ticktock(False)
        set_config_param(36, c.get_config_param(36))
        set_config_param(34, c.get_config_param(34))
        set_config_param(32, c.get_config_param(32))

        if elect_at == start_time:
            status('Deploying depool')
            depool = DePool()
            depool.call_method("constructor", dict(
                minStake = 10 * GRAM,
                validatorAssurance = 10 * GRAM,
                proxyCode = Cell("te6ccgECJQEABl0ABCSK7VMg4wMgwP/jAiDA/uMC8gsiAgEkAsSNCGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAT4aSHbPNMAAZ+BAgDXGCD5AVj4QvkQ8qje0z8B+EMhufK0IPgjgQPoqIIIG3dAoLnytPhj0x8B2zz4R27yfBIDAUIi0NMD+kAw+GmpOADcIccA3CHXDR/yvCHdAds8+Edu8nwDAzwgghBFOpeAu+MCIIIQ83RITLvjAiCCEP////674wIXDAQEUCCCEPgilhK64wIgghD5b3MkuuMCIIIQ/////brjAiCCEP////664wILCQcFAyQw+EJu4wDTP9Mf0ds84wB/+GchBh8AavhJImim/mCCEAVdSoChtX/4S3DIz4WAygBzz0DOAfoCcc8LalnIz5ErP+dKyz/Ozclw+wBbAyQw+EJu4wDTP9Mf0ds84wB/+GchCB8AciD4SSNopv5gghAFXUqAobV/+EtwyM+FgMoAc89AzgH6AnHPC2pVIMjPkAwUQqLLP87LH83JcPsAWwMgMPhCbuMA0z/R2zzjAH/4ZyEKHwBq+EkhaKb+YIIQBV1KgKG1f/hLcMjPhYDKAHPPQM4B+gJxzwtqWcjPkfPtBxrLP87NyXD7ADACnjD4Qm7jANM/0gDTH9H4SVRxI2im/mCCEAVdSoChtX/4S3DIz4WAygBzz0DOAfoCcc8LalUwyM+Q9108pss/ygDLH87NyXD7AF8D4wB/+GchHwRQIIIQUErVF7rjAiCCEGi1Xz+64wIgghDub0VMuuMCIIIQ83RITLrjAhURDw0DJDD4Qm7jANM/0x/R2zzjAH/4ZyEOHwBy+ElTEmim/mCCEAVdSoChtX/4S3DIz4WAygBzz0DOAfoCcc8LalUgyM+QmfXguss/yx/Ozclw+wBbAyQw+EJu4wDTP9Mf0ds84wB/+GchEB8AcvhJUxJopv5gghAFXUqAobV/+EtwyM+FgMoAc89AzgH6AnHPC2pVIMjPkTtkCybLP8sfzs3JcPsAWwI4MPhCbuMA+Ebyc3/4ZtH4SfhLxwXy4GbbPH/4ZxIfAhbtRNDXScIBio6A4iETAf5w7UTQ9AVxIYBA9A6T1wsHkXDi+GpyIYBA9A6OJI0IYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABN/4a3MhgED0Do4kjQhgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE3/hsgED0DvK91wv/+GJwFAAK+GNw+GYDHDD4Qm7jANHbPOMAf/hnIRYfAHb4SfhMxwXy4Gj4J28QIIIQdzWUALU/vo4gIIIQdzWUALU/obV/IPhMyM+FCM4B+gKAa89AyXD7ADDeMARQIIIQBU2h/rrjAiCCEBOLrIy64wIgghAtvEKeuuMCIIIQRTqXgLrjAh4cGhgDRjD4Qm7jANM/+kGV1NHQ+kDf1w0fldTR0NMf39HbPNs8f/hnIRkfAKz4SfhLxwXy4Gb4J28QaKb+YIIQO5rKAKC1f77y4GdTAmim/mCCEAVdSoChtX8kyM+FiM4B+gKNBEAAAAAAAAAAAAAAAAACOyuhLM8Wyz/LH8lw+wBfAwNqMPhCbuMA0ds8Io4hJNDTAfpAMDHIz4cgznHPC2ECyM+StvEKes7LP83JcPsAkVvi4wB/+GchGx8AEPhLghA7msoAAvww+EJu4wDTP9P/0x/TH9cN/5XU0dDT/98g10vAAQHAALCT1NHQ3tT6QZXU0dD6QN/R+En4S8cF8uBm+CdvEGim/mCCEDuaygCgtX++8uBnVHEjVHeJaKb+YIIQBV1KgKG1fyfIz4WIzgH6AnHPC2pVUMjPkTnN0S7LP8v/yx8hHQEiyx/L/8zNyXD7AF8H2zx/+GcfAzIw+EJu4wDTP/pBldTR0PpA39HbPNs8f/hnISAfADr4TPhL+Er4RvhD+ELIy//LP8oAywfOAcjOzcntVACk+En4S8cF8uBm+CdvEGim/mCCEDuaygCgtX++8uBnIWim/mCCEAVdSoChtX8iyM+FiM4B+gKNBEAAAAAAAAAAAAAAAAACOyuhNM8Wyz/JcPsAWwA+7UTQ0//TP9IA0wf6QNTR0PpA0fhs+Gv4avhm+GP4YgIK9KQg9KEkIwAUc29sIDAuNDcuMAAA"),
                validatorWallet = Address("0:" + ('34' * 32)),
                participantRewardFraction = 69
            ), private_key=depool_private_key)
            info = depool.getDePoolInfo()
            dispatch_messages()

            depool_helper = DePoolHelper(depool.address)
            depool_helper.call_method("constructor", dict(
                pool = depool.address
            ))
            depool_helper.sendTickTock()
            dispatch_messages()

            rounds = depool.getRounds()
            pprint.pp(rounds)

def test_change_config_internal():

    globals.reset()
    showtime = 86400
    time_set(showtime)

    keypair = make_keypair()

    e = deploy_elector()
    c = deploy_config(keypair = keypair, capabilities = 0)

    # main contract to control config
    w = Validator(keypair)
    assert eq(int(w.validator_pubkey, 16), c.call_getter('public_key'))

    # alien contract
    w1 = Validator()

    c.print_config_param(5)
    c.print_config_param(8)
    c.print_config_param(17)

    assert eq(Cell(EMPTY_CELL), c.get_config_param(5))
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    print(bright_blue('addr'), w.address)
    addr = w.address.str()[3:]
    print(bright_blue('addr'), addr)

    p5 = dict(p5 = addr)
    p8 = dict(p8 = dict(
        version = 6,
        capabilities = 0x42e
    ))
    p8_cell = parse_config_param(p8)

    # try to send external message to config contract without signature
    status('try set p8 using external message without signature')
    c.call_method('set_config_param', dict(
        index = 8,
        data = p8_cell
    ), None, 100)
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    # try to send external message to config contract with wrong signature
    status('try set p8 using external message with wrong signature')
    c.call_method('set_config_param', dict(
        index = 8,
        data = p8_cell
    ), w1.private_key, 40)
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    # try to send internal message to config contract instead of external
    status('try set p8 using internal message instead of external')
    params = dict(
        index = 8,
        data = p8_cell
    )
    payload = encode_message_body(
        c.addr,
        c.abi_path,
        "set_config_param",
        params
    )
    w.call_method_signed('transfer_to_config', dict(payload = payload))

    dispatch_one_message(71) # validator: config.set_config_param()
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    # try to change config via contract without setting p5
    status('try set p8 with other contract but p5 was not set')
    c.change_config_param_internal(w, 8, p8)
    dispatch_one_message(501) # validator: config.change_config_param()
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    status('set p5')
    c.change_config_param_owner(5, p5)

    param = c.print_config_param(5)
    assert eq(addr, param.strip('"'))

    status('try set p8 with extrnal message like other contract with signature')
    c.call_method_signed('change_config_param', dict(
        index = 8,
        data = p8_cell
    ), 72)
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    status('try set p8 with extrnal message like other contract w/o signature')
    c.call_method('change_config_param', dict(
        index = 8,
        data = p8_cell
    ), None, 72)
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    status('try to change p8 with alien contract')
    c.change_config_param_internal(w1, 8, p8)
    dispatch_one_message(502) # validator: config.change_config_param()
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    status('try to clear public key of config with wrong signature')
    c.call_method('set_public_key', dict(
        pubkey = 0
    ), w1.private_key, 40)
    assert eq(int(w.validator_pubkey, 16), c.call_getter('public_key'))

    status('try to clear public key of config without signature')
    c.call_method('set_public_key', dict(
        pubkey = 0
    ), None, 100)
    assert eq(int(w.validator_pubkey, 16), c.call_getter('public_key'))

    status('clear public key of config')
    c.call_method_signed('set_public_key', dict(
        pubkey = 0
    ))
    assert eq(0, c.call_getter('public_key'))

    status('clear public key of config twice')
    c.call_method_signed('set_public_key', dict(
        pubkey = 0
    ), 40)

    status('change p8 using owner key with cleared public key')
    c.call_method_signed('set_config_param', dict(
        index = 8,
        data = p8_cell
    ), 40)
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    status('try to change p8 without signature with cleared public key')
    c.call_method('set_config_param', dict(
        index = 8,
        data = p8_cell
    ), None, 101)
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

    status('set public key of config with new public key')
    c.change_config_public_key(w, w1.validator_pubkey)
    dispatch_one_message() # validator: config.change_public_key()
    assert eq(int(w1.validator_pubkey, 16), c.call_getter('public_key'))

    status('try to change p8 with original signature')
    c.call_method_signed('set_config_param', dict(
        index = 8,
        data = p8_cell
    ), 40)
    assert eq(Cell(EMPTY_CELL), c.get_config_param(8))

##################################################################################################
##################################################################################################

init('binaries/', verbose = True)

start = time.time()
test_change_config_internal()

print()
# test_old_config_code_upgrade()
# print()
# test_old_elector_code_upgrade()
# print()
# test_identical_validators() ##
print()
# test_elector_code_upgrade()
#
print()
# test_seven_validators()##
# print()
# test_rich_validator()##
# print()
# test_thirty_validators()##
# print()
# test_insufficient_number_of_validators()##
# print()
test_bonuses()##
# print()
test_reset_utime_until()##
# print()
test_ban("0")##
# print()
# test_ban_multiple()##
# print()
# test_on_bounce()##
# print()
# test_1000()##

## test_complaints() # it is not working now due to non using algorithms
## test_depool() # TODO: it stopped work

## prepare_change_code_messages(0)

end = time.time()
print(yellow('OK - FINISHED'), '{} total elapsed'.format(end - start))
