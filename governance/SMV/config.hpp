#pragma once

#include <features.h>
#include <tvm/message_flags.hpp>

namespace tvm {

// without `SENDER_WANTS_TO_PAY_FEES_SEPARATELY` rawreserve + send_all_gas scheme doesn't work correctly in local node se
static const unsigned INT_RETURN_FLAG = SEND_ALL_GAS | SENDER_WANTS_TO_PAY_FEES_SEPARATELY | IGNORE_ACTION_ERRORS;

} // namespace tvm

