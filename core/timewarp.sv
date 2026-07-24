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
    parameter int LECTURE_TIME = 8000,    // Delais Lecture présent, HIT_TIME > 0 
    parameter int CHARGE_TIME = 8000, // temps ajouter au compteur de la charge 
    parameter int MAX_HIT = 20000
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
    output logic [31:0] charge_o
);
    logic [$clog2(LECTURE_TIME+1)-1:0] compteur_lecture;
    logic [31:0] compteur_coherence_temps;

    logic hit_en ;
    logic [4:0] dcache_hit_q;

    logic [31:0] charge_q, charge_d;    
    logic reset_charge;
    logic csr_lecture;

    logic [31:0] nombre_hit; 
    logic hit_enable;
    logic deblocage_lecture;

    always_comb begin : charge
        charge_d = charge_q; // On recupere la charge en cours 
        // Si lecture csr et hit, on crée une offuscation en rajoutant une charge x qu'on envoie au csr_regfile.
        if (csr_lecture && nombre_hit > 0 ) begin 
            charge_d = (nombre_hit << 2) + nombre_hit;
        end else if (reset_charge) begin 
            charge_d = '0;
        end

    end 

    assign charge_o = charge_d ; // Sortie de la charge en cours. 

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            hit_en <= 1'b0;
            compteur_lecture <= '0;
            compteur_coherence_temps <= '0;
            dcache_hit_q <= '0;
            charge_q  <= '0;
            reset_charge <= 1'b0;
            csr_lecture <= 1'b0;
            nombre_hit <= '0;
            hit_enable <= 1'b0;
            deblocage_lecture <= 1'b0;  
        end else begin 

            // Si une lecture au commit,on ouvre la fenetre de comptage proctection + démarrage comptage hit 
            if (csr_lecture_cycle)begin
                hit_enable <= 1'b1;
                deblocage_lecture <= 1'b1;
            end 
            // Comptage des hits en cours dans la fenetre 
            if ((dcache_hit_q>0) && load_commit_i && hit_enable ) begin
                if (nombre_hit < 32'(MAX_HIT)) begin
                    nombre_hit <= nombre_hit + 1'b1;
                end
            end  
            //Compteur load en vol
            dcache_hit_q <= dcache_hit_q + 5'(dcache_hit_i) - 5'((dcache_hit_q>0) && load_commit_i) - 5'((dcache_hit_q>0) && load_invalid_i);
            // Sauvegarde de la charge en cours
            charge_q  <= charge_d;

            // Si on a une Lecture csr qui arrive dans le Ex stage, on active le flag
            if (lecture_csr_i)
                csr_lecture <= 1'b1;
            else if (csr_lecture_cycle) // Si on le consomme ou qu'on a pas de hit load (le csr commit est arrive sans load avant), on reset le flag
                csr_lecture <= 1'b0;
            
            if ((dcache_hit_q > 0) && load_commit_i) begin
                hit_en <= 1'b1; 
            end else  if (hit_en && csr_lecture_cycle) begin 
                hit_en <= 1'b0; 
            end
            
            if (deblocage_lecture) begin
                compteur_lecture <= LECTURE_TIME[$bits(compteur_lecture)-1:0];
                deblocage_lecture <= 1'b0; 
                //$display("[cycle %0d] START compteur_lecture timer = %0d",
         //nb_cycle , LECTURE_TIME);
            end else if (compteur_lecture != 0) begin
                compteur_lecture <= compteur_lecture - 1 ; 
                if (compteur_lecture == 1) begin // Fin du compteur on reset tout 
                    nombre_hit <= '0;
                    hit_enable <= 1'b0; 
                    hit_en <= 1'b0; 
                    //$display("[cycle %0d] END compteur_lecture timer ",
         //nb_cycle);
                end
            end 

            reset_charge <= 1'b0;
            // A partir du commit de la lecture csr, on demarre le timer pendant au minimum de charge cycle + une valeur possible, 
            //si on fait moins on pourrait avoir une incoherence du temps
            if (nombre_hit>0 && deblocage_lecture) begin 
                compteur_coherence_temps <=  32'(CHARGE_TIME) +  charge_d;
                compteur_lecture <= '0;
                /*$display("[cycle %0d] START coherence_timer hits=%0d charge=%0d total=%0d",
                    nb_cycle,
                    nombre_hit,
                    charge_d,
                     32'(CHARGE_TIME) + charge_d);*/
            end else if (deblocage_lecture && compteur_coherence_temps > 0) begin // Lecture donc relance du timer si timer déja lancer et commit csr sans hit load 
                compteur_coherence_temps <=  32'(CHARGE_TIME) + charge_d;
                compteur_lecture <= '0;
                //$display("[cycle %0d] Relance la charge timer ! charge_q=%0d charge_d=%0d ", nb_cycle, charge_q , charge_d) ;
            end else if (compteur_coherence_temps !=  0) begin
                compteur_coherence_temps <= compteur_coherence_temps - 1 ; 
                if (compteur_coherence_temps == 1) begin
                    reset_charge <= 1'b1; 
                    nombre_hit <= '0;
                    hit_enable <= 1'b0; 
                    hit_en <= 1'b0; 
                    //$display("[cycle %0d] END coherence_timer",
         //nb_cycle);
                end
            end 
        end  
            
    end


    
    logic hit_en_q;
    logic csr_cycle_q;
    logic [4:0] dcache_hit_c;    
    int nb_cycle;
    logic load_commit_q;
    logic lecture_csr_i_q;
    logic csr_lecture_q;
    logic [31:0] nombre_hit_q;
    logic hit_enable_q;
    logic dcache_hit_i_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            hit_en_q      <= 1'b0;
            dcache_hit_c  <= '0;
            csr_cycle_q   <= 1'b0;
            nb_cycle      <= '0;
            csr_lecture_q <= 1'b0;
            lecture_csr_i_q <= 1'b0;
            nombre_hit_q <= '0;
            hit_enable_q <= 1'b0;
            dcache_hit_i_q <=  1'b0;
        end else begin
            
            if (csr_lecture_cycle != csr_cycle_q)
                $display("[cycle %0d] csr_lecture_cycle -> %0b \n" , nb_cycle, csr_lecture_cycle);
            if (charge_o != charge_q)
                $display("[cycle %0d] charge_o -> %0d", nb_cycle, charge_o);

            
            /*
            if (csr_lecture_q != csr_lecture)
                $display("[cycle %0d] csr_lecture -> %0d", nb_cycle, csr_lecture);

            if (lecture_csr_i_q != lecture_csr_i)
                $display("[cycle %0d] lecture_csr_i_q -> %0d", nb_cycle, lecture_csr_i);


            if (dcache_hit_c != dcache_hit_q)
                $display("[cycle %0d] dcache_hit_cnt -> %0d", nb_cycle, dcache_hit_q);

            if (hit_en != hit_en_q)
                $display("[cycle %0d] hit_en -> %0b \n ", nb_cycle, hit_en);

            if (load_commit_i != load_commit_q)
                $display("[cycle %0d] load_commit_i -> %0b \n", nb_cycle, load_commit_i);

            if (load_commit_i && load_invalid_i )
                $display("[cycle %0d] erreur load valid et invalid !\n", nb_cycle);

     
            if (charge_d != charge_q)
                $display("[cycle %0d] charge_q=%0d charge_d=%0d charge_o=%0d",
                        nb_cycle, charge_q, charge_d, charge_o);
            if (nombre_hit_q != nombre_hit || nombre_hit== MAX_HIT)
                $display("[cycle %0d] nombre_hit -> %0d", nb_cycle, nombre_hit);
            
            if (hit_enable_q != hit_enable )
                $display("[cycle %0d] hit_enable -> %0d", nb_cycle, hit_enable);
            if (dcache_hit_i_q != dcache_hit_i)
                $display("[cycle %0d] dcache_hit_i -> %0d", nb_cycle, dcache_hit_i);
            */
            dcache_hit_i_q <= dcache_hit_i; 
            hit_enable_q <= hit_enable; 
            hit_en_q <= hit_en;
            csr_cycle_q <= csr_lecture_cycle;
            dcache_hit_c <= dcache_hit_q;
            load_commit_q <= load_commit_i;
            csr_lecture_q <= csr_lecture;
            lecture_csr_i_q <= lecture_csr_i;
            nombre_hit_q <= nombre_hit; 
            nb_cycle <= nb_cycle + 1;

        end
    end
endmodule 
