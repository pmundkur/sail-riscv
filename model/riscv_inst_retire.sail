/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

// Return value from `execute()` function.
union ExecutionResult('a : Type) = {
  // Successfully retired.
  Retire_Success                 : unit,

  // The instruction is a compressed instruction, and should be
  // executed as an uncompressed instruction.
  // The `ast` type is abstracted over to break a mutual recursion
  // cycle.
  ExecuteAs                      : 'a,

  // An instruction such as WFI, WRS.{STO,NTO}
  // entered a wait state, which may or may not
  // retire depending on the configuration.
  Enter_Wait                     : WaitReason,

  // Did not retire for a standard reason.
  Illegal_Instruction            : unit,
  Trap                           : (Privilege, ctl_result, xlenbits),
  Memory_Exception               : (virtaddr, ExceptionType),

  // Did not retire for custom reason.
  Ext_CSR_Check_Failure          : unit,
  Ext_ControlAddr_Check_Failure  : ext_control_addr_error,
  Ext_DataAddr_Check_Failure     : ext_data_addr_error,
  Ext_XRET_Priv_Failure          : unit,
}
