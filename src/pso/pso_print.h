/*
 * pso_print.h
 *
 *  Created on: Oct 17, 2011
 *      Author: tkalbitz
 */

#ifndef PSO_PRINT_H_
#define PSO_PRINT_H_

#include "pso_instance.h"

void print_global_matrix_pretty(FILE* f, struct pso_instance* inst, int block);
void print_particle_ratings(struct pso_instance *inst);
void print_particle_matrix_pretty(FILE* f, struct pso_instance* inst,
				 int block, int particle);
void print_lbest_particle_matrix_pretty(FILE* f, struct pso_instance* inst,
				        int block, int particle);
void print_gbest_particle_ratings(struct pso_instance *inst);
void print_rules(FILE* f, struct pso_instance *inst);

#endif /* PSO_PRINT_H_ */
