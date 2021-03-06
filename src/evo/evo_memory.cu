/*
 * Copyright (c) 2011, 2012 Tobias Kalbitz <tobias.kalbitz@googlemail.com>
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the GNU Public License v2.0
 * which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#ifndef EVO_MEMORY_H_
#define EVO_MEMORY_H_

#define C_ROW(y) ((double*) (mem->c_slice + (y) * mem->c_pitch))
#define P_ROW(y) ((double*) (mem->p_slice + (y) * mem->p_pitch))
#define R_ROW(y) ((double*) (mem->r_slice + (y) * mem->r_pitch))
#define CR_ROW(y) ((double*) (res_mem.r_slice + (y) * res_mem.r_pitch))

#ifdef  DEBUG
#define MDEBUG(inst, rule, part, value) { \
	int d_tmp = (inst)->rules_count * 2 * (inst)->dim.matrix_width * blockIdx.y + \
                    rule * 2 * (inst)->dim.matrix_width + \
                    part * (inst)->dim.matrix_width; \
        ((double*) (mem->debug_slice + (ty) * mem->debug_pitch))[d_tmp + tx] = value; \
}
#else
#define MDEBUG(inst, rule, part, value)
#endif

#define SP(x) (mem->sparam[3*(x)])
#define MR(x) (mem->sparam[3*(x)+1])
#define RR(x) (mem->sparam[3*(x)+2])

#define PSP(x) (mem->psparam[3*(x)])
#define PMR(x) (mem->psparam[3*(x)+1])
#define PRR(x) (mem->psparam[3*(x)+2])

struct memory {
	size_t p_pitch;
	char  *p_slice;

	size_t c_pitch;
	char  *c_slice;

	int c_zero;
	int c_end;

	size_t r_pitch;
	char  *r_slice;

	int r_zero;
	int r_end;

#ifdef DEBUG
	size_t debug_pitch;
	char  *debug_slice;
#endif

	double* c_rat;
	double* p_rat;
	double* sparam;
	double* psparam;
};

__device__ static void evo_init_mem(const struct instance* const inst,
		                    struct memory * const mem)
{
	char* const p_dev_ptr = (char*)inst->dev_parent.ptr;
	const size_t p_pitch = inst->dev_parent.pitch;
	const size_t p_slice_pitch = p_pitch * inst->dim.matrix_height;
	char* const p_slice = p_dev_ptr + blockIdx.x /* z */ * p_slice_pitch;
	mem->p_pitch = p_pitch;
	mem->p_slice = p_slice;

	char* const c_dev_ptr = (char*)inst->dev_child.ptr;
	const size_t c_pitch = inst->dev_child.pitch;
	const size_t c_slice_pitch = c_pitch * inst->dim.matrix_height;
	char* const c_slice = c_dev_ptr + blockIdx.x /* z */ * c_slice_pitch;
	mem->c_pitch = c_pitch;
	mem->c_slice = c_slice;

	/*
	 * each thread represent one child which has a
	 * defined pos in the matrix
	 */
	mem->c_zero = inst->width_per_inst * threadIdx.x;
	mem->c_end  = inst->width_per_inst * (threadIdx.x + 1);

	char* const r_dev_ptr = (char*)inst->dev_res.ptr;
	const size_t r_pitch = inst->dev_res.pitch;
	const size_t r_slice_pitch = r_pitch * inst->dim.matrix_height;
	char* const r_slice = r_dev_ptr + blockIdx.x /* z */ * r_slice_pitch;
	mem->r_pitch = r_pitch;
	mem->r_slice = r_slice;

	mem->r_zero = threadIdx.x * inst->dim.matrix_width;
	mem->r_end  = mem->r_zero + inst->dim.matrix_width;

	const char* const t_dev_ptr = (char*)inst->dev_crat.ptr;
	mem->c_rat = (double*) (t_dev_ptr + blockIdx.x * inst->dev_crat.pitch);

	const char* const t_dev_ptr2 = (char*)inst->dev_prat.ptr;
	mem->p_rat = (double*) (t_dev_ptr2 + blockIdx.x * inst->dev_prat.pitch);

	const char* const s_dev_ptr = (char*)inst->dev_sparam.ptr;
	mem->sparam  = (double*)(s_dev_ptr + blockIdx.x * inst->dev_sparam.pitch);
	const char* const ps_dev_ptr = (char*)inst->dev_psparam.ptr;
	mem->psparam = (double*)(ps_dev_ptr + blockIdx.x * inst->dev_psparam.pitch);

#ifdef DEBUG
	char* const debug_dev_ptr = (char*)inst->dev_debug.ptr;
	const size_t debug_pitch = inst->dev_debug.pitch;
	const size_t debug_slice_pitch = debug_pitch * inst->dim.matrix_height;
	char* const debug_slice = debug_dev_ptr + blockIdx.x /* z */ * debug_slice_pitch;
	mem->debug_pitch = debug_pitch;
	mem->debug_slice = debug_slice;
#endif
}

/* calculate the thread id for the current block topology */
__device__ inline static int get_thread_id() {
	return threadIdx.x + blockIdx.x * blockDim.x;
}

#endif /* EVO_MEMORY_H_ */
