/* -*- Mode: C -*- */

#define PERL_NO_GET_CONTEXT 1

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

static HV *package_int64_stash;
static HV *package_uint64_stash;

#ifdef __MINGW32__
#include <stdint.h>
#include <stdlib.h>
#define INT64_HAS_ATOLL
#endif

#ifdef _MSC_VER
#include <stdlib.h>
typedef __int64 int64_t;
typedef unsigned __int64 uint64_t;
#define INT64_HAS__ATOI64;

#define atoll _atoi64
#define strtoull _strtoui64
#endif

#if !defined(INT64_HAS_ATOLL)
#  if defined(INT64_HAS_STRTOLL)
#    define atoll(x) strtoll((x), NULL, 10)
#  elif defined(INT64_HAS__ATOI64)
#    define atoll(x) _atoi64(x)
#  else
#    error "no int64 parsing function available from C library"
#  endif
#endif

#if !defined(INT64_HAS_ATOULL)
#  if defined(INT64_HAS_STRTOULL)
#    define atoull(x) strtoull((x), NULL, 10)
#  else
#    define atoull(x) atoll(x)
#  endif
#endif

#if defined(INT64_BACKEND_DOUBLE)

int
SvI64OK(pTHX_ SV *sv) {
    if (SvROK(sv)) {
        SV *si64 = SvRV(sv);
        return (si64 && (SvTYPE(si64) == SVt_PVMG) && sv_isa(sv, "Math::Int64"));
    }
    return 0;
}

int
SvU64OK(pTHX_ SV *sv) {
    if (SvROK(sv)) {
        SV *su64 = SvRV(sv);
        return (su64 && (SvTYPE(su64) == SVt_PVMG) && sv_isa(sv, "Math::UInt64"));
    }
    return 0;
}

SV *
newSVi64(pTHX_ int64_t i64) {
    SV *sv;
    SV *si64 = newSV(0);
    SvUPGRADE(si64, SVt_PVMG);
    *(int64_t*)(&(SvNVX(si64))) = i64;
    sv = newRV_noinc(si64);
    sv_bless(sv, package_int64_stash);
    return sv;
}

SV *
newSVu64(pTHX_ uint64_t u64) {
    SV *sv;
    SV *su64 = newSV(0);
    SvUPGRADE(su64, SVt_PVMG);
    *(int64_t*)(&(SvNVX(su64))) = u64;
    sv = newRV_noinc(su64);
    sv_bless(sv, package_uint64_stash);
    return sv;
}

#define SvI64X(sv) (*(int64_t*)(&(SvNVX(SvRV(sv)))))

#define SvU64X(sv) (*(uint64_t*)(&(SvNVX(SvRV(sv)))))

SV *
SvSI64(pTHX_ SV *sv) {
    if (SvRV(sv)) {
        SV *si64 = SvRV(sv);
        if (si64 && (SvTYPE(si64) == SVt_PVMG))
            return si64;
    }
    Perl_croak(aTHX_ "internal error: reference to NV expected");
}

SV *
SvSU64(pTHX_ SV *sv) {
    if (SvRV(sv)) {
        SV *su64 = SvRV(sv);
        if (su64 && (SvTYPE(su64) == SVt_PVMG))
            return su64;
    }
    Perl_croak(aTHX_ "internal error: reference to NV expected");
}

#define SvI64x(sv) (*(int64_t*)(&(SvNVX(SvSI64(aTHX_ sv)))))

#define SvU64x(sv) (*(uint64_t*)(&(SvNVX(SvSU64(aTHX_ sv)))))

int64_t
SvI64(pTHX_ SV *sv) {
    if (!SvOK(sv)) {
        return 0;
    }
    if (SvIOK_UV(sv)) {
        return SvUV(sv);
    }
    if (SvIOK(sv)) {
        return SvIV(sv);
    }
    if (SvNOK(sv)) {
        return SvNV(sv);
    }
    if (SvROK(sv)) {
        SV *si64 = SvRV(sv);
        if (si64 && (SvTYPE(si64) == SVt_PVMG) && (sv_isa(sv, "Math::Int64") || sv_isa(sv, "Math::UInt64"))) {
            return *(int64_t*)(&(SvNVX(si64)));
        }
    }
    return atoll(SvPV_nolen(sv));
}

