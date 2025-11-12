# 檔案: print_utils.s
# 
# 提供了 3 個全域函式 (請確保 .globl):
# 1. print_char(a0: char_to_print)
# 2. print_str(a0: ptr_to_null_terminated_string)
# 3. print_u32_dec(a0: uint32_to_print)
#
# 也提供了 __udivsi3 和 __umodsi3 (給 print_u32_dec 用)

.section .text
.align 2

# -----------------------------------------------
# 函式: print_char(a0: char)
# 功能: 使用 ecall 64 印出 1 個位元組
# -----------------------------------------------
.globl print_char
.type print_char, @function
print_char:
    addi sp, sp, -16    # 在堆疊上分配 16 bytes (保持對齊)
    sb a0, 15(sp)       # 把字元存到緩衝區的頂端

    li a7, 64           # ecall 64 (write)
    li a0, 1            # 1 = stdout
    addi a1, sp, 15     # a1 = 指向緩衝區的指標
    li a2, 1            # length = 1
    ecall

    addi sp, sp, 16     # 釋放堆疊
    ret
.size print_char, . - print_char

# -----------------------------------------------
# 函式: print_str(a0: ptr)
# 功能: 印出一個以 \0 結尾的字串
# -----------------------------------------------
.globl print_str
.type print_str, @function
print_str:
    mv s0, a0           # s0 = 保存字串指標
    addi sp, sp, -4
    sw ra, 0(sp)
print_str_loop:
    lbu a0, 0(s0)       # a0 = 載入 1 個 byte (字元)
    beq a0, x0, print_str_done # <-- 這是迴圈結束標籤
    jal ra, print_char  # 印出字元
    addi s0, s0, 1      # 指標++
    j print_str_loop
print_str_done:         # <-- 這是迴圈結束標籤
    lw ra, 0(sp)
    addi sp, sp, 4
    ret
.size print_str, . - print_str

# --- 以下是 32-bit 除法和模數 (給 print_u32_dec 用) ---
.globl __udivsi3
.type __udivsi3, @function
__udivsi3:
    beq a1, x0, div_by_zero
    mv t0, a0
    mv t1, a1
    li a0, 0
    li a1, 0
    li t2, 31
div_loop_udiv:
    sll a1, a1, 1
    srl t3, t0, t2
    andi t3, t3, 1
    or a1, a1, t3
    bge a1, t1, div_sub
    j div_continue
div_sub:
    sub a1, a1, t1
    li t3, 1
    sll t3, t3, t2
    or a0, a0, t3
div_continue:
    addi t2, t2, -1
    bge t2, x0, div_loop_udiv
    ret
div_by_zero:
    li a0, 0
    ret
.size __udivsi3, . - __udivsi3

.globl __umodsi3
.type __umodsi3, @function
__umodsi3:
    beq a1, x0, mod_by_zero
    mv t0, a0
    mv t1, a1
    li a1, 0
    li t2, 31
mod_loop:
    sll a1, a1, 1
    srl t3, t0, t2
    andi t3, t3, 1
    or a1, a1, t3
    bge a1, t1, mod_sub
    j mod_continue
mod_sub:
    sub a1, a1, t1
mod_continue:
    addi t2, t2, -1
    bge t2, x0, mod_loop
    ret
mod_by_zero:
    li a1, 0
    ret
.size __umodsi3, . - __umodsi3

# -----------------------------------------------
# 函式: print_u32_dec(a0: value)
# 功能: 印出 32-bit 十進位整數
# -----------------------------------------------
.globl print_u32_dec
.type print_u32_dec, @function
print_u32_dec:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)
    sw s2, 0(sp)
    
    mv s0, a0           # s0 = val
    li s1, 10           # s1 = 10
    li s2, 0            # s2 = digit count (push 到堆疊的次數)
    
    bne s0, x0, dec_loop # 如果 val = 0, 跳去印 '0'
    li a0, '0'
    jal ra, print_char
    j dec_done
    
dec_loop:
    beq s0, x0, dec_print_loop # 如果 val 變成 0 了, 開始印
    mv a0, s0
    mv a1, s1
    jal ra, __umodsi3   # a1 = val % 10 (remainder)
    mv a0, s0
    mv a1, s1
    jal ra, __udivsi3   # a0 = val / 10 (quotient)
    mv s0, a0           # val = quotient
    mv a0, a1           # a0 = remainder
    addi a0, a0, '0'    # a0 = '0' + remainder (ASCII)
    addi sp, sp, -4     # 為 1 個字元分配堆疊
    sw a0, 0(sp)        # Push char to stack
    addi s2, s2, 1      # 計數器 +1
    j dec_loop
    
dec_print_loop:
    beq s2, x0, dec_done # 如果計數器 = 0, 結束
    lw a0, 0(sp)         # Pop char from stack
    addi sp, sp, 4
    jal ra, print_char   # 印出字元
    addi s2, s2, -1      # 計數器 -1
    j dec_print_loop
    
dec_done:
    lw ra, 12(sp)
    lw s0, 8(sp)
    lw s1, 4(sp)
    lw s2, 0(sp)
    addi sp, sp, 16
    ret
.size print_u32_dec, . - print_u32_dec

# <-- 確保檔案結尾有一個換行