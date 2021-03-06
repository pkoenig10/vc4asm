# BCM2835 "GPU_FFT" release 3.0
#
# Copyright (c) 2015, Andrew Holme.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the copyright holder nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

.set STAGES, 8

.include "gpu_fft.qinc"

##############################################################################
# Twiddles: src

.set TW16_P1_BASE,  0   # rx_tw_shared
.set TW16_P2_STEP,  1

.set TW16_P2_BASE,  0   # rx_tw_unique

##############################################################################
# Twiddles: dst

.set TW16_STEP, 0  # 1
.set TW16,      1  # 5

##############################################################################
# Registers

.set ra_link_1,         ra0
#                       rb0
.set ra_save_ptr,       ra1
#                       rb1
.set ra_temp,           ra2
.set rx_vpm,            rb2
.set ra_addr_x,         ra3
#                       rb3
.set ra_save_16,        ra4
#
.set ra_load_idx,       ra5
#                       rb5
.set ra_sync,           ra6
#                       rb6
.set ra_points,         ra7
#                       rb7
.set rx_tw_shared,      ra8
.set rx_tw_unique,      rb8

.set ra_tw_re,          ra9 # 6
.set rb_tw_im,          rb9 # 6

.set ra_vdw,            ra28
.set rb_vdw,            rb28

.set rx_inst,           ra29

.set rb_0x5555,         rb29
.set rx_0x3333,         rb30
.set rx_0x0F0F,         ra31

.set rb_0x80,           rb31

##############################################################################
# Constants

mov rb_0x80,    0x80

mov rb_0x5555,  0x5555
mov rx_0x3333,  0x3333
mov rx_0x0F0F,  0x0F0F

mov ra_vdw, vdw_setup_0(16, 16, dma_h32( 0,0))
# (MM) Optimized: use xor for vpm swap (less memory I/O, save A register)
mov rb_vdw, vdw_setup_0(16, 16, dma_h32(16,0)) - vdw_setup_0(16, 16, dma_h32( 0,0))

##############################################################################
# Twiddles: ptr

init_tw

##############################################################################
# Instance

# (MM) Optimized: better procedure chains
# Saves several branch instructions and 2 registers
    mov r3, unif;              mov ra_save_16, 0
    shl.setf r0, r3, 5;        mov ra_sync, 0
    mov.ifnz r1, :sync_slave - :sync - 4*8 # -> rx_inst-1
    add.ifnz ra_sync, r1, r0
    mov.ifnz r1, :save_slave - :save_16
    mov.ifnz ra_save_16, r1;
    
# (MM) Optimized: reduced VPM registers to 1
inst_vpm r3, rx_vpm

    ;mov rx_inst, r3


##############################################################################
# Redefining macros

.macro read_rev, stride
    ;and r1, ra_load_idx, rb_0x5555
    shr r0, ra_load_idx, 1
    and r0, r0, rb_0x5555; v8adds r1, r1, r1 # can't overflow because of mask
    v8adds r0, r0, r1;                       # can't overflow because of mask
    .if stride != 0
    # (MM) Optimized: join stride with v8adds
    ;add ra_load_idx, ra_load_idx, stride
    .endif

    bit_rev 2, rx_0x3333
    bit_rev 4, rx_0x0F0F
    
    shl r0, r0, 3
    add t0s, r0, ra_addr_x; v8adds r1, ra_addr_x, 4 # {idx[0:7], 1'b0, 2'b0}
    add t0s, r0, r1                                 # {idx[0:7], 1'b1, 2'b0}
.endm

# (MM) Optimized: avoid time consuming high accouracy for small FFTs
.macro next_twiddles_16
    mov r2, ra_tw_re+TW16+3;  fmul r1, ra_tw_re+TW16+3, rb_tw_im+TW16_STEP # b.cos
    mov r3, rb_tw_im+TW16+3;  fmul r0, rb_tw_im+TW16+3, ra_tw_re+TW16_STEP # a.sin
    fsub r0, r0, r1;          fmul r1, r2, ra_tw_re+TW16_STEP # a.cos
    fsub r3, r3, r0;          fmul r0, r3, rb_tw_im+TW16_STEP # b.sin
    fadd r0, r0, r1;          mov r1, r3
    fsub r0, r2, r0
    
    unpack_twiddles
