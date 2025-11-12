#include <stdint.h>
#include <stddef.h>

// --- 保持你所有的輔助函式不變 ---

extern uint64_t get_cycles(void);
extern uint64_t get_instret(void);

#define printstr(ptr, length)                                          \
    do {                                                               \
        asm volatile(                                                  \
            "add a7, x0, 0x40;" /* 64 = write */                       \
            "add a0, x0, 0x1;"  /* 1 = stdout */                       \
            "add a1, x0, %0;"  /* a1 = ptr */                         \
            "mv a2, %1;"        /* a2 = length */                      \
            "ecall;"                                                   \
            :                                                          \
            : "r"(ptr), "r"(length)                                    \
            : "a0", "a1", "a2", "a7");                                 \
    } while (0)

#define TEST_OUTPUT(msg, length) printstr(msg, length)

#define TEST_LOGGER(msg)                 \
    {                                    \
        char _msg[] = msg;               \
        TEST_OUTPUT(_msg, sizeof(_msg) - 1); \
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

/* 提供 __mulsi3 給 GCC */
uint32_t __mulsi3(uint32_t a, uint32_t b)
{
    return umul(a, b);
}

/* 簡易的「整數轉十進位」字串並印出 (裸機環境) */
static void print_dec(unsigned long val)
{
    char buf[20];
    char *p = buf + sizeof(buf) - 1;
    
    // *p = '\n'; // 不在這裡加換行
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

// --- 你的 rsqrt 相關程式碼 ---

static const uint32_t rsqrt_table[32] = {
    65536, 46341, 32768, 23170, 16384,  /* 2^0 to 2^4 */
    11585,  8192,  5793,  4096,  2896,  /* 2^5 to 2^9 */
     2048,  1448,  1024,   724,   512,  /* 2^10 to 2^14 */
      362,   256,   181,   128,    90,  /* 2^15 to 2^19 */
       64,    45,    32,    23,    16,  /* 2^20 to 2^24 */
       11,     8,     6,     4,     3,  /* 2^25 to 2^29 */
        2,     1                       /* 2^30, 2^31 */
};

/* 你的 64-bit 軟體乘法 (fast_rsqrt 需要它) */
static uint64_t mul32(uint32_t a, uint32_t b){
    uint64_t r=0;
    for(int i=0;i<32;i++){
        if(b & (1U<<i))
            r+=(uint64_t) a<<i;
    }
    return r;
}

/* 你的 clz (fast_rsqrt 需要它) */
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

/* * 移除了 fast_rsqrt 函式，因為我們將其邏輯直接內聯到 main 中
 * 以便捕捉每次迭代的結果。
 */

// --- 測試主程式 (已修改) ---
int main(void) {

    // 輸出 CSV 標頭
    TEST_LOGGER("x,y0,y1,y2\n");

    uint64_t start_cycles, end_cycles, cycles_elapsed;
    uint64_t start_instret, end_instret, instret_elapsed;

    start_cycles = get_cycles();
    start_instret = get_instret();

    for (uint32_t x = 1; x <= 100; x++) {
        
        // 1. 輸出 'x'
        print_dec(x);
        TEST_LOGGER(",");

        uint32_t y, y0, y1, y2;

        // 處理 x=1 的特殊情況
        if (x == 1) {
            y0 = 65536; // 1.0 in Q1.16
            y1 = 65536;
            y2 = 65536;
        } else {
            // --- 這是 fast_rsqrt 的邏輯 ---
            
            // 步驟 1: 查表和內插 (得到 y0)
            int exp = 31 - clz(x);
            y = rsqrt_table[exp];

            if (x > (1u << exp)) {
                uint32_t y_next = (exp < 31) ? rsqrt_table[exp + 1] : 0;
                uint32_t delta = y - y_next;
                // 注意: 這裡的 64 位元轉換 (uint64_t)x 很重要，避免 32 位元溢位
                uint32_t frac = (uint32_t)((((uint64_t)x - (1UL << exp)) << 16) >> exp);
                
                // 這裡的 * 運算子會被 GCC 自動替換成 __mulsi3
                y -= (uint32_t)((delta * frac) >> 16);
            }
            y0 = y; // 儲存初始猜測值

            // 步驟 2: 第 1 次牛頓法迭代 (得到 y1)
            uint32_t y2_nr = (uint32_t)mul32(y, y);
            uint32_t xy2_nr = (uint32_t)(mul32(x, y2_nr) >> 16);
            y = (uint32_t)(mul32(y, (3u << 16) - xy2_nr) >> 17);
            y1 = y; // 儲存第 1 次迭代結果

            // 步驟 3: 第 2 次牛頓法迭代 (得到 y2)
            y2_nr = (uint32_t)mul32(y, y);
            xy2_nr = (uint32_t)(mul32(x, y2_nr) >> 16);
            y = (uint32_t)(mul32(y, (3u << 16) - xy2_nr) >> 17);
            y2 = y; // 儲存第 2 次迭代結果
        }

        // 2. 輸出 y0, y1, y2
        print_dec(y0); TEST_LOGGER(",");
        print_dec(y1); TEST_LOGGER(",");
        print_dec(y2); TEST_LOGGER("\n");
    }

    end_cycles = get_cycles();
    end_instret = get_instret();

    // --- 計算總和與平均 ---
    cycles_elapsed = end_cycles - start_cycles;
    instret_elapsed = end_instret - start_instret;

    // 印出效能數據 (在 CSV 數據之後)
    TEST_LOGGER("--- Performance ---\n");
    TEST_LOGGER("Total Cycles (100 calls): ");
    print_dec((unsigned long) cycles_elapsed);
    TEST_LOGGER("\nAvg Cycles per call: ");
    print_dec(udiv((unsigned long) cycles_elapsed, 100)); // 使用您的軟體除法
    TEST_LOGGER("\n");

    TEST_LOGGER("Total Instructions (100 calls): ");
    print_dec((unsigned long) instret_elapsed);
    TEST_LOGGER("\nAvg Instructions per call: ");
    print_dec(udiv((unsigned long) instret_elapsed, 100)); // 使用您的軟體除法
    TEST_LOGGER("\n");

    return 0; // 這個 return 會被 start.S 裡的 ecall 93 接住
}