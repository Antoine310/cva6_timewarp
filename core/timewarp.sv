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
    parameter int LECTURE_TIME = 5000,    // Delais Lecture présent, HIT_TIME > 0 
    parameter int CHARGE_TIME = 5000, // temps ajouter au compteur de la charge 
    parameter int MAX_HIT = 20000,
    parameter int TAILLETAB = 128 // Taille des tableaux hit et miss


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
    output logic [63:0] charge_o,
    //latence load retour
    input logic [63:0] latence_load_i,
    //Retour d'un load du cache
    input logic nouvelle_valeur_i,
    //miss dcache
    input logic dcache_miss_i
);
    logic [$clog2(LECTURE_TIME+1)-1:0] compteur_lecture;
    logic [63:0] compteur_coherence_temps;

    logic hit_en ;
    logic [4:0] dcache_hit_q;

    logic [63:0] charge_q, charge_d;    
    logic reset_charge;
    logic csr_lecture;

    logic hit_enable;
    logic deblocage_lecture;

    logic [63:0] delta_MissHit;
    logic [63:0] cumul_charge;

    always_comb begin : charge
        charge_d = charge_q; // On recupere la charge en cours 
        // Si lecture csr et hit, on crée une offuscation en rajoutant une charge +10 qu'on envoie au csr_regfile.
        if (csr_lecture && cumul_charge > 0 ) begin 
            charge_d = cumul_charge;       
        end else if (reset_charge) begin 
            charge_d = '0;
        end

    end 
    int nb_cycle;

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
            hit_enable <= 1'b0;
            deblocage_lecture <= 1'b0;  
            cumul_charge  <= '0;
        end else begin 

            if(nouvelle_valeur_i) begin
                //$display( "[cycle %0d ] [Latence timewarp] =%0d ",nb_cycle,latence_load_i);
            end 
            if (csr_lecture_cycle)begin
                hit_enable <= 1'b1;
                deblocage_lecture <= 1'b1;
            end 

            if ((dcache_hit_q>0) && load_commit_i && hit_enable ) begin
                cumul_charge <= cumul_charge + delta_MissHit ; 
            end  
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
                if (compteur_lecture == 1) begin
                    cumul_charge <= '0;
                    hit_enable <= 1'b0; 
                    hit_en <= 1'b0; 
                    //$display("[cycle %0d] END compteur_lecture timer ",
         //nb_cycle);
                end
            end 

            reset_charge <= 1'b0;
            // A partir du commit de la lecture csr, on demarre le timer pendant au minimum de charge cycle + une valeur possible, 
            //si on fait moins on pourrait avoir une incoherence du temps
            if (cumul_charge>0 && deblocage_lecture) begin 
                compteur_coherence_temps <=  64'(CHARGE_TIME) +  charge_d;
                compteur_lecture <= '0;
                /*$display("[cycle %0d] START coherence_timer hits=%0d charge=%0d total=%0d",
                    nb_cycle,
                    nombre_hit,
                    charge_d,
                     32'(CHARGE_TIME) + charge_d);*/
            end else if (deblocage_lecture && compteur_coherence_temps > 0) begin // Lecture donc relance du timer si timer déja lancer et commit csr sans hit load 
                compteur_coherence_temps <=  64'(CHARGE_TIME) + charge_d;
                compteur_lecture <= '0;
                //$display("[cycle %0d] Relance la charge timer ! charge_q=%0d charge_d=%0d ", nb_cycle, charge_q , charge_d) ;
            end else if (compteur_coherence_temps !=  0) begin
                compteur_coherence_temps <= compteur_coherence_temps - 1 ; 
                if (compteur_coherence_temps == 1) begin
                    reset_charge <= 1'b1; 
                    cumul_charge <= '0;
                    hit_enable <= 1'b0; 
                    hit_en <= 1'b0; 
                    //$display("[cycle %0d] END coherence_timer",
         //nb_cycle);
                end
            end 
            nb_cycle <= nb_cycle + 1 ; 
        end  
            
    end

    logic [63:0] tab_hit [TAILLETAB-1:0]; 
    logic [63:0] tab_miss [TAILLETAB-1:0]; 
    logic [$clog2(TAILLETAB)-1:0] miss_idx;
    logic [$clog2(TAILLETAB)-1:0] hit_idx;
    logic [4:0] wait_hit_q;
    logic [4:0] wait_miss_q;
    logic [63:0] cumul_hit;
    logic [63:0] cumul_miss;
    logic [63:0] moyenne_hit;
    logic [63:0] moyenne_miss;
    logic [$clog2(TAILLETAB+1)-1:0] nb_hit;
    logic [$clog2(TAILLETAB+1)-1:0] nb_miss;

    // Calcul moyenne et delta 
    always_comb begin : moyenne

        moyenne_hit  = (nb_hit  != 0) ? (cumul_hit  / 64'(nb_hit))  : '0;
        moyenne_miss = (nb_miss != 0) ? (cumul_miss / 64'(nb_miss)) : '0;

        delta_MissHit = (nb_hit != 0 && nb_miss != 0 && moyenne_miss > moyenne_hit) ? moyenne_miss - moyenne_hit : 4;    
        //(nb_hit >= TAILLETAB && nb_miss >= TAILLETAB)
    end


    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            miss_idx <= '0;
            hit_idx <= '0;
            wait_hit_q  <= '0;
            wait_miss_q <= '0;
            cumul_hit <= '0;
            cumul_miss <= '0; 
            nb_hit  <= '0;
            nb_miss <= '0;
            for (int i = 0; i < TAILLETAB; i++) begin
                tab_hit[i]  <= '0;
                tab_miss[i] <= '0;
            end 
        end else begin 
            // Si retour du cache, on regarde ce que c'est, le miss a la priorité sur le hit.
            // Pour le miss et le hit, on ajoute la valeur a leur cumul qui compte le temps total de tout le tableau
            // et on retire a ce cumul la valeur qu'on enleve du tableau.
            // Le miss et le Hit on a compteur en vol pour attendre l'arriver des informations de latence.
            if (nouvelle_valeur_i) begin
                /*
                if ((wait_hit_q>0) && (wait_miss_q>0)) begin 
                    $display("[cycle %0d] Bug probleme 1 :d", nb_cycle);
                    wait_hit_q  <= '0;
                    wait_miss_q <= '0;
                end else */ 
                if ((wait_miss_q>0)) begin
                    if (cumul_charge>0) begin 
                    $display("\n==============================");
                    $display("[cycle %0d] UPDATE TABLEAUX", nb_cycle);

                    $display("MISS : ");
                    for (int i = 0; i < TAILLETAB; i++) begin
                        $display("%0d ", tab_miss[i]);
                    end
                    $display("");

                    $display("nb_hit      = %0d", nb_hit);
                    $display("nb_miss     = %0d", nb_miss);

                    $display("cumul_hit   = %0d", cumul_hit);
                    $display("cumul_miss  = %0d", cumul_miss);

                    $display("moyenne_hit = %0d", moyenne_hit);
                    $display("moyenne_miss= %0d", moyenne_miss);

                    $display("delta       = %0d", delta_MissHit);
                    $display("cumul_charge       = %0d", cumul_charge);
                    $display("miss_idx       = %0d", miss_idx);
                    $display("==============================\n");
                    end 
                    cumul_miss <= cumul_miss + latence_load_i - tab_miss[miss_idx]; 

                    tab_miss[miss_idx] <= latence_load_i;
                    if (nb_miss <  TAILLETAB) begin 
                        nb_miss <= nb_miss + 1'b1;
                    end
                    miss_idx <= miss_idx + 1'b1;
                    if (dcache_miss_i<1) begin
                        wait_miss_q <= wait_miss_q - 1; 
                    end 
                    
                    wait_hit_q  <= wait_hit_q  + 5'(dcache_hit_i);

                end else if ((wait_hit_q>0)) begin
                    if (cumul_charge>0) begin 
                    $display("\n==============================");
                    $display("[cycle %0d] UPDATE TABLEAUX", nb_cycle);

                    $display("HIT  : ");
                    for (int i = 0; i < TAILLETAB; i++) begin
                        $display("%0d ", tab_hit[i]);
                    end
                    $display("");

                    $display("nb_hit      = %0d", nb_hit);
                    $display("nb_miss     = %0d", nb_miss);

                    $display("cumul_hit   = %0d", cumul_hit);
                    $display("cumul_miss  = %0d", cumul_miss);

                    $display("moyenne_hit = %0d", moyenne_hit);
                    $display("moyenne_miss= %0d", moyenne_miss);

                    $display("delta       = %0d", delta_MissHit);
                    $display("cumul_charge       = %0d", cumul_charge);
                    $display("hit_idx       = %0d", hit_idx);
                    $display("==============================\n");
                    end 
                    cumul_hit <= cumul_hit + latence_load_i - tab_hit[hit_idx]; 

                    tab_hit[hit_idx] <= latence_load_i;
                    if (nb_hit <  TAILLETAB) begin 
                        nb_hit <= nb_hit + 1'b1;
                    end
                    hit_idx <= hit_idx + 1'b1;
                    if (dcache_hit_i<1) begin
                        wait_hit_q <= wait_hit_q - 1; 
                    end 
                    
                    wait_miss_q <= wait_miss_q + 5'(dcache_miss_i);

                end else begin
                    //$display("[cycle %0d] Bug probleme 2 :d", nb_cycle);
                    wait_hit_q  <= wait_hit_q  + 5'(dcache_hit_i);
                    wait_miss_q <= wait_miss_q + 5'(dcache_miss_i);
                end 
            end else begin
                wait_hit_q  <= wait_hit_q  + 5'(dcache_hit_i);
                wait_miss_q <= wait_miss_q + 5'(dcache_miss_i);
            end
        end
    end
    logic hit_en_q;
    logic csr_cycle_q;
    logic [4:0] dcache_hit_c;    
    logic load_commit_q;
    logic lecture_csr_i_q;
    logic csr_lecture_q;
    logic [63:0] cumul_charge_q;
    logic hit_enable_q;
    logic dcache_hit_i_q;
    logic dcache_miss_i_q;
    logic [4:0] wait_hit_q_b;
    logic [4:0] wait_miss_q_b;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            hit_en_q      <= 1'b0;
            dcache_hit_c  <= '0;
            csr_cycle_q   <= 1'b0;
            csr_lecture_q <= 1'b0;
            lecture_csr_i_q <= 1'b0;
            cumul_charge_q <= '0;
            hit_enable_q <= 1'b0;
            dcache_hit_i_q <=  1'b0;
        end else begin
            if (dcache_hit_i_q != dcache_hit_i)
                $display("[cycle %0d] dcache_hit_i -> %0d", nb_cycle, dcache_hit_i);
            if (dcache_miss_i != dcache_miss_i_q)
                $display("[cycle %0d] dcache_miss_i -> %0d", nb_cycle, dcache_miss_i);
            if (csr_cycle_q != csr_lecture_cycle)
                $display("[cycle %0d] csr_lecture_cycle -> %0d", nb_cycle, csr_lecture_cycle);
            if (dcache_miss_i_q && dcache_hit_i)
                $display("[cycle %0d] Hmmm probleme", nb_cycle);
            if (wait_hit_q_b != wait_hit_q)
                $display("[cycle %0d] wait_hit_q -> %0d", nb_cycle, wait_hit_q);
            if (wait_miss_q_b != wait_miss_q)
                $display("[cycle %0d] wait_miss_q -> %0d", nb_cycle, wait_miss_q);
            
            if (charge_o != charge_q)
                $display("[cycle %0d] charge_o -> %0d", nb_cycle, charge_o);

            if (charge_d != charge_q)
                $display("[cycle %0d] charge_q=%0d charge_d=%0d charge_o=%0d",
                        nb_cycle, charge_q, charge_d, charge_o);

            if (cumul_charge_q != cumul_charge )
                $display("[cycle %0d]  cumul_charge -> %0d", nb_cycle, cumul_charge);
            
            if (hit_enable_q != hit_enable )
                $display("[cycle %0d] hit_enable -> %0d", nb_cycle, hit_enable);

            
            wait_hit_q_b <= wait_hit_q;
            wait_miss_q_b <= wait_miss_q;
            dcache_hit_i_q <= dcache_hit_i; 
            hit_enable_q <= hit_enable; 
            hit_en_q <= hit_en;
            csr_cycle_q <= csr_lecture_cycle;
            dcache_hit_c <= dcache_hit_q;
            load_commit_q <= load_commit_i;
            csr_lecture_q <= csr_lecture;
            lecture_csr_i_q <= lecture_csr_i;
            cumul_charge_q <= cumul_charge; 
            dcache_miss_i_q <= dcache_miss_i;
        end
    end
endmodule 
