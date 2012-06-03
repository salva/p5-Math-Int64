/* -*- Mode: C -*- */

#define PERL_NO_GET_CONTEXT 1

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

static HV *capi_hash;

static int may_die_on_overflow;
static int may_use_native;

#ifdef __MINGW32__
#include <stdint.h>
#endif

#ifdef _MSC_VER
#include <stdlib.h>
typedef __int64 int64_t;
typedef unsigned __int64 uint64_t;

#ifndef INT64_MAX
#define INT64_MAX _I64_MAX
#endif
#ifndef INT64_MIN
#define INT64_MIN _I64_MIN
#endif
#ifndef UINT64_MAX
#define UINT64_MAX _UI64_MAX
#endif
#ifndef UINT32_MAX
#define UINT32_MAX _UI32_MAX
#endif

#endif

#if (PERL_VERSION >= 10)

#ifndef cop_hints_fetch_pvs
#define cop_hints_fetch_pvs(cop, key, flags) \
    Perl_refcounted_he_fetch(aTHX_ (cop)->cop_hints_hash, NULL, STR_WITH_LEN(key), (flags), 0)
#endif

static int
check_die_on_overflow_hint(pTHX) {
    SV *hint = cop_hints_fetch_pvs(PL_curcop, "Math::Int64::die_on_overflow", 0);
    return (hint && SvTRUE(hint));
}

static int
check_use_native_hint(pTHX) {
    SV *hint = cop_hints_fetch_pvs(PL_curcop, "Math::Int64::native_if_available", 0);
    return (hint && SvTRUE(hint));
}

#define use_native (may_use_native && check_use_native_hint(aTHX))

#else

static int
check_die_on_overflow_hint(pTHX) {
    return 1;
}

static int
check_use_native_hint(pTHX) {
    return 1;
}

#define use_native may_use_native

#endif



static void
overflow(pTHX_ char *msg) {
    if (check_die_on_overflow_hint(aTHX))
        Perl_croak(aTHX_ "Math::Int64 overflow: %s", msg);
}

static char *out_of_bounds_error_s = "number is out of bounds for int64_t conversion";
static char *out_of_bounds_error_u = "number is out of bounds for uint64_t conversion";
static char *mul_error            = "multiplication overflows";
static char *add_error            = "addition overflows";
static char *sub_error            = "subtraction overflows";
static char *inc_error            = "increment operation wraps";
static char *dec_error            = "decrement operation wraps";
static char *left_b_error         = "left-shift right operand is out of bounds";
static char *left_error           = "left shift overflows";
static char *right_b_error        = "right-shift right operand is out of bounds";
static char *right_error          = "right shift overflows";

#include "strtoint64.h"
#include "isaac64.h"

#if defined(INT64_BACKEND_NV)
#  define BACKEND "NV"
#  define SvI64Y SvNVX
#  define SvI64_onY SvNOK_on
#  define SVt_I64 SVt_NV
#elif defined(INT64_BACKEND_IV)
#  define BACKEND "IV"
#  define SvI64Y SvIVX
#  define SvI64_onY SvIOK_on
#  define SVt_I64 SVt_IV
#else
#  error "unsupported backend"
#endif

static int
SvI64OK(pTHX_ SV *sv) {
    if (SvROK(sv)) {
        SV *si64 = SvRV(sv);
        return (si64 && (SvTYPE(si64) >= SVt_I64) && sv_isa(sv, "Math::Int64"));
    }
    return 0;
}

static int
SvU64OK(pTHX_ SV *sv) {
    if (SvROK(sv)) {
        SV *su64 = SvRV(sv);
        return (su64 && (SvTYPE(su64) >= SVt_I64) && sv_isa(sv, "Math::UInt64"));
    }
    return 0;
}

static SV *
newSVi64(pTHX_ int64_t i64) {
    SV *sv;
    SV *si64 = newSV(0);
    SvUPGRADE(si64, SVt_I64);
    *(int64_t*)(&(SvI64Y(si64))) = i64;
    SvI64_onY(si64);
    sv = newRV_noinc(si64);
    sv_bless(sv, gv_stashpvs("Math::Int64", TRUE));
    return sv;
}

