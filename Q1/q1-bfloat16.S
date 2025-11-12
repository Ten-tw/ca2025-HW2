.include "syscall.S"

.data

# a, b, add(a+b), sub(a−b), mul(a*b), div(a/b), sqrt(a)

# (1) 9.0, 3.0
# add = 12.0, sub = 6.0, mul = 27.0, div = 3.0, sqrt = 3.0
test_case1: .word 0x41100000, 0x40400000, 0x41400000, 0x40C00000, 0x41D80000, 0x40400000, 0x40400000

# (2) 1.5, 2.5
# add = 4.0, sub = -1.0, mul = 3.75, div = 0.59765625, sqrt = 1.2265625
test_case2: .word 0x3FC00000, 0x40200000, 0x40800000, 0xBF800000, 0x40700000, 0x3f190000, 0x3f9d0000

# (3) -8.0, 0
# add = -8.0, sub = -8.0, mul = -0.0, div = -inf, sqrt = NaN
test_case3: .word 0xC1000000, 0x00000000, 0xC1000000, 0xC1000000, 0x80000000, 0xff800000, 0x7FC00000

# (4) NaN, NaN
# 所有結果都是 NaN
test_case4: .word 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x7FC00000

# (5) inf, inf
# add = inf, sub = NaN, mul = inf, div = NaN, sqrt = inf
test_case5: .word 0x7F800000, 0x7F800000, 0x7F800000, 0x7FC00000, 0x7F800000, 0x7FC00000, 0x7F800000


test_case_end:


msg_pass: .asciz "All operation passed !!\n"
msg_failed: .asciz "Failed\n"

.text
.global _start
_start:
    # Prologue
    addi sp, sp, -4
    sw ra, 0(sp)

    la s3, test_case1 # test case start address
    la s4, test_case_end
    addi s5, x0, 1 # init result

test_loop:

    addi s5, x0, 1 # init result
    beq s3, s4, done

    lw a0, 0(s3)
    jal f32_to_bf16
    add s0, a0, x0

    lw a0, 4(s3)
    jal f32_to_bf16
    add s1, a0, x0

    

    # Test add
    add a0, s0, x0
    add a1, s1, x0
    jal bf16_add
    jal bf16_to_f32

    lw s2, 8(s3)
    xor t0, a0, s2
    seqz t0, t0
    and s5, s5, t0

    # Test sub
    add a0, s0, x0
    add a1, s1, x0
    jal bf16_sub
    jal bf16_to_f32

    lw s2, 12(s3)
    xor t0, a0, s2
    seqz t0, t0
    and s5, s5, t0

    # Test mul
    add a0, s0, x0
    add a1, s1, x0
    jal bf16_mul
    jal bf16_to_f32

    lw s2, 16(s3)
    xor t0, a0, s2
    seqz t0, t0
    and s5, s5, t0

    # Test div
    add a0, s0, x0
    add a1, s1, x0
    jal bf16_div
    jal bf16_to_f32

    lw s2, 20(s3) 
    xor t0, a0, s2
    seqz t0, t0
    and s5, s5, t0

    # Test sqrt
    add a0, s0, x0
    jal bf16_sqrt
    jal bf16_to_f32

    lw s2, 24(s3)
    xor t0, a0, s2
    seqz t0, t0
    and s5, s5, t0

    # Print result
    bnez s5, print_pass 
    j print_failed

print_pass:

    li a0, STDOUT  # file descriptor
    la a1, msg_pass     # address of string
    li a2, 24       # length of string
    li a7, WRITE
    ecall
    j next_case

print_failed:
    li a0, STDOUT  # file descriptor
    la a1, msg_failed     # address of string
    li a2, 7       # length of string
    li a7, WRITE
    ecall

next_case:
    addi s3, s3, 28
    j test_loop

done:
    # Epilogue
    lw ra, 0(sp)
    addi sp, sp, 4
    j end

############################################################
# bf16_isnan(bf16_t a)
# 參數: a.bits 在 a0 (低 16 位有效)
# 回傳: a0 = 1 若為 NaN, 否則 0
############################################################
bf16_isnan:
    li    t1, 0x7F80    #BF16_EXP_MASK = 0x7F80
    and t0, a0, t1    # 取 exponent bits
    bne   t0, t1, Lnot_nan  # exp != 0x7F80 → false
    andi  t2, a0, 0x007F     # 取 mantissa bits
    beqz  t2, Lnot_nan      # mant == 0 → false
    li    a0, 1              # true
    ret
