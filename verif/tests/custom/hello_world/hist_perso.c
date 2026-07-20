#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "rlibsc.h" 

#define HISTOGRAM_ENTRIES 10000
#define HISTOGRAM_SCALE 10
#define MEASUREMENTS 10


#define CSR_MHPMEVENT3 0x323
#define CSR_MHPMEVENT4 0x324
#define CSR_MHPMEVENT5   0x325
#define CSR_HPMCOUNTER5  0xC05
#define CSR_MHPMEVENT6  0x326
#define CSR_HPMCOUNTER6 0xC06
#define CSR_HPMCOUNTER7 0xC07
#define CSR_MHPMEVENT7  0x327

#define read_csr(csr) ({ \
    unsigned long __tmp; \
    asm volatile("csrr %0, " stringify(csr) : "=r"(__tmp)); \
    __tmp; \
})

#define stringify(x) #x
#define csr_write(csr, val) \
    asm volatile("csrw " stringify(csr) ", %0" :: "rK"(val))


//char __attribute__((aligned(4096))) buffer[64 * 1024];

static inline void set_miss_counter(void)
{
    csr_write(CSR_MHPMEVENT6, 2);
}
static inline void set_evinc_counter(void)
{
    csr_write(CSR_MHPMEVENT7, 18);
}
static inline void set_enclave_id(uint8_t id)
{
    uint32_t v = ((uint32_t)(id & 0xF)) << 23;
    csr_write(CSR_MHPMEVENT4, v);
}

#define PRIME_T 20 // taille tab
#define PRIME_P 8 // Prime probe
#define PRIME_I 16 // Init 
#define PRIME_STRIDE 4096
char __attribute__((aligned(4096))) buffer[(PRIME_T ) * PRIME_STRIDE];

static inline void Init_cache (void *addr) // set le cache pour avoir la bonne mesure prime probe 
{
    size_t pset = (((size_t)addr) >> 4) & 0xFF; // Init le set pour le cache 
    size_t other_set = 41;

    for (int k = 1; k <= PRIME_P ; k++) {
        maccess(buffer + k * PRIME_STRIDE + (other_set << 4)); // Calcul adresse buffet + index dans buffer + bon set 
    }

    asm volatile("fence");
}

static inline void Init_cache_prime (void *addr) // set le cache pour avoir la bonne mesure prime probe 
{
    size_t pset = (((size_t)addr) >> 4) & 0xFF; // Init le set pour le cache 
    size_t other_set = 41;

    for (int k = 0; k <= 8 ; k++) { 
    for (int k = 1; k <= PRIME_P ; k++) {
        maccess(buffer + k * PRIME_STRIDE + (other_set << 4)); // Calcul adresse buffet + index dans buffer + bon set 
        }
    }
    asm volatile("fence");
}

static inline void prime_probe(void *addr) // set le cache pour avoir la bonne mesure prime probe 
{
    size_t pset = (((size_t)addr) >> 4) & 0xFF; // Init le set pour le cache 
    size_t other_set = 41;

    for (int k = 1; k <= PRIME_P ; k++) {
        maccess(buffer + k * PRIME_STRIDE + (other_set << 4));
    }

    asm volatile("fence");
}

static inline void victime(void *addr)
{
    size_t pset = (((size_t)addr) >> 4) & 0xFF; // Init le set pour le cache 
    size_t other_set = 41;

    maccess(buffer + 17 * PRIME_STRIDE + (other_set << 4)); // Calcul adresse buffet + index dans buffer + bon set 
    maccess(buffer + 18 * PRIME_STRIDE + (other_set << 4)); // Calcul adresse buffet + index dans buffer + bon set 
    
    asm volatile("fence");
}

/* 
static inline void prime(void *addr)
{
    size_t pset = (((size_t)addr) >> 4) & 0xFF;

    int pn = ((size_t)addr) & 4096;
    int bufpn = ((size_t)buffer) & 4096;

    int i = 1;
    int j = (pn == bufpn) ? 0 : 1;

    REP36(
        maccess(
            buffer +
            i++ * 2 * 4096 +
            j * 4096 +
            (pset << 4)
        );
    )

    asm volatile("fence");
}*/
/*
static inline void prime(void *addr)
{
    size_t pset = (((size_t)addr) >> 4) & 0xFF;

    int pn = ((size_t)addr) & 4096;
    int bufpn = ((size_t)buffer) & 4096;

    int i = 1;
    int j = (pn == bufpn) ? 0 : 1;

    printf("victim=%lx set=%lu\n",
           (unsigned long)addr,
           (unsigned long)(((size_t)addr >> 4) & 0xFF));

    for(int k=1;k<=8;k++)
    {
        uintptr_t a =
            (uintptr_t)(buffer +
                        k * 2 * 4096 +
                        j * 4096 +
                        (pset << 4));

        printf("prime[%d]=%lx set=%lu\n",
               k,
               (unsigned long)a,
               (unsigned long)((a >> 4) & 0xFF));
    }

    REP8(
        maccess(
            buffer +
            i++ * 2 * 4096 +
            j * 4096 +
            (pset << 4)
        );
    )

    asm volatile("fence");
}*/
static inline size_t empty_time(void) {
  uint64_t x = rdcycle();
  uint64_t y = rdcycle();
  return y - x;
}

