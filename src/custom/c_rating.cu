/*
 * Copyright (c) 2011, 2012 Tobias Kalbitz <tobias.kalbitz@googlemail.com>
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the GNU Public License v2.0
 * which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#include <limits.h>
#include <float.h>

#include <cuda.h>
#include <curand_kernel.h>

#include "c_rating.h"
#include "c_instance.h"

#include "c_calc_function.cu"

__shared__ float old_rat;
__shared__ curandState rnd;

template<int mnum, int mdim>
__device__ void copy_to_child(struct c_instance& inst, unsigned int crnd)
{
	__shared__ int child;
	const int bbx = bx;
	float* const rat = inst.rating + bbx * inst.icount;
	const int iwidth = mnum*mdim*mdim;

	if(tx == 0 && ty == 0) {
		child = crnd % inst.icount;

		if(old_rat < rat[child]) {
			if(old_rat < inst.best[bbx]) {
				inst.best[bbx] = old_rat;
				inst.best_idx[bbx] = child;
			}

			rat[child] = old_rat;
			child = (bbx * inst.icount + child) * iwidth;
		} else {
			child = -1;
		}
	}
	__syncthreads();

	if(child == -1)
		return;

	float* dest = inst.instances + child;
	for(int i = RIDX(ty, tx); i < iwidth; i += mdim*mdim) {
		dest[i] = sind[i];
	}
}

template<int mnum, int mdim>
__device__ void copy_parent(struct c_instance& inst, unsigned int p)
{
	const int iwidth = mnum*mdim*mdim;

	__shared__ int parent;
	if(tx == 0 && ty == 0) {
		parent = p % inst.icount;
		parent = (blockIdx.x * inst.icount + parent) * iwidth;
	}
	__syncthreads();
	float* src = inst.instances + parent;

	for(int i = RIDX(ty, tx); i < iwidth; i += mdim*mdim) {
		sind[i] = src[i];
	}
}

template<int mnum, int mdim>
__device__  void path_mutate_p1(struct c_instance& inst,
		                int3*          __restrict__ stack,
		                unsigned int*  __restrict__ top)
{
	const int* rules = srules;
	const int iwidth = mnum*mdim*mdim;

	int pos;
	int cur_rule = 0;
	int3 entry;

	stack += bx * inst.rules_count * iwidth;
	top += bx;

	if(tx == 0 && ty == 0) {
		atomicExch(top, 0);

		entry.x = 0;
		entry.y = 0;
		entry.z = 0;
		stack[0] = entry;
	}

	__syncthreads();

	const int rows = mdim - 1;
	int special = 0;

	if(inst.cond_right == COND_UPPER_LEFT && ty == 0 && tx == 0)
		special = 1;
	if(inst.cond_right == COND_UPPER_RIGHT && ty == 0 && tx == rows)
		special = 1;
	if(inst.cond_right == COND_UPPER_LEFT_LOWER_RIGHT &&
		((ty == 0 && tx == 0) || (ty == rows && tx == rows)))
		special = 1;

	float lhs, rhs;

	do {
		rules++;
		rules = eval_interpret_rule<mdim>(rules, &lhs);

		rules++;
		rules = eval_interpret_rule<mdim>(rules, &rhs);
		__syncthreads();

		entry.x = tx;
		entry.y = ty;
		entry.z = cur_rule;

		const int ok = special ? ((lhs - rhs) >= 1.f) : lhs >= rhs;
		if(!ok) {
			pos = atomicAdd(top, 1);
			stack[pos] = entry;
		}

		cur_rule++;
		__syncthreads();
	} while(rules != rend);
}

template<int mnum, int mdim>
__device__ void path_mutate_p2(struct c_instance& inst,
		               int3*         __restrict__ stack,
		               unsigned int* __restrict__ top,
		               int rchosen)
{
	const int iwidth = mnum*mdim*mdim;

	const int tid = bx;
	const int* rules = srules;

	int cur_rule = 0;

	stack += tid * inst.rules_count * iwidth;
	top += tid;

	const int chosen = (*top < 2 ? 0 : rchosen % *top);
	int3 entry = stack[chosen];
	int l = entry.y;
	int r = entry.x;
	int goal;

	/* at least go to the first entry */
	rules++;

	/* we have to jump to the rule for that entry */
	while(cur_rule != entry.z) {
		while(*rules >= MUL_SPECIAL)
			rules++;

		rules++;

		while(*rules >= MUL_SPECIAL)
			rules++;

		rules++;
		cur_rule++;
	}

	/* put new weights on the path */
	for(; *rules >= MUL_SPECIAL; rules++) {
		/*
		 * mod 0 is a bug and mod 1 returns always 0
		 * so we have to offer an alternative
		 */
		if(mdim < 4) {
			goal = *(rules+1) < 0 ? r : curand(&rnd) % mdim;
		} else {
			goal = *(rules+1) < 0 ? r : 1 + curand(&rnd) % (mdim - 2);
		}

		float* pos = sind + (*rules) * mdim * mdim + l * mdim + goal;
		*pos = max(*pos + inst.delta, 1.);
		l = goal;
	}
}

#define MAX_RND 5