Lnot_nan:
    li    a0, 0
    ret

############################################################
# bf16_isinf(bf16_t a)
# 回傳: a0 = 1 若為 ±INF, 否則 0
############################################################
bf16_isinf:
    li    t1, 0x7F80
    and t0, a0, t1
    bne   t0, t1, Lnot_inf
    andi  t2, a0, 0x007F
    bnez  t2, Lnot_inf
    li    a0, 1
    ret
Lnot_inf:
    li    a0, 0
    ret

############################################################
# bf16_iszero(bf16_t a)
# 回傳: a0 = 1 若為 ±0, 否則 0
############################################################
bf16_iszero:
    li    t1, 0x7FFF
    and  t0, a0, t1    
    seqz  a0, t0            
    ret

############################################################
# f32_to_bf16(float val)
############################################################
f32_to_bf16:
    mv    t0, a0       
    srli  t1, t0, 23        
    andi  t1, t1, 0xFF
    li    t2, 0xFF
    beq   t1, t2, Lnan_inf 

    # ---- 正常四捨五入情況 ----
    srli  t3, t0, 16        
    andi  t3, t3, 1         
    li    t4, 0x7FFF
    add   t0, t0, t4       
    add   t0, t0, t3
    srli  t0, t0, 16        
    li    t5, 0xFFFF
    and  a0, t0,  t5  
    ret

Lnan_inf:
    srli  t0, t0, 16
    li    t5, 0xFFFF
    and  a0, t0,  t5
    ret

############################################################
# bf16_to_f32(bf16_t val)
############################################################
bf16_to_f32:
    slli a0,a0,16
    ret

############################################################
# bf16_add(bf16_t a, bf16_t b)
############################################################
bf16_add:
    addi  sp, sp, -48
    sw    ra, 44(sp)
    sw    s0, 40(sp)
    sw    s1, 36(sp)
    sw    s2, 32(sp)
    sw    s3, 28(sp)
    sw    s4, 24(sp)
    sw    s5, 20(sp)
    sw    s6, 16(sp)
    sw    s7, 12(sp)

    # ---- 萃取符號、指數、尾數 ----
    srli  t0, a0, 15          
    andi  t0, t0, 1
    srli  t1, a1, 15         
    andi  t1, t1, 1

    srli  t2, a0, 7         
    andi  t2, t2, 0xFF
    srli  t3, a1, 7          
    andi  t3, t3, 0xFF

    andi  t4, a0, 0x7F        
    andi  t5, a1, 0x7F        

    # ---- 處理 NaN / Inf ----
    li    t6, 0xFF
    beq   t2, t6, label_a_inf_check 
    beq   t3, t6, label_b_inf_check 
    j     label_normal_check

label_a_inf_check:
    bnez  t4, label_return_a      
    beq   t3, t6, label_both_inf  
    j     label_return_a

label_both_inf:
    bnez  t5, label_return_b     
    beq   t0, t1, label_return_b 
    # else 返回 NaN
    li    a0, 0x7FC0
    j     label_epilogue

label_b_inf_check:
    j     label_return_b

label_return_a:
    mv    a0, a0    
    j     label_epilogue
label_return_b:
    mv    a0, a1
    j     label_epilogue

    

    # ---- 零處理 ----
label_normal_check:           
    beqz  t2, label_a_exp_zero  
    j     label_a_nonzero

label_a_exp_zero:
    beqz  t4, label_return_b      
label_a_nonzero:               
    beqz  t3, label_b_exp_zero  
    j     label_b_nonzero

label_b_exp_zero:
    beqz  t5, label_return_a      

label_b_nonzero:

    # ---- 還原隱藏位 ----
    beqz  t2, label_skip_a_norm 
    ori   t4, t4, 0x80
label_skip_a_norm:
    beqz  t3, label_skip_b_norm 
    ori   t5, t5, 0x80

