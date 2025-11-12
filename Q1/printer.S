.section .text
.align 2

# -----------------------------------------------
# 函式: print_char(a0: char)
# 功能: 使用 ecall 64 印出 1 個位元組
# -----------------------------------------------
.globl print_char
.type print_char, @function
print_char:
    addi sp, sp, -16    
    sb a0, 15(sp)       

    li a7, 64           
    li a0, 1            
    addi a1, sp, 15     
    li a2, 1            
    ecall

    addi sp, sp, 16     
    ret
.size print_char, . - print_char

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
    
    mv s0, a0          
    li s1, 10           
    li s2, 0            
    
    bne s0, x0, dec_loop 
    li a0, '0'
    jal ra, print_char
    j dec_done
    
dec_loop:
    beq s0, x0, dec_print_loop 
    mv a0, s0
    mv a1, s1
    jal ra, __umodsi3   
    mv a0, s0
    mv a1, s1
    jal ra, __udivsi3   
    mv s0, a0           
    mv a0, a1           
    addi a0, a0, '0'    
    addi sp, sp, -4     
    sw a0, 0(sp)        
    addi s2, s2, 1      
    j dec_loop
    
dec_print_loop:
    beq s2, x0, dec_done 
    lw a0, 0(sp)         
    addi sp, sp, 4
    jal ra, print_char   
    addi s2, s2, -1      
    j dec_print_loop
    
dec_done:
    lw ra, 12(sp)
    lw s0, 8(sp)
    lw s1, 4(sp)
    lw s2, 0(sp)
    addi sp, sp, 16
    ret
.size print_u32_dec, . - print_u32_dec

