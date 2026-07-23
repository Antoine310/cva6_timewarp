# cva6_timewarp

## Utiliser dans le cadre

- Chaîne : `riscv-none-elf-gcc`
- GCC Version : `13.1.0`
- Verilator Version : `5.008`
- Configuration : `cv64a6_imafdc_sv39`
- ISA : `rv64gc_zba_zbb_zbs_zbc`
- Ubuntu : 22.04

---
# Tester le projet

1. Cloner le dépôt :

```bash
git clone git@github.com:Antoine310/cva6_timewarp.git
```

2. Choisir la branche souhaitée :

```bash
git checkout <nom_de_la_branche>
```

3. Initialiser les sous-modules :

```bash
git submodule update --init --recursive
```

4. Charger l'environnement :

```bash
source setup-env.sh
```

5. Modifier le test cible dans :

```text
/tests/custom/hello_world/?.c
```

6. Lancer la commande :

```bash
python3 cva6.py \
  --target cv64a6_imafdc_sv39 \
  --iss "$DV_SIMULATORS" \
  --iss_yaml cva6.yaml \
  --c_tests ../tests/custom/hello_world/instr.c \
  --linker ../../config/gen_from_riscv_config/linker/link.ld \
  --gcc_opts='-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S -lgcc -I../tests/custom/env -I../tests/custom/common' \
  --issrun_opts='+echo_uart'
```
7. Resultat de test

les resultats sont dans les fichiers : au Dossier Out_DateDuJours dans le fichier .log.iss au nom du programme de test : 
  /cva6_timewarp/verif/sim/out_2026-07-23/veri-testharness_sim$
  
---

# Différentes branches disponibles

## timewarp_stall

Première version de TimeWarp utilisant une fonction de **stall** pour l'obfuscation.

### Fichiers modifiés

- `cva6.sv` (ajout du module TimeWarp)
- `timewarp.sv` (logique principale)
- `commit.sv` (système de stall + commit des load) `//timewarp`
- `wt_cache.sv` (signal load hit) `//timewarp`

### Tests

- `instr.c` : scénario d'activation de la solution (les instructions assembleur peuvent être déplacées).
    . Pour observer le comportement : activer les displays dans le fichier timewarp.sv
    . Chercher le signal csr_lecture_cycle_i dans le fichier .iss pour voir les simulations d'attaques et l'activation du signal protect_en_o.
- `attack.c` : attaque simple retournant le delta en `printf`.

---

## timewarp_charge

Version utilisant une fonction de charge pour l'obfuscation.

### Fichiers modifiés

- `cva6.sv` (ajout du module TimeWarp)
- `timewarp.sv` (logique principale)
- `commit.sv` (load commit) `//timewarp`
- `wt_cache.sv` (signal load hit) `//timewarp`
- `csr_regfile.sv`
  - ajout du signal de charge
  - signal `cycle_timewarp`
  - retour de la lecture du compteur au commit `//timewarp`

### Tests

- `instr.c` : scénario d'activation.
- `attack.c` : attaque simple retournant le delta.

---

## timewarp_multiload_enclave

Version stable Multi-loads et enclaves.

### Fichiers modifiés

- `cva6.sv`
- `timewarp.sv`
- `commit.sv`
- `wt_cache.sv`
- `csr_regfile.sv`

### Modifications supplémentaires par rapport à `timewarp_charge`

- `timewarp.sv` (nouvelle logique)
- `wt_cache.sv` (gestion des enclaves)
- `perf_counter.sv` (identifiant d'enclave)
- `wt_dcache_mem.sv` (identifiant d'enclave)

### Tests

- `test_enclave_multi.c` : comparaison de boucles avec CSR pour vérifier hit/miss.
- `hist_perso.c` : scénario d'attaque Prime+Probe.

---

## timewarp_dynamique

Version avec charge dynamique basée sur un tableau permettant d'estimer le delta entre les hit et les miss.

### Modifications par rapport à `timewarp_multiload_enclave`

- `timewarp.sv`
  - ajout des tableaux
  - calcul de la moyenne
- `load_unit.sv`
  - calcul de la latence dans le cache `//timewarp`

### Tests

- `test_enclave_multi.c` : comparaison de boucles avec CSR pour vérifier hit/miss.
- `hist_perso.c` : scénario d'attaque Prime+Probe.
