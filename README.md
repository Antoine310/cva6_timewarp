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
4. Config environnement :
   
  - Si déja une toolchain et un précédent dépot cva6 configurer, il est possible de transferer directement le repertoire tools de votre dépot cva6 vers ce dépot sans autre installation.
  - Si Pas de dépot cva6 déja installer il est necessaire de suivre a partir de l'étape 2 jusqu'a l'étape 6 le quick startup présent dans le README des autres branches,puis ensuite de faire :
    export DV_SIMULATORS=veri-testharness
    
5. Charger l'environnement :

```bash
source setup-env.sh
```

6. Modifier le test cible dans :

```text
/tests/custom/hello_world/?.c
```

7. Lancer la commande :

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
8. Resultat de test

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

- `instr.c` : scénario d'activation de la solution (les instructions d'assembleur peuvent être déplacées).
    . Pour observer le comportement : activer les displays dans le fichier timewarp.sv
    . Chercher le signal csr_lecture_cycle_i dans le fichier de resultat .iss pour voir les simulations d'attaques et l'activation du signal protect_en_o sur le nombre de cycles indiqué en paramètre du module.
- `attack.c` : Schéma d'attaque avec un delta qui renvoie la différence de temps entre les deux.

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

- `instr.c` : scénario d'activation de la solution (les instructions d'assembleur peuvent être déplacées).
    . Pour observer le comportement : activer les displays dans le fichier timewarp.sv
    . Chercher le signal csr_lecture_cycle dans le fichier de resultat .iss pour voir les simulations d'attaques et l'activation du signal charge_o qui envoie la charge.
- `attack.c` : Schéma d'attaque avec un delta qui renvoie la différence de temps entre les deux.


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
    . Dans le fichier resultat .iss chercher ctrl f : "miss delta" montre le nombre de miss sur la boucle ( 100 miss ou 100 hit par exemple ici )
    et les prinft "miss loop" montre le nombre de cycle pour chaque boucle.
      On peut activer les display et regarder les même signal que timewarp_charge et le compteur de hit pour verifier le fonctionnement.
- `hist_perso.c` : scénario d'attaque Prime+Probe.
    . Dans le fichier resultat .iss chercher ctrl f : "Temps" permet de voir les valeur de référence et les valeurs du probe en nombre de cycle chacun. Il peut y avoir deux variations au niveau de l'attaque : une petite variation cumul_refTab = 819 , cumul_primeTab = 835 qui correspond a que la victime n'a pas été bien évincé avant de refaire la mesure comme le remplacement est aléatoire ça peut arriver, et une grande variation : cumul_refTab = 1108 , cumul_primeTab = 816 qui est l'utilisation du set cible par le processeur pour autre chose comme printf en simultané du test. Il est possible d'arriver à une obfuscation parfaite mais généralement il y a un décalage car cela dépend de l'obfuscation nécessaire et souvent du Pc qui lance car l'obfuscation nécessaire peut changer un peu.
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
" Les résultats de cette version ne sont pas correct mais comme mentionner dans le rapport mais son principe fonctionne et est une piste intéressante futur dans les améliorations."

- `test_enclave_multi.c` : comparaison de boucles avec CSR pour vérifier hit/miss.
     .On peut voir dans le fichier de resultat l'affichage en display des tableaux Miss et Hit qui calcule bien le delta en fonction des latences dans le cache.
- `hist_perso.c` : scénario d'attaque Prime+Probe.