static SV *
newSVu64(pTHX_ uint64_t u64) {
    SV *sv;
    SV *su64 = newSV(0);
    SvUPGRADE(su64, SVt_I64);
    *(int64_t*)(&(SvI64Y(su64))) = u64;
    SvI64_onY(su64);
    sv = newRV_noinc(su64);
    sv_bless(sv, gv_stashpvs("Math::UInt64", TRUE));
    return sv;
}

#define SvI64X(sv) (*(int64_t*)(&(SvI64Y(SvRV(sv)))))
#define SvU64X(sv) (*(uint64_t*)(&(SvI64Y(SvRV(sv)))))

static SV *
SvSI64(pTHX_ SV *sv) {
    if (SvRV(sv)) {
        SV *si64 = SvRV(sv);
        if (si64 && (SvTYPE(si64) >= SVt_I64))
            return si64;
    }
    Perl_croak(aTHX_ "internal error: reference to NV expected");
}

static SV *
SvSU64(pTHX_ SV *sv) {
    if (SvRV(sv)) {
        SV *su64 = SvRV(sv);
        if (su64 && (SvTYPE(su64) >= SVt_I64))
            return su64;
    }
    Perl_croak(aTHX_ "internal error: reference to NV expected");
}

#define SvI64x(sv) (*(int64_t*)(&(SvI64Y(SvSI64(aTHX_ sv)))))
#define SvU64x(sv) (*(uint64_t*)(&(SvI64Y(SvSU64(aTHX_ sv)))))

static int64_t
SvI64(pTHX_ SV *sv) {
    if (SvROK(sv)) {
        SV *si64 = SvRV(sv);
        if (si64 && SvOBJECT(si64)) {
            GV *method;
            HV *stash = SvSTASH(si64);
            char const * classname = HvNAME_get(stash);
            if (strncmp(classname, "Math::", 6) == 0) {
                int u;
                if (classname[6] == 'U') {
                    u = 1;
                    classname += 7;
                }
                else {
                    u = 0;
                    classname += 6;
                }
                if (strcmp(classname, "Int64") == 0) {
                    if (SvTYPE(si64) < SVt_I64)
                        Perl_croak(aTHX_ "Wrong internal representation for %s object", HvNAME_get(stash));
                    if (u) {
                        uint64_t u = *(uint64_t*)(&(SvI64Y(si64)));
                        if (may_die_on_overflow && (u > INT64_MAX)) overflow(aTHX_ out_of_bounds_error_s);
                        return u;
                    }
                    else {
                        return *(int64_t*)(&(SvI64Y(si64)));
                    }
                }
            }
            method = gv_fetchmethod(stash, "as_int64");
            if (method) {
                SV *result;
                int count;
                dSP;
                ENTER;
                SAVETMPS;
                PUSHSTACKi(PERLSI_MAGIC);
                PUSHMARK(SP);
                XPUSHs(sv);
                PUTBACK;
                count = perl_call_sv( (SV*)method, G_SCALAR );
                SPAGAIN;
                if (count != 1)
                    Perl_croak(aTHX_ "internal error: method call returned %d values, 1 expected", count);
                result = newSVsv(POPs);
                PUTBACK;
                POPSTACK;
                SPAGAIN;
                FREETMPS;
                LEAVE;
                return SvI64(aTHX_ sv_2mortal(result));
            }
        }
    }
    else {
        SvGETMAGIC(sv);
        if (SvIOK(sv)) {
            if (SvIOK_UV(sv)) {
                UV uv = SvUV(sv);
                if (may_die_on_overflow &&
                    (uv > INT64_MAX)) overflow(aTHX_ out_of_bounds_error_s);
                return uv;
            }
            return SvIV(sv);
        }
        if (SvNOK(sv)) {
            NV nv = SvNV(sv);
            if (may_die_on_overflow) {
#ifdef _MSC_VER
                int64_t i64 = nv;
                if ((NV)i64 != nv) overflow(aTHX_ out_of_bounds_error_s);
#else
                if ((nv >= 0x1p63) || (nv < -0x1p63)) overflow(aTHX_ out_of_bounds_error_s);
#endif
	    }
            return nv;
        }
    }
    return strtoint64(aTHX_ SvPV_nolen(sv), 10, 1);
}