label_skip_b_norm:

    # ---- 指數差 ----
    sub   t6, t2, t3           

    # 儲存暫存符號、尾數、指數
    mv    s0, t0              
    mv    s1, t1               
    mv    s2, t2               
    mv    s3, t3               
    mv    s4, t4               
    mv    s5, t5              
    mv    s6, t6              
    # ---- 對齊 mantissa ----
    bgtz  s6, label_a_larger_exp   
    bltz  s6, label_b_larger_exp    
    mv    s7, s2              
    j     label_same_exp

label_a_larger_exp:
    mv    s7, s2   
    li    t0, 8
    bgt   s6, t0, label_return_a  
    mv    t1, s6
    srl   s5, s5, t1          
    j     label_same_exp

label_b_larger_exp:
    mv    s7, s3
    li    t0, -8
    blt   s6, t0, label_return_b  
    neg   t1, s6
    srl   s4, s4, t1          
    j     label_same_exp

label_same_exp:
    # ---- 加或減 mantissa ----
    beq   s0, s1, label_same_sign   
    j     label_diff_sign           

label_same_sign:
    mv    t0, s0               
    add   t1, s4, s5          
    li    t2, 0x100
    and   t3, t1, t2
    beqz  t3, label_store_result
    srli  t1, t1, 1            
    addi  s7, s7, 1             
    li    t4, 0xFF
    bge   s7, t4, label_inf_overflow
    j     label_store_result

label_inf_overflow:
    slli  t0, t0, 15
    li    t1 ,0x7F80
    or   a0, t0, t1
    j     label_epilogue

label_diff_sign:
    bgeu  s4, s5, label_a_bigger    
    mv    t0, s1        
    sub   t1, s5, s4       
    j     label_diff_done
label_a_bigger:
    mv    t0, s0
    sub   t1, s4, s5
label_diff_done:
    beqz  t1, label_zero_return 

    # normalize mantissa
label_norm_loop:
    andi  t2, t1, 0x80
    bnez  t2, label_store_result
    slli  t1, t1, 1
    addi  s7, s7, -1    
    blez  s7, label_zero_return
    j     label_norm_loop

label_zero_return:
    li    a0, 0x0000
    j     label_epilogue

label_store_result:
    slli  t0, t0, 15          
    andi  t2,s7,0xFF           
    slli  t2, t2, 7           
    andi  t3, t1, 0x7F        
    or    t0, t0, t2
    or    t0, t0, t3
    mv    a0, t0
    j     label_epilogue

# ---- epilogue/returns ----
label_epilogue:
    # restore s0..s7 and ra
    lw    s7, 12(sp)
    lw    s6, 16(sp)
    lw    s5, 20(sp)
    lw    s4, 24(sp)
    lw    s3, 28(sp)
    lw    s2, 32(sp)
    lw    s1, 36(sp)
    lw    s0, 40(sp)
    lw    ra, 44(sp)
    addi  sp, sp, 48
    ret
############################################################
# bf16_sub(bf16_t a, bf16_t b)
############################################################
bf16_sub:

    addi  sp,sp, -4
    sw    ra, 0(sp)
    # 翻轉 b 的符號位元
    li    t0, 0x8000        
    xor   a1, a1, t0        

    # 呼叫 bf16_add(a, b)
    call  bf16_add          

    lw    ra, 0(sp)
    addi  sp, sp, 4
    ret                    

