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

core = globals.core

class Config(BaseContract):
    def __init__(self,
                 elector_addr,
                 elect_for,
                 elect_begin_before,
                 elect_end_before,
                 stake_held,
                 max_validators,
                 main_validators,
                 min_validators,
                 min_stake,
                 max_stake,
                 min_total_stake,
                 max_stake_factor,
                 utime_since,
                 utime_until,
                 capabilities = 0,
                 keypair = None
             ):
        if elector_addr is None:
            elector_addr = '0x' + '3'*64
        override_address = Address('-1:' + '5'*64)
        self.elect_for          = elect_for
        self.elect_begin_before = elect_begin_before
        self.elect_end_before   = elect_end_before
        self.stake_held         = stake_held
        if keypair is not None:
            (_, public_key) = keypair
        else:
            public_key = '0' * 64
        pubkey       = '0x' + public_key
        config_addr  = '0x' + override_address.str().split(':')[1]
        super(Config, self).__init__(
            'Config', dict(), keypair = keypair, wc = -1, override_address = override_address)

        real_pubkey = self.call_getter('public_key')
        assert isinstance(real_pubkey, int)

        assert ne(0, real_pubkey)
        assert eq(decode_int(pubkey), real_pubkey)

        if capabilities != 0:
            self.change_config_param_owner(2, dict(p8 = dict(
                version = 6,
                capabilities = capabilities
            )))

        self.change_config_param_owner(0, dict(p0 = config_addr))
        self.change_config_param_owner(1, dict(p1 = elector_addr))
        self.change_config_param_owner(15, dict(p15 = dict(
            validators_elected_for = elect_for,
            elections_start_before = elect_begin_before,
            elections_end_before   = elect_end_before,
            stake_held_for         = stake_held,
        )))
        self.change_config_param_owner(16, dict(p16 = dict(
            max_validators      = max_validators,
            max_main_validators = main_validators,
            min_validators      = min_validators,
        )))
        self.change_config_param_owner(17, dict(p17 = dict(
            min_stake          = min_stake,
            max_stake          = max_stake,
            min_total_stake    = min_total_stake,
            max_stake_factor   = max_stake_factor,
        )))
        self.change_config_param_owner(18, dict(p18 = [dict(
            utime_since      = 0,
            bit_price_ps     = 0,
            cell_price_ps    = 0,
            mc_bit_price_ps  = 0,
            mc_cell_price_ps = 0
        )]))
        p = dict(
            gas_price         = 0,
            gas_limit         = 0xFFFFFFFFFF,
            special_gas_limit = 0xFFFFFFFFFF,
            gas_credit        = 0xFFFFFF,
            block_gas_limit   = 0,
            freeze_due_limit  = 0,
            delete_due_limit  = 0,
            flat_gas_limit    = 0,
            flat_gas_price    = 0
        )
        self.change_config_param_owner(20, dict(p20 = p))
        self.change_config_param_owner(21, dict(p21 = p))
        p = dict(
            lump_price       = 0,
            bit_price        = 0,
            cell_price       = 0,
            ihr_price_factor = 0,
            first_frac       = 0,
            next_frac        = 0
        )
        self.change_config_param_owner(24, dict(p24 = p))
        self.change_config_param_owner(25, dict(p25 = p))
        p = dict(
            main         = 1,
            utime_since  = utime_since,
            utime_until  = utime_until,
            total        = 0,
            total_weight = 0,
            list = [dict(
                public_key = '0'*64,
                weight = 0
            )]
        )
        self.change_config_param_owner(34, dict(p34 = p))

        # old = self.print_config_param(18)
        # assert eq(old, self.print_config_param(18))

    def get_config_param(self, index: int) -> Cell:
        cell = self.call_getter("get_config_param", dict(index = index))
        assert isinstance(cell, Cell)
        return cell

    def get_current_vset(self, wc_id: str):
        cell = self.call_getter("get_current_vset", dict(wc_id = wc_id))
        assert isinstance(cell, Cell)
        return cell

    def print_config_param(self, index: int) -> str:
        cell = self.get_config_param(index)
        return core.print_config_param(index, cell.raw_)

    def set_config_params(self):
        for i in [0, 1, 5, 13, 15, 16, 17, 34, 36,100]:
            set_config_param(i, Config.get_config_param(self, i))

    def reset_utime_until(self):
        return self.call_method('reset_utime_until')

    def get_previous_vset(self):
        return self.call_getter_raw('get_previous_vset')['value0']

    def get_real_vset(self) -> dict:
        vset = self.get_slashed_vset(GLOBAL_DEFAULT_wc_id)
        assert isinstance(vset, dict)
        if decode_int(vset['main']) == 0:
            return self.get_current_vset(GLOBAL_DEFAULT_wc_id)
        else:
            return vset

    def get_current_vset(self, wc_id: str) -> dict:
        vset = self.call_getter_raw('get_current_vset',dict(
            wc_id = wc_id
        ))['value0']
        assert isinstance(vset, dict)
        return vset

    def get_slashed_vset(self, wc_id: str) -> dict:
        vset = self.call_getter_raw('get_slashed_vset', dict(wc_id = wc_id))['value0']
        assert isinstance(vset, dict)
        return vset

    def get_next_vset(self, wc_id: str) -> dict:
        vset = self.call_getter_raw('get_next_vset',dict(
            wc_id = wc_id
        ))['value0']
        assert isinstance(vset, dict)
        return vset
    def get_vset(self, wc_id: str, type: int):
       return self.call_getter_raw("get_vset",dict(vset_type = type, wc_id = wc_id))
    def set_elector_code(self, code, data):
        return self.call_method_signed('set_elector_code', dict(
            code = code,
            data = data
        ))

    def change_config_param_owner(self, index: int, params: dict):
        # print('change by p' + str(index), json_dumps(params))
        # p = dict()
        # p["p" + index] = params
        data = parse_config_param(params)
        self.call_method_signed('set_config_param', dict(
            index = index,
            data = data
        ))
        set_config_param(index, Config.get_config_param(self, index))

    def change_config_param_internal(self, v: BaseContract, index: int, params: dict):
        assert isinstance(params, dict)
        data = parse_config_param(params)
        params = dict(
            index = index,
            data = data
        )
        payload = encode_message_body(
            self.addr,
            self.abi_path,
            "change_config_param",
            params
        )
        v.call_method_signed('transfer_to_config', dict(
            payload = payload
        ))
        # don't forget to dispatch message and call set_config_param after dispatch

    def change_config_public_key(self, v: BaseContract, pubkey: str):
        params = dict(
            pubkey = pubkey,
        )
        payload = encode_message_body(
            self.addr,
            self.abi_path,
            "change_public_key",
            params
        )
        v.call_method_signed('transfer_to_config', dict(
            payload = payload
        ))
    def add_new_wc(self, wc: str):
        self.call_method_signed("add_new_wc", dict(wc_id = wc))
        self.set_config_params()
        dispatch_one_message()