uint64_t
SvU64(pTHX_ SV *sv) {
    if (!SvOK(sv)) {
        return 0;
    }
    if (SvIOK_UV(sv)) {
        return SvUV(sv);
    }
    if (SvIOK(sv)) {
        return SvIV(sv);
    }
    if (SvNOK(sv)) {
        return SvNV(sv);
    }
    if (SvROK(sv)) {
        SV *su64 = SvRV(sv);
        if (su64 && (SvTYPE(su64) == SVt_PVMG) && (sv_isa(sv, "Math::UInt64")) || sv_isa(sv, "Math::Int64"))
            return *(uint64_t*)(&(SvNVX(su64)));
    }
    return atoull(SvPV_nolen(sv));
}

SV *
si64_to_number(pTHX_ SV *sv) {
    int64_t i64 = SvI64x(sv);
    IV iv;
    UV uv;
    uv = i64;
    if (uv == i64)
        return newSVuv(uv);
    iv = i64;
    if (iv == i64)
        return newSViv(iv);
    return newSVnv(i64);
}

SV *
su64_to_number(pTHX_ SV *sv) {
    uint64_t u64 = SvU64x(sv);
    IV iv;
    UV uv;
    uv = u64;
    if (uv == u64)
        return newSVuv(uv);
    iv = u64;
    if (iv == u64)
        return newSViv(iv);
    return newSVnv(u64);
}

#elif defined(INT64_BACKEND_STRING)

#elif defined(INT64_BACKEND_NATIVE)

#endif


MODULE = Math::Int64		PACKAGE = Math::Int64		PREFIX=miu64_
PROTOTYPES: DISABLE

BOOT:
package_int64_stash = gv_stashsv(newSVpv("Math::Int64", 0), 1);
package_uint64_stash = gv_stashsv(newSVpv("Math::UInt64", 0), 1);

SV *
miu64_int64(value=&PL_sv_undef)
    SV *value;
CODE:
    RETVAL = newSVi64(aTHX_ SvI64(aTHX_ value));
OUTPUT:
    RETVAL

SV *
miu64_uint64(value=&PL_sv_undef)
    SV *value;
CODE:
    RETVAL = newSVu64(aTHX_ SvU64(aTHX_ value));
OUTPUT:
    RETVAL

SV *
miu64_int64_to_number(self)
    SV *self
CODE:
    RETVAL = si64_to_number(aTHX_ self);
OUTPUT:
    RETVAL

SV *
miu64_uint64_to_number(self)
    SV *self
CODE:
    RETVAL = su64_to_number(aTHX_ self);
OUTPUT:
    RETVAL

SV *
miu64_net_to_int64(net)
    SV *net;
PREINIT:
    STRLEN len;
    unsigned char *pv = (unsigned char *)SvPV(net, len);
CODE:
    if (len != 8)
        Perl_croak(aTHX_ "Invalid length for int64");
    RETVAL = newSVi64(aTHX_
                      (((((((((((((((int64_t)pv[0]) << 8)
                                  + (int64_t)pv[1]) << 8)
                                  + (int64_t)pv[2]) << 8)
                                  + (int64_t)pv[3]) << 8)
                                  + (int64_t)pv[4]) << 8)
                                  + (int64_t)pv[5]) << 8)
                                  + (int64_t)pv[6]) <<8)
                                  + (int64_t)pv[7]);
OUTPUT:
    RETVAL

SV *
miu64_net_to_uint64(net)
    SV *net;
PREINIT:
    STRLEN len;
    unsigned char *pv = (unsigned char *)SvPV(net, len);
CODE:
    if (len != 8)
        Perl_croak(aTHX_ "Invalid length for uint64");
    RETVAL = newSVu64(aTHX_
                      (((((((((((((((uint64_t)pv[0]) << 8)
                                  + (uint64_t)pv[1]) << 8)
                                  + (uint64_t)pv[2]) << 8)
                                  + (uint64_t)pv[3]) << 8)
                                  + (uint64_t)pv[4]) << 8)
                                  + (uint64_t)pv[5]) << 8)
                                  + (uint64_t)pv[6]) <<8)
                                  + (uint64_t)pv[7]);
