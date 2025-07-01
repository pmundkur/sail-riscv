/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

// Trigger field types and encodings

enum Trig_Type = {
  TT_none,       // no trigger
  TT_legacy,
  TT_mcontrol,   // address/data match (deprecated)
  TT_icount,     // instruction count
  TT_itrigger,   // interrupt
  TT_etrigger,   // exception
  TT_mcontrol6,  // address/data match
  TT_exttrigger, // external
  TT_custom,
  TT_disabled,
  TT_reserved,
}

mapping trig_type : bits(4) <-> Trig_Type = {
  0b0000 <-> TT_none,
  0b0001 <-> TT_legacy,
  0b0010 <-> TT_mcontrol,
  0b0011 <-> TT_icount,
  0b0100 <-> TT_itrigger,
  0b0101 <-> TT_etrigger,
  0b0110 <-> TT_mcontrol6,
  0b0111 <-> TT_exttrigger,
  0b1111 <-> TT_disabled,
  forwards 0b1100 => TT_custom,
  forwards 0b1101 => TT_custom,
  forwards 0b1110 => TT_custom,
  forwards 0b1000 => TT_reserved,
  forwards 0b1001 => TT_reserved,
  forwards 0b1010 => TT_reserved,
  forwards 0b1011 => TT_reserved,
}

mapping trig_name : Trig_Type <-> string = {
  TT_none       <-> "none",
  TT_legacy     <-> "legacy",
  TT_mcontrol   <-> "mcontrol",
  TT_icount     <-> "icount",
  TT_itrigger   <-> "itrigger",
  TT_etrigger   <-> "etrigger",
  TT_mcontrol6  <-> "mcontrol6",
  TT_exttrigger <-> "exttrigger",
  TT_custom     <-> "custom",
  TT_disabled   <-> "disabled",
  TT_reserved   <-> "reserved",
}

function is_supported_trig_type(tt : bits(4)) -> bool = {
  if not(trig_type_forwards_matches(tt)) then return false;
  let typ = trig_type(tt);
  typ == TT_icount // XXX: add others
}

function make_info(t : Trig_Type) -> bits(16) =
  zero_extend(16, 0b1) << unsigned(trig_type(t))

// This could be converted into a top-level let binding once
// the Sail compiler supports incomplete pattern matches in
// such bindings; this will avoid the overhead of a function
// call for a constant value.
function supported_triggers_info() -> bits(16) = {
  var info : bits(16) = zeros();
  info = info | (zero_extend(16, 0b1) << unsigned(trig_type(TT_icount)));
  // XXX: add others
  info
}


enum Trig_Action = {
  TA_BREAKPOINT, TA_ENTER_DEBUG, TA_TRACE_ON, TA_TRACE_OFF,
  TA_TRACE_NOTIFY, TA_EXT_TRIGGER_0, TA_EXT_TRIGGER_1,
}

mapping trig_action : bits(4) <-> Trig_Action = {
  0b0000 <-> TA_BREAKPOINT,
  0b0001 <-> TA_ENTER_DEBUG,
  0b0010 <-> TA_TRACE_ON,
  0b0011 <-> TA_TRACE_OFF,
  0b0100 <-> TA_TRACE_NOTIFY,
  0b1000 <-> TA_EXT_TRIGGER_0,
  0b1001 <-> TA_EXT_TRIGGER_1,
}

function is_supported_action(a : bits(4)) -> bool = {
  let act = trig_action(a) in
  act == TA_BREAKPOINT // | (currentlyEnabled(Ext_Sdext) & TA_ENTER_DEBUG)
}

enum Hit = {Hit_false, Hit_before, Hit_after, Hit_imm_after}

mapping hit_bits : bits(2) <-> Hit = {
  0b00 <-> Hit_false,
  0b01 <-> Hit_before,
  0b10 <-> Hit_after,
  0b11 <-> Hit_imm_after,
}

type Trig_Match_Size = {0, 8, 16, 32, 48, 64, 128}

mapping trig_match_size : bits(3) <-> Trig_Match_Size = {
  0b000 <-> 0,
  0b001 <-> 8,
  0b010 <-> 16,
  0b011 <-> 32,
  0b100 <-> 48,
  0b101 <-> 64,
  0b110 <-> 128,
}

enum Trig_Match = {
  TM_EQ, TM_NAPOT, TM_GE, TM_LT, TM_MASK_LO, TM_MASK_HI,
  TM_NEQ, TM_NOT_NAPOT, TM_NOT_MASK_LO, TM_NOT_MASK_HI,
}