class DePoolHelper(BaseContract):
    def __init__(self, depool_address):
        name = 'DePoolHelper'
        self.depool_address = depool_address
        super(DePoolHelper, self).__init__(name, ctor_params = None)

    def sendTickTock(self):
        return self.call_method('sendTicktock')
class DePool(BaseContract):
    def __init__(self):
        name = 'DePool'
        address = Address('0:' + ('69' * 32))
        super(DePool, self).__init__(name, ctor_params = None, override_address=address)

    def getDePoolInfo(self):
        return self.call_getter_raw('getDePoolInfo')

    def getRounds(self):
        return self.call_getter_raw('getRounds')['rounds']
class Elector(BaseContract):
    def __init__(self, name = 'Elector'):
        override_address = Address('-1:' + ('3' * 64))
        super(Elector, self).__init__(name, ctor_params = dict(), override_address = override_address, wc = -1)

    def get(self):
        return self.call_getter_raw('get')
    def get_chain(self, wc_id: str):
        return self.call_getter_raw("get")['chains'][wc_id]
    def get_chain_election(self, wc_id: str):
        return self.call_getter_raw("get")['chains'][wc_id]['election']
    def get_chain_past_elections(self, wc_id: str):
        return self.call_getter_raw("get")['chains'][wc_id]['past_elections']
    def get_banned(self):
        return self.call_getter_raw('get_banned')["value0"]

    def get_buckets(self, victim_pubkey):
        return self.call_getter('get_buckets', dict(victim_pubkey = victim_pubkey))

    def elect_id(self) -> int:
        state = self.get()
        assert isinstance(state, dict)
        return state['cur_elect']['elect_at']

    def dump(self):
        print(json.dumps(self.get(), indent = 2, sort_keys = True))

    def active_election_id(self, wc_id: str):
        return self.call_getter('active_election_id',dict(wc_id = wc_id))

    def compute_returned_stake(self, address):
        return self.call_getter('compute_returned_stake',
            dict(wallet_addr = address))

    def report(
        self,
        signature_hi,
        signature_lo,
        reporter_pubkey,
        victim_pubkey,
        metric_id,
        wc_id: str,
        expected_ec: int = 0
    ):
        return self.call_method('report', dict(
            signature_hi    = signature_hi,
            signature_lo    = signature_lo,
            reporter_pubkey = reporter_pubkey,
            victim_pubkey   = victim_pubkey,
            metric_id       = metric_id,
            wc_id         = wc_id),
            None,
            expected_ec)