OUTPUT:
    RETVAL

SV *
miu64_int64_to_net(self)
    SV *self
PREINIT:
    char *pv;
    int64_t i64 = SvI64(aTHX_ self);
    int i;
CODE:
    RETVAL = newSV(8);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, 8);
    pv = SvPVX(RETVAL);
    pv[8] = '\0';
    for (i = 7; i >= 0; i--, i64 >>= 8)
        pv[i] = i64;
OUTPUT:
    RETVAL

SV *
miu64_uint64_to_net(self)
    SV *self
PREINIT:
    char *pv;
    uint64_t u64 = SvU64(aTHX_ self);
    int i;
CODE:
    RETVAL = newSV(8);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, 8);
    pv = SvPVX(RETVAL);
    pv[8] = '\0';
    for (i = 7; i >= 0; i--, u64 >>= 8)
        pv[i] = u64;
OUTPUT:
    RETVAL

SV *
miu64_native_to_int64(native)
    SV *native
PREINIT:
    STRLEN len;
    char *pv = SvPV(native, len);
CODE:
    if (len != 8)
        Perl_croak(aTHX_ "Invalid length for int64");
    RETVAL = newSVi64(aTHX_ 0);
    Copy(pv, &(SvI64X(RETVAL)), 8, char);
OUTPUT:
    RETVAL

SV *
miu64_native_to_uint64(native)
    SV *native
PREINIT:
    STRLEN len;
    char *pv = SvPV(native, len);
CODE:
    if (len != 8)
        Perl_croak(aTHX_ "Invalid length for uint64");
    RETVAL = newSVu64(aTHX_ 0);
    Copy(pv, &(SvU64X(RETVAL)), 8, char);
OUTPUT:
    RETVAL

SV *
miu64_int64_to_native(self)
    SV *self
PREINIT:
    char *pv;
    int64_t i64 = SvI64(aTHX_ self);
CODE:
    RETVAL = newSV(8);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, 8);
    pv = SvPVX(RETVAL);
    Copy(&i64, pv, 8, char);
OUTPUT:
    RETVAL

SV *
miu64_uint64_to_native(self)
    SV *self
PREINIT:
    char *pv;
    uint64_t u64 = SvU64(aTHX_ self);
CODE:
    RETVAL = newSV(8);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, 8);
    pv = SvPVX(RETVAL);
    Copy(&u64, pv, 8, char);
OUTPUT:
    RETVAL


MODULE = Math::Int64		PACKAGE = Math::Int64		PREFIX=mi64
PROTOTYPES: DISABLE

