#include <stdint.h>
#include <stdio.h>

#define CSR_MHPMEVENT3 0x323
#define CSR_MHPMEVENT4 0x324
#define CSR_MHPMEVENT5   0x325
#define CSR_HPMCOUNTER5  0xC05
#define CSR_MHPMEVENT6  0x326
#define CSR_HPMCOUNTER6 0xC06


#define STRIDE 4

#define stringify(x) #x
#define csr_write(csr, val) \
    asm volatile("csrw " stringify(csr) ", %0" :: "rK"(val))

#define read_csr(csr) ({ \
    unsigned long __tmp; \
    asm volatile("csrr %0, " stringify(csr) : "=r"(__tmp)); \
    __tmp; \
})

static inline void set_enclave_id(uint8_t id)
{
    uint32_t v = ((uint32_t)(id & 0xF)) << 23;
    csr_write(CSR_MHPMEVENT4, v);
}
static inline void desac_enclave_id(uint8_t id)
{
    uint32_t v = ((uint32_t)(id & 0xF)) << 23;
    csr_write(CSR_MHPMEVENT4, v);
}

static inline void set_lecture_hit(void)
{
    csr_write(CSR_MHPMEVENT5, 28);
}

static inline uint64_t lecture_hit(void)
{
    return read_csr(CSR_HPMCOUNTER5);
}

static inline void set_secure_flag(void)
{
    csr_write(CSR_MHPMEVENT3, (1u << 23));
}

static inline void none_secure_flag(void)
{
    csr_write(CSR_MHPMEVENT3, (0u << 23 ));
}

static inline uint64_t rdcycle(void)
{
    uint64_t v;
    asm volatile("rdcycle %0" : "=r"(v));
    return v;
}
static inline void set_miss_counter(void)
{
    csr_write(CSR_MHPMEVENT6, 2);
}
static inline void fence_rw(void) { asm volatile("fence rw, rw" ::: "memory"); }
static inline void keep_u32(uint32_t x) { asm volatile("" :: "r"(x) : "memory"); }

int main(void)
{
    set_enclave_id(1);
    set_secure_flag();

static volatile uint32_t line __attribute__((aligned(64))) = 0x12345678;    volatile uint32_t sink = 0;


    static volatile uint32_t array[128 * STRIDE]
        __attribute__((aligned(64)));

    set_miss_counter();
    set_lecture_hit();

    uint64_t miss0 = read_csr(CSR_HPMCOUNTER6);
    uint64_t a0 = rdcycle();


    for (uint32_t i = 0; i < 99; i++) {
        sink += array[i * STRIDE];
    }
    fence_rw();

    uint64_t a1 = rdcycle();
    uint64_t miss1 = read_csr(CSR_HPMCOUNTER6);

    uint64_t h2 = lecture_hit();
    uint64_t miss3 = read_csr(CSR_HPMCOUNTER6);
    uint64_t a2 = rdcycle();

    for (uint32_t i = 0; i < 99; i++) {
        sink += array[i * STRIDE];
    }
    fence_rw();

    uint64_t a3 = rdcycle();
    uint64_t miss4 = read_csr(CSR_HPMCOUNTER6);
    uint64_t h3 = lecture_hit();
    uint64_t a4 = rdcycle();
    uint64_t missBis = read_csr(CSR_HPMCOUNTER6);


    const uint32_t N = 110;

    sink += line;
    fence_rw();
    uint64_t h0 = lecture_hit();
    uint64_t t0 = rdcycle();
    for (uint32_t i = 0; i < N; i++) {
        sink += line;
    }
    uint64_t t1 = rdcycle();
    uint64_t h1 = lecture_hit();

    fence_rw();

    desac_enclave_id(0);
    none_secure_flag();

    keep_u32(sink);
    
    sink += line;
    fence_rw();

    uint64_t t3 = rdcycle();

    for (uint32_t i = 0; i < N; i++) {
        sink += line;
    }

    uint64_t t4 = rdcycle();

    uint64_t cycles = t1 - t0;

    uint64_t cycles2 = t4 - t3 ;

    printf(" Hit event 1  %llu\n", h1 - h0 );

    printf(" Hit event 2  %llu\n", h3 - h2 );

    printf("\n Boucle Hit 20 : total=%llu cycles, per_load=%llu + %llu/%u cycles, sink=%u (0x%08x)\n",
           (unsigned long long)cycles,
           (unsigned long long)(cycles / N),
           (unsigned long long)(cycles % N),
           (unsigned)N,
           (unsigned)sink, (unsigned)sink);

    printf("\n Boucle Hit desactiver : total=%llu cycles, per_load=%llu + %llu/%u cycles, sink=%u (0x%08x)\n",
           (unsigned long long)cycles2,
           (unsigned long long)(cycles2 / N),
           (unsigned long long)(cycles2 % N),
           (unsigned)N,
           (unsigned)sink, (unsigned)sink);       

    uint64_t miss_cycles = a1 - a0;
    uint64_t miss_delta  = miss1 - miss0;
    
    uint64_t miss_cycles2 = a3 - a2;
    uint64_t miss_delta2  = miss4 - miss3;



    printf("miss verif fonc = %llu\n",
        (unsigned long long)miss4 );

    printf("miss delta 2 = %llu\n",
        (unsigned long long)miss_delta2);

    printf("miss loop 2 : total=%llu cycles, per_load=%llu + %llu/%u cycles\n",
        (unsigned long long)miss_cycles2,
        (unsigned long long)(miss_cycles2 / 100),
        (unsigned long long)(miss_cycles2 % 100),
        100u);

    printf("miss delta = %llu\n",
        (unsigned long long)miss_delta);

    printf("miss loop : total=%llu cycles, per_load=%llu + %llu/%u cycles\n",
        (unsigned long long)miss_cycles,
        (unsigned long long)(miss_cycles / 100),
        (unsigned long long)(miss_cycles % 100),
        100u);
 
    return 0;
}