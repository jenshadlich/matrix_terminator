/*
 * Copyright (c) 2011, 2012 Tobias Kalbitz <tobias.kalbitz@googlemail.com>
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the GNU Public License v2.0
 * which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#include <getopt.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <math.h>

#include <sys/wait.h>

#include <cuda.h>
#include <curand_kernel.h>

#include "custom/c_instance.h"
#include "custom/c_setup.h"
#include "custom/c_print.h"
#include "custom/c_rating.h"

#include "ya_malloc.h"


struct matrix_option {
	int      matrix_dim;
	int	 blocks;
	uint32_t rounds;
	char enable_maxima;
	char plot_log_enable;
	char plot_log_best;
	unsigned long asteps;
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
	printf("  -p|--parent-max         <float number>  -- default: %.2f\n",  PARENT_MAX);
	printf("  -w|--matrix-dim         <2 - %d>        -- default: 5\n",     MATRIX_WIDTH);
	printf("  -i|--instances                          -- default: 100\n");
	printf("  -a|--asteps                             -- default: 25\n");
	printf("  -e|--eps                                -- default: reasonable\n");
	printf("  -b|--blocks                             -- default: %d\n", BLOCKS);
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


static void parse_rules(struct c_instance& inst, const char *rules)
{
	inst.rules_count = 0;
	inst.rules_len  = strlen(rules);
	inst.rules = (int*)ya_malloc(sizeof(int) * inst.rules_len);
	int max_len = 0;
	int cur_len = 0;

	uint8_t tmp = 0;
	for(size_t i = 0; i < inst.rules_len; i++) {
		switch(rules[i]) {
		case 'X': {
			inst.rules[i] = MUL_SEP;
			break;
		}
		case 'Y': {
			inst.rules[i] = MUL_MARK;
			break;
		}
		default:
			if(rules[i] >= 'a')
				inst.rules[i] = rules[i] - 'a';
			else
				inst.rules[i] = rules[i] - '0';
			break;
		}

		if(rules[i] == 'X' || rules[i] == 'Y') {
			tmp = (tmp + 1) % 2;
			if(!tmp) {
				inst.rules_count++;
			}

			max_len = max(max_len, cur_len);
			cur_len = 0;
		} else {
			cur_len++;
		}
	}

	if(inst.eps == 0.f)
	    inst.eps = max(powf(inst.delta, (float)max_len), FLT_EPSILON);
}

static void parse_configuration(struct c_instance&    inst,
				struct matrix_option& mopt,
				int argc, char** argv)
{
	int c;
	int idx;

	inst.match       = MATCH_ANY;
	inst.cond_left   = COND_UPPER_LEFT_LOWER_RIGHT;
	inst.cond_right  = COND_UPPER_RIGHT;
	inst.delta       = 0.1;
	inst.parent_max  = PARENT_MAX;
	inst.icount      = 100;
	inst.eps         = 0.f;

	mopt.rounds          = 500;
	mopt.enable_maxima   = 0;
	mopt.plot_log_enable = 0;
	mopt.matrix_dim      = 5;
	mopt.asteps          = 25;
	mopt.blocks          = BLOCKS;

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
		{"matrix-dim"        , required_argument, 0, 'w'},
		{"instances"         , required_argument, 0, 'i'},
		{"asteps"            , required_argument, 0, 'a'},
		{"eps"               , required_argument, 0, 'e'},
		{"blocks"            , required_argument, 0, 'b'},
		{0, 0, 0, 0}
	};

	while((c = getopt_long(argc, argv, "m:l:r:c:d:hp:xg:w:i:a:e:b:",
			      opt, &idx)) != EOF) {
		switch(c) {
		case 'm':
			if(!strcmp(optarg, "all"))
				inst.match = MATCH_ALL;
			else if(!strcmp(optarg, "any"))
				inst.match = MATCH_ANY;
			else {
				print_usage();
				exit(EXIT_FAILURE);
			}
			break;
		case 'l':
			if(!strcmp(optarg, "uleft"))
				inst.cond_left = COND_UPPER_LEFT;
			else if(!strcmp(optarg, "uright"))
				inst.cond_left = COND_UPPER_RIGHT;
			else if(!strcmp(optarg, "uleft_lright"))
				inst.cond_left = COND_UPPER_LEFT_LOWER_RIGHT;
			else {
				print_usage();
				exit(EXIT_FAILURE);
			}

			break;
		case 'r':
			if(!strcmp(optarg, "uleft"))
				inst.cond_right = COND_UPPER_LEFT;
			else if(!strcmp(optarg, "uright"))
				inst.cond_right = COND_UPPER_RIGHT;
			else if(!strcmp(optarg, "uleft_lright"))
				inst.cond_right = COND_UPPER_LEFT_LOWER_RIGHT;
			else {
				print_usage();
				exit(EXIT_FAILURE);
			}

			break;
		case 'i':
			inst.icount = strtoul(optarg, NULL, 10);
			if(inst.icount < 1)
				inst.icount = 1;
			break;
		case 'a':
			mopt.asteps = strtoul(optarg, NULL, 10);
			if(mopt.asteps < 1)
				mopt.asteps = 1;
			break;
		case 'c':
			mopt.rounds = strtoul(optarg, NULL, 10);
			break;
		case 'b':
			mopt.blocks = strtoul(optarg, NULL, 10);
			break;
		case 'd':
			inst.delta = strtod(optarg, NULL);
			break;
        case 'e':
            inst.eps = strtod(optarg, NULL);
            break;
		case 'w':
			mopt.matrix_dim = (int)strtod(optarg, NULL);
			if(mopt.matrix_dim < 2 ||
			   mopt.matrix_dim > MATRIX_WIDTH) {
				printf("matrix width was to small or to big!\n");
				print_usage();
				exit(EXIT_FAILURE);
			}
			break;
		case 'h':
			print_usage();
			exit(EXIT_FAILURE);
		case 'p':
			inst.parent_max = strtod(optarg, NULL);
			break;
		case 'x':
			mopt.enable_maxima = 1;
			break;
		case 'g': {
			mopt.plot_log_enable = 1;

			if(!strcmp(optarg, "all"))
				mopt.plot_log_best = 0;
			else if(!strcmp(optarg, "best"))
				mopt.plot_log_best = 1;
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
			case 's':
			case 'i':
			case 'a':
			case 'e':
			case 'b':
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

int main(int argc, char** argv)
{
	struct c_instance inst;
	struct c_instance host_inst;
	struct matrix_option mopt;
	size_t freeBefore, freeAfter, total;

	srand(time(0));
	parse_configuration(host_inst, mopt, argc, argv);

	CUDA_CALL(cudaMemGetInfo(&freeBefore, &total));
	c_inst_init(host_inst, mopt.blocks, mopt.matrix_dim);

	inst = host_inst;
	inst.rules = c_create_dev_rules(inst);

	int3* stack;
	unsigned int* top;
	const size_t slen = mopt.blocks * inst.rules_count * inst.width_per_matrix;
	CUDA_CALL(cudaMalloc(&stack, inst.num_matrices * slen * sizeof(*stack)));
	CUDA_CALL(cudaMalloc(&top, mopt.blocks * sizeof(*top)));

	dim3 threads(inst.mdim, inst.mdim);
	dim3 blocks(mopt.blocks);

	CUDA_CALL(cudaMemGetInfo(&freeAfter, &total));
	printf("Allocated %.2f MiB from %.2f MiB\n",
			(freeBefore - freeAfter) / 1024 / 1024.f,
			total / 1024 / 1024.f);

	printf("Using %u instances, %u asteps and %g eps.\n",
	            inst.icount, mopt.asteps, inst.eps);

	setup_best_kernel<<<1, mopt.blocks>>>(inst);
	CUDA_CALL(cudaGetLastError());

	setup_instances_kernel<<<1, 320>>>(inst);
	CUDA_CALL(cudaGetLastError());

	patch_matrix_kernel<<<mopt.blocks, inst.mdim>>>(inst);
	CUDA_CALL(cudaGetLastError());

	setup_rating(inst, mopt.blocks);

	cudaEvent_t start, stop;
	float elapsedTime;
	float elapsedTimeTotal = 0.f;

	float* rating   = (float*)ya_malloc(mopt.blocks * sizeof(*rating));
	int* best_idx = (int*)ya_malloc(mopt.blocks * sizeof(*best_idx));

	int rounds = -1;
	int block = 0; int pos = 0;

	for(unsigned long i = 0; i < mopt.rounds; i++) {
		cudaEventCreate(&start);
		cudaEventCreate(&stop);
		// Start record
		cudaEventRecord(start, 0);

		start_astep(inst, mopt.blocks, stack, top, mopt.asteps);

		cudaEventRecord(stop, 0);
		cudaEventSynchronize(stop);
		cudaEventElapsedTime(&elapsedTime, start, stop); // that's our time!
		elapsedTimeTotal += elapsedTime;

		// Clean up:
		cudaEventDestroy(start);
		cudaEventDestroy(stop);

		if(i % 100 == 0) {
			printf("Round: %7ld Time: %10.2f: ", i, elapsedTimeTotal);
			CUDA_CALL(cudaMemcpy(rating, inst.best, mopt.blocks * sizeof(*rating), cudaMemcpyDeviceToHost));
			CUDA_CALL(cudaMemcpy(best_idx, inst.best_idx, mopt.blocks * sizeof(*best_idx), cudaMemcpyDeviceToHost));
			pos   = best_idx[0];

			for(int j = 0; j < mopt.blocks; j++) {
				printf("%.2e ", rating[j]);

				if(rating[j] == 0.) {
					printf("drin!\n");
					rounds = i;
					block = j;
					i = mopt.rounds;
					pos = best_idx[j];
					break;
				}
			}

			printf("\n");
		}
	}

	free(rating);
	free(best_idx);

	pos = min(pos, inst.icount - 1);
	printf("Time needed: %f\n", elapsedTimeTotal);
	printf("Needed rounds: %d\n", rounds);
	printf("Result is block: %d, pos: %d\n", block, pos);

	print_matrix_pretty(stdout, inst, block, pos);
	print_rules(stdout, host_inst);
	printf("Clean up and exit.\n");

	c_inst_cleanup(inst);
	free(host_inst.rules);
	cudaFree(inst.rules);
	cudaFree(stack);
	cudaThreadExit();

	if(rounds == -1)
		return 0;

	return 1;
}
