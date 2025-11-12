#include <stdint.h> // 保留這個，因為 C 語言需要 uint32_t, uint64_t 等類型
#include <stddef.h> // 為了 size_t

extern uint64_t get_cycles(void);
extern uint64_t get_instret(void);

#define printstr(ptr, length)                                  \
    do {                                                       \
        asm volatile(                                          \
            "add a7, x0, 0x40;" /* 64 = write */               \
            "add a0, x0, 0x1;"  /* 1 = stdout */               \
            "add a1, x0, %0;"   /* a1 = ptr */                 \
            "mv a2, %1;"        /* a2 = length */              \
            "ecall;"                                           \
            :                                                  \
            : "r"(ptr), "r"(length)                            \
            : "a0", "a1", "a2", "a7");                         \
    } while (0)

#define TEST_OUTPUT(msg, length) printstr(msg, length)

#define TEST_LOGGER(msg)                       \
    {                                          \
        char _msg[] = msg;                     \
        TEST_OUTPUT(_msg, sizeof(_msg) - 1);   \
    }

/* 裸機 memcpy 實作 */
void *memcpy(void *dest, const void *src, size_t n)
{
    uint8_t *d = (uint8_t *) dest;
    const uint8_t *s = (const uint8_t *) src;
    while (n--)
        *d++ = *s++;
    return dest;
}

/* 軟體除法 (RV32I) */
static unsigned long udiv(unsigned long dividend, unsigned long divisor)
{
    if (divisor == 0)
        return 0;
    unsigned long quotient = 0, remainder = 0;
    for (int i = 31; i >= 0; i--) {
        remainder <<= 1;
        remainder |= (dividend >> i) & 1;
        if (remainder >= divisor) {
            remainder -= divisor;
            quotient |= (1UL << i);
        }
    }
    return quotient;
}

/* 軟體模數 (RV32I) */
static unsigned long umod(unsigned long dividend, unsigned long divisor)
{
    if (divisor == 0)
        return 0;
    unsigned long remainder = 0;
    for (int i = 31; i >= 0; i--) {
        remainder <<= 1;
        remainder |= (dividend >> i) & 1;
        if (remainder >= divisor) {
            remainder -= divisor;
        }
    }
    return remainder;
}

/* 軟體 32-bit 乘法 (RV32I) */
static uint32_t umul(uint32_t a, uint32_t b)
{
    uint32_t result = 0;
    while (b) {
        if (b & 1)
            result += a;
        a <<= 1;
        b >>= 1;
    }
    return result;
}

/* * 關鍵：提供 __mulsi3 給 GCC。
 * 當 GCC 看到 32-bit 乘法 (*) 且沒有 M 擴展時，
 * 它會自動呼叫這個函式。
 */
uint32_t __mulsi3(uint32_t a, uint32_t b)
{
    return umul(a, b);
}

/* 簡易的「整數轉十六進位」字串並印出 */
static void print_hex(unsigned long val)
{
    char buf[20];
    char *p = buf + sizeof(buf) - 1;
    // *p = '\n'; // 我們在緩衝區結尾放 \n
    // p--;

    if (val == 0) {
        *p = '0';
        p--;
    } else {
        while (val > 0) {
            int digit = val & 0xf;
            *p = (digit < 10) ? ('0' + digit) : ('a' + digit - 10);
            p--;
            val >>= 4;
        }
    }
    p++;
    printstr(p, (buf + sizeof(buf) - p)); // 印出包含結尾 \n 之前的所有內容
}

/* 簡易的「整數轉十進位」字串並印出 */
static void print_dec(unsigned long val)
{
    char buf[20];
    char *p = buf + sizeof(buf) - 1;
    // *p = '\n'; // 同上
    // p--;

    if (val == 0) {
        *p = '0';
        p--;
    } else {
        while (val > 0) {
            *p = '0' + umod(val, 10);
            p--;
            val = udiv(val, 10);
        }
    }
    p++;
    printstr(p, (buf + sizeof(buf) - p));
}

// -----------------------------------------------------------------
// 你的 problemC.c 程式碼 (保留你需要的部分)
// -----------------------------------------------------------------