#############################################################
# bf16_mul(a0=a.bits, a1=b.bits)
# return a0 = result.bits
# Uses only t0–t6 and s0–s11
#############################################################
bf16_mul:

    # --- prologue: save ra and s0..s9 (we use s0..s9) ---
    addi  sp, sp, -48
    sw    ra, 44(sp)
    sw    s0, 40(sp)
    sw    s1, 36(sp)
    sw    s2, 32(sp)
    sw    s3, 28(sp)
    sw    s4, 24(sp)
    sw    s5, 20(sp)
    sw    s6, 16(sp)
    sw    s7, 12(sp)
    sw    s8, 8(sp)
    sw    s9, 4(sp)
    # --- extract sign bits ---
    srli   t0, a0, 15        
    andi   t0, t0, 1
    srli   t1, a1, 15         
    andi   t1, t1, 1
    xor    s0, t0, t1         

    # --- extract exponents ---
    srli   t2, a0, 7
    andi   s1, t2, 0xFF       
    srli   t3, a1, 7
    andi   s2, t3, 0xFF       

    # --- extract mantissas ---
    andi   s3, a0, 0x7F        
    andi   s4, a1, 0x7F        
    # --- check exp_a == 0xFF ---
    li     t0, 0xFF
    beq    s1, t0, Linf_nan_a
    beq    s2, t0, Linf_nan_b

    # --- check for zero operands ---
    or     t0, s1, s3
    beqz   t0, Lreturn_zero
    or     t0, s2, s4
    beqz   t0, Lreturn_zero

    # --- exp_adjust = 0 ---
    li     s5, 0

    # --- normalize a ---
    beqz   s1, Lnorm_a_sub
    ori    s3, s3, 0x80       
    j      Lnorm_a_done
Lnorm_a_sub:
    beqz   s3, Lnorm_a_done
Lnorm_a_loop:
    andi   t0, s3, 0x80
    bnez   t0, Lnorm_a_done
    slli   s3, s3, 1
    addi   s5, s5, -1
    j      Lnorm_a_loop
Lnorm_a_done:
    beqz   s1, Lset_exp_a1
    j      Lexp_a_ok
Lset_exp_a1:
    li     s1, 1
Lexp_a_ok:

    # --- normalize b ---
    beqz   s2, Lnorm_b_sub
    ori    s4, s4, 0x80
    j      Lnorm_b_done
Lnorm_b_sub:
    beqz   s4, Lnorm_b_done
Lnorm_b_loop:
    andi   t0, s4, 0x80
    bnez   t0, Lnorm_b_done
    slli   s4, s4, 1
    addi   s5, s5, -1
    j      Lnorm_b_loop
Lnorm_b_done:
    beqz   s2, Lset_exp_b1
    j      Lexp_b_ok
Lset_exp_b1:
    li     s2, 1
Lexp_b_ok:

    # --- multiply mantissas (8x8 → 16-bit) ---
    mv     s6, s3          
    mv     s7, s4            
    li     s8, 0            
mul_return_zero:
    andi   t0, s7, 1
    beqz   t0, Lno_add
    add    s8, s8, s6
Lno_add:
    slli   s6, s6, 1
    srli   s7, s7, 1
    bnez   s7, mul_return_zero
    mv     s3, s8            
    # --- result_exp = exp_a + exp_b - 127 + exp_adjust ---
    add    s9, s1, s2
    addi   s9, s9, -127
    add    s9, s9, s5

    # --- normalize mantissa ---
    li     t0, 0x8000
    and    t1, s3, t0
    beqz   t1, Lnorm_shift7
    srli   s3, s3, 8
    andi   s3, s3, 0x7F
    addi   s9, s9, 1
    j      Lnorm_done
Lnorm_shift7:
    srli   s3, s3, 7
    andi   s3, s3, 0x7F
Lnorm_done:

    # --- overflow ---
    li     t0, 0xFF
    bge    s9, t0, Lreturn_inf

    # --- underflow ---
    blez   s9, Lunderflow

    # --- normal result ---
    slli   t0, s0, 15
    andi   t1, s9, 0xFF
    slli   t1, t1, 7
    or     t0, t0, t1
    or     a0, t0, s3
    j     Lepilogue

# --- underflow handling ---
Lunderflow:
    li     t0, -6
    blt    s9, t0, Lreturn_zero
    addi   t1, zero, 1
    sub    t1, t1, s9           
Lshift_loop:
    beqz   t1, Lshift_done
    srli   s3, s3, 1
    addi   t1, t1, -1
    j      Lshift_loop
Lshift_done:
    slli   t0, s0, 15
    or     a0, t0, s3
    j     Lepilogue

# --- INF / NAN handling ---
Linf_nan_a:
    andi   t0, a0, 0x7F
    bnez   t0, Lreturn_a
    or     t1, s2, s4
    beqz   t1, Lreturn_nan
    li     t2, 0x7F80
    slli   s0, s0, 15
    or     a0, s0, t2
    j     Lepilogue

