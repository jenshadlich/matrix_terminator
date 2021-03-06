/*
 * Copyright (c) 2011, 2012 Tobias Kalbitz <tobias.kalbitz@googlemail.com>
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the GNU Public License v2.0
 * which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <assert.h>
#include <getopt.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>

#include <sys/wait.h>

#include <cuda.h>
#include <curand_kernel.h>

#include "ccpso2/pso_config.h"
#include "ccpso2/pso_instance.h"

#include "ccpso2/pso.h"
#include "ccpso2/pso_rating.h"
#include "ccpso2/pso_setup.h"
#include "ccpso2/pso_param_s.h"

#include "ccpso2/pso_print.h"
#include "ccpso2/pso_copy.h"

#include "ya_malloc.h"
//#include "plot_log.h"

struct matrix_option {
	int      matrix_width;
	uint32_t rounds;
	char enable_maxima;
	char plot_log_enable;
	char plot_log_best;
};

static void print_usage()
{
	printf("Usage: matrix_generator [options] rules\n\n");
	printf("  -m|--match any|all -- default: any\n");
	printf("	`- any -- termination contest rules\n");
	printf("	   all -- ICFP rules\n\n");
	printf("  -l|--left-cond  uleft|uright|uleft_lright -- default: uleft_lright\n");
	printf("	`- uleft        -- upper left  has to be >= 1\n");
	printf("	   uright       -- upper right has to be >= 1\n");
	printf("	   uleft_lright -- upper left and lower right has to be >= 1\n\n");
	printf("  -r|--right-cond uleft|uright|uleft_lright -- default: uright\n");
	printf("	`- uleft        -- upper left  has to be >= 1\n");
	printf("	   uright       -- upper right has to be >= 1\n");
	printf("	   uleft_lright -- upper left and lower right has to be >= 1\n\n");
	printf("  -d|--delta  <float number>              -- default: 0.1\n");
	printf("  -c|--rounds <number>                    -- default: 500\n\n");
	printf("  -p|--parent-max         <float number>  -- default: %.2f\n",   PARENT_MAX);
	printf("  -w|--matrix-width       <2 - %d>        -- default: 5\n",      MATRIX_WIDTH);
	printf("  -g|--plot-log\n");
	printf("	`- best         -- log only the best rating\n");
	printf("	   all          -- log all ratings 1\n");
	printf("  -x|--enable-maxima\n\n");
	printf("Rules should be supplied in the form:\n");
	printf("  X10X01X110X0011X or XbaXabXbbaXaabbX\n");
	printf("  |<--->|<------>|    |<--->|<------>|\n");
	printf("   first  second  rule  first  second\n\n");
	printf("  Meaning: BA < AB and BBA < AABB in this case A and B\n");
	printf("           are matrices of dimension (n,n). Parameter n is\n");
	printf("           supplied at compile time and is %d\n\n", MATRIX_WIDTH);
	printf("If the option --plot-log is given all ratings will be written in"
		" a '.dat' file plus a '.plot' file for gnuplot.\n\n");
	printf("If the option --enable-maxima is given the result will be written"
		" in an 'mg_XXXXXX' file and maxima recalculate and prints the "
		"result.\n\n");
}

static void parse_rules(struct pso_instance * const inst, const char *rules)
{
	inst->rules_count = 0;
	inst->rules_len  = strlen(rules);
	inst->rules = (int*)ya_malloc(sizeof(int) * inst->rules_len);

	uint8_t tmp = 0;
	for(size_t i = 0; i < inst->rules_len; i++) {
		if(rules[i] >= 'a')
			inst->rules[i] = (rules[i] == 'X') ? MUL_SEP : rules[i] - 'a';
		else
			inst->rules[i] = (rules[i] == 'X') ? MUL_SEP : rules[i] - '0';

		if(rules[i] == 'X') {
			tmp = (tmp + 1) % 2;
			if(!tmp) {
				inst->rules_count++;
			}
		}
	}
}

static void parse_configuration(struct pso_instance* const inst,
				struct matrix_option* const mopt,
				int argc, char** argv)
{
	int c;
	int idx;

	inst->match       = MATCH_ANY;
	inst->cond_left   = COND_UPPER_LEFT_LOWER_RIGHT;
	inst->cond_right  = COND_UPPER_RIGHT;
	inst->delta       = 0.1;
	inst->parent_max  = PARENT_MAX;

	mopt->rounds          = 500;
	mopt->enable_maxima   = 0;
	mopt->plot_log_enable = 0;
	mopt->matrix_width    = 5;

	struct option opt[] =
	{
		{"match"             , required_argument, 0, 'm'},
		{"left-cond"         , required_argument, 0, 'l'},
		{"right-cond"        , required_argument, 0, 'r'},
		{"rounds"            , required_argument, 0, 'c'},
		{"delta"             , required_argument, 0, 'd'},
		{"help"              , no_argument,       0, 'h'},
		{"parent-max"        , required_argument, 0, 'p'},
		{"enable-maxima"     , no_argument,       0, 'x'},
		{"plot-log"          , required_argument, 0, 'g'},
		{"matrix-width"      , required_argument, 0, 'w'},
		{0, 0, 0, 0}
	};

	while((c = getopt_long(argc, argv, "m:l:r:c:d:hp:xg:w:",
			      opt, &idx)) != EOF) {
		switch(c) {
		case 'm':
			if(!strcmp(optarg, "all"))
				inst->match = MATCH_ALL;
			else if(!strcmp(optarg, "any"))
				inst->match = MATCH_ANY;
			else {
				print_usage();
				exit(EXIT_FAILURE);
			}
			break;
		case 'l':
			if(!strcmp(optarg, "uleft"))
				inst->cond_left = COND_UPPER_LEFT;
			else if(!strcmp(optarg, "uright"))
				inst->cond_left = COND_UPPER_RIGHT;
			else if(!strcmp(optarg, "uleft_lright"))
				inst->cond_left = COND_UPPER_LEFT_LOWER_RIGHT;
			else {
				print_usage();
				exit(EXIT_FAILURE);
			}

			break;
		case 'r':
			if(!strcmp(optarg, "uleft"))
				inst->cond_right = COND_UPPER_LEFT;
			else if(!strcmp(optarg, "uright"))
				inst->cond_right = COND_UPPER_RIGHT;
			else if(!strcmp(optarg, "uleft_lright"))
				inst->cond_right = COND_UPPER_LEFT_LOWER_RIGHT;
			else {
				print_usage();
				exit(EXIT_FAILURE);
			}

			break;
		case 'c':
			mopt->rounds = strtoul(optarg, NULL, 10);
			break;
		case 'd':
			inst->delta = strtod(optarg, NULL);
			break;
		case 'w':
			mopt->matrix_width = (int)strtod(optarg, NULL);
			if(mopt->matrix_width < 2 ||
			   mopt->matrix_width > MATRIX_WIDTH) {
				printf("matrix width was to small or to big!\n");
				print_usage();
				exit(EXIT_FAILURE);
			}
			break;
		case 'h':
			print_usage();
			exit(EXIT_FAILURE);
		case 'p':
			inst->parent_max = strtod(optarg, NULL);
			break;
		case 'x':
			mopt->enable_maxima = 1;
			break;
		case 'g': {
			mopt->plot_log_enable = 1;

			if(!strcmp(optarg, "all"))
				mopt->plot_log_best = 0;
			else if(!strcmp(optarg, "best"))
				mopt->plot_log_best = 1;
			else {
				print_usage();
				exit(EXIT_FAILURE);
			}
			break;
		}
		case '?':
			switch (optopt) {
			case 'm':
			case 'l':
			case 'r':
			case 'c':
			case 'd':
			case 'p':
			case 'g':
			case 'w':
				fprintf(stderr, "Option -%c requires an "
						"argument!\n", optopt);
				exit(EXIT_FAILURE);
				break;
			default:
				if (isprint(optopt)) {
					fprintf(stderr, "Unknown option "
							"character `0x%X\'!\n",
							optopt);
				}
				exit(EXIT_FAILURE);
				break;
			}
			break;

		default:
			printf("\n");
			print_usage();
			exit(EXIT_FAILURE);
		}
	}

	if(optind == argc) {
		printf("Rules are missing!\n\n");
		print_usage();
		exit(EXIT_FAILURE);
	}

	parse_rules(inst, argv[optind]);
}

void update_lbest(struct pso_instance& inst, struct param_s& ps)
{
	const dim3 blocks(BLOCKS, inst.dim.particles);
	const dim3 threads(inst.dim.matrix_width, inst.dim.matrix_height);

	for(int c = 0; c < ps.s_count; c++) {
		pso_calc_res<<<blocks, threads>>>(inst, ps.s, c);
		CUDA_CALL(cudaGetLastError());
		cudaThreadSynchronize();
		CUDA_CALL(cudaGetLastError());

		pso_evaluation_lbest<<<BLOCKS, PARTICLE_COUNT>>>(inst, ps.s, c * PARTICLE_COUNT);
		CUDA_CALL(cudaGetLastError());
		cudaThreadSynchronize();
		CUDA_CALL(cudaGetLastError());
	}
}

int main(int argc, char** argv)
{
	struct pso_instance inst;
	struct matrix_option mopt;
	struct pso_instance *dev_inst;
	struct pso_instance host_inst;
	int* dev_rules;
	size_t freeBefore, freeAfter, total;

	srand(time(0));
	parse_configuration(&inst, &mopt, argc, argv);

	CUDA_CALL(cudaMemGetInfo(&freeBefore, &total));

	pso_inst_init(&inst, mopt.matrix_width);
	host_inst = inst;
	dev_inst = pso_inst_create_dev_inst(&inst, &dev_rules);

	CUDA_CALL(cudaMemGetInfo(&freeAfter, &total));
	printf("Allocated %.2f MiB from %.2f MiB\n",
			(freeBefore - freeAfter) / 1024 / 1024.f,
			total / 1024 / 1024.f);


	setup_global_particle_kernel<<<1, 320>>>(dev_inst);
	CUDA_CALL(cudaGetLastError());
	setup_particle_kernel<<<1, 320>>>(dev_inst);
	CUDA_CALL(cudaGetLastError());

	setup_rating<<<1, 512>>>(dev_inst);
	CUDA_CALL(cudaGetLastError());

	setup_col_permut<<<1, 512>>>(inst.col_permut,
			             inst.width_per_line * BLOCKS,
			             inst.width_per_line);
	CUDA_CALL(cudaGetLastError());

	// Prepare
	cudaEvent_t start, stop;
	float elapsedTime;
	float elapsedTimeTotal = 0.f;

	struct param_s ps;
	param_s_init(inst, ps);

	int width = inst.dim.blocks;
	double *rating = (double*)ya_malloc(width * sizeof(double));
////	struct plot_log* pl = init_plot_log(mopt.plot_log_enable,
////					    mopt.plot_log_best);
//
	int rounds = -1;
	int block = 0; int thread = 0;

	for(unsigned long i = 0; i < mopt.rounds; i++) {
		cudaEventCreate(&start);
		cudaEventCreate(&stop);
		// Start record
		cudaEventRecord(start, 0);

		update_lbest(inst, ps);
		param_s_update(inst, ps);

		pso_neighbor_best<<<BLOCKS, PARTICLE_COUNT>>>(inst, ps.s);
		CUDA_CALL(cudaGetLastError());
		cudaThreadSynchronize();
		CUDA_CALL(cudaGetLastError());

		pso_swarm_step_ccpso2<<<BLOCKS, 64>>>(inst, ps.s);
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

		if(i % 200 == 0)
			print_gbest_particle_ratings(inst);
		CUDA_CALL(cudaMemcpy(rating, inst.gbrat, width * sizeof(double),
						cudaMemcpyDeviceToHost));

		if(rating[0] == 0.) {
			rounds = i;
			block = i;
			i = mopt.rounds;
		}
	}

	free(rating);
////	clean_plot_log(pl);

	printf("Time needed: %f\n", elapsedTimeTotal);
	printf("Needed rounds: %d\n", rounds);
	printf("Result is block: %d, parent: %d\n", block, thread);
	printf("Result was in block: %d, child: %d, selection: %d\n",
		inst.res_child_block, inst.res_child_idx, inst.res_parent);

	print_gbest_particle_ratings(inst);
	print_global_matrix_pretty(stdout, &inst, block);
	print_rules(stdout, &host_inst);

	printf("Clean up and exit.\n");
	pso_inst_cleanup(&inst, dev_inst);
	param_s_destroy(ps);
	cudaFree(dev_rules);
	cudaThreadExit();

	if(rounds == -1)
		return 0;

	return 1;
}
