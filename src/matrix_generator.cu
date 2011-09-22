/*
 * matrix_generator.c
 *
 *  Created on: Sep 22, 2011
 *      Author: tkalbitz
 */

extern "C"
{
#include "matrix_generator.h"
}

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <assert.h>
#include <ctype.h>
#include <errno.h>

#include <sys/wait.h>

#include <cuda.h>
#include <curand_kernel.h>

#include "instance.h"

#include "evo.h"
#include "evo_rating.h"
#include "evo_setup.h"

#include "matrix_print.h"
#include "matrix_copy.h"
#include "ya_malloc.h"
#include "plot_log.h"

#define INFO_LEN 16

struct evo_info_t {
	char is_initialized;
	struct instance inst;
	struct instance *dev_inst;

	double mut_rate;
	double recomb_rate;
	double sparam;
};

static struct evo_info_t evo_info[INFO_LEN];
static int max_init_instances;

void evo_init()
{
	max_init_instances = 0;
	for(int i = 0; i < INFO_LEN; i++) {
		evo_info[i].is_initialized = 0;
	}
}

static int evo_get_rules_count(const int * const rules,
			       const size_t      rules_len)
{
	uint8_t tmp = 0;
	int rules_count = 0;
	for(size_t i = 0; i < rules_len; i++) {
		if(rules[i] == MUL_SEP) {
			tmp = (tmp + 1) % 2;
			if(!tmp) {
				rules_count++;
			}
		}
	}

	if(rules[rules_len - 1] != MUL_SEP || tmp != 1)
		return E_RULES_FORMAT_WRONG;

	return rules_count;
}

int evo_init_instance(const int         matrix_width,
		      const int * const rules,
		      const size_t      rules_len)
{
	int free_inst = -1;
	for(int i = 0; i < INFO_LEN; i++) {
		if(evo_info[i].is_initialized == 0) {
			free_inst = i;
			break;
		}
	}

	if(free_inst == -1) {
		return E_NO_FREE_INST;
	}


	evo_info[free_inst].mut_rate    = MUT_RATE;
	evo_info[free_inst].recomb_rate = RECOMB_RATE;
	evo_info[free_inst].sparam      = SPARAM;
	struct instance* inst = &evo_info[free_inst].inst;

	inst->match       = MATCH_ANY;
	inst->cond_left   = COND_UPPER_LEFT_LOWER_RIGHT;
	inst->cond_right  = COND_UPPER_RIGHT;
	inst->delta       = 0.1;
	inst->parent_max  = 10;
	inst->rules_len   = rules_len;
	inst->rules       = (int*)ya_malloc(sizeof(int) * rules_len);
	memcpy(inst->rules, rules, sizeof(int) * rules_len);

	int rules_count = evo_get_rules_count(rules, rules_len);
	if(rules_count < 0)
		return rules_count;
	inst->rules_count = rules_count;

	inst_init(inst, matrix_width);
	max_init_instances++;
	return free_inst;
}

static void copy_result_to_buffer(struct instance* inst,
				  int block, int parent,
				  double* buffer)
{
	int width = inst->dim.parents    * /* there are n parents per block */
		    inst->width_per_inst *
		    sizeof(double) *
		    inst->dim.matrix_height * inst->dim.blocks;

	double* parent_cpy = (double*)ya_malloc(width);
	memset(parent_cpy, 1, width);
	copy_parents_dev_to_host(inst, parent_cpy);

	int line = inst->dim.parents *  inst->width_per_inst;
	int block_offset = line * inst->dim.matrix_height;
	double* block_ptr = parent_cpy + block_offset * block;

	double* to;
	double* from;

	for(int i = 0; i < inst->dim.matrix_height; i++) {
		to   = buffer     + i * inst->width_per_inst;
		from = block_ptr + (i * line);
		memcpy(to, from, inst->width_per_inst * sizeof(double));
	}

	free(parent_cpy);
}

