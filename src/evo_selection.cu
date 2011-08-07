/*
 * evo_selection.cu
 *
 *  Created on: Jun 24, 2011
 *      Author: tkalbitz
 */

__device__ void evo_parent_selection_best(struct instance * const inst,
					  struct memory   * const mem)
{
	if(ty != 0)
		return;

	__shared__ struct double2 res[PARENTS * CHILDS];
	double2* const arr   = (double2*)mem->c_rat;

	for(int i = tx; i < PARENTS * CHILDS; i += MATRIX_WIDTH) {
		res[i]   = arr[i];
	}

	__syncthreads();

	if(tx == 0) {
		double2 key;

		/* insertion sort */
		for(int i = 1; i < PARENTS * CHILDS; i++) {
			key = res[i];

			int j = i - 1;
			while(j >=0 && res[j].x > key.x) {
				res[j + 1] = res[j];
				j = j - 1;
			}
			res[j + 1] = key;
		}
	}

	__syncthreads();

	for(int i = tx; i < PARENTS * CHILDS; i += MATRIX_WIDTH) {
		arr[i] = res[i];
	}
}

__device__ void evo_parent_selection_turnier(struct instance * const inst,
		                             struct memory   * const mem,
					     curandState* rnd_state,
					     const uint8_t q)
{
	if(threadIdx.y != 0 || threadIdx.x >= PARENTS)
		return;

	__shared__ struct double2 src[PARENTS * CHILDS];
	__shared__ struct double2 dest[PARENTS * CHILDS];
	double2* const arr = (double2*)mem->c_rat;

	for(int i = tx; i < PARENTS * CHILDS; i += MATRIX_WIDTH) {
		src[i]   = arr[i];
	}

	uint32_t idx = curand(rnd_state) % (PARENTS * CHILDS);

	for(int pos = tx; pos < PARENTS; pos += MATRIX_WIDTH) {
		for(uint8_t t = 0; t < q; t++) {
			uint32_t opponent = curand(rnd_state) % (PARENTS * CHILDS);

			if(src[opponent].x < src[idx].x)
				idx = opponent;
		}

		dest[pos] = arr[idx];
	}

	__syncthreads();

	if(threadIdx.x == 0) {
		double2 key;

		/* insertion sort */
		for(int i = 1; i < PARENTS; i++) {
			key = dest[i];

			int j = i - 1;
			while(j >=0 && dest[j].x > key.x) {
				dest[j + 1] = dest[j];
				j = j - 1;
			}
			dest[j + 1] = key;
		}

//		#ifdef DEBUG
//		if(res[0] == 0.0) {
//			inst->res_parent = res[1];
//
//			const int off  = inst->width_per_inst;
//			const int off2 = res[1] * inst->width_per_inst;
//			for(uint8_t row = 0; row < MATRIX_HEIGHT; row++) {
//				for(int i = 0; i < inst->width_per_inst; i++) {
//					R_ROW(row)[off + i] =
//							C_ROW(row)[mem->c_zero + off2 + i];
//				}
//			}
//
//		}
//		#endif
	}
	__syncthreads();

	for(int i = tx; i < PARENTS; i += MATRIX_WIDTH) {
		arr[i] = dest[i];
	}
}