template<int mnum, int mdim, int mcond>
__global__ void all_in_one_kernel(struct c_instance inst,
                        int3*          __restrict__ stack,
                        unsigned int*  __restrict__ top,
                		const int search_steps)
{
	const int bbx = blockIdx.x;

	/* mutation */
	float old_val;
	int    mut_pos;

	__shared__ curandState srnd[MAX_RND];
	__shared__ unsigned int r[MAX_RND];

	if(tx == 0 && ty == 0) {
		rnd = inst.rnd_states[bbx * mdim + MAX_RND];
		rend = srules + inst.rules_len - 1;
		res = sind + mnum * mdim * mdim;
	}

	if(ty == 0 && tx < MAX_RND) {
		srnd[tx] = inst.rnd_states[bbx * mdim + tx];
		r[tx] = curand(&srnd[tx]);
	}

	/* caching of rules to speed up access */
	for(int i = RIDX(ty, tx); i < inst.rules_len; i += mdim*mdim)
		srules[i] = inst.rules[i];

	copy_parent<mnum, mdim>(inst, r[0]);
	__syncthreads();

	path_mutate_p1<mnum, mdim>(inst, stack, top);
	__syncthreads();

	if(tx == 0 && ty == 0)
		path_mutate_p2<mnum, mdim>(inst, stack, top, r[1]);
	__syncthreads();

	c_calc_res<mdim, mcond>(inst.match, inst.eps);
	if(tx == 0 && ty == 0)
		old_rat = shrd_rating;
	__syncthreads();

	for(int steps = 0; steps < search_steps; steps++) {
		/* rnd numbers for this iteration */
		if(ty == 0 && tx < MAX_RND)
			r[tx] = curand(&srnd[tx]);

		__syncthreads();

		if(tx == 0 && ty == 0) {
			const int mat  =      r[0] % mnum;
			int row;
			int col;

			/* mod 1 returns always 0 so we have to offer an alternative */
			if(mdim < 3) {
				row  = r[1]     % mdim;
				col  = 1 + r[2] % mdim;
			} else {
				row  =     r[1] % (mdim-1);
				col  = 1 + r[2] % (mdim-1);
			}

			const int diff = 2 * (r[3] % 2) - 1 ;
			mut_pos = mat * mdim*mdim + row * mdim + col;
			old_val = sind[mut_pos];
			sind[mut_pos] = max(old_val + diff * inst.delta, 0.);
		}
		__syncthreads();

		/* rating of mutated kernel */
		c_calc_res<mdim, mcond>(inst.match, inst.eps);
		__syncthreads();

		/* restore old version when it's worse */
		if(tx == 0 && ty == 0) {
			const int luck = r[4] % search_steps;

			if(shrd_rating > old_rat && luck) {
				sind[mut_pos] = old_val;
			} else {
				old_rat = shrd_rating;
			}
		}
	}

	if(shrd_rating < 0.f)
		shrd_rating = FLT_MAX;

	copy_to_child<mnum, mdim>(inst, r[0]);
	inst.rnd_states[bbx * mdim + MAX_RND] = rnd;

	if(ty == 0 && tx < MAX_RND)
		inst.rnd_states[bbx * mdim + tx] = srnd[tx];
}

#define case_for_kernel(num,dim) case dim: \
  all_in_one_kernel<num, dim, COND_UPPER_RIGHT><<<blocks, threads, space>>> \
      (inst, stack, top, asteps); \
  CUDA_CALL(cudaGetLastError());  \
  break;

#define switch_for_num(num) \
switch(inst.mdim) {         \
  case_for_kernel(num,2)    \
  case_for_kernel(num,3)    \
  case_for_kernel(num,4)    \
  case_for_kernel(num,5)    \
  case_for_kernel(num,6)    \
  case_for_kernel(num,7)    \
  case_for_kernel(num,8)    \
  case_for_kernel(num,9)    \
  case_for_kernel(num,10)   \
  case_for_kernel(num,11)   \
  case_for_kernel(num,12)   \
  case_for_kernel(num,13)   \
  case_for_kernel(num,14)   \
  case_for_kernel(num,15)   \
  case_for_kernel(num,16)   \
}

#define case_for_num(num) case num: switch_for_num(num); break;

void start_astep(struct c_instance& inst,
		int blocks,
		int3*          __restrict__ stack,
		unsigned int*  __restrict__ top,
		unsigned int asteps)
{
	size_t space = (inst.num_matrices * inst.mdim * inst.mdim +
			inst.mdim * inst.mdim) * sizeof(float);

	#if __CUDA_ARCH__ >= 200
		const size_t max_shm = 48128;
	#else
		const size_t max_shm = 15360;
	#endif
	if(space > max_shm) {
		printf("Can't fit all matrices in shm. Skipping calculation!\n");
		return;
	}

	dim3 threads(inst.mdim, inst.mdim);

	if(inst.cond_right == COND_UPPER_RIGHT) {
		switch (inst.num_matrices) {
		case_for_num(2);
		case_for_num(3);
		case_for_num(4);
		case_for_num(5);
		case_for_num(6);
		case_for_num(7);
		case_for_num(8);
		case_for_num(9);
		case_for_num(10);
		case_for_num(11);
		case_for_num(12);
		case_for_num(13);
		case_for_num(14);
		case_for_num(15);
		case_for_num(16);
		case_for_num(17);
		case_for_num(18);
		case_for_num(19);
		case_for_num(20);
		default:
			printf("No rule defined for that matrix counts"
					"Skipping calculation.\n");
			fflush(stdout);
			exit(0);
		}
	}
}
