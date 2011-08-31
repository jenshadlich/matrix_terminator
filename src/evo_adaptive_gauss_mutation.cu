#include <cuda.h>
#include <math.h>

__device__ static double evo_mut_new_value(struct instance * const inst,
					   curandState     * const rnd_state)
{
	const int rnd_val = (curand(rnd_state) % ((int)inst->parent_max - 1)) + 1;
	int factor = (int)(rnd_val / inst->delta);
	if((factor * inst->delta) < 1.0)
		factor++;

	if(factor * inst->delta < 1.)
		return 1;

	return factor * inst->delta;
}

__device__ void evo_ensure_constraints(struct instance * const inst,
				       struct memory   * const mem,
				       curandState     * const rnd_state)
{
	double* const row   = C_ROW(0);
	double* const lrow  = C_ROW(MATRIX_HEIGHT-1);

	const int end = mem->c_end;

	for(int start = mem->c_zero; start < end; start += MATRIX_WIDTH) {
		const int lidx = start + inst->dim.matrix_width - 1;

		if(inst->cond_left == COND_UPPER_LEFT && row[start] < 1.0) {
			row[start] = evo_mut_new_value(inst, rnd_state);
		} else if(inst->cond_left == COND_UPPER_RIGHT && row[lidx] < 1.0) {
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
			for(int i = 0; i < MATRIX_WIDTH; i++) {
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
	const int rows = MATRIX_HEIGHT;
	const double delta = inst->delta;
	const uint32_t elems = MATRIX_WIDTH*MATRIX_HEIGHT*inst->num_matrices;
	double tmp;

	SP(tx) = SP(tx) * exp(curand_normal(rnd_s) /
				     sqrtf(inst->num_matrices * MATRIX_HEIGHT));
	SP(tx) = min(max(SP(tx), 2*delta), inst->parent_max);

	MR(tx) = MR(tx) + (curand_normal(rnd_s) / 20);
	MR(tx) = min(max(MR(tx), 1./elems), 1.);

	const double mr = MR(tx);
	const double sp = SP(tx);

	#pragma unroll
	for(int r = 0; r < rows; r++) {
		double* const row = C_ROW(r);

		for(int c = mem->c_zero; c < mem->c_end; c++) {

			if(curand_uniform(rnd_s) > mr) {
				if(curand_uniform(rnd_s) < mr)
					row[c] = 0.;
				continue;
			}

			tmp = (double)(curand_normal(rnd_s) * sp);
			tmp = row[c] + tmp;
			/* we want x * delta, where x is an int */
			tmp = ((unsigned long)(tmp / delta)) * delta;
			tmp = max(tmp, 0.0);
			tmp = min(inst->parent_max, tmp);

			row[c] = tmp;
		}
	}

	evo_ensure_constraints(inst, mem, rnd_s);
}
