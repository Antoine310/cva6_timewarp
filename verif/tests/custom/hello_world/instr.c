volatile int array[1] = {1};

int main() {

    unsigned long c1, c2, i1, i2;

    asm volatile(
        "la t0, array\n"

        // Warmup load
        "lw x10, 0(t0)\n" // Load en assembleur 

        "lw x11, 0(t0)\n"
        "lw x12, 0(t0)\n"
        "csrr %2, cycle\n" // Lecture de cycle en assembleur 
        "csrr %3, cycle\n"
        "lw x10, 0(t0)\n"
        "lw x11, 0(t0)\n"
        "csrr %1, cycle\n"
        "csrr %2, cycle\n"


        : "=r"(c1), "=r"(i1), "=r"(c2), "=r"(i2)
        :
        : "t0", "x10", "x11", "x12", "x13", "memory"
    );

    //printf("cycle delta   = %lu\n", c2 - c1);
    //printf("instret delta = %lu\n", i2);

    return 0;
}