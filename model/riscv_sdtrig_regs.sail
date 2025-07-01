/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

function clause currentlyEnabled(Ext_Sdtrig) = hartSupports(Ext_Sdtrig)

register tcontrol : TControl

register scontext : SContext

register mcontext : MContext

register tselect : xlenbits

type num_triggers : Int = config extensions.Sdtrig.num_triggers

// If Sdtrig is implemented, at least one trigger is supported.
// The upper bound should reflect the constraint checked in the
// `check_sdtrig()` validator.  It is needed for the typechecker to
// ensure that it fits into tselect.
// TODO: make the upper bound configurable
constraint 1 <= num_triggers <= 16

// If num_triggers = 0 is allowed (e.g. as in Spike), then it can be
// handled by returning tdata1 corresponding to TT_none (i.e. zeros())
// in read_CSR for tdata1 for a tselect of 0.

register triggers : vector(num_triggers, Trigger) = vector_init(trig_reset_val)

mapping clause csr_name_map = 0x7a0  <-> "tselect"
function clause is_CSR_defined(0x7a0) = currentlyEnabled(Ext_Sdtrig)
function clause read_CSR(0x7a0) = tselect
function clause write_CSR(0x7a0, value) = {
  if   unsigned(value) >= sizeof(num_triggers)
  then tselect = to_bits(sizeof(num_triggers) - 1)
  else tselect = value;
  tselect
}

mapping clause csr_name_map = 0x7a1  <-> "tdata1"
function clause is_CSR_defined(0x7a1) = currentlyEnabled(Ext_Sdtrig)
function clause read_CSR(0x7a1) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "read(tdata1): out-of-range tselect: " ^ BitStr(tselect));
  tdata1_of_trigger(triggers[idx])
}
function clause write_CSR(0x7a1, value) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "write(tdata1): out-of-range tselect: " ^ BitStr(tselect));
  let t = trigger_write_tdata1(triggers[idx], value);
  triggers[idx] = t;
  tdata1_of_trigger(t)
}

mapping clause csr_name_map = 0x7a2  <-> "tdata2"
function clause is_CSR_defined(0x7a2) = currentlyEnabled(Ext_Sdtrig)
function clause read_CSR(0x7a2) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "read(tdata2): out-of-range tselect: " ^ BitStr(tselect));
  tdata2_of_trigger(triggers[idx])
}
function clause write_CSR(0x7a2, value) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "write(tdata2): out-of-range tselect: " ^ BitStr(tselect));
  let t = trigger_write_tdata2(triggers[idx], value);
  triggers[idx] = t;
  tdata2_of_trigger(t)
}

mapping clause csr_name_map = 0x7a3  <-> "tdata3"
function clause is_CSR_defined(0x7a3) = currentlyEnabled(Ext_Sdtrig)
function clause read_CSR(0x7a3) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "read(tdata3): out-of-range tselect: " ^ BitStr(tselect));
  tdata3_of_trigger(triggers[idx])
}
function clause write_CSR(0x7a3, value) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "write(tdata3): out-of-range tselect: " ^ BitStr(tselect));
  let t = trigger_write_tdata3(triggers[idx], value);
  triggers[idx] = t;
  tdata3_of_trigger(t)
}

mapping clause csr_name_map = 0x7a4  <-> "tinfo"
function clause is_CSR_defined(0x7a4) = currentlyEnabled(Ext_Sdtrig)
function clause read_CSR(0x7a4) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "read(tinfo): out-of-range tselect: " ^ BitStr(tselect));
  tinfo_of_trigger(triggers[idx]).bits
}
function clause write_CSR(0x7a4, value) = {
  let idx = unsigned(tselect);
  assert(idx < sizeof(num_triggers), "write(tinfo): out-of-range tselect: " ^ BitStr(tselect));
  // Writing the tinfo CSR has no effect.
  tinfo_of_trigger(triggers[idx]).bits
}
