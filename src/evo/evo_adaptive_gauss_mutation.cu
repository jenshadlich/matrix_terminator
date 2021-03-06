/*
 * Copyright (c) 2011, 2012 Tobias Kalbitz <tobias.kalbitz@googlemail.com>
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the GNU Public License v2.0
 * which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#include <cuda.h>
#include <math.h>

#if __CUDA_ARCH__ >= 200
	#define DIV(x,y) __ddiv_rn((x),(y))
#else
	#define DIV(x,y) ((x)/(y))
#endif

__device__ static double evo_mut_new_value(struct instance * const inst,
					   curandState     * const rnd_state)
{
	/* we want to begin with small numbers */
	const int tmp = (inst->parent_max > 10) ? 10 : (int)inst->parent_max;

	const int rnd_val = (curand(rnd_state) % (tmp - 1)) + 1;
	int factor = (int)(rnd_val / inst->delta);
	if((factor * inst->delta) < 1.0)
		factor++;

	if(factor * inst->delta < 1.0)
		return 1;

	return factor * inst->delta;
}

__device__ void evo_ensure_constraints(struct instance * const inst,
				       struct memory   * const mem,
				       curandState     * const rnd_state)
{
	double* const row   = C_ROW(0);
	double* const lrow  = C_ROW(inst->dim.matrix_height-1);

	const int end = mem->c_end;

	for(int start = mem->c_zero; start < end; start += inst->dim.matrix_width) {
		const int lidx = start + inst->dim.matrix_width - 1;

		if(inst->cond_left == COND_UPPER_LEFT) {
			if(row[start] < 1.0)
				row[start] = evo_mut_new_value(inst, rnd_state);
		} else if(inst->cond_left == COND_UPPER_RIGHT) {
			if(row[lidx] < 1.0)
				row[lidx] = evo_mut_new_value(inst, rnd_state);
		} else if(inst->cond_left == COND_UPPER_LEFT_LOWER_RIGHT) {
			if(row[start] < 1.0)
				row[start] = evo_mut_new_value(inst, rnd_state);

			if(lrow[lidx] < 1.0)
				lrow[lidx] = evo_mut_new_value(inst, rnd_state);
		} else {
			/*
			 * This should be recognized ;) It's only a 1.3 card
			 *  so there is no printf :/
			 */
			for(int i = 0; i < inst->dim.matrix_width; i++) {
				row[start + i] = 1337;
				lrow[start + i] = 1337;
			}
		}
	}
}

__device__ void evo_mutation(struct instance * const inst,
			     struct memory   * const mem,
			     curandState     * const rnd_s)
{
	const int rows = inst->dim.matrix_height;
	const double delta = inst->delta;
	const uint32_t elems = inst->dim.matrix_width  *
			       inst->dim.matrix_height *
			       inst->num_matrices;

	const int parent = curand(rnd_s) % inst->dim.parents;

	MR(tx) = PMR(parent);
	SP(tx) = PSP(parent);

	SP(tx) *= __expf((1 / __fsqrt_rn(elems)) * curand_normal(rnd_s));
	SP(tx) = min(max(SP(tx), 2*delta), inst->parent_max);

	MR(tx) = MR(tx) + DIV(curand_normal(rnd_s), 20);
	MR(tx) = min(max(MR(tx), 1./elems), 1.);

	const double mr = MR(tx);
	const double sp = SP(tx);
	double tmp;

	#pragma unroll
	for(int r = 0; r < rows; r++) {
		double* const c_row = C_ROW(r);
		double* const p_row = P_ROW(r);

		for(int c = mem->c_zero, p = parent * inst->width_per_inst; c < mem->c_end; c++, p++) {

			if(curand_uniform(rnd_s) > mr) {
				if(curand_uniform(rnd_s) < DIV(mr, 10)) {
					c_row[c] = 0.;
				} if(curand_uniform(rnd_s) < DIV(mr, 10)) {
					c_row[c] = evo_mut_new_value(inst, rnd_s);
				} else {
					c_row[c] = p_row[p];
				}
				continue;
			}

			tmp = (double)(curand_normal(rnd_s) * sp);
			tmp = __dmul_rn((tmp < 0 ? -1 : 1), max(delta, fabs(tmp)));
			tmp = __dadd_rn(p_row[p], tmp);
			/* we want x * delta, where x is an int */
			tmp = __dmul_rn((__double2uint_rn(DIV(tmp, delta))), delta);
			tmp = max(tmp, 0.0);
			tmp = min(inst->parent_max, tmp);

			c_row[c] = tmp;
		}
	}

	__syncthreads();
	evo_ensure_constraints(inst, mem, rnd_s);
}