mapping trig_match_val : bits(4) <-> Trig_Match = {
  0b0000 <-> TM_EQ,
  0b0001 <-> TM_NAPOT,
  0b0010 <-> TM_GE,
  0b0011 <-> TM_LT,
  0b0100 <-> TM_MASK_LO,
  0b0101 <-> TM_MASK_HI,
  0b1000 <-> TM_NEQ,
  0b1001 <-> TM_NOT_NAPOT,
  0b1100 <-> TM_NOT_MASK_LO,
  0b1101 <-> TM_NOT_MASK_HI,
}

// Trigger types and their layouts.

// Each trigger has an associated struct and a bitfield.  The struct
// is used for efficient trigger matching and action handling, while
// the bitfield is used for the serialization and deserialization needed
// to handle reads and writes to the tdata1 register.  The expectation
// is that the former happens much more often than the latter.

struct Disabled = {
  dmode  : bool,
  data   : bits(xlen - 5),
  tdata2 : xlenbits,
  tdata3 : xlenbits,
}

bitfield Disabled_bits : xlenbits = {
  trig_type : xlen - 1 .. xlen - 4,
  dmode     : xlen - 5,
  data      : xlen - 6 .. 0,
}

function Disabled_to_bits(t : Disabled) -> Disabled_bits =
  [Mk_Disabled_bits(zeros()) with
    trig_type = trig_type(TT_disabled),
    dmode = bool_bits(t.dmode),
    data  = t.data
  ]

struct MControl6 = {
  dmode      : bool,
  uncertain  : bool,
  hit        : Hit,
  vs         : bool,
  vu         : bool,
  select     : bool,
  size       : Trig_Match_Size,
  action     : Trig_Action,
  chain      : bool,
  t_match    : Trig_Match,
  m          : bool,
  uncertainm : bool,
  s          : bool,
  u          : bool,
  execute    : bool,
  store      : bool,
  load       : bool,
  tdata2     : xlenbits,
  tdata3     : xlenbits,
  info       : bits(16),
}

bitfield MControl6_bits : xlenbits = {
  trig_type     : xlen - 1 .. xlen - 4,
  dmode         : xlen - 5,
  uncertain     : 26,
  hit1          : 25,
  vs            : 24,
  vu            : 23,
  hit0          : 22,
  select        : 21,
  size          : 18 .. 16,
  action        : 15 .. 12,
  chain         : 11,
  t_match       : 10 .. 7,
  m             : 6,
  uncertainm    : 5,
  s             : 4,
  u             : 3,
  execute       : 2,
  store         : 1,
  load          : 0,
}

function MControl6_to_bits(t : MControl6) -> MControl6_bits =
  let hit = hit_bits(t.hit) in
  [Mk_MControl6_bits(zeros()) with
    trig_type  = trig_type(TT_mcontrol6),
    dmode      = bool_bits(t.dmode),
    uncertain  = bool_bits(t.uncertain),
    hit1       = [hit[1]],
    vs         = bool_bits(t.vs),
    vu         = bool_bits(t.vu),
    hit0       = [hit[0]],
    select     = bool_bits(t.select),
    size       = trig_match_size(t.size),
    action     = trig_action(t.action),
    chain      = bool_bits(t.chain),
    t_match    = trig_match_val(t.t_match),
    m          = bool_bits(t.m),
    uncertainm = bool_bits(t.uncertainm),
    s          = bool_bits(t.s),
    u          = bool_bits(t.u),
    execute    = bool_bits(t.execute),
    store      = bool_bits(t.store),
    load       = bool_bits(t.load),
  ]

struct ICount = {
  dmode   : bool,
  vs      : bool,
  vu      : bool,
  hit     : bool,
  count   : bits(14),
  m       : bool,
  pending : bool,
  s       : bool,
  u       : bool,
  action  : Trig_Action,
  tdata3  : xlenbits,
  info    : bits(16),
}

bitfield ICount_bits : xlenbits = {
  trig_type : xlen - 1 .. xlen - 4,
  dmode     : xlen - 5,
  vs        : 26,
  vu        : 25,
  hit       : 24,
  count     : 23 .. 10,
  m         : 9,
  pending   : 8,
  s         : 7,
  u         : 6,
  action    : 5 .. 0,
}

