/*
 * evo_setup.cu
 *
 *  Created on: Jun 24, 2011
 *      Author: tkalbitz
 */

#include "evo_setup.h"
#include "evo_memory.cu"

__global__ void setup_rnd_kernel(curandState* const rnd_states,
				 const int seed)
{
	const int id = get_thread_id();

	/*
         * Each thread get the same seed,
         * a different sequence number and no offset.
         */
	curand_init(seed, id, 0, &rnd_states[id]);
}

__device__ static double evo_mut_new_value(struct instance * const inst,
					   curandState     * const rnd_state)
{
	const int rnd_val = (curand(rnd_state) % ((int)inst->parent_max - 1)) + 1;
	int factor = (int)(rnd_val / inst->delta);
	if((factor * inst->delta) < 1.0)
		factor++;

	return factor * inst->delta;
}

/*
 * Initialize the parent memory with random values.
 */
__global__ void setup_parent_kernel(struct instance * const inst)
{
	if(threadIdx.x >= inst->dim.matrix_height)
		return;

	const int id = get_thread_id();
	curandState rnd = inst->rnd_states[id];

	char* const devPtr = (char*)inst->dev_parent.ptr;
	const size_t pitch = inst->dev_parent.pitch;
	const size_t slicePitch = pitch * inst->dim.matrix_height;
	char* const slice = devPtr + blockIdx.x * slicePitch;
	double* row = (double*) (slice + threadIdx.x * pitch);

	for(int x = 0; x < inst->dim.parents * inst->width_per_inst; x++) {
		if(curand_uniform(&rnd) < MATRIX_TAKEN_POS) {
			row[x] = curand(&rnd) % (int)inst->parent_max;
		} else {
			row[x] = 0;
		}
	}

	inst->rnd_states[id] = rnd;

	if(threadIdx.x != 0)
		return;

	const int matrices = inst->num_matrices * inst->dim.parents;
	int y;

	if(inst->cond_left == COND_UPPER_LEFT) {
		y = 0;
		row = (double*) (slice + y * pitch);

		for(int i = 0; i < matrices; i++) {
			row[i * MATRIX_WIDTH] = evo_mut_new_value(inst, &rnd);
		}
	} else if(inst->cond_left == COND_UPPER_RIGHT) {
		y = 0;
		row = (double*) (slice + y * pitch);

		for(int i = 0; i < matrices; i++) {
			int idx = i * MATRIX_WIDTH + (MATRIX_WIDTH - 1);
			row[idx] = evo_mut_new_value(inst, &rnd);
		}
	} else if(inst->cond_left == COND_UPPER_LEFT_LOWER_RIGHT) {
		y = 0;
		row = (double*) (slice + y * pitch);
		for(int i = 0; i < matrices; i++) {
			row[i * MATRIX_WIDTH] = evo_mut_new_value(inst, &rnd);
		}

		y = (inst->dim.matrix_height - 1);
		row = (double*) (slice + y * pitch);
		for(int i = 0; i < matrices; i++) {
			int idx = i * MATRIX_WIDTH + (MATRIX_WIDTH - 1);
			row[idx] = evo_mut_new_value(inst, &rnd);
		}
	}

	inst->rnd_states[id] = rnd;
}

__global__ void setup_sparam(struct instance * const inst)
{
	struct memory mem;
	evo_init_mem(inst, &mem);
	mem.sparam[tx] = inst->def_sparam;

	if(tx < PARENTS)
		mem.psparam[tx] = inst->def_sparam;
}