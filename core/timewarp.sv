// Module protection miss/hit
// Module protection hit/read
/*
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

*/

module timewarp
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type dcache_req_o_t = logic,
    parameter int HIT_TIME = 40,    // Delais Hit présent, HIT_TIME > 0 
    parameter int CHARGE_TIME = 5 // temps ajouter au compteur de la charge 
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Lecture du cycle en cours dans csr_regfile 
    input logic csr_lecture_cycle,
    // HIT du Dcache 
    input logic dcache_hit_i,
    // Load commit 
    input logic load_commit_i,
    // Load invalid du commit  
    input logic load_invalid_i,
    // Ex_stage lecture csr 
    input logic lecture_csr_i,
    // Charge cycle csr_regfile
    output logic [6:0] charge_o
);
    logic [$clog2(HIT_TIME+1)-1:0] compteur_hit;
    logic [8:0] compteur_stall;

    logic hit_en ;
    logic [2:0] dcache_hit_q;

    logic [6:0] charge_q, charge_d;    
    logic reset_charge;
    logic csr_lecture;

    always_comb begin : charge

        charge_d = charge_q; // On recupere la charge en cours 
        // Si lecture csr et hit, on crée une offuscation en rajoutant une charge +10 qu'on envoie au csr_regfile.
        if (csr_lecture && (hit_en)) begin 
            charge_d = charge_q + 7'd10; 
        end else if (reset_charge) begin 
            charge_d = '0;
        end

    end 

    assign charge_o = charge_d ; // Sortie de la charge en cours.

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            hit_en <= 1'b0;
            compteur_hit <= '0;
            compteur_stall <= '0;
            dcache_hit_q <= '0;
            charge_q  <= '0;
            reset_charge <= 1'b0;
            csr_lecture <= 1'b0;
        end else begin 

            dcache_hit_q <= dcache_hit_q + dcache_hit_i - ((dcache_hit_q>0) && load_commit_i) - ((dcache_hit_q>0) && load_invalid_i);
            // Sauvegarde de la charge en cours
            charge_q  <= charge_d;

            // Si on a une Lecture csr qui arrive dans le Ex stage, on active le flag
            if (lecture_csr_i)
                csr_lecture <= 1'b1;
            else if ((csr_lecture && (hit_en)) || csr_lecture_cycle) // Si on le consomme ou qu'on a pas de hit load (le csr commit est arrive sans load avant), on reset le flag
                csr_lecture <= 1'b0;
            // Meme fonctionnement du compteur de Hit que version 1 
            if ((dcache_hit_q > 0) && load_commit_i) begin
                hit_en <= 1'b1; 
                compteur_hit <= HIT_TIME[$bits(compteur_hit)-1:0];
            end else if (compteur_hit != 0) begin
                compteur_hit <= compteur_hit - 1 ; 
                if (compteur_hit == 1) begin
                    hit_en <= 1'b0; 
                end
            end 

            reset_charge <= 1'b0;
            // A partir du commit de la lecture csr, on demarre le timer pendant au minimum de charge cycle + une valeur possible, 
            //si on fait moins on pourrait avoir une incoherence du temps
            if (hit_en && csr_lecture_cycle) begin 
                hit_en <= 1'b0; 
                compteur_stall <= CHARGE_TIME[$bits(compteur_stall)-1:0] + charge_d;
            end else if (csr_lecture_cycle && compteur_stall>0) begin // Lecture donc relance du timer si timer déja lancer et commit csr sans hit load 
                compteur_stall <= CHARGE_TIME[$bits(compteur_stall)-1:0] + charge_d ;  
            end else if (compteur_stall !=  0) begin
                compteur_stall <= compteur_stall - 1 ; 
                if (compteur_stall == 1) begin
                    reset_charge <= 1'b1; 
                end
            end 
        end 
    end


endmodule 