static uint64_t
SvU64(pTHX_ SV *sv) {
    if (SvROK(sv)) {
        SV *su64 = SvRV(sv);
        if (su64 && SvOBJECT(su64)) {
            GV *method;
            HV *stash = SvSTASH(su64);
            char const * classname = HvNAME_get(stash);
            if (strncmp(classname, "Math::", 6) == 0) {
                int u;
                if (classname[6] == 'U') {
                    u = 1;
                    classname += 7;
                }
                else {
                    u = 0;
                    classname += 6;
                }
                if (strcmp(classname, "Int64") == 0) {
                    if (SvTYPE(su64) < SVt_I64)
                        Perl_croak(aTHX_ "Wrong internal representation for %s object", HvNAME_get(stash));
                    if (u) {
                        return *(uint64_t*)(&(SvI64Y(su64)));
                    }
                    else {
                        int64_t i = *(int64_t*)(&(SvI64Y(su64)));
                        if (may_die_on_overflow && (i < 0)) overflow(aTHX_ out_of_bounds_error_u);
                        return i;
                    }
                }
            }
            method = gv_fetchmethod(SvSTASH(su64), "as_uint64");
            if (method) {
                SV *result;
                int count;
                dSP;
                ENTER;
                SAVETMPS;
                PUSHSTACKi(PERLSI_MAGIC);
                PUSHMARK(SP);
                XPUSHs(sv);
                PUTBACK;
                count = perl_call_sv( (SV*)method, G_SCALAR );
                SPAGAIN;
                if (count != 1)
                    Perl_croak(aTHX_ "internal error: method call returned %d values, 1 expected", count);
                result = newSVsv(POPs);
                PUTBACK;
                POPSTACK;
                SPAGAIN;
                FREETMPS;
                LEAVE;
                return SvU64(aTHX_ sv_2mortal(result));
            }
        }
    }
    else {
        SvGETMAGIC(sv);
        if (SvIOK(sv)) {
            if (SvIOK_UV(sv)) {
                return SvUV(sv);
            }
            else {
                IV iv = SvIV(sv);
                if (may_die_on_overflow &&
                    (iv < 0) ) overflow(aTHX_ out_of_bounds_error_u);
                return SvIV(sv);
            }
        }
        if (SvNOK(sv)) {
            NV nv = SvNV(sv);
            // fprintf(stderr, "        nv: %15f\nuint64_max: %15f\n", nv, (NV)UINT64_MAX);
            if (may_die_on_overflow) {
#ifdef _MSC_VER
	      uint64_t u64 = nv;
	      if ((NV)u64 != nv) overflow(aTHX_ out_of_bounds_error_u);
#else
	      if ((nv < 0) || (nv >= 0x1p64)) overflow(aTHX_ out_of_bounds_error_u);
#endif
	    }
            return nv;
        }
    }
    return strtoint64(aTHX_ SvPV_nolen(sv), 10, 0);
}

static SV *
si64_to_number(pTHX_ SV *sv) {
    int64_t i64 = SvI64(aTHX_ sv);
    if (i64 < 0) {
        IV iv = i64;
        if (iv == i64)
            return newSViv(iv);
    }
    else {
        UV uv = i64;
        if (uv == i64)
            return newSVuv(uv);
    }
    return newSVnv(i64);
}

static SV *
su64_to_number(pTHX_ SV *sv) {
    uint64_t u64 = SvU64(aTHX_ sv);
    UV uv = u64;
    if (uv == u64)
        return newSVuv(uv);
    return newSVnv(u64);
}

#define I64STRLEN 65

static SV *
u64_to_string_with_sign(pTHX_ uint64_t u64, int base, int sign) {
    char str[I64STRLEN];
    int len = 0;
    if ((base > 36) || (base < 2))
        Perl_croak(aTHX_ "base %d out of range [2,36]", base);
    while (u64) {
        char c = u64 % base;
        u64 /= base;
        str[len++] = c + (c > 9 ? 'A' - 10 : '0');
    }
    if (len) {
        int i;
        int svlen = len + (sign ? 1 : 0);
        SV *sv = newSV(svlen);
        char *pv = SvPVX(sv);
        SvPOK_on(sv);
        SvCUR_set(sv, svlen);
        if (sign) *(pv++) = '-';
        for (i = len; i--;) *(pv++) = str[i];
        return sv;
    }
    else {
        return newSVpvs("0");
    }
}