static inline size_t one_load_time(void *addr) {
  uint64_t x = rdcycle();
  maccess(addr);
  uint64_t y = rdcycle();
  return y - x;
}

size_t measure_access_time(void *address) {
  uint64_t x = rdcycle();
  prime_probe(address);
  uint64_t y = rdcycle();

  return y - x;
}


uint64_t max_ref = 0;
uint64_t cumul_ref = 0;
uint64_t max_probe = 0;
uint64_t cumul_prime = 0;

uint64_t check_miss_ref = 0;
uint64_t check_miss_prime_probe = 0;
uint64_t check_miss_victime = 0;

uint64_t check_evinc_victime = 0;

uint64_t ref_miss[MEASUREMENTS];
uint64_t victim_miss[MEASUREMENTS];
uint64_t victim_evict[MEASUREMENTS];
uint64_t probe_miss[MEASUREMENTS];
uint64_t cumul_refTab [MEASUREMENTS];
uint64_t cumul_primeTab [MEASUREMENTS];

// Mesure le temps de reference pour parcourir les Hit du cache 
void measure_prime_ref(void *address, size_t *histogram, size_t number_of_measurements) {

  for (size_t i = 0; i < number_of_measurements; i++) {

    prime_probe(address); 

    uint64_t m0 = read_csr(CSR_HPMCOUNTER6);

    size_t prime = measure_access_time(address); 

    uint64_t m1 = read_csr(CSR_HPMCOUNTER6);

    check_miss_ref = check_miss_ref + (m1-m0); 
    ref_miss[i] = m1-m0;
    cumul_refTab[i] = prime;
    cumul_ref = cumul_ref + prime;
    if (prime > max_ref) max_ref = prime;
    if (prime < HISTOGRAM_ENTRIES) histogram[prime]++;
  }
}

// Mesure le temps avec l'evection fait par la victime 
void measure_prime_probe(void *address, size_t *histogram, size_t number_of_measurements) {

  for (size_t i = 0; i < number_of_measurements; i++) {

    //Init_cache(address); // besoin pour avoir assez de ligne virer
    Init_cache_prime(address); // re remplace les lignes parasites 
    //prime_probe(address); 

    uint64_t m0 = read_csr(CSR_HPMCOUNTER6);
    uint64_t e0 = read_csr(CSR_HPMCOUNTER7);
    victime(address);
    uint64_t e1 = read_csr(CSR_HPMCOUNTER7);
    uint64_t m1 = read_csr(CSR_HPMCOUNTER6);

    size_t probe = measure_access_time(address);

    uint64_t e2 = read_csr(CSR_HPMCOUNTER7);

    uint64_t m2 = read_csr(CSR_HPMCOUNTER6);
    
    victim_miss[i] = (m1-m0); 
    victim_evict[i]= (e1-e0);
    probe_miss[i] =(e2-e1) ;
    cumul_primeTab[i] = probe;

    //check_evinc_victime = check_evinc_victime + (e1-e0);
    //check_miss_prime_probe = check_miss_prime_probe + (m2-m1); 
    //check_miss_victime = check_miss_victime + (m1-m0); 
    cumul_prime = cumul_prime + probe ; 

    if (probe > max_probe) max_probe = probe;
    if (probe < HISTOGRAM_ENTRIES) histogram[probe]++;
  }
  
}

/* 
void measure_hits(void *address, size_t *histogram,
                  size_t number_of_measurements) {
  for (size_t i = 0; i < number_of_measurements; i++) {
    size_t hit = measure_access_time(address);
    if (hit < HISTOGRAM_ENTRIES)
      histogram[hit]++;
  }
}

void measure_misses(void *address, size_t *histogram,
                    size_t number_of_measurements) {
  for (size_t i = 0; i < number_of_measurements; i++) {
    maccess(address);
    size_t miss = measure_access_time(address);
    if (miss < HISTOGRAM_ENTRIES)
      histogram[miss]++;
  }
}*/

