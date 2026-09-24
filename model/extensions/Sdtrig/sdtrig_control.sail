// =======================================================================================
// This Sail RISC-V architecture model, comprising all files and
// directories except where otherwise noted is subject the BSD
// two-clause license in the LICENSE file.
//
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// Trigger matching and processing

// This function returns true when triggers are prevented from
// matching or firing due to reentrancy protection.
function prevent_reentrance(act: Trig_Action, priv : Privilege) -> bool = {
  // Reentrancy controls only apply for Breakpoint actions.
  if act != TA_Breakpoint then return false;

  match sdtrig_breakpoint_reentrancy {
    Use_tcontrol          => priv == Machine & tcontrol[mte] == 0b0,
    Use_interrupt_enables => match priv {
      Machine             => mstatus[MIE] == 0b0,
      Supervisor          => medeleg[Breakpoint] == 0b1 & mstatus[SIE] == 0b0,
      VirtualSupervisor   => medeleg[Breakpoint] == 0b1 & hedeleg[Breakpoint] == 0b1 & vsstatus[SIE] == 0b0,
      VirtualUser         => false,
      User                => false,
    },
    No_reentrancy_support => false,
  }
}

// icount triggers

function icount_match(t : ICount, priv : Privilege, reentrance : bool) -> bool = {
  not(t.action == TA_Breakpoint & reentrance) & (match priv {
    Machine           => t.m,
    Supervisor        => t.s,
    User              => t.u,
    VirtualSupervisor => t.vs,
    VirtualUser       => t.vu,
  })
}

function match_icount_triggers(priv : Privilege, reentrance : bool) -> unit = {
  if not(currentlyEnabled(Ext_Sdtrig)) then return ();

  foreach (i from 0 to num_triggers - 1) {
    match triggers[i] {
      T_icount(t) =>
        if t.active & icount_match(t, priv, reentrance) then {
          // If the trigger matched on a write to the icount trigger
          // with count = 1, pending might (configured with
          // `write_sets_pending` as true) or might not
          // (`write_sets_pending` as false) be set.  If that write
          // updated `pending`, that value may be overridden.
          let set_pending : bool = match written_trigger_index {
            Some(idx, TDATA1) => idx != i | icount_self_write_sets_pending,
            Some(_, _)        => true,
            None()            => true,
          };

          // As implemented, this trigger cannot match for multiple
          // events during a single instruction.
          let new_t : ICount = match unsigned(t.count) {
            // When count is 0, it stays at 0 until explicitly written.
            0 => t,
            1 => {t with
                   count = if icount_count_is_hardwired_one then t.count else zeros(),
                   pending = set_pending},
            _ => {t with count = t.count - 1},
          };
          triggers[i] = T_icount(new_t);

          if get_config_print_trigger()
          then print_log("Matched icount at index #" ^ dec_str(i) ^ " with action " ^ trigger_action_name(t.action));
          trigger_match_callback(i);
        },
      _ => (),
    }
  }
}

// itrigger

// TODO: handle NMI interrupts.

function itrigger_match(t : ITrigger, intr : InterruptType, from_priv : Privilege, to_priv : Privilege) -> bool = {
  let priv_match : bool = not(prevent_reentrance(t.action, to_priv)) & (match from_priv {
    Machine           => t.m,
    Supervisor        => t.s,
    User              => t.u,
    VirtualSupervisor => t.vs,
    VirtualUser       => t.vu,
  });

  priv_match & ((t.tdata2 & make_itrigger_flag(intr)) != zeros())
}

function match_itrigger_triggers(intr : InterruptType, from_priv : Privilege, to_priv : Privilege) -> unit = {
  if not(currentlyEnabled(Ext_Sdtrig)) then return ();

  foreach (i from 0 to num_triggers - 1) {
    match triggers[i] {
      T_itrigger(t) =>
        if itrigger_match(t, intr, from_priv, to_priv) then {
          triggers[i] = T_itrigger({t with pending = true, hit = true});

          if get_config_print_trigger()
          then print_log("Interrupt " ^ interruptType_to_str(intr) ^ " matched itrigger at index #" ^ dec_str(i) ^ " with action " ^ trigger_action_name(t.action));
          trigger_match_callback(i);
        },
      _ => (),
    }
  }
}

// etrigger

private function etrigger_match(t : ETrigger, e : ExceptionType, from_priv : Privilege, to_priv : Privilege) -> bool = {
  let priv_match : bool = not(prevent_reentrance(t.action, to_priv)) & (match from_priv {
    Machine           => t.m,
    Supervisor        => t.s,
    User              => t.u,
    VirtualSupervisor => t.vs,
    VirtualUser       => t.vu,
  });

  priv_match & ((t.tdata2 & make_etrigger_flag(e)) != zeros())
}

