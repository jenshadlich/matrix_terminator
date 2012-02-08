/*
 * pso_setup.cu
 *
 *  Created on: Sep 28, 2011
 *      Author: tkalbitz
 */

#include <float.h>

#include "c_config.h"
#include "c_setup.h"

/* calculate the thread id for the current block topology */
__device__ inline int get_thread_id() {
	const int uniqueBlockIndex = blockIdx.y * gridDim.x + blockIdx.x;
	const int uniqueThreadIndex =
			uniqueBlockIndex * blockDim.y * blockDim.x +
			threadIdx.y * blockDim.x + threadIdx.x;
	return uniqueThreadIndex;
}

/* calculate the thread id for the current block topology */
__device__ inline int get_max_thread_id() {
	const int uniqueBlockIndex =
			(gridDim.y - 1) * gridDim.x + (gridDim.x - 1);
	const int uniqueThreadIndex =
			uniqueBlockIndex * blockDim.y * blockDim.x +
			(blockDim.y - 1) * blockDim.x + (blockDim.x - 1);
	return uniqueThreadIndex;
}

__device__ static double new_value(struct c_instance& inst,
					   curandState* const rnd_state)
{
	/* we want to begin with small numbers */
	const int tmp = (inst.parent_max > 10) ? 10 : (int)inst.parent_max;
	const int rnd_val = (curand(rnd_state) % (tmp - 1)) + 1;
	int factor = (int)(rnd_val / inst.delta);
	if((factor * inst.delta) < 1.0)
		factor++;

	const double val = factor * inst.delta;
	if(val < 1.0)
		return 1.0;

	return val;
}

__global__ void setup_c_rnd_kernel(struct c_instance inst,
				   const int seed)
{
	const int end = inst.scount * BLOCKS;
	for(int i = tx; i < end; i+= blockDim.x)
		curand_init(seed + i, i, 0, &(inst.rnd_states[i]));
}

__global__ void
setup_instances_kernel(struct c_instance inst)
{
	const int id = get_thread_id();
	const int max_id = get_max_thread_id();
	curandState rnd = inst.rnd_states[id];

	const int max1 = (int)inst.parent_max;
	const double delta = inst.delta;
	int x;
	double tmp;


	for(x = id; x < inst.itotal; x += max_id) {
		tmp = curand(&rnd) % max1;
		tmp = __dmul_rn(__double2uint_rn(tmp / delta), delta);
		inst.instances[x] = tmp;
	}

	__syncthreads();

	const int matrices = inst.num_matrices * inst.icount * BLOCKS;

	if(inst.cond_left == COND_UPPER_LEFT) {
		for(x = id; x < matrices; x += max_id) {
			const int matrix = x * inst.width_per_matrix;
                        inst.instances[matrix] = new_value(inst, &rnd);
		}
	} else if(inst.cond_left == COND_UPPER_RIGHT) {
		for(x = id; x < matrices; x += max_id) {
			const int matrix = x * inst.width_per_matrix +
					inst.mdim - 1;
                        inst.instances[matrix] = new_value(inst, &rnd);
		}
	} else if(inst.cond_left == COND_UPPER_LEFT_LOWER_RIGHT) {
		for(x = id; x < matrices; x += max_id) {
			const int matrix1 = x * inst.width_per_matrix;
			const int matrix2 = (x + 1) * inst.width_per_matrix - 1;
                        inst.instances[matrix1] = new_value(inst, &rnd);
                        inst.instances[matrix2] = new_value(inst, &rnd);
		}
	}
	inst.rnd_states[id] = rnd;
}