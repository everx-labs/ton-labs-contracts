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

core = globals.core

def stake(stake_at, max_factor, value, wc_id:str, v = None, verbose = True, e: Elector | None = None) -> Validator:
    if verbose:
        status('Staking {} grams with max factor {}'.format(value / EVER, max_factor / 0x10000))
    if v is None:
        v = Validator()
    query_id = generate_query_id()
    cell = v.stake_sign_helper(stake_at, max_factor)
    signature = sign_cell(cell, v.private_key)
    v.stake(query_id, stake_at, max_factor, value + EVER, signature, wc_id)
    # dispatch_one_message() # validator: elector.process_new_stake()
    # dispatch_one_message() # validator: elector.process_new_stake()
    dispatch_messages()

    # ensure_queue_empty()

    state = v.get()
    assert eq(decode_int(query_id), decode_int(state['confirmed_query_id']))
    assert eq(0, decode_int(state['confirmed_body']))
    return v
def generate_query_id():
    return '0x' + secrets.token_hex(4).lstrip('0')

def make_elections(configurations, e: Elector, wc_id: str) -> list[Validator]:
    status('Announcing new elections')
    state = e.get_chain_election(wc_id)

    assert eq(False, state['open'])

    e.ticktock(False) # announce_new_elections
    return make_stakes(configurations, e, wc_id)

def conduct_elections(c: Config, e: Elector, members_cnt: int, wc_id: str, msg = None):
    assert isinstance(c, Config)
    assert isinstance(e, Elector)
    status(msg if msg is not None else 'Conducting elections')
    balance_before_conduct_elections = e.balance

    state = e.get_chain_election(wc_id)
    time_set(decode_int(state['elect_close']))
    assert eq(members_cnt, len(state['members']))
    e.ticktock(False) # conduct_elections

    e.ensure_balance(balance_before_conduct_elections - (1 << 30))

    dispatch_one_message(src = e, dst = c) # elector: config.set_next_validator_set()
    set_config_param(100, c.get_config_param(100))
    dispatch_one_message(src = c, dst = e) # config: elector.config_set_confirmed_ok()
    e.ensure_balance(balance_before_conduct_elections)

    assert eq(True, e.get_chain_election(wc_id)['open'])

    # state = e.get()
    # assert eq(0, len(state['cur_elect']['members']))
def make_stakes(configurations: list[tuple[float, int]], e: Elector, wc_id: str):
    state = e.get_chain_election(wc_id)

    count = len(state['members'])
    assert eq(True, state['open'])
    elect_id = state['elect_at']
    vv = []
    for i in range(len(configurations)):
        v = stake(elect_id, int(configurations[i][0] * 0x10000), configurations[i][1] * EVER, wc_id, e = e, )
        v.ensure_balance(globals.G_DEFAULT_BALANCE - configurations[i][1] * EVER)
        vv.append(v)
        assert eq(count + i + 1, len(e.get_chain_election(wc_id)['members']))
    return vv


