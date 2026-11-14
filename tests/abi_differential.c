/*
 * The differential program: one sequence of C ABI operations, compiled
 * twice -- against upstream's libtr7 and against this library -- and the
 * two reports are diffed by scripts/diff_upstream.sh.
 *
 * Only operations the two implementations agree on functionally are
 * included; the documented deviations (tr7_load_string's error return,
 * make_string_fill above byte range, eqv on distinct doubles, error
 * objects after a failed evaluation) are deliberately excluded.  Values
 * are reported through each library's own accessors, so the two sides
 * need not share an encoding.
 *
 * Built with -DTR7_UPSTREAM_LIBS="path", the upstream side first imports
 * (scheme r5rs) from the upstream checkout's tr7libs, because a bare
 * upstream engine has an empty environment; this library's engine comes
 * with the core bindings already global.  Either way both sides then run
 * the same operations.
 */
#include "tr7.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static tr7_engine_t E;
static unsigned long step;

static void pint(const char *name, long v)
{
   printf("%s: %ld\n", name, v);
   fflush(stdout);
}

static void pstr(const char *name, const char *s)
{
   printf("%s: %s\n", name, s);
   fflush(stdout);
}

static void pdbl(const char *name, double v)
{
   char buf[64];
   snprintf(buf, sizeof buf, "%.17g", v);
   pstr(name, buf);
}