.endm

##############################################################################
# Top level

    ;mov ra_addr_x, unif  # Ping buffer or null
    # (MM) Optimized: check loop condition below, load target buffer in init_stage
:loop

##############################################################################
# Pass 1

    # (MM) Optimized separate preparation of TMU from ldtmu for better pipeline processing.
    read_tw rx_tw_shared, TW16_P1_BASE
    init_stage 4, -
    read_rev rb_0x80
    # (MM) Optimized: do not unnecessarily advance ra_load_idx at the last turn
    read_rev 0

    # (MM) Optimized: move swap_vpm_vdw to pass1/2

    # (MM) Optimized: move branch before the last instruction of read_rev
    .back 3
    brr ra_link_1, r:pass_1
    .endb

    brr_opt ra_link_1, r:pass_1, 0
    # (MM) Optimized: move swap_vpm_vdw to pass1/2
    
    # (MM) Optimized: easier procedure chains
    brr ra_link_1, r:sync, ra_sync
    nop
    nop
    nop

##############################################################################
# Pass 2

    # (MM) More powerful init macros to simplify code
    read_tw rx_tw_unique, TW16_P2_BASE
    # (MM) Load source buffer per stage, saves another register
    ;mov ra_addr_x, unif;  # Ping buffer
    read_tw rx_tw_shared, TW16_P2_STEP
    init_stage 4, -
    read_lin rb_0x80
    store_tw TW16_STEP, -

    # (MM) Optimized: do not unnecessarily advance ra_load_idx at the last turn
    read_lin 0
    # (MM) Optimized: move swap_vpm_vdw to pass1/2
    # (MM) Optimized: move branch before the last instructions of read_lin
    .back 3
    brr ra_link_1, r:pass_2
    .endb

    next_twiddles_16
    # (MM) Optimized: move swap_vpm_vdw to pass1/2
    # (MM) Optimized: move branch before the last instructions of next_twiddles
    .back 3
    brr ra_link_1, r:pass_2
    .endb

    # (MM) Optimized: redirect ra_link_1 to :loop to save branch and 3 nop.
    # Also check loop condition immediately.
    mov.setf ra_addr_x, unif  # Ping buffer or null
    # (MM) Optimized: easier procedure chains
    brr r0, ra_link_1, r:sync, ra_sync
    mov r1, r:loop - r:1f
    add.ifnz ra_link_1, r0, r1
    nop
:1

##############################################################################

    # (MM) flag obsolete
    exit

# (MM) Optimized: easier procedure chains
##############################################################################
# Subroutines

:pass_1
:pass_2
    body_fft_16_lin

    # (MM) Optimized: move swap_vpm_vdw to pass1/2
    # (MM) Optimized: use xor for vpm swap (less memory I/O, save A register)
    ;mov r2, vpm_setup(1, 1, v32(16,0)) - vpm_setup(1, 1, v32(0,0))

    # (MM) Optimized: move write_vpm_16 to body_pass_16
    # and expand inline to pack with VPM swap code, saves 2 instructions
    xor vw_setup, rx_vpm, r2;      mov r3, rx_vpm
    xor rx_vpm,   r3,     r2;      mov vpm, r0
    xor ra_vdw,   ra_vdw, rb_vdw;  mov vpm, r1

    # (MM) Optimized: link directly to save_16
    .back 3
    brr -, ra_save_16, r:save_16
    .endb

:save_16
    body_ra_save_16 ra_vdw

:save_slave
    body_rx_save_slave

:sync_slave
    body_rx_sync_slave

:sync
    body_ra_sync