SV *
mi64_inc(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    SvI64x(self)++;
    RETVAL = self;
    SvREFCNT_inc(RETVAL);
OUTPUT:
    RETVAL

SV *
mi64_dec(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    SvI64x(self)--;
    RETVAL = self;
    SvREFCNT_inc(RETVAL);
OUTPUT:
    RETVAL

SV *
mi64_add(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    /*
    fprintf(stderr, "self: ");
    sv_dump(self);
    fprintf(stderr, "other: ");
    sv_dump(other);
    fprintf(stderr, "rev: ");
    sv_dump(rev);
    fprintf(stderr, "\n");
    */
    if (SvOK(rev)) 
        RETVAL = newSVi64(aTHX_ SvI64x(self) + SvI64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) += SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mi64_sub(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_
                          SvTRUE(rev)
                          ? SvI64(aTHX_ other) - SvI64x(self)
                          : SvI64x(self) - SvI64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) -= SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mi64_mul(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ SvI64x(self) * SvI64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) *= SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mi64_div(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    int64_t up;
    int64_t down;
CODE:
    if (SvOK(rev)) {
        if (SvTRUE(rev)) {
            up = SvI64(aTHX_ other);
            down = SvI64x(self);
        }
        else {
            up = SvI64x(self);
            down = SvI64(aTHX_ other);
        }
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = newSVi64(aTHX_ up/down);
    }
    else {
        down = SvI64(aTHX_ other);
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) /= down;
    }
OUTPUT:
    RETVAL

SV *
mi64_rest(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    int64_t up;
    int64_t down;
CODE:
    if (SvOK(rev)) {
        if (SvTRUE(rev)) {
            up = SvI64(aTHX_ other);
            down = SvI64x(self);
        }
        else {
            up = SvI64x(self);
            down = SvI64(aTHX_ other);
        }
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = newSVi64(aTHX_ up % down);
    }
    else {
        down = SvI64(aTHX_ other);
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) %= down;
    }
OUTPUT:
    RETVAL

SV *mi64_left(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_
                          SvTRUE(rev)
                          ? SvI64(aTHX_ other) << SvI64x(self)
                          : SvI64x(self) << SvI64(aTHX_ other) );
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) <<= SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *mi64_right(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_
                          SvTRUE(rev)
                          ? SvI64(aTHX_ other) >> SvI64x(self)
                          : SvI64x(self) >> SvI64(aTHX_ other) );
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) >>= SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

int
mi64_spaceship(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    int64_t left;
    int64_t right;
CODE:
    if (SvTRUE(rev)) {
        left = SvI64(aTHX_ other);
        right = SvI64x(self);
    }
    else {
        left = SvI64x(self);
        right = SvI64(aTHX_ other);
    }
    RETVAL = (left < right ? -1 : left > right ? 1 : 0);
OUTPUT:
    RETVAL

SV *
mi64_eqn(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    RETVAL = ( SvI64x(self) == SvI64(aTHX_ other)
               ? &PL_sv_yes
               : &PL_sv_no );
OUTPUT:
    RETVAL

SV *
mi64_nen(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    RETVAL = ( SvI64x(self) != SvI64(aTHX_ other)
               ? &PL_sv_yes
               : &PL_sv_no );
OUTPUT:
    RETVAL

SV *
mi64_gtn(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvI64x(self) < SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvI64x(self) > SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mi64_ltn(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvI64x(self) > SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvI64x(self) < SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mi64_gen(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvI64x(self) <= SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvI64x(self) >= SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mi64_len(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvI64x(self) >= SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvI64x(self) <= SvI64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mi64_and(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ SvI64x(self) & SvI64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) &= SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mi64_or(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ SvI64x(self) | SvI64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) |= SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mi64_xor(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ SvI64x(self) ^ SvI64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) ^= SvI64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mi64_not(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = SvI64x(self) ? &PL_sv_no : &PL_sv_yes;
OUTPUT:
    RETVAL

SV *
mi64_bnot(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = newSVi64(aTHX_ ~SvI64x(self));
OUTPUT:
    RETVAL    

SV *
mi64_neg(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = newSVi64(aTHX_ -SvI64x(self));
OUTPUT:
    RETVAL

SV *
mi64_bool(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = SvI64x(self) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mi64_number(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = si64_to_number(aTHX_ self);
OUTPUT:
    RETVAL

SV *
mi64_clone(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = newSVi64(aTHX_ SvI64x(self));
OUTPUT:
    RETVAL

SV *
mi64_string(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
PREINIT:
    STRLEN len;
CODE:
    RETVAL = newSV(22);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, sprintf(SvPVX(RETVAL), "%lli", SvI64x(self)));
OUTPUT:
    RETVAL


MODULE = Math::Int64		PACKAGE = Math::UInt64		PREFIX=mu64
PROTOTYPES: DISABLE

SV *
mu64_inc(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    SvU64x(self)++;
    RETVAL = self;
    SvREFCNT_inc(RETVAL);
OUTPUT:
    RETVAL

SV *
mu64_dec(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    SvU64x(self)--;
    RETVAL = self;
    SvREFCNT_inc(RETVAL);
OUTPUT:
    RETVAL

SV *
mu64_add(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    /*
    fprintf(stderr, "self: ");
    sv_dump(self);
    fprintf(stderr, "other: ");
    sv_dump(other);
    fprintf(stderr, "rev: ");
    sv_dump(rev);
    fprintf(stderr, "\n");
    */
    if (SvOK(rev)) 
        RETVAL = newSVu64(aTHX_ SvU64x(self) + SvU64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) += SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mu64_sub(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_
                          SvTRUE(rev)
                          ? SvU64(aTHX_ other) - SvU64x(self)
                          : SvU64x(self) - SvU64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) -= SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mu64_mul(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ SvU64x(self) * SvU64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) *= SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mu64_div(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    uint64_t up;
    uint64_t down;
CODE:
    if (SvOK(rev)) {
        if (SvTRUE(rev)) {
            up = SvU64(aTHX_ other);
            down = SvU64x(self);
        }
        else {
            up = SvU64x(self);
            down = SvU64(aTHX_ other);
        }
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = newSVu64(aTHX_ up/down);
    }
    else {
        down = SvU64(aTHX_ other);
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) /= down;
    }
OUTPUT:
    RETVAL

SV *
mu64_rest(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    uint64_t up;
    uint64_t down;
CODE:
    if (SvOK(rev)) {
        if (SvTRUE(rev)) {
            up = SvU64(aTHX_ other);
            down = SvU64x(self);
        }
        else {
            up = SvU64x(self);
            down = SvU64(aTHX_ other);
        }
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = newSVu64(aTHX_ up % down);
    }
    else {
        down = SvU64(aTHX_ other);
        if (!down)
            Perl_croak(aTHX_ "Illegal division by zero");
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) %= down;
    }
OUTPUT:
    RETVAL

SV *mu64_left(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_
                          SvTRUE(rev)
                          ? SvU64(aTHX_ other) << SvU64x(self)
                          : SvU64x(self) << SvU64(aTHX_ other) );
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) <<= SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *mu64_right(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_
                          SvTRUE(rev)
                          ? SvU64(aTHX_ other) >> SvU64x(self)
                          : SvU64x(self) >> SvU64(aTHX_ other) );
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) >>= SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

int
mu64_spaceship(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    uint64_t left;
    uint64_t right;
CODE:
    if (SvTRUE(rev)) {
        left = SvU64(aTHX_ other);
        right = SvU64x(self);
    }
    else {
        left = SvU64x(self);
        right = SvU64(aTHX_ other);
    }
    RETVAL = (left < right ? -1 : left > right ? 1 : 0);
OUTPUT:
    RETVAL

SV *
mu64_eqn(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    RETVAL = ( SvU64x(self) == SvU64(aTHX_ other)
               ? &PL_sv_yes
               : &PL_sv_no );
OUTPUT:
    RETVAL

SV *
mu64_nen(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    RETVAL = ( SvU64x(self) != SvU64(aTHX_ other)
               ? &PL_sv_yes
               : &PL_sv_no );
OUTPUT:
    RETVAL

SV *
mu64_gtn(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvU64x(self) < SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvU64x(self) > SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mu64_ltn(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvU64x(self) > SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvU64x(self) < SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mu64_gen(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvU64x(self) <= SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvU64x(self) >= SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mu64_len(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvTRUE(rev))
        RETVAL = SvU64x(self) >= SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
    else
        RETVAL = SvU64x(self) <= SvU64(aTHX_ other) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mu64_and(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ SvU64x(self) & SvU64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) &= SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mu64_or(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ SvU64x(self) | SvU64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) |= SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mu64_xor(self, other, rev)
    SV *self
    SV *other
    SV *rev = NO_INIT
CODE:
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ SvU64x(self) ^ SvU64(aTHX_ other));
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) ^= SvU64(aTHX_ other);
    }
OUTPUT:
    RETVAL

SV *
mu64_not(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = SvU64x(self) ? &PL_sv_no : &PL_sv_yes;
OUTPUT:
    RETVAL

SV *
mu64_bnot(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = newSVu64(aTHX_ ~SvU64x(self));
OUTPUT:
    RETVAL    

SV *
mu64_neg(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = newSVu64(aTHX_ -SvU64x(self));
OUTPUT:
    RETVAL

SV *
mu64_bool(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = SvU64x(self) ? &PL_sv_yes : &PL_sv_no;
OUTPUT:
    RETVAL

SV *
mu64_number(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = su64_to_number(aTHX_ self);
OUTPUT:
    RETVAL

SV *
mu64_clone(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    RETVAL = newSVu64(aTHX_ SvU64x(self));
OUTPUT:
    RETVAL

SV *
mu64_string(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
PREINIT:
    STRLEN len;
CODE:
    RETVAL = newSV(22);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, sprintf(SvPVX(RETVAL), "%llu", SvU64x(self)));
OUTPUT:
    RETVAL








    