static SV *
i64_to_string(pTHX_ int64_t i64, int base) {
    if (i64 < 0) {    
        return u64_to_string_with_sign(aTHX_ -i64, base, 1);
    }
    return u64_to_string_with_sign(aTHX_ i64, base, 0);
}

MODULE = Math::Int64		PACKAGE = Math::Int64		PREFIX=miu64_
PROTOTYPES: DISABLE

BOOT:
    may_die_on_overflow = 0;
    may_use_native = 0;
    capi_hash = get_hv("Math::Int64::C_API", TRUE|GV_ADDMULTI);
    hv_stores(capi_hash, "version", newSViv(1));
    hv_stores(capi_hash, "newSVi64", newSViv(PTR2IV(&newSVi64)));
    hv_stores(capi_hash, "newSVu64", newSViv(PTR2IV(&newSVu64)));
    hv_stores(capi_hash, "SvI64", newSViv(PTR2IV(&SvI64)));
    hv_stores(capi_hash, "SvU64", newSViv(PTR2IV(&SvU64)));
    hv_stores(capi_hash, "SvI64OK", newSViv(PTR2IV(&SvI64OK)));
    hv_stores(capi_hash, "SvU64OK", newSViv(PTR2IV(&SvU64OK)));
    randinit(0);

char *
miu64__backend()
CODE:
    RETVAL = BACKEND;
OUTPUT:
    RETVAL

void
miu64__set_may_die_on_overflow(v)
    int v
CODE:
    may_die_on_overflow = v;

void
miu64__set_may_use_native(v)
    int v;
CODE:
    may_use_native = v;

SV *
miu64_int64(value=&PL_sv_undef)
    SV *value;
CODE:
    RETVAL = (use_native
              ? newSViv(SvIV(value))
              : newSVi64(aTHX_ SvI64(aTHX_ value)));
OUTPUT:
    RETVAL

SV *
miu64_uint64(value=&PL_sv_undef)
    SV *value;
CODE:
    RETVAL = (use_native
              ? newSVuv(SvUV(value))
              : newSVu64(aTHX_ SvU64(aTHX_ value)));
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
    int64_t i64;
CODE:
    if (len != 8) Perl_croak(aTHX_ "Invalid length for int64");
    i64 = (((((((((((((((int64_t)pv[0]) << 8)
                      + (int64_t)pv[1]) << 8)
                    + (int64_t)pv[2]) << 8)
                  + (int64_t)pv[3]) << 8)
                + (int64_t)pv[4]) << 8)
              + (int64_t)pv[5]) << 8)
            + (int64_t)pv[6]) <<8)
        + (int64_t)pv[7];
    RETVAL = ( use_native
               ? newSViv(i64)
               : newSVi64(aTHX_ i64) );
OUTPUT:
    RETVAL

SV *
miu64_net_to_uint64(net)
    SV *net;
PREINIT:
    STRLEN len;
    unsigned char *pv = (unsigned char *)SvPV(net, len);
    uint64_t u64;
CODE:
    if (len != 8)
        Perl_croak(aTHX_ "Invalid length for uint64");
    u64 = (((((((((((((((uint64_t)pv[0]) << 8)
                      + (uint64_t)pv[1]) << 8)
                    + (uint64_t)pv[2]) << 8)
                  + (uint64_t)pv[3]) << 8)
                + (uint64_t)pv[4]) << 8)
              + (uint64_t)pv[5]) << 8)
            + (uint64_t)pv[6]) <<8)
        + (uint64_t)pv[7];
    RETVAL = ( use_native
               ? newSVuv(u64)
               : newSVu64(aTHX_ u64) );
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
    if (use_native) {
        RETVAL = newSViv(0);
        Copy(pv, &(SvIVX(RETVAL)), 8, char);
    }
    else {
        RETVAL = newSVi64(aTHX_ 0);
        Copy(pv, &(SvI64X(RETVAL)), 8, char);
    }
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
    if (use_native) {
        RETVAL = newSVuv(0);
        Copy(pv, &(SvUVX(RETVAL)), 8, char);
    }
    else {
        RETVAL = newSVu64(aTHX_ 0);
        Copy(pv, &(SvU64X(RETVAL)), 8, char);
    }