static inline size_t probe_time(void *addr)
{
    uint64_t x = rdcycle();
    maccess(addr);
    uint64_t y = rdcycle();
    return y - x;
}
static inline void set_secure_flag(void)
{
    csr_write(CSR_MHPMEVENT3, (1u << 23));
}

static inline void test(void *addr) // set le cache pour avoir la bonne mesure prime probe 
{
    size_t pset = (((size_t)addr) >> 4) & 0xFF; // Init le set pour le cache 
    printf("victim=%lx\n", (unsigned long)addr);

    for(int k=1;k<=10;k++) {

        uintptr_t a =
            (uintptr_t)(buffer +
                        k * PRIME_STRIDE +
                        (pset << 4));

        printf("k=%d time=%lu\n",
              k,
              (unsigned long)probe_time((void*)a));
    }
    asm volatile("fence");
}
size_t hit_histogram[HISTOGRAM_ENTRIES], miss_histogram[HISTOGRAM_ENTRIES];
char __attribute__((aligned(4096))) address[4096];

int main(int argc, char *argv[]) {
  
  set_secure_flag();

  set_miss_counter();
  set_evinc_counter();

  set_enclave_id(0);
  
  printf("START\n");

  memset(address, 1, 4096);
  memset(buffer, 2, sizeof(buffer));
  /* 
  for (uint64_t i=0; i<10; i++) {

      Init_cache(address);

      prime_probe(address);

      uint64_t e0 = read_csr(CSR_HPMCOUNTER7);

      victime(address);

      asm volatile("fence rw,rw");

      uint64_t e1 = read_csr(CSR_HPMCOUNTER7);

      printf("evictions=%lu\n",
            (unsigned long)(e1-e0));
  }*/
  measure_prime_ref(address, hit_histogram, MEASUREMENTS);
  measure_prime_probe(address, miss_histogram, MEASUREMENTS);

  printf("max_ref=%lu\n", (unsigned long)max_ref);
  printf("moyenne cumul ref =%lu\n", (unsigned long)cumul_ref/MEASUREMENTS);
  //printf("moyenne check_miss_ref =%lu\n", (unsigned long)check_miss_ref/MEASUREMENTS ); // Normalement 0
  
  printf("max_probe=%lu\n", (unsigned long)max_probe);
  printf("moyenne cumul prime_probe =%lu\n", (unsigned long)cumul_prime/MEASUREMENTS);

  /*
  printf("moyenne check_miss_victime =%lu\n", (unsigned long)check_miss_victime/MEASUREMENTS ); // normalement 1 ici  
  printf("moyenne check_miss_prime_probe =%lu\n", (unsigned long)check_miss_prime_probe/MEASUREMENTS );  // nombre de lignes de l'attaquant evinc par la victime
  printf("moyenne check_evinc_victime =%lu\n", (unsigned long)check_evinc_victime/MEASUREMENTS ); // normalement 1 ici  
  
  printf("\n===== REF =====\n");
  for (size_t i = 0; i < MEASUREMENTS; i++) {
      printf("Prime Ref i : %lu , nombre miss = %lu\n",
            (unsigned long)i,
            (unsigned long)ref_miss[i]);
  }
*/
   /*
  printf("\n===== PRIME+PROBE =====\n");
  for (size_t i = 0; i < MEASUREMENTS; i++) {
      printf("Prime probe i : %lu , evinc victime = %lu , miss victime = %lu , miss probe = %lu\n",
            (unsigned long)i,
            (unsigned long)victim_evict[i],
            (unsigned long)victim_miss[i],
            (unsigned long)probe_miss[i]);
  } */

    printf("\n===== Temps =====\n");
  for (size_t i = 0; i < MEASUREMENTS; i++) {
      printf("Temps cumul i : %lu , cumul_refTab = %lu , cumul_primeTab = %lu , miss probe = %lu\n",
            (unsigned long)i,
            (unsigned long)cumul_refTab[i],
            (unsigned long)cumul_primeTab[i],
            (unsigned long)probe_miss[i]);
  } 
  /*
  for (size_t i = 0; i < HISTOGRAM_ENTRIES; i += HISTOGRAM_SCALE) {
    size_t hit = 0, miss = 0;
    for (size_t scale = 0; scale < HISTOGRAM_SCALE; scale++) {
      hit += hit_histogram[i + scale];
      miss += miss_histogram[i + scale];
    }
    if (hit || miss)
      printf("sortie b %lu: %lu %lu\n", (unsigned long)i, (unsigned long)hit, (unsigned long)miss);  
    }*/
   
  return 0;
}