function match_etrigger_triggers(exc : ExceptionType, from_priv : Privilege, to_priv : Privilege) -> unit = {
  if not(currentlyEnabled(Ext_Sdtrig)) then return ();

  foreach (i from 0 to num_triggers - 1) {
    match triggers[i] {
      T_etrigger(t) =>
        if etrigger_match(t, exc, from_priv, to_priv) then {
          triggers[i] = T_etrigger({t with pending = true, hit = true});

          if get_config_print_trigger()
          then print_log("Exception " ^ exceptionType_to_str(exc) ^ " matched etrigger at index #" ^ dec_str(i) ^ " with action " ^ trigger_action_name(t.action));
          trigger_match_callback(i);
        },
      _ => (),
    }
  }
}

// memory triggers

private function compare_value_napot(value : xlenbits, tdata2 : xlenbits) -> bool = {
  let lsz : range(0, xlen - 1) = match least_significant_zero(tdata2) {
    None()  => internal_error(__FILE__, __LINE__, "Invalid tdata2 for NAPOT match: " ^ bits_str(tdata2)),
    Some(i) => i,
  };
  // `tdata2` should have been validated.
  assert(lsz < sdtrig_mcontrol6_maskmax);
  let M = xlen - 1 - lsz;
  assert(M > 0);
  value[xlen - 1 .. xlen - M] == tdata2[xlen - 1 .. xlen - M]
}

private enum mask_type = {MASK_LO, MASK_HI}

private function compare_value_mask(value : xlenbits, tdata2 : xlenbits, mask_type : mask_type) -> bool = {
  let test_val  = if mask_type == MASK_LO
                  then value[xlen / 2 - 1 .. 0]
                  else value[xlen - 1 .. xlen / 2];
  let mask      = tdata2[xlen - 1 .. xlen / 2];
  let check_val = tdata2[xlen / 2 - 1 .. 0];

  (test_val & mask) == check_val
}

private function match_compare_value_xlen(t_match : Trig_Match, value : xlenbits, tdata2 : xlenbits) -> bool = {
  match t_match {
    TM_EQ          => value == tdata2,
    TM_NAPOT       => compare_value_napot(value, tdata2),
    TM_GE          => value >=_u tdata2,
    TM_LT          => value <_u tdata2,
    TM_MASK_LO     => compare_value_mask(value, tdata2, MASK_LO),
    TM_MASK_HI     => compare_value_mask(value, tdata2, MASK_HI),

    TM_NEQ         => value != tdata2,
    TM_NOT_NAPOT   => not(compare_value_napot(value, tdata2)),
    TM_NOT_MASK_LO => not(compare_value_mask(value, tdata2, MASK_LO)),
    TM_NOT_MASK_HI => not(compare_value_mask(value, tdata2, MASK_HI)),
  }
}

let address_select_matches_all : bool = config extensions.Sdtrig.mcontrol6.address_select_matches_all_addresses