function ICount_to_bits(t : ICount) -> ICount_bits =
  [Mk_ICount_bits(zeros()) with
    trig_type = trig_type(TT_icount),
    dmode     = bool_bits(t.dmode),
    vs        = bool_bits(t.vs),
    vu        = bool_bits(t.vu),
    hit       = bool_bits(t.hit),
    count     = t.count,
    m         = bool_bits(t.m),
    pending   = bool_bits(t.pending),
    s         = bool_bits(t.s),
    u         = bool_bits(t.u),
    action    = zero_extend(trig_action(t.action)),
  ]

struct ITrigger = {
  dmode  : bool,
  hit    : bool,
  vs     : bool,
  vu     : bool,
  nmi    : bool,
  m      : bool,
  s      : bool,
  u      : bool,
  action : Trig_Action,
  tdata2 : xlenbits,
  tdata3 : xlenbits,
  info   : bits(16),
}

struct ETrigger = {
  dmode  : bool,
  hit    : bool,
  vs     : bool,
  vu     : bool,
  nmi    : bool,
  m      : bool,
  s      : bool,
  u      : bool,
  action : Trig_Action,
  tdata2 : xlenbits,
  tdata3 : xlenbits,
  info   : bits(16),
}

bitfield IETrigger_bits : xlenbits = {
  trig_type : xlen - 1 .. xlen - 4,
  dmode     : xlen - 5,
  hit       : xlen - 6,
  vs        : 12,
  vu        : 11,
  nmi       : 10, // zeroed in etrigger
  m         : 9,
  s         : 7,
  u         : 6,
  action    : 5 .. 0,
}

function ITrigger_to_bits(t : ITrigger) -> IETrigger_bits =
 [Mk_IETrigger_bits(zeros()) with
   trig_type = trig_type(TT_itrigger),
   dmode     = bool_bits(t.dmode),
   hit       = bool_bits(t.hit),
   vs        = bool_bits(t.vs),
   vu        = bool_bits(t.vu),
   nmi       = bool_bits(t.nmi),
   m         = bool_bits(t.m),
   s         = bool_bits(t.s),
   u         = bool_bits(t.u),
   action    = zero_extend(trig_action(t.action)),
 ]

function ETrigger_to_bits(t : ETrigger) -> IETrigger_bits =
 [Mk_IETrigger_bits(zeros()) with
   trig_type = trig_type(TT_itrigger),
   dmode     = bool_bits(t.dmode),
   hit       = bool_bits(t.hit),
   vs        = bool_bits(t.vs),
   vu        = bool_bits(t.vu),
   nmi       = 0b0,
   m         = bool_bits(t.m),
   s         = bool_bits(t.s),
   u         = bool_bits(t.u),
   action    = zero_extend(trig_action(t.action)),
 ]

union Trigger = {
  T_none      : unit,
  T_disabled  : Disabled,
  T_mcontrol6 : MControl6,
  T_icount    : ICount,
  T_itrigger  : ITrigger,
  T_etrigger  : ETrigger,
  // other types (mcontrol, tmexttrigger) not yet implemented
}

let trig_reset_val : Trigger =
  T_disabled(struct { dmode = false, data = zeros(), tdata2 = zeros(), tdata3 = zeros() })

function tdata1_of_trigger(t : Trigger) -> xlenbits =
  match t {
    T_none(()) => zeros(),
    T_disabled(s) => Disabled_to_bits(s).bits,
    T_mcontrol6(s) => MControl6_to_bits(s).bits,
    T_icount(s) => ICount_to_bits(s).bits,
    T_itrigger(s) => ITrigger_to_bits(s).bits,
    T_etrigger(s) => ETrigger_to_bits(s).bits,
  }

function tdata2_of_trigger(t : Trigger) -> xlenbits =
  match t {
    T_none(()) => zeros(),
    T_disabled(s) => s.tdata2,
    T_mcontrol6(s) => s.tdata2,
    T_icount(s) => zeros(),  // ICount doesn't use tdata2
    T_itrigger(s) => s.tdata2,
    T_etrigger(s) => s.tdata2,
  }

function tdata3_of_trigger(t : Trigger) -> xlenbits =
  match t {
    T_none(()) => zeros(),
    T_disabled(s) => s.tdata3,
    T_mcontrol6(s) => s.tdata3,
    T_icount(s) => s.tdata3,
    T_itrigger(s) => s.tdata3,
    T_etrigger(s) => s.tdata3,
  }

function info_of_trigger(t : Trigger) -> bits(16) =
  match t {
    T_none(()) => zeros(),
    T_disabled(s) => supported_triggers_info(),
    T_mcontrol6(s) => s.info,
    T_icount(s) => s.info,
    T_itrigger(s) => s.info,
    T_etrigger(s) => s.info,
  }

