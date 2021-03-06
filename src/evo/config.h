/*
 * Copyright (c) 2011, 2012 Tobias Kalbitz <tobias.kalbitz@googlemail.com>
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the GNU Public License v2.0
 * which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#ifndef __M_CONFIG_H__
#define __M_CONFIG_H__

#define PARENTS  32
#define CHILDS   6
#define NEXT_2POW 256

#define RECOMB_RATE 1.
#define MUT_RATE    0.05

#define PARENT_MAX 1000.0f
#define SPARAM     ((PARENT_MAX) * 0.01)

/* HACK: we can't allocate memory dynamically, this should be enough */
#define MUL_ROW_LEN (MATRIX_WIDTH)

/* how many positions in the matrix should contain a value 0 < x <= 1 */
#define MATRIX_TAKEN_POS 0.3f

#endif