private function match_compare_address forall 'width, 0 < 'width <= max_mem_access. (
  t_match : Trig_Match,
  addr    : xlenbits,
  width   : int('width),
  tdata2  : xlenbits,
) -> option(xlenbits) = {
  // Match all the accessed virtual addresses.
  let span = if address_select_matches_all then width - 1 else 0;

  foreach (i from 0 to span) {
    let match_addr = addr + width;
    if match_compare_value_xlen(t_match, match_addr, tdata2)
    then return Some(match_addr);
  };

  None();
}

private function match_compare_value forall 'width, is_mem_width_wide('width) . (
  t_match : Trig_Match,
  t_size  : Trig_Match_Size,
  value   : bits(8 * 'width),
  width   : int('width),
  tdata2  : xlenbits,
) -> bool = {
  // `tdata2` is of size XLEN, and accesses of larger size are not supported.
  if   width > xlen_bytes | (t_size != 0 & t_size != 8 * width)
  then false
  else match_compare_value_xlen(t_match, zero_extend(value), tdata2)
}

// Returns the value to be used for `tval` if there is a match.
private function memory_trigger_match(
  t       : MControl6,
  priv    : Privilege,
  payload : MemoryTriggerPayload
) -> option(xlenbits) = {

  let priv_match : bool = not(prevent_reentrance(t.action, priv)) & (match priv {
    Machine           => t.m,
    Supervisor        => t.s,
    User              => t.u,
    VirtualSupervisor => t.vs,
    VirtualUser       => t.vu,
  });
  if not(priv_match) then return None();

  match payload {
    TriggerFetchAddr(addr) =>
      if t.execute & t.select == Compare_Address & match_compare_value_xlen(t.t_match, addr, t.tdata2)
      then Some(addr) else None(),
    TriggerFetchInstr(addr, inst) =>
      if t.execute & t.select == Compare_Data & match_compare_value_xlen(t.t_match, inst, t.tdata2)
      then Some(addr) else None(),
    TriggerLoadAddress(addr, width) =>
      if t.load & t.select == Compare_Address
      then match_compare_address(t.t_match, addr, width, t.tdata2)
      else None(),
    TriggerStoreAddress(addr, width) =>
      if t.store & t.select == Compare_Address
      then match_compare_address(t.t_match, addr, width, t.tdata2)
      else None(),
    TriggerLoadData(addr, data, width) =>
      if t.load & t.select == Compare_Data & match_compare_value(t.t_match, t.size, data, width, t.tdata2)
      then Some(addr) else None(),
    TriggerStoreData(addr, data, width) =>
      if t.store & t.select == Compare_Data & match_compare_value(t.t_match, t.size, data, width, t.tdata2)
      then Some(addr) else None(),
  }
}

private enum loop_chain_state = {
  NotInChain,
  InChainWithMatch,
  InChainWithoutMatch,
}

private function match_memory_triggers(
  priv    : Privilege,
  payload : MemoryTriggerPayload,
  hit     : Hit
) -> option(pending_trigger_info) = {
  assert(num_triggers > 0);

  var chain_state : loop_chain_state =
    if trigger_is_in_chain(triggers[0]) then InChainWithMatch else NotInChain;

  // The loop takes the last matching trigger.
  var matched_info : option(pending_trigger_info) = None();

  foreach (i from 0 to num_triggers - 1) {
    match triggers[i] {
      T_mcontrol6(t) => {
        // Only do a match if there is no existing match and we're not
        // prevented by chain conditions.
        let match_result = if   is_none(t.match_info) & chain_state != InChainWithoutMatch
                           then match memory_trigger_match(t, priv, payload) {
                             None()     => None(),
                             Some(tval) => Some(tval, hit),
                           } else t.match_info;
        triggers[i] = T_mcontrol6({t with match_info = match_result});
        match chain_state {
          NotInChain =>
            if t.chain then {
              chain_state = if is_some(match_result) then InChainWithMatch else InChainWithoutMatch;
            } else match match_result {
              None()        => (),
              Some(tval, _) => matched_info = Some(t.action, i, tval),
            },
          InChainWithoutMatch => {
            // This trigger should not have matched yet.
            assert(is_none(match_result));
            if not(t.chain) then chain_state = NotInChain;
          },
          InChainWithMatch =>
            if t.chain then {
              if is_none(match_result) then chain_state = InChainWithoutMatch;
            } else {
              chain_state = NotInChain;
              // The chain ended.
              match match_result {
                None()        => (),
                Some(tval, _) => matched_info = Some(t.action, i, tval),
              }
            }
        }
      },
      _ => chain_state = NotInChain,
    }
  };

  matched_info
}

// This function can be called multiple times during the execution of
// an instruction, for progressively lower priority `before` triggers.
function match_memory_trigger_before(priv : Privilege, payload : MemoryTriggerPayload) -> option(pending_trigger_info) = {
  if not(currentlyEnabled(Ext_Sdtrig)) then return None();

  match_memory_triggers(priv, payload, Hit_before)
}

function match_memory_trigger_after(priv : Privilege, payload : MemoryTriggerPayload) -> unit = {
  if not(currentlyEnabled(Ext_Sdtrig)) then return ();

  // Update the trigger internal state for where
  // `find_highest_priority_pending_trigger` can find it.
  let _ = match_memory_triggers(priv, payload, Hit_imm_after);
}

// firing

// Find and fire all pending `before` triggers (currently only
// `mcontrol6`).  This clears their match state and sets `hit` to
// `Hit_before`.  It clears the match state of any partially matched
// chains, since they will have lower priority than the current
// matched and pending triggers, and cannot fire for the current
// instruction.

function fire_pending_before_triggers(_pti : pending_trigger_info) -> unit = {
  assert(num_triggers > 0);

  foreach (i from 0 to num_triggers - 1) {
    match triggers[i] {
      T_mcontrol6(t) => match t.match_info {
        None()       => (),
        Some(_, hit) => {
          // Set hit only on triggers that terminate a chain since they are the ones
          // that fire; the action on the other triggers is ignored.
          let t = if not(t.chain) & hit == Hit_before
                  then {t with hit}
                  else t;
          triggers[i] = T_mcontrol6({t with match_info = None()});
        },
      },
      _ => (),
    };
  }
}

private function fire_trigger_after(idx : trigger_index) -> bool = {
  let (t, action, fired) : (Trigger, Trig_Action, bool) = match triggers[idx] {
    T_icount(t) => {
      let t = if icount_count_is_hardwired_one
              then {t with m = false, s = false, u = false, vs = false, vu = false}
              else t;
      (T_icount({t with pending = false, hit = true}), t.action, true)
    },
    T_itrigger(t) => {
      (T_itrigger({t with pending = false}), t.action, true)
    },
    T_etrigger(t) => {
      (T_etrigger({t with pending = false}), t.action, true)
    },
    T_mcontrol6(t) => match t.match_info {
      Some(_, hit) => {
        // We could have chains with mixed `before` and `after`
        // timing; these can only fire `after`.  For partially matched
        // `before` triggers, this resets their match state; for
        // matched triggers it also sets `hit`.
        assert(t.chain | hit == Hit_imm_after);
        let fire = not(t.chain);
        (T_mcontrol6({t with
           hit = if fire then Hit_imm_after else t.hit,
           match_info = None()
         }), t.action, fire)
      },
      // Shouldn't really get this case, since it is handled in the caller.
      None()       => (T_mcontrol6(t), t.action, false),
    },
    T_disabled(_) => internal_error(__FILE__, __LINE__, "Disabled triggers cannot fire."),
  };
  triggers[idx] = t;

  if fired then {
    if get_config_print_trigger()
    then print_log("Fired " ^ trigger_name(t) ^ " at index #" ^ dec_str(idx) ^ " with action " ^ trigger_action_name(action));
    trigger_fire_callback(idx);
  };

  fired
}

// Find and fire the highest priority pending triggers, and return the
// selected action, trigger index and `tval`.  If the selected action is
// not `TA_Breakpoint`, then the `tval` should not be used.

function find_highest_priority_pending_trigger(priv : Privilege) -> option(pending_trigger_info) = {
  if not(currentlyEnabled(Ext_Sdtrig)) then return None();
  // TODO: Triggers do not fire while in Debug Mode.

  assert(num_triggers > 0);

  // TODO: When TA_Enter_Debug when Sdext is supported and TA_Enter_Debug
  // and TA_Breakpoint actions are both pending, make both actions
  // take place.

  // "If more than one of these triggers has action=0 (TA_Breakpoint),
  // then tval is updated in accordance with one of them, but which
  // one is unspecified."
  //
  // Here, we pick `tval` from the last fired trigger with an action
  // of `TA_Breakpoint`.

  var found_pending : bool = false;
  var pending_index : trigger_index = 0;
  var pending_action : Trig_Action = TA_Breakpoint;
  var pending_tval : xlenbits = zeros();

  foreach (i from 0 to num_triggers - 1) {
    match triggers[i] {
      T_disabled(_) => (),
      T_icount(t) => {
        assert(t.pending ==> t.active);
        // icount triggers fire in a mode where the trigger is enabled.
        if t.pending & icount_match(t, priv, prevent_reentrance(TA_Breakpoint, priv)) then {
          found_pending = true;
          pending_index  = i;
          pending_action = t.action;
          if pending_action == TA_Breakpoint then pending_tval = zeros();
          let fired = fire_trigger_after(i);
          assert(fired);
        }
      },
      T_itrigger(t) =>
        if t.pending & not(prevent_reentrance(t.action, priv)) then {
          found_pending = true;
          pending_index  = i;
          pending_action = t.action;
          if pending_action == TA_Breakpoint then pending_tval = zeros();
          let fired = fire_trigger_after(i);
          assert(fired);
        },
      T_etrigger(t) =>
        if t.pending & not(prevent_reentrance(t.action, priv)) then {
          found_pending = true;
          pending_index  = i;
          pending_action = t.action;
          if pending_action == TA_Breakpoint then pending_tval = zeros();
          let fired = fire_trigger_after(i);
          assert(fired);
        },
      T_mcontrol6(t) => {
        match t.match_info {
          Some(tval, _) => {
            // Since these triggers matched, their reentrancy condition
            // should not have changed. For `before` triggers, the
            // instruction did not execute, so there should be no change;
            // for `after` triggers (that apply to Loads and AMOs), the
            // instruction retired successfully.
            assert(not(prevent_reentrance(t.action, priv)));
            let fired = fire_trigger_after(i);
            if fired then {
              found_pending = true;
              pending_index  = i;
              pending_action = t.action;
              if pending_action == TA_Breakpoint then pending_tval = tval;
            };
          },
          None()  => (),
        }
      },
    }
  };

  if found_pending then Some(pending_action, pending_index, pending_tval)
  else None()
}

// update at the end of a step

function update_triggers() -> unit = {
  match written_trigger_index {
    None()    => (),
    Some(idx, TDATA1) => {
      match triggers[idx] {
        T_icount(t) => match t.new_count {
          Some(c) => triggers[idx] = T_icount({t with count = c, new_count = None(), active = true}),
          None()  => assert(t.active),
        },
        _ => (),
      };
      written_trigger_index = None()
    },
    Some(_) => {
      written_trigger_index = None()
    },
  }
}