OUTPUT:
    RETVAL

SV *
miu64_int64_to_native(self)
    SV *self
PREINIT:
    char *pv;
    int64_t i64 = SvI64(aTHX_ self);
CODE:
    RETVAL = newSV(9);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, 8);
    pv = SvPVX(RETVAL);
    Copy(&i64, pv, 8, char);
    pv[8] = '\0';
OUTPUT:
    RETVAL

SV *
miu64_uint64_to_native(self)
    SV *self
PREINIT:
    char *pv;
    uint64_t u64 = SvU64(aTHX_ self);
CODE:
    RETVAL = newSV(9);
    SvPOK_on(RETVAL);
    SvCUR_set(RETVAL, 8);
    pv = SvPVX(RETVAL);
    Copy(&u64, pv, 8, char);
    pv[8] = '\0';
OUTPUT:
    RETVAL

SV *
miu64_int64_to_string(self, base = 10)
    SV *self
    int base
CODE:
    RETVAL = i64_to_string(aTHX_ SvI64(aTHX_ self), base);
OUTPUT:
    RETVAL

SV *
miu64_uint64_to_string(self, base = 10)
    SV *self
    int base
CODE:
    RETVAL = u64_to_string_with_sign(aTHX_ SvU64(aTHX_ self), base, 0);
OUTPUT:
    RETVAL

SV *
miu64_int64_to_hex(self)
    SV *self
CODE:
    RETVAL = i64_to_string(aTHX_ SvI64(aTHX_ self), 16);
OUTPUT:
    RETVAL

SV *
miu64_uint64_to_hex(self)
    SV *self
CODE:
    RETVAL = u64_to_string_with_sign(aTHX_ SvU64(aTHX_ self), 16, 0);
OUTPUT:
    RETVAL

SV *
miu64_string_to_int64(str, base = 0)
    const char *str;
    int base;
CODE:
    RETVAL = ( use_native
               ? newSViv(strtoint64(aTHX_ str, base, 1))
               : newSVi64(aTHX_ strtoint64(aTHX_ str, base, 1)) );
OUTPUT:
    RETVAL

SV *
miu64_string_to_uint64(str, base = 0)
    const char *str;
    int base;
CODE:
    RETVAL = ( use_native
               ? newSVuv(strtoint64(aTHX_ str, base, 0))
               : newSVu64(aTHX_ strtoint64(aTHX_ str, base, 0)) );
OUTPUT:
    RETVAL

SV *
miu64_hex_to_int64(str)
    const char *str;
CODE:
    RETVAL = ( use_native
               ? newSViv(strtoint64(aTHX_ str, 16, 1))
               : newSVi64(aTHX_ strtoint64(aTHX_ str, 16, 1)) );
OUTPUT:
    RETVAL

SV *
miu64_hex_to_uint64(str)
    const char *str;
CODE:
    RETVAL = ( use_native
               ? newSVuv(strtoint64(aTHX_ str, 16, 0))
               : newSVu64(aTHX_ strtoint64(aTHX_ str, 16, 0)) );
OUTPUT:
    RETVAL


SV *
miu64_int64_rand()
PREINIT:
    int64_t i64 = rand64();
CODE:
    RETVAL = ( use_native
               ? newSViv(i64)
               : newSVi64(aTHX_ i64) );
OUTPUT:
    RETVAL

SV *
miu64_uint64_rand()
PREINIT:
    uint64_t u64 = rand64();
CODE:
    RETVAL = ( use_native
               ? newSViv(u64)
               : newSVu64(aTHX_ u64) );
OUTPUT:
    RETVAL

void
miu64_int64_srand(seed=&PL_sv_undef)
    SV *seed