int evo_run(const int     instance,
	    const int     cycles,
	    double* const result)
{

	if(instance < 0 || instance >= max_init_instances) {
		return E_INVALID_INST;
	}

	struct instance *inst = &evo_info[instance].inst;
	struct instance *dev_inst;
	int *dev_rules;

	dev_inst = inst_create_dev_inst(inst, &dev_rules);
	int evo_threads = get_evo_threads(inst);

	const dim3 blocks(BLOCKS, PARENTS*CHILDS);
	const dim3 threads(inst->dim.matrix_width, inst->dim.matrix_height);
	const dim3 copy_threads(inst->dim.matrix_width, inst->dim.matrix_height);
	const dim3 setup_threads(inst->dim.matrix_width * inst->dim.matrix_height);

	setup_childs_kernel<<<BLOCKS, setup_threads>>>(dev_inst, false);
	CUDA_CALL(cudaGetLastError());
	cudaThreadSynchronize();
	CUDA_CALL(cudaGetLastError());

	setup_sparam<<<BLOCKS, evo_threads>>>(dev_inst,
			evo_info[instance].sparam, evo_info[instance].mut_rate,
			evo_info[instance].recomb_rate, false);
	CUDA_CALL(cudaGetLastError());
	cudaThreadSynchronize();
	CUDA_CALL(cudaGetLastError());

	// Prepare
	cudaEvent_t start, stop;
	float elapsedTime;
	float elapsedTimeTotal = 0.f;

	const int width = inst->dim.parents * inst->dim.blocks;
	double * const rating = (double*)ya_malloc(width * sizeof(double));
	int rounds = cycles + 1;
	int block = 0; int thread = 0;

	evo_calc_res<<<blocks, threads>>>(dev_inst);
	CUDA_CALL(cudaGetLastError());
	cudaThreadSynchronize();
	CUDA_CALL(cudaGetLastError());

	evo_kernel_part_two<<<BLOCKS, copy_threads>>>(dev_inst);
	CUDA_CALL(cudaGetLastError());
	cudaThreadSynchronize();
	CUDA_CALL(cudaGetLastError());

	for(int i = 0; i < cycles; i++) {
		if(i % 300 == 0) {
			setup_childs_kernel<<<BLOCKS, setup_threads>>>(dev_inst, true);
			CUDA_CALL(cudaGetLastError());
			evo_calc_res<<<blocks, threads>>>(dev_inst);
			CUDA_CALL(cudaGetLastError());
			evo_kernel_part_two<<<BLOCKS, copy_threads>>>(dev_inst);
			CUDA_CALL(cudaGetLastError());
			setup_sparam<<<BLOCKS, evo_threads>>>(dev_inst,
					evo_info[instance].sparam,
					evo_info[instance].mut_rate,
					evo_info[instance].recomb_rate, true);
			CUDA_CALL(cudaGetLastError());
		}

		cudaEventCreate(&start);
		cudaEventCreate(&stop);
		// Start record
		cudaEventRecord(start, 0);

		evo_kernel_part_one<<<BLOCKS, evo_threads>>>(dev_inst);
		CUDA_CALL(cudaGetLastError());
		cudaThreadSynchronize();
		CUDA_CALL(cudaGetLastError());

		evo_calc_res<<<blocks, threads>>>(dev_inst);
		CUDA_CALL(cudaGetLastError());
		cudaThreadSynchronize();
		CUDA_CALL(cudaGetLastError());

		evo_kernel_part_two<<<BLOCKS, copy_threads>>>(dev_inst);
		CUDA_CALL(cudaGetLastError());
		cudaThreadSynchronize();
		CUDA_CALL(cudaGetLastError());

		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		cudaEventElapsedTime(&elapsedTime, start, stop); // that's our time!
		elapsedTimeTotal += elapsedTime;
		// Clean up:
		cudaEventDestroy(start);
		cudaEventDestroy(stop);

		copy_parent_rating_dev_to_host(inst, rating);

		for(int j = 0; j < width; j += PARENTS) {
			if(rating[j] == 0.) {
				block = j / PARENTS;
				thread = j % PARENTS;
				rounds = i;
				i = cycles;
				break;
			}
		}
	}

	free(rating);
	copy_result_to_buffer(inst, block, thread, result);

	cudaFree(dev_inst);
	cudaFree(dev_rules);
	return rounds;
}

int evo_destroy_instance(int instance)
{
	if(instance < 0 || instance >= max_init_instances) {
		return E_INVALID_INST;
	}

	evo_info[instance].is_initialized = 0;

	inst_cleanup(&evo_info[instance].inst, NULL);
	free(evo_info[instance].inst.rules);
	max_init_instances--;

	return 0;
}
