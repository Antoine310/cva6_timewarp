volatile int array[1] = {1};

int main() {
    unsigned long c1, c2;

    asm volatile(
        "la t0, array\n"

        // Warmup
        "lw x10, 0(t0)\n"
        

        // Série de loads (pipeline plein)
        "lw x11, 0(t0)\n"
        "lw x12, 0(t0)\n"
        "lw x13, 0(t0)\n"

        // Lecture cycle 
        "csrr %0, cycle\n"


        "lw x10, 0(t0)\n"
        "lw x11, 0(t0)\n"
        "lw x12, 0(t0)\n"
        "lw x13, 0(t0)\n"
        "lw x10, 0(t0)\n"

        // Deuxième Lecture cycle 
        "csrr %1, cycle\n"

        : "=r"(c1), "=r"(c2)
        :
        : "t0", "x10", "x11", "x12", "x13", "memory"
    );

    //printf("delta = %lu\n", c2 - c1);
    return 0;
}