Linf_nan_b:
    andi   t0, a1, 0x7F
    bnez   t0, Lreturn_b
    or     t1, s1, s3
    beqz   t1, Lreturn_nan
    li     t2, 0x7F80
    slli   s0, s0, 15
    or     a0, s0, t2
    j     Lepilogue

# --- return helpers ---
Lreturn_nan:
    li     a0, 0x7FC0
    j     Lepilogue
Lreturn_inf:
    li     t0, 0x7F80
    slli   s0, s0, 15
    or     a0, s0, t0
    j     Lepilogue
Lreturn_zero:
    slli   a0, s0, 15
    j     Lepilogue
Lreturn_a:
    mv     a0, a0
    j     Lepilogue
Lreturn_b:
    mv     a0, a1
    j     Lepilogue


#############################################################
# bf16_div(a0=a.bits, a1=b.bits)
#############################################################
bf16_div:
    addi  sp, sp, -56
    sw    ra, 48(sp)
    sw    s0, 44(sp)
    sw    s1, 40(sp)
    sw    s2, 36(sp)
    sw    s3, 32(sp)
    sw    s4, 28(sp)
    sw    s5, 24(sp)
    sw    s6, 20(sp)
    sw    s7, 16(sp)
    sw    s8, 12(sp)
    sw    s9, 8(sp)
    sw    s10, 4(sp)
    sw    s11, 0(sp)

    mv     s10, a0        
    mv     s11, a1         
    # extract sign bits
    srli   t0, a0, 15
    andi   t0, t0, 1
    srli   t1, a1, 15
    andi   t1, t1, 1
    xor    s0, t0, t1      

    # extract exponents
    srli   t2, a0, 7
    andi   s1, t2, 0xFF    
    srli   t3, a1, 7
    andi   s2, t3, 0xFF    

    # extract mantissas
    andi   s3, a0, 0x7F    
    andi   s4, a1, 0x7F   

    li     t0, 0xFF

    beq    s2, t0, Lexpb_ff
    beqz   s2, Lb_exp_zero_check
    beq    s1, t0, Lexpa_ff
    beqz   s1, La_exp_check_zero
    j      Ldo_div

# ---------- exp_b == 0xFF ----------
Lexpb_ff:
    andi   t1, s4, 0x7F
    bnez   t1, div_return_b     
    beq    s1, t0, Lboth_inf_check  
    slli   a0, s0, 15
    j     Lepiloguetos11

Lboth_inf_check:
    andi   t1, s3, 0x7F
    beqz   t1, div_return_nan     
    slli   a0, s0, 15
    j     Lepiloguetos11

# ---------- b exponent == 0 (maybe zero or subnormal) ----------
Lb_exp_zero_check:
    beqz   s4, Lb_both_zero     
    beq    s1, t0, Lexpa_ff     
    beqz   s1, La_exp_check_zero
    j      Ldo_div

Lb_both_zero:
    or     t1, s1, s3
    beqz   t1, div_return_nan
    li     t1, 0x7F80
    slli   t2, s0, 15
    or     a0, t2, t1
    j     Lepiloguetos11

# ---------- exp_a == 0xFF ----------
Lexpa_ff:
    andi   t1, s3, 0x7F
    bnez   t1, div_return_a 
    li     t1, 0x7F80
    slli   t2, s0, 15
    or     a0, t2, t1
    j     Lepiloguetos11

# ---------- exp_a == 0 and mant_a == 0 -> signed zero ----------
La_exp_check_zero:
    or     t1, s1, s3
    beqz   t1, Lreturn_zero
    j      Ldo_div

# ---------- main division core ----------
Ldo_div:
    beqz   s1, Lskip_set_a_implicit
    ori    s3, s3, 0x80
Lskip_set_a_implicit:
    beqz   s2, Lskip_set_b_implicit
    ori    s4, s4, 0x80
Lskip_set_b_implicit:

    slli   s5, s3, 15     
    slli   s6, s4, 15      
    li     s7, 0            
    li     t0, 16         
Ldiv_loop:
    slli   s7, s7, 1
    bgeu   s5, s6, Ldiv_sub
    j      Ldiv_next
Ldiv_sub:
    sub    s5, s5, s6
    ori    s7, s7, 1
