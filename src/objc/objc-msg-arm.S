/*
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Copyright (C) 2011 Dmitry Skiba
 * Copyright (c) 1999-2007 Apple Computer, Inc.  All Rights Reserved.
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

#ifdef __arm__

/********************************************************************
 * 
 *  objc-msg-arm.s - ARM code to support objc messaging
 *
 ********************************************************************/


#ifdef ARM11
#define MOVE cpy
#define MOVEEQ cpyeq
#define MOVENE cpyne
#else
#define MOVE mov
#define MOVEEQ moveq
#define MOVENE movne
#endif

#ifdef VFP_ARGS
#define SAVE_VFP    fstmfdd  sp!, {d0-d7}
#define RESTORE_VFP    fldmfdd  sp!, {d0-d7}
#else
#define SAVE_VFP    /* empty */
#define RESTORE_VFP    /* empty */
#endif

    
#if defined(__DYNAMIC__)
#define MI_EXTERN(var) \
    .non_lazy_symbol_pointer                        ;\
L ## var ## __non_lazy_ptr:                             ;\
    .indirect_symbol var                            ;\
    .long 0
#else
#define MI_EXTERN(var) \
    .globl var
#endif

#if defined(__DYNAMIC__)
#define MI_GET_ADDRESS(reg,var)  \
    ldr     reg, 4f                                 ;\
3:    ldr     reg, [pc, reg]                          ;\
    b       5f                                      ;\
4:    .long   L ## var ## __non_lazy_ptr - (3b + 8)   ;\
5:
#else
#define MI_GET_ADDRESS(reg,var)  \
    ldr     reg, 3f ;\
    b       4f      ;\
3:    .long var       ;\
4:
#endif

#if defined(__DYNAMIC__)
#define MI_BRANCH_EXTERNAL(var)                         \
    MI_GET_ADDRESS(ip, var)                         ;\
    bx      ip
#else
#define MI_BRANCH_EXTERNAL(var)                         ;\
    b       var
#endif

#if defined(__DYNAMIC__)
#define MI_CALL_EXTERNAL(var)    \
    MI_GET_ADDRESS(ip,var)  ;\
    MOVE    lr, pc          ;\
    bx      ip
#else
#define MI_CALL_EXTERNAL(var)                           \
    bl      var
#endif


MI_EXTERN(_class_lookupMethodAndLoadCache)
MI_EXTERN(FwdSel)
MI_EXTERN(__objc_error)
MI_EXTERN(_objc_forward_handler)
MI_EXTERN(_objc_forward_stret_handler)

#if 0
// Special section containing a function pointer that dyld will call
// when it loads new images.
MI_EXTERN(__objc_notify_images)
.text
.align 2
L__objc_notify_images:
    MI_BRANCH_EXTERNAL(__objc_notify_images)

.section __DATA,__image_notify
.long L__objc_notify_images
#endif


# _objc_entryPoints and _objc_exitPoints are used by method dispatch
# caching code to figure out whether any threads are actively 
# in the cache for dispatching.  The labels surround the asm code
# that do cache lookups.  The tables are zero-terminated.
.data
.globl _objc_entryPoints
_objc_entryPoints:
    .long   _cache_getImp
    .long   _cache_getMethod
    .long   objc_msgSend
    .long   objc_msgSend_stret
    .long   objc_msgSendSuper
    .long   objc_msgSendSuper_stret
    .long   0

.data
.globl _objc_exitPoints
_objc_exitPoints:
    .long   LGetImpExit
    .long   LGetMethodExit
    .long   LMsgSendExit
    .long   LMsgSendStretExit
    .long   LMsgSendSuperExit
    .long   LMsgSendSuperStretExit
    .long   0


/* objc_super parameter to sendSuper */
.set RECEIVER,         0
.set CLASS,            4

/* Selected field offsets in class structure */
.set ISA,              0
.set CACHE,            8

/* Method descriptor */
.set METHOD_NAME,      0
.set METHOD_IMP,       8

