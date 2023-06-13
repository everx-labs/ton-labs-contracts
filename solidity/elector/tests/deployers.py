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

core = globals.core
def deploy_elector():
    status('Deploying Elector')
    e = Elector()

    # assert eq(False, e.get_chain_election(wc_id)['open'])
    return e
def deploy_config(
        showtime: int = 86400,
        keypair = None,
        min_validators  = 3,
        max_validators  = 7,
        main_validators = 100,
        min_stake       = 2 * EVER,
        max_stake       = 50 * EVER,
        min_total_stake = 10 * EVER,
        capabilities = 0x42e,
        elector_addr = None,
    ) -> Config:
    status('Setting config parameters')
    if keypair is None:
        keypair = make_keypair()
    c = Config(elector_addr       = elector_addr,
               elect_for          = 6000,
               elect_begin_before = 3600,
               elect_end_before   = 1800,
               stake_held         = 32768,
               max_validators     = max_validators,
               main_validators    = main_validators,
               min_validators     = min_validators,
               min_stake          = min_stake,
               max_stake          = max_stake,
               min_total_stake    = min_total_stake,
               max_stake_factor   = 0x30000,
               utime_since        = showtime - 3000,
               utime_until        = showtime + 3000,
               keypair            = keypair,
               capabilities       = capabilities)

    return c