Ldiv_next:
    srli   s6, s6, 1        
    addi   t0, t0, -1
    bnez   t0, Ldiv_loop

    sub    s9, s1, s2
    addi   s9, s9, 127

    beqz   s1, Lexp_a_zero_adj
    j      Lcheck_exp_b_zero
Lexp_a_zero_adj:
    addi   s9, s9, -1
Lcheck_exp_b_zero:
    beqz   s2, Lexp_b_zero_adj
    j      Lnormalize_quotient
Lexp_b_zero_adj:
    addi   s9, s9, 1

# ---------- normalize quotient ----------
Lnormalize_quotient:
    li t4, 0x8000
    and   t1, s7, t4
    bnez   t1, Lquot_shift8
    # while (!(quotient & 0x8000) && result_exp > 1) { quotient <<= 1; result_exp--; }
Lnorm_loop:
    li t4, 0x8000
    and   t1, s7, t4
    bnez   t1, Lquot_shift8_check_done
    li     t2, 1
    ble    s9, t2, Lquot_shift8_check_done
    slli   s7, s7, 1
    addi   s9, s9, -1
    j      Lnorm_loop
Lquot_shift8_check_done:
    srli   s7, s7, 8
    j      Lquot_after_mask

Lquot_shift8:
    srli   s7, s7, 8

Lquot_after_mask:
    andi   s7, s7, 0x7F

    # check overflow / underflow
    li     t1, 0xFF
    bge    s9, t1, div_return_inf
    blez   s9, Lreturn_zero

    # pack result bits: (sign<<15) | ((exp & 0xFF) << 7) | (quotient & 0x7F)
    slli   t1, s0, 15
    andi   t2, s9, 0xFF
    slli   t2, t2, 7
    or     t1, t1, t2
    or     a0, t1, s7
    j     Lepiloguetos11

# ---------- returns ----------
div_return_a:
    mv     a0, s10
    j     Lepiloguetos11
div_return_b:
    mv     a0, s11
    j     Lepiloguetos11
div_return_nan:
    li     a0, 0x7FC0
    j     Lepiloguetos11
div_return_inf:
    li     t1, 0x7F80
    slli   t2, s0, 15
    or     a0, t2, t1
    j     Lepiloguetos11
div_return_zero:
    slli   a0, s0, 15
    j     Lepiloguetos11

Lepiloguetos11:
    lw    s11, 0(sp)
    lw    s10, 4(sp)
    lw    s9, 8(sp)
    lw    s8, 12(sp)
    lw    s7, 16(sp)
    lw    s6, 20(sp)
    lw    s5, 24(sp)
    lw    s4, 28(sp)
    lw    s3, 32(sp)
    lw    s2, 36(sp)
    lw    s1, 40(sp)
    lw    s0, 44(sp)
    lw    ra, 48(sp)
    addi  sp, sp, 48
    ret

#############################################################
# bf16_sqrt(a0 = a.bits)
#############################################################

bf16_sqrt:
    # --- prologue: save ra and s0..s9 (we use s0..s9) ---
    addi  sp, sp, -48
    sw    ra, 44(sp)
    sw    s0, 40(sp)
    sw    s1, 36(sp)
    sw    s2, 32(sp)
    sw    s3, 28(sp)
    sw    s4, 24(sp)
    sw    s5, 20(sp)
    sw    s6, 16(sp)
    sw    s7, 12(sp)
    sw    s8, 8(sp)
    sw    s9, 4(sp)

    # --- Extract fields: sign, exp, mant ---
    srli  t0, a0, 15     
    andi  s0, t0, 1   

    srli  t0, a0, 7
    andi  s1, t0, 0xFF    

    andi  s2, a0, 0x7F  

    # --- Handle special cases: exp == 0xFF ---
    li    t0, 0xFF
    beq   s1, t0, Lexp_ff_check

    or    t0, s1, s2
    beqz  t0, Lret_zero

    bnez  s0, Lret_nan

    beqz  s1, Lret_zero

    # --- Normal path: compute e = exp - BF16_EXP_BIAS (127) ---
    li    t0, 127
    sub   s3, s1, t0   

    ori   s5, s2, 0x80 

    andi  t0, s3, 1
    beqz  t0, Leven_exp

    # odd exponent
    slli  s5, s5, 1      
    addi  t0, s3, -1
    srai  t1, t0, 1       
    addi  s4, t1, 127      
    j     Lstart_bisearch

