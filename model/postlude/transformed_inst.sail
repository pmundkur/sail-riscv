// =======================================================================================
// This Sail RISC-V architecture model, comprising all files and
// directories except where otherwise noted is subject the BSD
// two-clause license in the LICENSE file.
//
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// Transformed instructions written to mtinst/htinst on a trap.

// Exceptions that may write a transformed instruction to mtinst/htinst.
private function allows_transformed_instruction(e : ExceptionType) -> bool =
  match e {
    E_Load_Addr_Align()   => true,
    E_Load_Access_Fault() => true,
    E_SAMO_Addr_Align()   => true,
    E_SAMO_Access_Fault() => true,
    E_Load_Page_Fault()   => true,
    E_SAMO_Page_Fault()   => true,
    E_Load_GPage_Fault()  => true,
    E_SAMO_GPage_Fault()  => true,
    _                     => false,
  }

private function transformed_instruction(insn : instruction) -> option(bits(32)) =
  match insn {
    LOAD(_, _, rd, is_unsigned, width)     => Some(encdec(LOAD(zeros(), zreg, rd, is_unsigned, width))),
    STORE(_, rs2, _, width)                => Some(encdec(STORE(zeros(), rs2, zreg, width))),
    LOAD_FP(_, _, rd, width)               => Some(encdec(LOAD_FP(zeros(), zreg, rd, width))),
    STORE_FP(_, rs2, _, width)             => Some(encdec(STORE_FP(zeros(), rs2, zreg, width))),
    LOADRES(aq, rl, _, width, rd)          => Some(encdec(LOADRES(aq, rl, zreg, width, rd))),
    STORECON(aq, rl, rs2, _, width, rd)    => Some(encdec(STORECON(aq, rl, rs2, zreg, width, rd))),
    AMO(op, aq, rl, rs2, _, width, rd)     => Some(encdec(AMO(op, aq, rl, rs2, zreg, width, rd))),
    HLVTYPE(width, op, is_unsigned, _, rd) => Some(encdec(HLVTYPE(width, op, is_unsigned, zreg, rd))),
    HSV(width, _, rs2)                     => Some(encdec(HSV(width, zreg, rs2))),
    ZICBOM(cbop, _)                        => Some(encdec(ZICBOM(cbop, zreg))),
    ZICBOZ(_)                              => Some(encdec(ZICBOZ(zreg))),
    _                                      => None(),
  }

function transform_trap_instruction(result : ExecutionResult, insn : instruction, compressed : bool) -> ExecutionResult =
  match result {
    Trap(priv, ctx, pc) if sys_trap_writes_transformed_instruction & currentlyEnabled(Ext_H) & allows_transformed_instruction(ctx.trap) =>
      match (ctx.excinst, transformed_instruction(insn)) {
        // Some(_) is the pseudoinstruction from vmem.sail, keep it
        (None(), Some(tinst)) => {
          // rs1 holds the Addr. Offset
          let tinst = [tinst with 19 .. 15 = ctx.excinst_offset];
          //"For a standard compressed instruction (16-bit size), the transformed instruction is found as follows:
          //   1. Expand the compressed instruction to its 32-bit equivalent.
          //   2. Transform the 32-bit equivalent instruction.
          //   3. Replace bit 1 with a 0."
          let tinst = if compressed then [tinst with 1 = bitzero] else tinst;
          Trap(priv, { ctx with excinst = Some(zero_extend(tinst)) }, pc)
        },
        _ => result,
      },
    _ => result,
  }
