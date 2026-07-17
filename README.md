# cva6_timewarp

Utiliser dans le cadre : 
    chaine : riscv-none-elf-gcc
    GCC Version : 13.1.0
    Verilator Version : Verilator 5.008
    Config : cv64a6_imafdc_sv39
    ISA : rv64gc_zba_zbb_zbs_zbc

Commande test : 
    python3 cva6.py   --target cv64a6_imafdc_sv39   --iss "$DV_SIMULATORS"   --iss_yaml cva6.yaml   --c_tests ../tests/custom/hello_world/instr.c   
    --linker ../../config/gen_from_riscv_config/linker/link.ld   --gcc_opts='-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g 
    ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S -lgcc -I../tests/custom/env -I../tests/custom/common'   --issrun_opts='+echo_uart'
    
à lancer dans : /verif/sim, changer le test cible dans la commande ici : /tests/custom/hello_world/?.c    

Les deux première version de timewarp pour load individuel : 
- timewarp_stall : fonction de stall pour l'obfuscation
- timewarp_charge : fonction de charge pour l'obfuscation

Version load multiple stable avec enclave :

- timewarp_multiload_enclave : fonction de charge sur multiple load en enclave

- timewarp_dynamique : fonction de charge dynamique avec tableau pour delta entre Hit et miss.
