/*
 * Copyright (C) 2011 Dmitry Skiba
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef _SOFCN_INCLUDED_
#define _SOFCN_INCLUDED_

#include <dlfcn.h>
#include <stdint.h>

__BEGIN_DECLS

///////////////////////////////////////////////// soinfo

#define SOINFO_NAME_LEN 128

typedef struct soinfo {
    const char name[SOINFO_NAME_LEN];
    void *phdr;
    int phnum;
    unsigned entry;
    unsigned base;
    unsigned size;

    int ba_index;

    unsigned *dynamic;

    unsigned wrprotect_start;
    unsigned wrprotect_end;

    struct soinfo *next;
   
    // more ...
} soinfo_t;

soinfo_t* get_first_so();
soinfo_t* find_so(const char* name);

/////////////////////////////////////////////////

__END_DECLS

#endif // _SOFCN_INCLUDED_