/* Cache header */
.set MASK,             0
.set OCCUPIED,         4
.set BUCKETS,          8     /* variable length array */


#####################################################################
#
# ENTRY        functionName
#
# Assembly directives to begin an exported function.
# We align on cache boundaries for these few functions.
#
# Takes: functionName - name of the exported function
#####################################################################

.macro ENTRY name
    .text
    .align    2
    .globl    \name
    .type \name, %function
\name:
.endm


#####################################################################
#
# END_ENTRY    functionName
#
# Assembly directives to end an exported function.  Just a placeholder,
# a close-parenthesis for ENTRY, until it is needed for something.
#
# Takes: functionName - name of the exported function
#####################################################################

.macro END_ENTRY name
.endm


#####################################################################
#
# CacheLookup selectorRegister, cacheMissLabel
#
# Locate the implementation for a selector in a class method cache.
#
# Takes: 
#     v1 = class whose cache is to be searched
#     $0 = register containing selector (a2 or a3 ONLY)
#     cacheMissLabel = label to branch to iff method is not cached
#
# Kills:
#    a4, v1, v2, v3, ip
#
# On exit: (found) method triplet in v1, imp in ip
#          (not found) jumps to cacheMissLabel
#
#####################################################################

.macro CacheLookup selReg, missLabel
    
    ldr     v2, [v1, #CACHE]        /* cache = class->cache */
    ldr     v3, [v2, #MASK]         /* mask = cache->mask */
    add     a4, v2, #BUCKETS        /* buckets = &cache->buckets */
    and     v2, v3, \selReg, LSR #2 /* index = mask & (sel >> 2) */

/* search the cache */
/* a1=receiver, a2 or a3=sel, v2=index, v3=mask, a4=buckets, v1=method */
1:
    ldr     v1, [a4, v2, LSL #2]    /* method = buckets[index] */
    teq     v1, #0                  /* if (method == NULL)     */
    add     v2, v2, #1              /* index++                 */
    beq     \missLabel                      /*     goto cacheMissLabel */
    ldr     ip, [v1, #METHOD_NAME]  /* load method->method_name        */
    teq     \selReg, ip                  /* if (method->method_name != sel) */
    and     v2, v2, v3              /* index &= mask                   */
    bne     1b                      /*     retry                       */

/* cache hit, v1 == method triplet address */
/* Return triplet in v1 and imp in ip      */
    ldr     ip, [v1, #METHOD_IMP]   /* imp = method->method_imp */

.endm

/********************************************************************
 * Method _cache_getMethod(Class cls, SEL sel, IMP msgForward_internal_imp)
 *
 * On entry:    a1 = class whose cache is to be searched
 *              a2 = selector to search for
 *              a3 = _objc_msgForward_internal IMP
 *
 * If found, returns method triplet pointer.
 * If not found, returns NULL.
 *
 * NOTE: _cache_getMethod never returns any cache entry whose implementation
 * is _objc_msgForward_internal. It returns NULL instead. This prevents thread-
 * safety and memory management bugs in _class_lookupMethodAndLoadCache. 
 * See _class_lookupMethodAndLoadCache for details.
 *
 * _objc_msgForward_internal is passed as a parameter because it's more 
 * efficient to do the (PIC) lookup once in the caller than repeatedly here.
 ********************************************************************/

    ENTRY _cache_getMethod

# save registers and load class for CacheLookup
    stmfd   sp!, {a4,v1-v3,r7,lr}
    add     r7, sp, #16
    MOVE    v1, a1

# search the cache
    CacheLookup a2, LGetMethodMiss

# cache hit, method triplet in v1 and imp in ip
    teq     ip, a3          /* check for _objc_msgForward_internal */
    MOVEEQ  a1, #1          /* return (Method)1 if forward */
    MOVENE  a1, v1          /* return triplet if not forward */
    ldmfd   sp!, {a4,v1-v3,r7,pc}
    
LGetMethodMiss:
    MOVE    a1, #0          /* return nil if cache miss */
    ldmfd   sp!, {a4,v1-v3,r7,pc}

LGetMethodExit: 
    END_ENTRY _cache_getMethod


/********************************************************************
 * IMP _cache_getImp(Class cls, SEL sel)
 *
 * On entry:    a1 = class whose cache is to be searched
 *              a2 = selector to search for
 *
 * If found, returns method implementation.
 * If not found, returns NULL.
 ********************************************************************/

    ENTRY _cache_getImp

# save registers and load class for CacheLookup
    stmfd   sp!, {a4,v1-v3,r7,lr}
    add     r7, sp, #16
    MOVE    v1, a1

# search the cache
    CacheLookup a2, LGetImpMiss

# cache hit, method triplet in v1 and imp in ip
    MOVE    a1, ip          @ return imp
    ldmfd   sp!, {a4,v1-v3,r7,pc}
    
LGetImpMiss:
    MOVE    a1, #0          @ return nil if cache miss
    ldmfd   sp!, {a4,v1-v3,r7,pc}

LGetImpExit: 
    END_ENTRY _cache_getImp


/********************************************************************
 * id        objc_msgSend(id    self,
 *            SEL    op,
 *            ...)
 *
 * On entry: a1 is the message receiver,
 *           a2 is the selector
 ********************************************************************/

    ENTRY objc_msgSend
# check whether receiver is nil
    teq     a1, #0
    moveq   a2, #0
    bxeq    lr
    
# save registers and load receiver's class for CacheLookup
    stmfd   sp!, {a4,v1-v3}
    ldr     v1, [a1, #ISA]

# receiver is non-nil: search the cache
    CacheLookup a2, LMsgSendCacheMiss

# cache hit (imp in ip) - prep for forwarding, restore registers and call
    teq    v1, v1        /* set nonstret (eq) */
    ldmfd   sp!, {a4,v1-v3}
    bx      ip

# cache miss: go search the method lists
LMsgSendCacheMiss:
    ldmfd    sp!, {a4,v1-v3}
    b    objc_msgSend_uncached

LMsgSendExit:
    END_ENTRY objc_msgSend


    .text
    .align 2
objc_msgSend_uncached:

# Push stack frame
    stmfd    sp!, {a1-a4,r7,lr}
    add     r7, sp, #16
    SAVE_VFP

# Load class and selector
    ldr    a1, [a1, #ISA]        /* class = receiver->isa  */
    # MOVE    a2, a2            /* selector already in a2 */

# Do the lookup
    MI_CALL_EXTERNAL(_class_lookupMethodAndLoadCache)
    MOVE    ip, a1

# Prep for forwarding, Pop stack frame and call imp
    teq    v1, v1        /* set nonstret (eq) */
    RESTORE_VFP
    ldmfd    sp!, {a1-a4,r7,lr}
    bx    ip


/********************************************************************
 * struct_type    objc_msgSend_stret(id    self,
 *                SEL    op,
 *                    ...);
 *
 * objc_msgSend_stret is the struct-return form of msgSend.
 * The ABI calls for a1 to be used as the address of the structure
 * being returned, with the parameters in the succeeding registers.
 *
 * On entry: a1 is the address where the structure is returned,
 *           a2 is the message receiver,
 *           a3 is the selector
 ********************************************************************/

    ENTRY objc_msgSend_stret
# check whether receiver is nil
    teq     a2, #0
    bxeq    lr

# save registers and load receiver's class for CacheLookup
    stmfd   sp!, {a4,v1-v3}
    ldr     v1, [a2, #ISA]

# receiver is non-nil: search the cache
    CacheLookup a3, LMsgSendStretCacheMiss

# cache hit (imp in ip) - prep for forwarding, restore registers and call
    tst    v1, v1        /* set stret (ne); v1 is nonzero (triplet) */
    ldmfd   sp!, {a4,v1-v3}
    bx      ip

# cache miss: go search the method lists
LMsgSendStretCacheMiss:
    ldmfd    sp!, {a4,v1-v3}
    b    objc_msgSend_stret_uncached
    
LMsgSendStretExit:
    END_ENTRY objc_msgSend_stret


    .text
    .align 2
objc_msgSend_stret_uncached:

# Push stack frame
    stmfd    sp!, {a1-a4,r7,lr}
    add     r7, sp, #16
    SAVE_VFP

# Load class and selector
    ldr    a1, [a2, #ISA]        /* class = receiver->isa */
    MOVE    a2, a3            /* selector */

# Do the lookup
    MI_CALL_EXTERNAL(_class_lookupMethodAndLoadCache)
    MOVE    ip, a1

# Prep for forwarding, pop stack frame and call imp
    tst    a1, a1        /* set stret (ne); a1 is nonzero (imp) */
    
    RESTORE_VFP
    ldmfd    sp!, {a1-a4,r7,lr}
    bx    ip


/********************************************************************
 * id    objc_msgSendSuper(struct objc_super    *super,
 *            SEL            op,
 *                        ...)
 *
 * struct objc_super {
 *    id    receiver
 *    Class    class
 * }
 ********************************************************************/

    ENTRY objc_msgSendSuper2
    @ objc_super->class is superclass of the class to search
    ldr    r12, [a1, #CLASS]
    ldr    r12, [r12, #4]        @ r12 = cls->super_class
    str    r12, [a1, #CLASS]
    b    objc_msgSendSuper
    END_ENTRY

    ENTRY objc_msgSendSuper

# save registers and load super class for CacheLookup
    stmfd   sp!, {a4,v1-v3}
    ldr     v1, [a1, #CLASS]

# search the cache
    CacheLookup a2, LMsgSendSuperCacheMiss

# cache hit (imp in ip) - prep for forwarding, restore registers and call
    teq    v1, v1            /* set nonstret (eq) */
    ldmfd   sp!, {a4,v1-v3}
    ldr     a1, [a1, #RECEIVER]    @ fetch real receiver
    bx      ip

# cache miss: go search the method lists
LMsgSendSuperCacheMiss:
    ldmfd   sp!, {a4,v1-v3}
    b    objc_msgSendSuper_uncached

LMsgSendSuperExit:
    END_ENTRY objc_msgSendSuper


    .text
    .align 2
objc_msgSendSuper_uncached:

# Push stack frame
    stmfd    sp!, {a1-a4,r7,lr}
    add     r7, sp, #16
    SAVE_VFP

# Load class and selector
    ldr     a1, [a1, #CLASS]        /* class = super->class   */
    # MOVE    a2, a2            /* selector already in a2 */

# Do the lookup
    MI_CALL_EXTERNAL(_class_lookupMethodAndLoadCache)
    MOVE    ip, a1

# Prep for forwarding, pop stack frame and call imp
    teq    v1, v1            /* set nonstret (eq) */
    RESTORE_VFP
    ldmfd    sp!, {a1-a4,r7,lr}
    ldr     a1, [a1, #RECEIVER]    @ fetch real receiver
    bx    ip


/********************************************************************
 * struct_type    objc_msgSendSuper_stret(objc_super    *super,
 *                    SEL        op,
 *                            ...)
 *
 * struct objc_super {
 *    id    receiver
 *    Class    class
 * }
 *
 *
 * objc_msgSendSuper_stret is the struct-return form of msgSendSuper.
 * The ABI calls for a1 to be used as the address of the structure
 * being returned, with the parameters in the succeeding registers.
 *
 * On entry:    a1 is the address to which to copy the returned structure,
 *        a2 is the address of the objc_super structure,
 *        a3 is the selector
 ********************************************************************/

    ENTRY objc_msgSendSuper2_stret
    @ objc_super->class is superclass of the class to search
    ldr    r12, [a2, #CLASS]
    ldr    r12, [r12, #4]        @ xx = cls->super_class
    str    r12, [a2, #CLASS]
    b    objc_msgSendSuper_stret
    END_ENTRY

    ENTRY objc_msgSendSuper_stret

# save registers and load super class for CacheLookup
    stmfd   sp!, {a4,v1-v3}
    ldr     v1, [a2, #CLASS]

# search the cache
    CacheLookup a3, LMsgSendSuperStretCacheMiss

# cache hit (imp in ip) - prep for forwarding, restore registers and call
    tst     v1, v1        /* set stret (ne); v1 is nonzero (triplet) */
    ldmfd   sp!, {a4,v1-v3}
    ldr     a2, [a2, #RECEIVER]      @ fetch real receiver
    bx        ip

# cache miss: go search the method lists
LMsgSendSuperStretCacheMiss:
    ldmfd   sp!, {a4,v1-v3}
    b    objc_msgSendSuper_stret_uncached

LMsgSendSuperStretExit:
    END_ENTRY objc_msgSendSuper_stret


    .text
    .align 2
objc_msgSendSuper_stret_uncached:

# Push stack frame
    stmfd    sp!, {a1-a4,r7,lr}
    add     r7, sp, #16
    SAVE_VFP

# Load class and selector
    ldr     a1, [a2, #CLASS]        /* class = super->class */
    MOVE    a2, a3            /* selector */

# Do the lookup
    MI_CALL_EXTERNAL(_class_lookupMethodAndLoadCache)
    MOVE    ip, a1

# Prep for forwarding, pop stack frame and call imp
    tst     v1, v1        /* set stret (ne); v1 is nonzero (triplet) */

    RESTORE_VFP
    ldmfd    sp!, {a1-a4,r7,lr}
    ldr     a2, [a2, #RECEIVER]    @ fetch real receiver
    bx      ip


/********************************************************************
 *
 * id        _objc_msgForward(id    self,
 *                SEL    sel,
 *                    ...);
 * struct_type    _objc_msgForward_stret    (id    self,
 *                    SEL    sel,
 *                    ...);
 *
 * Both _objc_msgForward and _objc_msgForward_stret 
 * send the message to a method having the signature:
 *
 *      - forward:(SEL)sel :(marg_list)args;
 * 
 * The marg_list's layout is:
 * d0   <-- args
 * d1
 * d2   |  increasing address
 * d3   v
 * d4
 * d5
 * d6
 * d7
 * a1
 * a2
 * a3
 * a4
 * stack args...
 * 
 * typedef struct objc_sendv_margs {
 * #ifdef VFP_ARGS
 *    double        vfp[8];
 * #endif
 *    int        a[4];
 *    int        stackArgs[...];
 * };
 *
 ********************************************************************/

.data
.extern FwdSel
FwdSel:
    .long 0

.extern _objc_forward_handler
_objc_forward_handler:
    .long 0

.extern _objc_forward_stret_handler
_objc_forward_stret_handler:
    .long 0


    ENTRY   _objc_msgForward_internal
    .extern __objc_msgForward_internal
    // Method cache version

    // THIS IS NOT A CALLABLE C FUNCTION
    // Out-of-band condition register is NE for stret, EQ otherwise.

    bne    _objc_msgForward_stret
    b    _objc_msgForward
    
    END_ENTRY _objc_msgForward_internal
    

    ENTRY   _objc_msgForward
    // Non-stret version

# check for user-installed forwarding handler
    MI_GET_ADDRESS(ip, _objc_forward_handler)
    ldr    ip, [ip]
    teq    ip, #0
    bxne    ip

# build marg_list
    stmfd   sp!, {a1-a4}             @ push args to marg_list
#ifdef VFP_ARGS
    fstmfdd sp!, {d0-d7}             @ push fp args to marg_list
#endif

# build forward::'s parameter list  (self, forward::, original sel, marg_list)
    # a1 already is self
    MOVE    a3, a2                   @ original sel
    MI_GET_ADDRESS(a2, FwdSel)  @ "forward::"
    ldr    a2, [a2]
    MOVE    a4, sp                   @ marg_list

# check for forwarding of forward:: itself
    teq     a2, a3
    beq     LMsgForwardError         @ original sel == forward:: - give up

# push stack frame
    str     lr, [sp, #-(2*4)]!       @ save lr and align stack

# send it
    bl      objc_msgSend

# pop stack frame and return
    ldr    lr, [sp]
#ifdef VFP_ARGS
    add    sp, sp, #(4 + 4 + 4*4 + 8*8)    @ skip lr, pad, a1..a4, d0..d7
#else
    add    sp, sp, #(4 + 4 + 4*4)         @ skip lr, pad, a1..a4
#endif
    bx    lr

    END_ENTRY _objc_msgForward


    ENTRY   _objc_msgForward_stret
    // Struct-return version
    
# check for user-installed forwarding handler
    MI_GET_ADDRESS(ip, _objc_forward_stret_handler)
    ldr    ip, [ip]
    teq    ip, #0
    bxne    ip

# build marg_list
    stmfd   sp!, {a1-a4}             @ push args to marg_list
#ifdef VFP_ARGS
    fstmfdd sp!, {d0-d7}             @ push fp args to marg_list
#endif

# build forward::'s parameter list  (self, forward::, original sel, marg_list)
    MOVE    a1, a2                   @ self
    MI_GET_ADDRESS(a2, FwdSel) @ "forward::"
    ldr    a2, [a2]
    # a3 is already original sel
    MOVE    a4, sp                   @ marg_list

# check for forwarding of forward:: itself
    teq     a2, a3
    beq     LMsgForwardError         @ original sel == forward:: - give up

# push stack frame
    str     lr, [sp, #-(2*4)]!       @ save lr and align stack

# send it
    bl      objc_msgSend

# pop stack frame and return
    ldr    lr, [sp]
#ifdef VFP_ARGS
    add    sp, sp, #(4 + 4 + 4*4 + 8*8)    @ skip lr, pad, a1..a4, d0..d7
#else
    add    sp, sp, #(4 + 4 + 4*4)         @ skip lr, pad, a1..a4
#endif
    bx    lr
    
    END_ENTRY _objc_msgForward_stret

LMsgForwardError:
    # currently a1=self, a2=forward::, a3 = original sel, a4 = marg_list
    # call __objc_error(self, format, original sel)
    add     a2, pc, #0     @ pc bias is 8 bytes
    MI_CALL_EXTERNAL(__objc_error)
    .ascii "Does not recognize selector %s\0"


/********************************************************************
 * id        objc_msgSendv(id    self,
 *            SEL        op,
 *            unsigned    arg_size,
 *            marg_list    arg_frame);
 *
 * typedef struct objc_sendv_margs {
 * #ifdef VFP_ARGS
 *    double        vfp[8];
 * #endif
 *    int        a[4];
 *    int        stackArgs[...];
 * };
 *
 * arg_frame is the number of bytes used in a[] plus stackArgs.
 * It does not include vfp[].
 * 
 ********************************************************************/

    ENTRY   objc_msgSendv

# Push stack frame
    SAVE_VFP
    stmfd    sp!, {a4,v1-v3,r7,lr}    @ a4 saved for stack alignment only
    add     r7, sp, #16

# save sendv's parameters
    # self stays in a1
    # sel stays in a2
    MOVE    v1, a3              @ v1 is arg count in bytes
    MOVE    v2, a4              @ v2 is marg_list

# load FP from marg_list
#ifdef VFP_ARGS
    fldmfdd v2!, {d0-d7}
#endif

# load arg registers from marg_list
# v1 is remaining count, v2 is pointer into marg_list
    # self already in a1
    # sel already in a2
    cmp     v1, #12
    ldrhs   a3, [v2, #8]        @ pop a3 if arg bytes is at least 12
    ldrhi   a4, [v2, #12]       @ pop a4 if arg bytes is more than 12
    subs    v1, v1, #16         @ skip past register args
    ble     LMsgSendvCall       @ call now if no args remain
    add     v2, v2, #16         @ skip past register args

# copy stack args from marg_list
# v1 is remaining bytes, v2 is pointer into marg_list, sp is pointer into stack
    tst     v1, #4
    subne   sp, sp, #4        @ push 4-byte pad if word count is odd

    sub     sp, sp, v1          @ move sp to end and copy backwards
                                    @ (this preserves ABI's stack constraints)
LMsgSendvArgLoop:
    subs    v1, v1, #4
    ldr     v3, [v2, v1]
    str     v3, [sp, v1]
    bne     LMsgSendvArgLoop

LMsgSendvCall:    
    bl      objc_msgSend

# Pop stack frame and return
    MOVE    sp, r7
    ldmfd    sp!, {a4,v1-v3,r7,pc}
#ifdef VFP_ARGS
#error broken for vfp
#endif

    END_ENTRY objc_msgSendv



/********************************************************************
 * struct_type        objc_msgSendv_stret(id    self,
 *            SEL        op,
 *            unsigned    arg_size,
 *            marg_list    arg_frame);
 *
 * typedef struct objc_sendv_margs {
 * #ifdef VFP_ARGS
 *    double        vfp[8];
 * #endif
 *    int        a[4];
 *    int        stackArgs[...];
 * };
 *
 * arg_frame is the number of bytes used in a[] plus stackArgs.
 * It does not include vfp[].
 ********************************************************************/

    ENTRY   objc_msgSendv_stret

# Push stack frame
    stmfd    sp!, {a4,v1-v3,r7,lr}    @ a4 saved for stack alignment only
    add     r7, sp, #16
    SAVE_VFP

# save sendv's parameters
    # stret address stays in a1
    # self stays in a2
    # sel stays in a3
    MOVE    v1, a4                  @ v1 is arg count in bytes
    ldr     v2, [r7, #24]        @ v2 is marg_list

# load FP from marg_list
#ifdef VFP_ARGS
    fldmfdd v2!, {d0-d7}
#endif

# load arg registers from marg_list
# v1 is remaining count, v2 is pointer into marg_list
    # stret already in a1
    # self already in a2
    # sel already in a3
    subs    v1, v1, #16         @ skip past register args
    ldrhs   a4, [v2, #12]       @ pop a4 if arg bytes is at least 16
    beq     LMsgSendvStretCall  @ call now if no args remain
    add     v2, v2, #16         @ skip past register args

# copy stack args from marg_list
# v1 is remaining count, v2 is pointer into marg_list, sp is pointer into stack
    tst     v1, #4
    subne   sp, sp, #4        @ push 4-byte pad if word count is odd

    sub     sp, sp, v1          @ move pointers to end and copy backwards
                                    @ (this preserves ABI's stack constraints)
LMsgSendvStretArgLoop:
    subs    v1, v1, #4
    ldr     v3, [v2, v1]
    str     v3, [sp, v1]
    bne     LMsgSendvStretArgLoop

LMsgSendvStretCall:    
    bl      objc_msgSend_stret

# Pop stack frame and return
    MOVE    sp, r7
    ldmfd   sp!, {a4,v1-v3,r7,pc}
#ifdef VFP_ARGS
#error broken for vfp
#endif

    END_ENTRY objc_msgSendv_stret


    ENTRY method_invoke
    # a2 is method triplet instead of SEL
    ldr    ip, [a2, #METHOD_IMP]
    ldr    a2, [a2, #METHOD_NAME]
    bx    ip
    END_ENTRY method_invoke


    ENTRY method_invoke_stret
    # a3 is method triplet instead of SEL
    ldr    ip, [a3, #METHOD_IMP]
    ldr    a3, [a3, #METHOD_NAME]
    bx    ip
    END_ENTRY method_invoke_stret

#endif
