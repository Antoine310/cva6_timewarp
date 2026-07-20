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
    
Première commande a faire :   depot/verif/sim$ source setup-env.sh 

à lancer dans : /verif/sim, changer le test cible dans la commande ici : /tests/custom/hello_world/?.c    

Les deux première version de timewarp pour load individuel : 

- timewarp_stall : fonction de stall pour l'obfuscation
    . Fichier modifier :
           cva6.sv ( ajout du module timewarp ), nouveau fichier timewarp (contient la logique), commit.sv (systeme de stall + load commit ) //timewarp commentaire, dans wt_cache.sv(fil load hit) //timewarp 
    Test : instr.c ( scenario d'activation de la solution, on peut bouger les instructions assembleurs un peut dans tout les sens ), attack.c ( attaque simple , retourne le delta en printf).
  
- timewarp_charge : fonction de charge pour l'obfuscation
  . Fichier modifier :
            cva6.sv ( ajout du module timewarp ), nouveau fichier timewarp (contient la logique), commit.sv (load commit) //timewarp commentaire, dans wt_cache.sv(fil load hit) //timewarp,
              csr_regfile (ajout de la charge signal cycle_timewarp et retour info lecture cycle au commit, //timewarp). 
    Test : instr.c ( scenario d'activation de la solution, on peut bouger les instructions assembleurs un peut dans tout les sens ), attack.c ( attaque simple , retourne le delta en printf).

Version load multiple stable avec enclave : 

- timewarp_multiload_enclave : fonction de charge sur multiple load en enclave
    . Fichier modifier :
            cva6.sv ( ajout du module timewarp ), nouveau fichier timewarp (contient la logique), commit.sv (load commit) //timewarp commentaire, dans wt_cache.sv(fil load hit) //timewarp,
              csr_regfile (ajout de la charge signal cycle_timewarp et retour info lecture cycle au commit, //timewarp).
      . Fichier modifier par rapport à timewarp_charge :
            timewarp.sv (contient la logique), wt_cache.sv(fil load hit avec enclave),perf_counter.sv (logique id enclave), wt_dache_mem (logique id enclave) 
  
    Test : test_enclave_multi.c ( scenario de comparaison de boucle avec csr pour verification miss hit ) , hist_perso.c ( scenario d'attaque prime probe )
  
Version load multiple avec une charge dynamique : 

- timewarp_dynamique : fonction de charge dynamique avec tableau pour delta entre Hit et miss.
      . Fichier modifier par rapport à timewarp_multiload_enclave :
            timewarp.sv (contient la logique - ajout des tableaux et calcul moyenne), load_unit (calcul de latence dans le cache -//timewarp)  
  
    Test : test_enclave_multi.c ( scenario de comparaison de boucle avec csr pour verification miss hit ) , hist_perso.c ( scenario d'attaque prime probe )
