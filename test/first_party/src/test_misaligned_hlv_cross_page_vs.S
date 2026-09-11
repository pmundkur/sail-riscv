#include "common/encoding.h"

// Tests a misaligned HLV load that crosses a page boundary where the second
// page is unmapped at VS-stage. A correct implementation splits the access
// and translates each page separately, taking a load page fault on the
// second page. A faulty implementation translates only the base address and
// performs the whole load at once, so the missing mapping goes unnoticed.
//
// See also test_misaligned_hlv_cross_page_g.S, which covers the equivalent
// G-stage-only fault.

// Page A: GVA/GPA/SPA 0x80000000, identity-mapped 1 GiB gigapage, fully valid.
// Page B: GVA 0xC0000000, deliberately left unmapped at VS-stage.
// LOAD_FROM: last doubleword straddling the A/B boundary (4 bytes in each page).
#define PAGE_A     0x80000000
#define PAGE_B     0xC0000000
#define LOAD_FROM  0xBFFFFFFC

.global main
main:

vs_pt_init:
  // VS-stage: map GVA 0x80000000 -> GPA 0x80000000 (gigapage). Leave
  // vspt_0[3] (GVA 0xC0000000) zero so the second page has no VS-stage
  // mapping.
  li t0, PAGE_A
  srl t0, t0, RISCV_PGSHIFT - PTE_PPN_SHIFT
  ori t0, t0, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D
  la t1, vspt_0
  li t2, 2       # VPN[2] = 2 for GVA 0x80000000 under Sv39
  sll t2, t2, 3  # byte offset = 2 * 8 (PTE size)
  add t1, t1, t2
  sd t0, 0(t1)   # vspt_0[2] = pte

init_vsatp:
  li t0, (SATP_MODE & ~(SATP_MODE << 1)) * SATP_MODE_SV39
  la t1, vspt_0
  srl t1, t1, RISCV_PGSHIFT
  or t1, t1, t0
  csrw vsatp, t1
  hfence.vvma

guest_pt_init:
  // G-stage: map GPA 0x80000000 -> SPA 0x80000000 (gigapage). This covers
  // both page A and the VS-stage page table, so the VS-stage walk itself
  // never faults.
  li t0, PAGE_A
  srl t0, t0, RISCV_PGSHIFT - PTE_PPN_SHIFT
  ori t0, t0, PTE_V | PTE_R | PTE_W | PTE_X | PTE_U | PTE_A | PTE_D
  la t1, gpt_0
  li t2, 2
  sll t2, t2, 3
  add t1, t1, t2
  sd t0, 0(t1)

init_hgatp:
  li t0, (SATP_MODE & ~(SATP_MODE << 1)) * SATP_MODE_SV39
  la t1, gpt_0
  srl t1, t1, RISCV_PGSHIFT
  or t1, t1, t0
  csrw hgatp, t1
  hfence.gvma

hstatus_init:
  li t0, HSTATUS_SPVP
  csrs hstatus, t0

  la t0, check_fault
  csrw mtvec, t0

  // 8-byte load from 0xBFFFFFFC: bytes 0xBFFFFFFC..0xC0000003 span page A and
  // the unmapped page B. Must raise a load page fault on the page B half.
  li t0, LOAD_FROM
  hlv.d t2, 0(t0)

  j fail # A faulty implementation reaches here (no fault raised).

.align 4
check_fault:
  // VS-stage fault on the page B half.
  csrr t0, mcause
  li t1, CAUSE_LOAD_PAGE_FAULT
  bne t0, t1, fail

  // mtval = faulting GVA, in page B.
  csrr t0, mtval
  li t1, PAGE_B
  bne t0, t1, fail

  // No G-stage involvement, so mtval2 must be 0.
  csrr t0, mtval2
  bne t0, x0, fail

  j pass

pass:
  li a0, 0
  ret

fail:
  li a0, 1
  ret

.bss

.align 12
vspt_0: .fill 512, 8, 0  # Sv39 VS-stage root page table (4 KiB)

.align 14
gpt_0: .fill 2048, 8, 0  # Sv39x4 G-stage root page table (16 KiB)
