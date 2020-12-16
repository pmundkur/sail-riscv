#include "sail.h"
#include "riscv_sail.h"
#include "riscv_hpmevents_impl.h"

riscv_hpm_event platform_events[] =
  {
   // One entry for each event defined in platform_events.enums, with
   // the second element being the value used in software to select
   // the event when written to the mhpmevent registers.

   // This should be the last entry.
   { E_last, 0 },
  };

// We process any platform-specific events here.  This file will
// differ on a per-platform basis.
void signal_platform_events() {
  // TODO: handle any instruction related events, and signal them
  // using riscv_signal_event().
  uint64_t inst = zinstruction;
  riscv_signal_event(E_branch_taken);
}