Leven_exp:
    srai  t1, s3, 1        
    addi  s4, t1, 127     

Lstart_bisearch:
    li    s6, 90           
    li    s7, 256         
    li    s8, 128        

Lbisearch_loop:
    # if low > high break
    ble   s7, s6, Lbisearch_done_check 
    add   t0, s6, s7
    srli  s9, t0, 1        

    li    t0, 0            
    mv    t1, s9          
    mv    t2, s9           

Lmul_loop:
    andi  t3, t2, 1
    beqz  t3, Lmul_skip_add
    add   t0, t0, t1
Lmul_skip_add:
    slli  t1, t1, 1
    srli  t2, t2, 1
    bnez  t2, Lmul_loop

    srli  t4, t0, 7      

    bgtu  t4, s5, Lset_high 
    mv    s8, s9             
    addi  s6, s9, 1         
    j     Lbisearch_loop
Lset_high:
    addi  s7, s9, -1
    j     Lbisearch_loop

# When loop condition fails we still may need to check low<=high one last time.
Lbisearch_done_check:
    ble   s6, s7, Lbisearch_one_more
    j     Lbisearch_after

Lbisearch_one_more:
    add   t0, s6, s7
    srli  s9, t0, 1    

    li    t0, 0
    mv    t1, s9
    mv    t2, s9
Lmul_loop2:
    andi  t3, t2, 1
    beqz  t3, Lmul2_skip
    add   t0, t0, t1
Lmul2_skip:
    slli  t1, t1, 1
    srli  t2, t2, 1
    bnez  t2, Lmul_loop2

    srli  t4, t0, 7       

    bgtu  t4, s5, Lset_high2
    mv    s8, s9
    addi  s6, s9, 1
    j     Lbisearch_after
Lset_high2:
    addi  s7, s9, -1
    j     Lbisearch_after

Lbisearch_after:
    # Normalize result:
    li    t0, 256
    bgeu  s8, t0, Lres_ge_256

    li    t0, 128
    bgeu  s8, t0, Lres_norm_done 
Lres_lt_loop:
    # while (result < 128 && new_exp > 1)
    li    t1, 128
    bgeu  s8, t1, Lres_norm_done
    li    t2, 1
    ble   s4, t2, Lres_norm_done   
    slli  s8, s8, 1
    addi  s4, s4, -1
    j     Lres_lt_loop

    # done
    j     Lres_norm_done

Lres_ge_256:
    srli  s8, s8, 1
    addi  s4, s4, 1
    j     Lres_norm_done

Lres_norm_done:
    andi  t0, s8, 0x7F

    # Check overflow/underflow
    li    t1, 0xFF
    bge   s4, t1, Lret_inf  
    blez  s4, Lret_zero   

    andi  t2, s4, 0xFF
    slli  t2, t2, 7
    or    a0, t2, t0
    j     Lepilogue

# --- special-case handlers ---

Lexp_ff_check:
    bnez  s2, Lret_a
    bnez  s0, Lret_nan

    j     Lret_a

# --- return labels set a0 and jump to epilogue ---
Lret_a:
    j     Lepilogue

Lret_nan:
    li    a0, 0x7FC0
    j     Lepilogue

Lret_zero:
    li    a0, 0x0000
    j     Lepilogue

Lret_inf:
    li    a0, 0x7F80
    j     Lepilogue

# --- epilogue: restore s0..s9 and ra, return ---
Lepilogue:
    lw    s9, 4(sp)
    lw    s8, 8(sp)
    lw    s7, 12(sp)
    lw    s6, 16(sp)
    lw    s5, 20(sp)
    lw    s4, 24(sp)
    lw    s3, 28(sp)
    lw    s2, 32(sp)
    lw    s1, 36(sp)
    lw    s0, 40(sp)
    lw    ra, 44(sp)
    addi  sp, sp, 48
    ret

end:
    # MISSING: Check for error condition
    li a0, 0       # 0 signals success
    li a7, EXIT
    ecall
