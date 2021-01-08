#pragma once

#include <tvm/contract_handle.hpp>

namespace tvm { namespace schema {

__interface IDePool {
  __attribute__((internal, noaccept))
  void transferStake(address destination, uint64 amount) = 0x6810bf4e; // = hash_v<"transferStake(address,uint64)()v2">
};

using IDePoolPtr = contract_handle<IDePool>;

}} // namespace tvm::schema