int main(void)
{
   tr7_t one, two, three, nine, l, l2, r, s, sym, vec, kv, found;
   tr7_t items[2];
   tr7_t cars[4];
   tr7_t cdr;
   double zero = 0.0;

   E = tr7_engine_create(NULL);
   if (E == NULL) {
      pstr("engine", "fail");
      return 1;
   }
   pstr("engine", "ok");

#ifdef TR7_UPSTREAM_LIBS
   /* A bare upstream engine binds nothing; give it the same operations
    * through the r5rs library shipped in the upstream checkout. */
   tr7_set_string(E, Tr7_StrID_Library_Path, TR7_UPSTREAM_LIBS);
   (void)tr7_import_lib(E, "scheme/r5rs");
#endif

   /* ---- immediates ---- */
   one = tr7_from_int(E, 1);
   two = tr7_from_int(E, 2);
   three = tr7_from_int(E, 3);
   nine = tr7_from_int(E, 9);
   pint("int-rt", (long)tr7_to_int(one));
   pint("int-neg-rt", (long)tr7_to_int(tr7_from_int(E, -42)));
   pint("isint", tr7_is_integer(one));
   pint("isint-nil", tr7_is_integer(TR7_NIL));
   pint("eq", tr7_eq(one, tr7_from_int(E, 1)));
   pint("eq-ne", tr7_eq(one, two));
   pint("eqv", tr7_eqv(one, tr7_from_int(E, 1)));
   pint("equal-imm", tr7_equal(one, tr7_from_int(E, 1)));

   pint("char-rt", (long)tr7_to_character(tr7_from_character(E, 'A')));
   pint("ischar", tr7_is_character(tr7_from_character(E, 'A')));
   pint("ischar-int", tr7_is_character(one));
   pint("isunicar", tr7_is_unicode_character(tr7_from_character(E, 'A')));
   pint("charuni", tr7_is_char_unicode(0x10FFFF));
   pint("charuni-surrogate", tr7_is_char_unicode(0xD800));

   /* ---- pairs and lists ---- */
   l = tr7_cons(E, one, tr7_cons(E, two, tr7_cons(E, three, TR7_NIL)));
   pint("cons-len", tr7_list_length(l));
   pint("cons-car", (long)tr7_to_int(tr7_car_or_void(l)));
   pint("cons-cadr", (long)tr7_to_int(tr7_cadr_or_void(l)));
   pint("cons-caddr", (long)tr7_to_int(tr7_caddr_or_void(l)));
   pint("cons-cdddr", TR7_IS_NIL(tr7_cdddr_or_void(l)));
   pint("len-atom", tr7_list_length(one));
   pint("len-nil", tr7_list_length(TR7_NIL));
   pint("len-dotted", tr7_list_length(tr7_cons(E, one, two)));
   pint("unsafe-len-dotted", tr7_unsafe_list_length(tr7_cons(E, one, two)));
   pint("car-atom-void", TR7_IS_VOID(tr7_car_or_void(one)));
   pint("equal-pairs", tr7_equal(tr7_cons(E, one, TR7_NIL),
                                 tr7_cons(E, one, TR7_NIL)));
   pint("eq-pairs", tr7_eq(tr7_cons(E, one, TR7_NIL),
                           tr7_cons(E, one, TR7_NIL)));

   l2 = tr7_reverse(E, l, TR7_NIL);
   pint("rev-len", tr7_list_length(l2));
   pint("rev-car", (long)tr7_to_int(tr7_car_or_void(l2)));
   pint("rev-in-place", (long)tr7_to_int(tr7_car_or_void(
              tr7_reverse_in_place(tr7_reverse(E, l, TR7_NIL), TR7_NIL))));

   items[0] = tr7_cons(E, one, TR7_NIL);
   items[1] = tr7_cons(E, two, TR7_NIL);
   pint("append-len", tr7_list_length(tr7_append(E, 2, items)));
   items[0] = two;
   pint("append-single-shared", tr7_eq(tr7_append(E, 1, items), two));

   kv = tr7_cons(E, tr7_cons(E, one, two), TR7_NIL);
   found = tr7_assq(one, kv);
   pint("assq-hit", found != TR7_FALSE);
   pint("assq-val", (long)tr7_to_int(tr7_cdr_or_void(found)));
   pint("assq-miss", TR7_IS_FALSE(tr7_assq(nine, kv)));
   pint("memq-hit", tr7_memq(two, l) != TR7_FALSE);
   pint("memq-miss", TR7_IS_FALSE(tr7_memq(nine, l)));

   {
      int n = tr7_get_list_cars(l, 4, cars, &cdr);
      pint("cars-n", n);
      pint("cars-c0", (long)tr7_to_int(cars[0]));
      pint("cars-c2", (long)tr7_to_int(cars[2]));
      pint("cars-cdr", TR7_IS_NIL(cdr));
   }

   /* ---- strings and symbols ---- */
   s = tr7_make_string_copy(E, "abc");
   pint("isstr", tr7_is_string(s));
   pint("strsize", (long)tr7_string_size(s));
   pint("strlen", (long)tr7_string_length(s));
   pstr("strbuf", tr7_string_buffer(s));
   pint("strref", (long)tr7_string_ref(s, 1));
   pint("strset", tr7_string_set(E, s, 0, 'X'));
   pstr("strbuf2", tr7_string_buffer(s));
   pint("strset-oob", tr7_string_set(E, s, 9, 'Y'));

   sym = tr7_get_symbol(E, "hello", 1);
   pint("issym", tr7_is_symbol(sym));
   pint("symsize", (long)tr7_symbol_size(sym));
   pstr("symname", tr7_symbol_string(sym));
   pint("symeq", tr7_equal(sym, tr7_get_symbol(E, "hello", 1)));
   pint("lookup-miss", TR7_IS_FALSE(tr7_symbol_lookup(E, "nope", 4, 0, 0)));

   /* ---- vectors ---- */
   vec = tr7_make_vector_fill(E, 3, one);
   pint("veclen", (long)tr7_vector_length(vec));
   pint("vecref", (long)tr7_to_int(tr7_vector_ref(vec, 2)));
   pint("vecset", (long)tr7_to_int(tr7_vector_set(vec, 0, two)));
   pint("v2l", tr7_list_length(tr7_vector_to_list(E, vec)));
   pint("l2v", (long)tr7_vector_length(tr7_list_to_vector(E, l)));

   /* ---- numbers ---- */
   pint("isnum-int", tr7_is_number(one));
   pint("isexact-int", tr7_is_exact(one));
   pint("isnum-dbl", tr7_is_number(tr7_from_double(E, 1.5)));
   pint("isreal-dbl", tr7_is_real(tr7_from_double(E, 1.5)));
   pint("isexact-dbl", tr7_is_exact(tr7_from_double(E, 1.5)));
   pdbl("todbl", tr7_to_double(tr7_from_double(E, 2.5)));
   pint("isinf", tr7_is_infinite(tr7_from_double(E, 1.0 / zero)));
   pint("isnan", tr7_is_NaN(tr7_from_double(E, zero / zero)));
   pint("isfinite-int", tr7_is_finite(one));

   /* ---- evaluation (part B: needs an environment on both sides) ---- */
   pint("run-good", tr7_run_string(E, "(+ 40 2)"));
   pint("run-err", tr7_run_string(E, "(car 5)"));
   pint("load-good", tr7_load_string(E, "(+ 1 2)"));

   r = tr7_from_utf8(E, "(+ 1 2)");
   pint("read-not-eof", TR7_IS_EOF(r) ? 0 : 1);
   pint("read-not-void", TR7_IS_VOID(r) ? 0 : 1);
   pint("eval", (long)tr7_to_int(tr7_eval(E, r)));
   pint("values-count", (long)tr7_get_values_count(E));
   pint("last-value", (long)tr7_to_int(tr7_get_last_value(E)));

   pint("apply0", (long)tr7_to_int(tr7_apply0(E, "+")));

   tr7_define(E, TR7_VOID, tr7_from_utf8(E, "dzz"), tr7_from_int(E, 7));
   pint("define", (long)tr7_to_int(tr7_eval(E, tr7_from_utf8(E, "dzz"))));

   pint("import-srfi1", tr7_import_lib(E, "srfi/1") == 0 ? 1 : 0);
   pint("iota", (long)tr7_to_int(tr7_eval(E, tr7_from_utf8(E,
              "(length (iota 3))"))));

   tr7_engine_destroy(E);
   pstr("done", "ok");
   return 0;
}