static const uint32_t rsqrt_table[32] = {
    65536, 46341, 32768, 23170, 16384,  /* 2^0 to 2^4 */
    11585,  8192,  5793,  4096,  2896,  /* 2^5 to 2^9 */
     2048,  1448,  1024,   724,   512,  /* 2^10 to 2^14 */
      362,   256,   181,   128,    90,  /* 2^15 to 2^19 */
       64,    45,    32,    23,    16,  /* 2^20 to 2^24 */
       11,     8,     6,     4,     3,  /* 2^25 to 2^29 */
        2,     1                         /* 2^30, 2^31 */
};

// 你的 64-bit 軟體乘法 (fast_rsqrt 需要它)
static uint64_t mul32(uint32_t a, uint32_t b){
    uint64_t r=0;
    for(int i=0;i<32;i++){
        if(b & (1U<<i))
            r+=(uint64_t) a<<i;
    }
    return r;
}

// 你的 clz (fast_rsqrt 需要它)
static int clz(uint32_t x){
    if(!x) return 32;
    int n=0;
    if(!(x&0xFFFF0000)) {n+=16; x<<=16;}
    if(!(x&0xFF000000)) {n+=8; x<<=8;}
    if(!(x&0xF0000000)) {n+=4; x<<=4;}
    if(!(x&0xC0000000)) {n+=2; x<<=2;}
    if(!(x&0x80000000)) {n+=1;}
    return n;
}

// 你的 fast_rsqrt
uint32_t fast_rsqrt(uint32_t x){
    if(x ==0) return 0xFFFFFFFF;
    if(x ==1) return 65536;

    int exp = 31 - clz(x);
    uint32_t y = rsqrt_table[exp];

    if(x > (1u<<exp)){
        uint32_t y_next = (exp <31)?rsqrt_table[exp+1] : 0;
        uint32_t delta = y - y_next;
        uint32_t frac = (uint32_t)((((uint64_t)x - (1UL << exp)) << 16) >>exp );
        
        // 這裡的 * 運算子會被自動替換成 __mulsi3 (由老師的程式碼提供)
        y -= (uint32_t)((delta * frac) >> 16);
    }

    for(int iter = 0; iter < 2; iter++){
        // 這裡明確呼叫你自己的 64-bit 軟體乘法
        uint32_t y2 = (uint32_t)mul32(y,y);
        uint32_t xy2 = (uint32_t)(mul32(x, y2) >> 16);
        y = (uint32_t)(mul32(y,(3u << 16) - xy2) >> 17);
    }
    return y;
}

// -----------------------------------------------------------------
// 刪除 fast_distance_3d 函式 (因為 main 沒用到, 且會導致 __muldi3 錯誤)
// -----------------------------------------------------------------


// --- 測試主程式 (已修改) ---
int main(void) {

    uint64_t start_cycles, end_cycles, cycles_elapsed;
    uint64_t start_instret, end_instret, instret_elapsed;

    TEST_LOGGER("Test ProbleC:\n");
    start_cycles = get_cycles();
    start_instret = get_instret();
    
    uint32_t x = 1000000;
    uint32_t inv = fast_rsqrt(x);

    // --- 修改：移除 printf 和浮點數運算 ---
    // 原始 printf: printf("fast_rsqrt(%u) ≈ %.6f\n", x, inv / 65536.0);

    TEST_LOGGER("fast_rsqrt(");
    print_dec(x);
    TEST_LOGGER(") = ");
    
    // 'inv' 是一個 Q1.16 定點數格式 (65536 代表 1.0)
    
    // 1. 印出整數部分 (inv >> 16)
    print_dec(inv >> 16);
    TEST_LOGGER(".");
    
    // 2. 印出小數部分 (inv & 0xFFFF)，用十六進位
    print_hex(inv & 0xFFFF);
    TEST_LOGGER(" (Q1.16 hex fraction)\n");

    end_cycles = get_cycles();
    end_instret = get_instret();
    cycles_elapsed = end_cycles - start_cycles;
    instret_elapsed = end_instret - start_instret;

    TEST_LOGGER("  Cycles: ");
    print_dec((unsigned long) cycles_elapsed);
    TEST_LOGGER("  Instructions: ");
    print_dec((unsigned long) instret_elapsed);
    TEST_LOGGER("\n");

    return 0; // 這個 return 會被 start.S 裡的 ecall 93 接住
}