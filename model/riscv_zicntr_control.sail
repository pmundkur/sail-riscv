/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/
function clause currentlyEnabled(Ext_Zicntr) = hartSupports(Ext_Zicntr) & currentlyEnabled(Ext_Zicsr)

/* unprivileged counters/timers */
mapping clause csr_name_map = 0xC00  <-> "cycle"
mapping clause csr_name_map = 0xC01  <-> "time"
mapping clause csr_name_map = 0xC02  <-> "instret"
mapping clause csr_name_map = 0xC80  <-> "cycleh"
mapping clause csr_name_map = 0xC81  <-> "timeh"
mapping clause csr_name_map = 0xC82  <-> "instreth"

function clause is_CSR_defined(0xC00) = currentlyEnabled(Ext_Zicntr) // cycle
function clause is_CSR_defined(0xC01) = currentlyEnabled(Ext_Zicntr) // time
function clause is_CSR_defined(0xC02) = currentlyEnabled(Ext_Zicntr) // instret
function clause is_CSR_defined(0xC80) = currentlyEnabled(Ext_Zicntr) & (mxlen == 32) // cycleh
function clause is_CSR_defined(0xC81) = currentlyEnabled(Ext_Zicntr) & (mxlen == 32) // timeh
function clause is_CSR_defined(0xC82) = currentlyEnabled(Ext_Zicntr) & (mxlen == 32) // instreth

function clause read_CSR(0xC00) = mcycle[(mxlen - 1) .. 0]
function clause read_CSR(0xC01) = mtime[(mxlen - 1) .. 0]
function clause read_CSR(0xC02) = minstret[(mxlen - 1) .. 0]
function clause read_CSR(0xC80 if mxlen == 32) = mcycle[63 .. 32]
function clause read_CSR(0xC81 if mxlen == 32) = mtime[63 .. 32]
function clause read_CSR(0xC82 if mxlen == 32) = minstret[63 .. 32]


/* machine counters/timers */
mapping clause csr_name_map = 0xB00  <-> "mcycle"
mapping clause csr_name_map = 0xB02  <-> "minstret"
mapping clause csr_name_map = 0xB80  <-> "mcycleh"
mapping clause csr_name_map = 0xB82  <-> "minstreth"

function clause is_CSR_defined(0xB00) = currentlyEnabled(Ext_Zicntr) // mcycle
function clause is_CSR_defined(0xB02) = currentlyEnabled(Ext_Zicntr) // minstret
function clause is_CSR_defined(0xB80) = currentlyEnabled(Ext_Zicntr) & mxlen == 32 // mcycleh
function clause is_CSR_defined(0xB82) = currentlyEnabled(Ext_Zicntr) & mxlen == 32 // minstreth

function clause read_CSR(0xB00) = mcycle[(mxlen - 1) .. 0]
function clause read_CSR(0xB02) = minstret[(mxlen - 1) .. 0]
function clause read_CSR(0xB80 if mxlen == 32)= mcycle[63 .. 32]
function clause read_CSR(0xB82 if mxlen == 32) = minstret[63 .. 32]

function clause write_CSR(0xB00, value) = { mcycle[(mxlen - 1) .. 0] = value; Ok(value) }
function clause write_CSR(0xB02, value) = { minstret[(mxlen - 1) .. 0] = value; minstret_increment = false; Ok(value) }
function clause write_CSR((0xB80, value) if mxlen == 32) = { mcycle[63 .. 32] = value; Ok(value) }
function clause write_CSR((0xB82, value) if mxlen == 32) = { minstret[63 .. 32] = value; minstret_increment = false; Ok(value) }
