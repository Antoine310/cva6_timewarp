volatile int array[1] = {1};
volatile int biss[1] = {1};

int main() {

    int t1, t2,t3;

    asm volatile(
        "la t0, array\n"
        "csrr %0, cycle\n"
        "lw x10, 0(t0)\n"
        "csrr %1, cycle\n"
        "lw x10, 0(t0)\n"
        "csrr %2, cycle\n"

        : "=r"(t1), "=r"(t2) , "=r"(t3)
        :
        : "t0", "x10", "memory"
    );

    printf("RESULTAT : delta = %d\n", (t2-t1)-(t3-t2));
    return 0;
}