PREINIT:
CODE:
    if (SvOK(seed) && SvCUR(seed)) {
        STRLEN len;
        const char *pv = SvPV_const(seed, len);
        char *shadow = (char*)randrsl;
        int i;
        if (len > sizeof(randrsl)) len = sizeof(randrsl);
        Zero(shadow, sizeof(randrsl), char);
        Copy(pv, shadow, len, char);

        /* make the seed endianness agnostic */
        for (i = 0; i < RANDSIZ; i++) {
            char *p = shadow + i * sizeof(uint64_t);
            randrsl[i] = (((((((((((((((uint64_t)p[0]) << 8) + p[1]) << 8) + p[2]) << 8) + p[3]) << 8) +
                               p[4]) << 8) + p[5]) << 8) + p[6]) << 8) + p[7];
    }
        randinit(1);
    }
    else
        randinit(0);

MODULE = Math::Int64		PACKAGE = Math::Int64		PREFIX=mi64
PROTOTYPES: DISABLE

SV *
mi64_inc(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    if (may_die_on_overflow && (SvI64x(self) == INT64_MAX)) overflow(aTHX_ inc_error);
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
    if (may_die_on_overflow && (SvI64x(self) == INT64_MIN)) overflow(aTHX_ dec_error);
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
PREINIT:
    int64_t a = SvI64x(self);
    int64_t b = SvI64(aTHX_ other);
CODE:
    if ( may_die_on_overflow &&
         ( a > 0
           ? ( (b > 0) && (INT64_MAX - a < b) )
           : ( (b < 0) && (INT64_MIN - a > b) ) ) ) overflow(aTHX_ add_error);
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ a + b);
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) = a + b;
    }
OUTPUT:
    RETVAL

SV *
mi64_sub(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    int64_t a = SvI64x(self);
    int64_t b = SvI64(aTHX_ other);
CODE:
    if (SvTRUE(rev)) {
        int64_t tmp = a;
        a = b; b = tmp;
    }
    if ( may_die_on_overflow &&
         ( a > 0
           ? ( ( b < 0) && (a - INT64_MAX > b) )
           : ( ( b > 0) && (a - INT64_MIN < b) ) ) ) overflow(aTHX_ sub_error);
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ a - b);
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) = a - b;
    }
OUTPUT:
    RETVAL

SV *
mi64_mul(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    int64_t a1 = SvI64x(self);
    int64_t b1 = SvI64(aTHX_ other);
CODE:
    if (may_die_on_overflow) {
        int neg = 0;
        uint64_t a, b, rl, rh;
        if (a1 < 0) {
            a = -a1;
            neg ^= 1;
        }
        else a = a1;
        if (b1 < 0) {
            b = -b1;
            neg ^= 1;
        }
        else b = b1;
        if (a < b) {
            uint64_t tmp = a;
            a = b; b = tmp;
        }
        if (b > UINT32_MAX) overflow(aTHX_ mul_error);
        else {
            rl = (a & UINT32_MAX) * b;
            rh = (a >> 32) * b + (rl >> 32);
            if (rh > UINT32_MAX) overflow(aTHX_ mul_error);
        }
        if (a * b > (neg ? (~(uint64_t)INT64_MIN + 1) : INT64_MAX)) overflow(aTHX_ mul_error);
    }
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ a1 * b1);
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvI64x(self) = a1 * b1;
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
PREINIT:
    int64_t a;
    uint64_t b;
CODE:
    if (SvTRUE(rev)) {
        a = SvI64(aTHX_ other);
        b = SvU64x(self);
    }
    else {
        a = SvI64x(self);
        b = SvU64(aTHX_ other);
    }
    if (may_die_on_overflow && (b > 64)) overflow(aTHX_ left_error);
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ (b > 64 ? 0 : (a << b)));
    else {
        RETVAL = SvREFCNT_inc(self);
        SvI64x(self) = (b > 64 ? 0 : (a << b));
    }
OUTPUT:
    RETVAL