class Validator(BaseContract):
    def __init__(self, keypair = None):
        if keypair is None:
            (private_key, public_key) = make_keypair()
        else:
            (private_key, public_key) = keypair
        super(Validator, self).__init__('Validator', dict(pubkey = int(public_key, 16)), wc = -1, pubkey = public_key,
            override_address = Address("-1:" + secrets.token_hex(32)))
        self.private_key      = private_key
        self.validator_pubkey = '0x' + public_key
        self.adnl_addr        = '0x' + secrets.token_hex(32)

    def stake(self, query_id, stake_at, max_factor, value, signature: str, wc_id: str):
        return self.call_method('stake', dict(
            query_id         = query_id,
            validator_pubkey = self.validator_pubkey,
            stake_at         = stake_at,
            max_factor       = max_factor,
            adnl_addr        = self.adnl_addr,
            value            = value,
            signature        = signature,
            wc_id         = wc_id
        ))

    def stake_sign_helper(self, stake_at, max_factor) -> Cell:
        cell = self.call_getter('stake_sign_helper', dict(
            stake_at   = stake_at,
            max_factor = max_factor,
            adnl_addr  = self.adnl_addr))
        assert isinstance(cell, Cell)
        return cell

    def recover(self, query_id):
        return self.call_method('recover', dict(query_id = query_id, value = 1 * EVER))

    def complain(self, query_id, election_id, validator_pubkey, value,
                 suggested_fine):
        return self.call_method('complain', dict(
            query_id         = query_id,
            election_id      = election_id,
            validator_pubkey = validator_pubkey,
            value            = value,
            suggested_fine   = suggested_fine))

    def vote(self, query_id, signature_hi, signature_lo, idx, elect_id, chash):
        return self.call_method('vote', dict(
            query_id     = query_id,
            signature_hi = signature_hi,
            signature_lo = signature_lo,
            idx          = idx,
            elect_id     = elect_id,
            chash        = chash))

    def vote_sign_helper(self, idx, elect_id, chash):
        return self.call_getter('vote_sign_helper', dict(
            idx      = idx,
            elect_id = elect_id,
            chash    = chash))

    def report_signature(self, victim_pubkey, metric_id) -> str:
        cell = self.call_getter('report_sign_helper', dict(
            reporter_pubkey = self.validator_pubkey,
            victim_pubkey   = victim_pubkey,
            metric_id       = metric_id))
        assert isinstance(cell, Cell)
        signature = sign_cell(cell, self.private_key)
        assert isinstance(signature, str)
        assert eq(128, len(signature))

        msg = '{0:0>64}{1:0>64}{2:0>2}'.format(self.validator_pubkey.lstrip('0x'), victim_pubkey.lstrip('0x'), hex(metric_id).lstrip('0x'))
        assert eq(130, len(msg))
        msg = bytes.fromhex(msg)
        sk = ed25519.SigningKey(bytes.fromhex(self.private_key))
        sign = sk.sign(msg, encoding="hex").decode()
        assert eq(sign, signature)

        return signature

    def transfer(self, value):
        return self.call_method('transfer', dict(value = value))

    def get(self):
        return self.call_getter_raw('get')

    def dump(self):
        print(json.dumps(self.get(), indent = 2, sort_keys = True))

    def toggle_defunct(self):
        return self.call_method('toggle_defunct')
class Zero(BaseContract):
    def __init__(self):
        address = Address('-1:' + ('0' * 64))
        super(Zero, self).__init__('Zero', {}, override_address = address, wc = -1)

    def grant(self, value):
        return self.call_method('grant', dict(value = value))

    def grant_to_chain(self, value: str, wc_id: str):
        return self.call_method('grant_by_wc_id', dict(
            value = value,
            wc_id = wc_id
        ))
