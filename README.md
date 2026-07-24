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
 4. Configurer l'environnement

- Si une toolchain ainsi qu'un dépôt CVA6 sont déjà installés, il est possible de copier directement le répertoire `tools` de ce dépôt dans celui-ci.

```bash
cp -a /path/to/cva6/tools .
```
- Si aucun dépôt CVA6 n'est déjà installé, il est nécessaire de suivre les étapes 2 à 6 du Quick Start présent dans le README de CVA6 (disponible sur les autres branches du dépôt), puis d'exécuter :

```bash
export DV_SIMULATORS=veri-testharness
 ```
5. Charger l'environnement :

```bash
source setup-env.sh
```

6. Modifier le test cible dans :

```text
/tests/custom/hello_world/x.c
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

Les résultats sont disponibles dans le dossier :

```text
verif/sim/out_<DateDuJour>/veri-testharness_sim/NomDuTest.log.iss
```
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
    - Pour observer le comportement : activer les displays dans le fichier timewarp.sv
    - Chercher le signal csr_lecture_cycle_i dans le fichier de résultat .iss pour voir les simulations d'attaques et l'activation du signal protect_en_o qui stall le commit.
- `attack.c` : Schéma d'attaque avec un delta qui renvoie la différence de temps entre le Load miss et le Hit.

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
    - Pour observer le comportement : activer les displays dans le fichier timewarp.sv
    - Chercher le signal csr_lecture_cycle dans le fichier de résultat .iss pour voir les simulations d'attaques et l'activation du signal charge_o qui envoie la charge au compteur de cycle.
- `attack.c` : Schéma d'attaque avec un delta qui renvoie la différence de temps entre le Load miss et le Hit.


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
  - Rechercher `"miss delta"` dans le fichier `.iss` pour afficher le nombre de miss de la boucle (ici delta 1 : 100 miss, delta 2 : 0 miss donc 100 hits).
  - Les affichages `"miss loop"` correspondent au nombre de cycles de chaque boucle.
  - Il est également possible d'activer les `display` afin d'observer les mêmes signaux que pour `timewarp_charge` ainsi que le compteur de hits.
- `hist_perso.c` : scénario d'attaque Prime+Probe.
  - Rechercher `"Temps"` dans le fichier `.iss` pour afficher les temps de référence ainsi que les temps du probe.
  - Deux variations peuvent être observées à cause d'événements irréguliers :
    - une faible variation (`cumul_refTab = 819`, `cumul_primeTab = 835`) lorsque la victime n'a pas été complètement évincée (politique de remplacement aléatoire des ways du CVA6) ;
    - une forte variation (`cumul_refTab = 1108`, `cumul_primeTab = 816`) lorsque le processeur utilise le même set pour d'autres opérations parallèles (par exemple `printf`).
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

" Les résultats de cette version ne sont pas satisfaisant mais comme mentionner dans le rapport mais son principe fonctionne et est une piste intéressante futur dans les améliorations."

- `test_enclave_multi.c` : comparaison de boucles avec CSR pour vérifier hit/miss.
  - Les `display` permettent d'observer les tableaux `Hit` et `Miss` ainsi que le calcul dynamique du delta en fonction des latences du cache.
- `hist_perso.c` : scénario d'attaque Prime+Probe.