SV *mi64_right(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    int64_t a;
    uint64_t b;
    if (SvTRUE(rev)) {
        a = SvI64(aTHX_ other);
        b = SvU64x(self);
    }
    else {
        a = SvI64x(self);
        b = SvU64(aTHX_ other);
    }
    if (may_die_on_overflow && (b > 64)) overflow(aTHX_ right_error);
    if (SvOK(rev))
        RETVAL = newSVi64(aTHX_ a >> b);
    else {
        RETVAL = SvREFCNT_inc(self);
        SvI64x(self) = (a >> b);
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
    SV *rev
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
    SV *rev
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
CODE:
    RETVAL = i64_to_string(aTHX_ SvI64x(self), 10);
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
    if (may_die_on_overflow && (SvU64x(self) == UINT64_MAX)) overflow(aTHX_ inc_error);
    SvU64x(self)++;
    RETVAL = SvREFCNT_inc(self);
OUTPUT:
    RETVAL

SV *
mu64_dec(self, other, rev)
    SV *self
    SV *other = NO_INIT
    SV *rev = NO_INIT
CODE:
    if (may_die_on_overflow && (SvU64x(self) == 0)) overflow(aTHX_ dec_error);
    SvU64x(self)--;
    RETVAL = SvREFCNT_inc(self);
OUTPUT:
    RETVAL

SV *
mu64_add(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    uint64_t a = SvU64x(self);
    uint64_t b = SvU64(aTHX_ other);
    if (may_die_on_overflow && (UINT64_MAX - a < b)) overflow(aTHX_ add_error);
    if (SvOK(rev)) 
        RETVAL = newSVu64(aTHX_ a + b);
    else {
        RETVAL = self;
        SvREFCNT_inc(RETVAL);
        SvU64x(self) = a + b;
    }
OUTPUT:
    RETVAL

SV *
mu64_sub(self, other, rev)
    SV *self
    SV *other
    SV *rev
PREINIT:
    uint64_t a, b;
CODE:
    if (SvTRUE(rev)) {
        a = SvU64(aTHX_ other);
        b = SvU64x(self);
    }
    else {
        a = SvU64x(self);
        b = SvU64(aTHX_ other);
    }
    if (may_die_on_overflow && (b > a)) overflow(aTHX_ sub_error);
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ a - b);
    else {
        RETVAL = SvREFCNT_inc(self);
        SvU64x(self) = a - b;
    }
OUTPUT:
    RETVAL

SV *
mu64_mul(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    int64_t a = SvU64x(self);
    int64_t b = SvU64(aTHX_ other);
    if (may_die_on_overflow) {
        if (a < b) {
            uint64_t tmp = a;
            a = b; b = tmp;
        }
        if (b > UINT32_MAX) overflow(aTHX_ mul_error);
        else {
            uint64_t rl, rh;
            rl = (a & UINT32_MAX) * b;
            rh = (a >> 32) * b + (rl >> 32);
            if (rh > UINT32_MAX) overflow(aTHX_ mul_error);
        }
    }
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ a * b);
    else {
        RETVAL = SvREFCNT_inc(self);
        SvU64x(self) = a * b;
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
    uint64_t a;
    uint64_t b;
    if (SvTRUE(rev)) {
        a = SvU64(aTHX_ other);
        b = SvU64x(self);
    }
    else {
        a = SvU64x(self);
        b = SvU64(aTHX_ other);
    }
    if (may_die_on_overflow && (b > 64)) overflow(aTHX_ left_b_error);
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ a << b);
    else {
        RETVAL = SvREFCNT_inc(self);
        SvU64x(self) = (a << b);
    }
OUTPUT:
    RETVAL

SV *mu64_right(self, other, rev)
    SV *self
    SV *other
    SV *rev
CODE:
    uint64_t a;
    uint64_t b;
    if (SvTRUE(rev)) {
        a = SvU64(aTHX_ other);
        b = SvU64x(self);
    }
    else {
        a = SvU64x(self);
        b = SvU64(aTHX_ other);
    }
    if ( may_die_on_overflow && (b > 64)) overflow(aTHX_ right_b_error);
    if (SvOK(rev))
        RETVAL = newSVu64(aTHX_ a >> b);
    else {
        RETVAL = SvREFCNT_inc(self);
        SvU64x(self) = (a >> b);
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
    SV *rev
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
    SV *rev
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
    RETVAL = newSVu64(aTHX_ ~(SvU64x(self)-1));
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
CODE:
    RETVAL = u64_to_string_with_sign(aTHX_ SvU64x(self), 10, 0);
OUTPUT:
    RETVAL
