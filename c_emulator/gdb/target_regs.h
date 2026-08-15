#pragma once

#include <cstdint>
#include <map>
#include <string>

class ModelImpl;
class protocol_handler;
struct CSRInfo;

// The indices of the registers in the register map.
struct register_map {
  // Registers before the PC are integer (X) registers, 0-31.
  int64_t pc_offset; // = 32 for the (non-E) base ISA.
  // Registers after the PC but before CSRs are floating-point
  // registers.
  // fpr_len is 0 if `F` is not enabled, and 32 otherwise.
  // Note that this length does not include the `fcsr` CSR.
  int64_t fpr_len;
  // The next two fields are undefined if fpr_len == 0.
  int64_t fpr_offset;
  int64_t fcsr_offset;
  // CSRs
  int64_t csr_offset;
  std::map<uint64_t, CSRInfo> csrs;
};

// TODO: make these take `const ModelImpl &`.

register_map get_register_map(ModelImpl &model);

// Generates the response for `qXfer:features:read:target.xml`.
std::string get_target_xml(ModelImpl &model);

// Generates the response for `g` (read general registers).
std::string get_general_regs(protocol_handler &proto_handler);
// Generates the response for `p` (read register).
std::string get_register(protocol_handler &proto_handler, uint64_t regidx);
// Generates the response for `P` (write register).
std::string set_register(protocol_handler &proto_handler, uint64_t regidx, uint64_t val);