bitfield TInfo : xlenbits = {
  version : 31 .. 24,
  info    : 15 .. 0,
}

function tinfo_of_trigger(t : Trigger) -> TInfo =
  [Mk_TInfo(zeros()) with
    version = 0x01, // Only support ratified version 1.0 for now.
    info = info_of_trigger(t)]

// Other register layouts

bitfield TData1 : xlenbits = {
  trig_type : xlen - 1 .. xlen - 4,
  dmode     : xlen - 5,
  data      : xlen - 6 .. 0,
}

bitfield TControl : xlenbits = {
  mptr : 7,
  mte  : 3,
}

bitfield SContext : xlenbits = {
  data : 31 .. 0,
}

bitfield MContext : xlenbits = {
  hcontext : 13 .. 0,
}

bitfield External_Trigger : xlenbits = {
  trig_type : xlen - 1 .. xlen - 4,
  dmode     : xlen - 5,
  hit       : xlen - 6,
  intctl    : 22,
  select    : 16,
  action    : 6,
}

bitfield Trigger_Extra_RV32 : bits(32) = {
  mhvalue   : 31 .. 26,
  mhselect  : 25 .. 23,
  sbytemask : 19 .. 18,
  svalue    : 17 .. 2,
  sselect   : 1 .. 0,
}

bitfield Trigger_Extra_RV64 : bits(64) = {
  mhvalue   : 63 .. 51,
  mhselect  : 50 .. 48,
  sbytemask : 39 .. 36,
  svalue    : 33 .. 2,
  sselect   : 1 .. 0,
}

// Retain the new bits in the ignored fields.
function make_disabled_trigger(tdata1 : TData1, tdata2 : xlenbits, tdata3 : xlenbits) -> Trigger =
  T_disabled(struct { dmode  = bool_bits(tdata1[dmode]),
                      data   = tdata1[data],
                      tdata2 = tdata2,
                      tdata3 = tdata3 })

function make_trigger(tdata1 : TData1, tdata2 : xlenbits, tdata3 : xlenbits) -> Trigger = {
  let tt = tdata1[trig_type];
  if   not(is_supported_trig_type(tt))
  then return make_disabled_trigger(tdata1, tdata2, tdata3);

  match trig_type(tt) {
    TT_icount => {
      let v = Mk_ICount_bits(tdata1.bits);
      let act = v[action][3..0];
      // TODO: tdata3 is not yet supported
      if is_supported_action(act) & tdata3 == zeros() then {
        T_icount(struct {
          dmode = bool_bits(v[dmode]),
          vs = if currentlyEnabled(Ext_H) then bool_bits(v[vs]) else false,
          vu = if currentlyEnabled(Ext_H) then bool_bits(v[vu]) else false,
          hit = false, // TODO: not yet supported
          count = v[count],
          m = bool_bits(v[m]),
          pending = bool_bits(v[pending]),
          s = if currentlyEnabled(Ext_S) then bool_bits(v[s]) else false,
          u = if currentlyEnabled(Ext_U) then bool_bits(v[u]) else false,
          action = trig_action(act),
          tdata3 = zeros(),
          info = make_info(TT_icount),
        })
      } else {
        make_disabled_trigger(tdata1, tdata2, tdata3)
      }
    },
    // XXX: other trigger types.
    _ =>
      make_disabled_trigger(tdata1, tdata2, tdata3)
  }
}

// For now, only change the type of disabled triggers.  This is _a_ legal
// implementation, as `tdata1` is WARL.

function trigger_write_tdata1(t : Trigger, tdata1 : xlenbits) -> Trigger =
  match t {
    T_disabled(s) => make_trigger(Mk_TData1(tdata1), s.tdata2, s.tdata3),
    _ => t,
  }

// For now, ignore all writes to `tdata2` and `tdata3` of non-disabled
// triggers.
// TODO: the written value should be checked to be supported by the
// enabled triggers.

function trigger_write_tdata2(t : Trigger, tdata2 : xlenbits) -> Trigger =
  match t {
    T_disabled(s) => T_disabled({s with tdata2 = tdata2}),
    _ => t,
  }

// For now, ignore all tdata3 configuration.
function trigger_write_tdata3(t : Trigger, tdata3 : xlenbits) -> Trigger =
  match t {
    T_disabled(s) => T_disabled({s with tdata3 = zeros()}),
    _ => t,
  }
