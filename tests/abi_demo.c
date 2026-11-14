/*
 * The C ABI demo: identify the library, build a configuration, create
 * engines, load good and failing source, and exercise the value ABI --
 * constructors, accessors, list/string/symbol/vector operations, printing,
 * evaluation -- plus the negative cases every wrapper must answer
 * gracefully (null engine, null command, bad config, unaligned and
 * unregistered engine pointers, out-of-range requests).
 *
 * Every line the Ada side writes is flushed, and so is every printf here:
 * the two buffering domains must not be allowed to reorder the report.
 * Expected output: tests/abi.expected.
 */
#include "tr7.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>

static int fail(const char *why)
{
   fprintf(stderr, "abi demo: %s\n", why);
   return 1;
}

#define CHECK(cond, why)                                                    \
   do {                                                                     \
      if (!(cond)) {                                                        \
         tr7_engine_destroy(eng);                                           \
         tr7_engine_destroy(eng2);                                          \
         return fail(why);                                                  \
      }                                                                     \
   } while (0)

int main(void)
{
   tr7_config_t cfg;
   tr7_engine_t eng;
   tr7_engine_t eng2;
   tr7_t a, b, l, l2, s, sym, v, r;
   tr7_t cars[4];
   tr7_t cdr;

   printf("id=%s version=%s\n", tr7_get_id(), tr7_get_version());
   fflush(stdout);

   tr7_config_init_default(&cfg);
   eng = tr7_engine_create(&cfg);
   if (eng == NULL)
      return fail("engine_create(&cfg)");

   eng2 = tr7_engine_create(NULL);
   if (eng2 == NULL) {
      tr7_engine_destroy(eng);
      return fail("engine_create(NULL)");
   }
   tr7_engine_destroy(eng2);

   if (!tr7_load_string(eng, "(display \"abi ok\")(newline)")) {
      tr7_engine_destroy(eng);
      return fail("good source rejected");
   }
   fflush(stdout);

   /* load traps errors: zero means the error was reported and we continue */
   if (tr7_load_string(eng, "(error \"boom\")")) {
      tr7_engine_destroy(eng);
      return fail("error source accepted");
   }
   fflush(stdout);

   /* the engine survives a trapped error and keeps working */
   if (!tr7_load_string(eng, "(display \"still alive\")(newline)")) {
      tr7_engine_destroy(eng);
      return fail("engine dead after a trapped error");
   }
   fflush(stdout);

   /* ---- exact integers, upstream's bit encoding ---- */
   a = tr7_from_int(eng, 42);
   b = tr7_from_int(eng, -7);
   CHECK(TR7_IS_INT(a) && tr7_is_integer(a), "from_int lost the encoding");
   CHECK(tr7_to_int(a) == 42 && tr7_to_int(b) == -7, "to_int round trip");
   CHECK(tr7_eq(a, tr7_from_int(eng, 42)) && tr7_eqv(a, a)
         && tr7_equal(a, tr7_from_int(eng, 42)), "eq family on ints");
   CHECK(TR7_IS_NIL(tr7_from_int(eng, 1L << 40)), "out-of-range int not NIL");
   printf("int=%ld neg=%ld big=nil=%d eq=%d\n", (long)tr7_to_int(a),
          (long)tr7_to_int(b), TR7_IS_NIL(tr7_from_int(eng, 1L << 40)),
          tr7_eq(a, tr7_from_int(eng, 42)));
   fflush(stdout);

   /* ---- characters and booleans ---- */
   a = tr7_from_character(eng, 'A');
   CHECK(TR7_IS_CHAR(a) && tr7_is_character(a) && tr7_is_unicode_character(a)
         && tr7_to_character(a) == 'A', "character round trip");
   CHECK(tr7_is_char_unicode(0x1F600) && !tr7_is_char_unicode(0xD800),
         "unicode predicate");
   CHECK(tr7_get_values_count(eng) == 1, "the slot holds the last load");
   printf("char=%c uni=%d\n", (int)tr7_to_character(a),
          tr7_is_unicode_character(a));
   fflush(stdout);

   /* ---- pairs, the cXr family, list lengths ---- */
   a = tr7_from_int(eng, 1);
   b = tr7_from_int(eng, 2);
   l = tr7_cons(eng, a, tr7_cons(eng, b, TR7_NIL));
   CHECK(tr7_list_length(l) == 2, "list_length");
   CHECK(tr7_to_int(tr7_car_or_void(l)) == 1
         && tr7_to_int(tr7_cadr_or_void(l)) == 2
         && TR7_IS_NIL(tr7_cddr_or_void(l)), "car/cdr walk");
   CHECK(tr7_list_length(tr7_from_int(eng, 9)) == -2, "length of an atom");
   CHECK(tr7_cdr_or_void(a) == TR7_VOID, "cdr of an atom is VOID");
   l2 = tr7_reverse(eng, l, TR7_NIL);
   CHECK(tr7_list_length(l2) == 2
         && tr7_to_int(tr7_car_or_void(l2)) == 2, "reverse");
   r = tr7_cons(eng, b, a);              /* (2 . 1) */
   CHECK(tr7_list_length(r) == -3, "dotted length");
   CHECK(tr7_get_list_cars(l, 4, cars, &cdr) == 2 && TR7_IS_NIL(cdr)
         && tr7_to_int(cars[0]) == 1 && tr7_to_int(cars[1]) == 2,
         "get_list_cars");
   printf("len=%d rev=%ld dotted=%d cars=%d\n", tr7_list_length(l),
          (long)tr7_to_int(tr7_car_or_void(l2)), tr7_list_length(r),
          tr7_get_list_cars(l, 4, cars, &cdr));
   fflush(stdout);

   /* ---- append, search ---- */
   {
      tr7_t items[2];
      items[0] = l;
      items[1] = tr7_cons(eng, tr7_from_int(eng, 3), TR7_NIL);
      l2 = tr7_append(eng, 2, items);
      CHECK(tr7_list_length(l2) == 3, "append length");
   }
   {
      tr7_t kv = tr7_cons(eng, tr7_cons(eng, a, b), TR7_NIL);
      tr7_t found = tr7_assq(a, kv);
      CHECK(found != TR7_FALSE
            && tr7_to_int(tr7_cdr_or_void(found)) == 2, "assq");
      CHECK(TR7_IS_FALSE(tr7_assq(tr7_from_int(eng, 9), kv)), "assq miss");
   }
   CHECK(tr7_memq(b, l) != TR7_FALSE
         && TR7_IS_FALSE(tr7_memq(tr7_from_int(eng, 9), l)), "memq");
   printf("app=%d mem=%d\n", tr7_list_length(l2), tr7_memq(b, l) != TR7_FALSE);
   fflush(stdout);

   /* ---- strings and symbols ---- */
   s = tr7_make_string_copy(eng, "abc");
   CHECK(tr7_is_string(s) && tr7_string_size(s) == 3
         && tr7_string_length(s) == 3
         && strcmp(tr7_string_buffer(s), "abc") == 0
         && tr7_string_ref(s, 0) == 'a', "string round trip");
   CHECK(tr7_string_set(eng, s, 0, 'X') == 1
         && tr7_string_ref(s, 0) == 'X', "string_set");
   CHECK(tr7_string_set(eng, s, 5, 'Y') == 0, "string_set out of range");
   CHECK(tr7_make_string_fill(eng, 0x263A, 1) == TR7_NIL,
         "non-byte string rejected");
   sym = tr7_get_symbol(eng, "hello", 1);
   CHECK(tr7_is_symbol(sym) && tr7_symbol_size(sym) == 5
         && strcmp(tr7_symbol_string(sym), "hello") == 0
         && tr7_equal(sym, tr7_get_symbol(eng, "hello", 1)), "symbol");
   CHECK(TR7_IS_FALSE(tr7_symbol_lookup(eng, "nope", 4, 0, 0)),
         "symbol lookup without create");
   printf("str=%s sym=%s look=%d\n", tr7_string_buffer(s),
          tr7_symbol_string(sym),
          TR7_IS_FALSE(tr7_symbol_lookup(eng, "nope", 4, 0, 0)));
   fflush(stdout);

   /* ---- vectors ---- */
   v = tr7_make_vector_fill(eng, 3, a);
   CHECK(tr7_vector_length(v) == 3
         && tr7_to_int(tr7_vector_ref(v, 2)) == 1, "vector fill");
   CHECK(tr7_vector_set(v, 0, b) == b
         && tr7_to_int(tr7_vector_ref(v, 0)) == 2, "vector set");
   CHECK(tr7_vector_ref(v, 9) == TR7_VOID, "vector_ref out of range");
   CHECK(tr7_vector_length(tr7_vector_to_list(eng, v)) == 0
          && tr7_list_length(tr7_vector_to_list(eng, v)) == 3
          && tr7_vector_length(tr7_list_to_vector(eng, l)) == 2,
         "vector/list conversions");
   printf("vec=%ld v2l=%ld l2v=%ld\n", (long)tr7_to_int(tr7_vector_ref(v, 0)),
          (long)tr7_list_length(tr7_vector_to_list(eng, v)),
          (long)tr7_vector_length(tr7_list_to_vector(eng, l)));
   fflush(stdout);

   /* ---- printing ---- */
   tr7_write(eng, a);                   /* 1 */
   tr7_display_string(eng, " ");
   tr7_display(eng, s);                 /* Xbc, unquoted */
   tr7_display_string(eng, "\n");
   tr7_write(eng, l);                   /* (1 2) */
   tr7_display_string(eng, "\n");
   tr7_flush(eng);
   fflush(stdout);

   /* ---- evaluation and the value slot ---- */
   r = tr7_from_utf8(eng, "(+ 1 2)");
   CHECK(!TR7_IS_VOID(r) && !TR7_IS_EOF(r), "read a datum");
   a = tr7_eval(eng, r);
   CHECK(tr7_to_int(a) == 3, "eval (+ 1 2)");
   CHECK(tr7_get_values_count(eng) == 1
         && tr7_to_int(tr7_get_last_value(eng)) == 3
         && tr7_to_int(tr7_get_value(eng, 0)) == 3
         && TR7_IS_VOID(tr7_get_value(eng, 1)), "value slot");
   r = tr7_apply0(eng, "+");
   CHECK(tr7_to_int(r) == 0, "apply0 (+) is 0");
   printf("eval=%ld apply0=%ld slot=%u\n", (long)tr7_to_int(a),
          (long)tr7_to_int(r), tr7_get_values_count(eng));
   fflush(stdout);

   /* ---- tr7_define, then read the binding back ---- */
   sym = tr7_from_utf8(eng, "zz");
   tr7_define(eng, TR7_VOID, sym, tr7_from_int(eng, 7));
   a = tr7_eval(eng, tr7_from_utf8(eng, "zz"));
   CHECK(tr7_to_int(a) == 7, "define + eval");
   printf("defined=%ld\n", (long)tr7_to_int(a));
   fflush(stdout);

   /* ---- import a library and use it ---- */
   CHECK(tr7_import_lib(eng, "srfi/1") == 0, "import (srfi 1)");
   a = tr7_eval(eng, tr7_from_utf8(eng, "(length (iota 3))"));
   CHECK(tr7_to_int(a) == 3, "srfi 1 through the ABI");
   printf("imported=%ld\n", (long)tr7_to_int(a));
   fflush(stdout);

   /* ---- run_string: no trapping, 0 on error ---- */
   CHECK(tr7_run_string(eng, "(+ 40 2)") == 1, "run good source");
   CHECK(tr7_run_string(eng, "(car 5)") == 0, "run failing source");
   CHECK(TR7_IS_VOID(tr7_get_last_value(eng)), "a failed run clears the slot");

   /* ---- negative cases: every wrapper answers gracefully ---- */
   CHECK(tr7_cons(NULL, a, TR7_NIL) == TR7_NIL, "cons with a null engine");
   CHECK(tr7_load_string(NULL, "(+ 1 2)") == 0, "load with a null engine");
   CHECK(tr7_load_string(eng, NULL) == 0, "load with a null command");
   CHECK(tr7_run_string(NULL, "(+ 1 2)") == 0, "run with a null engine");
   CHECK(tr7_get_symbol(NULL, "x", 1) == TR7_NIL, "symbol with null engine");
   CHECK(tr7_eval((tr7_engine_t)((intptr_t)eng + 1), a) == TR7_VOID,
         "eval with an unaligned engine");
   CHECK(tr7_eval((tr7_engine_t)(uintptr_t)&cfg, a) == TR7_VOID,
         "eval with an unregistered engine");
   CHECK(tr7_string_buffer(a) == NULL, "string_buffer of a non-string");
   CHECK(tr7_vector_length(a) == 0 && tr7_vector_ref(a, 0) == TR7_VOID,
         "vector accessors of a non-vector");
   CHECK(tr7_memq(a, a) == TR7_FALSE, "memq of a non-list");
   CHECK(tr7_eval(eng, TR7_VOID) == TR7_VOID, "eval of the absent value");
   {
      tr7_config_t bad = cfg;
      bad.malloc = NULL;
      CHECK(tr7_engine_create(&bad) == NULL, "config without an allocator");
      bad.malloc = cfg.malloc;
      bad.main_dictionary_size = 0;
      CHECK(tr7_engine_create(&bad) == NULL, "config without a dictionary");
   }
   printf("negatives ok\n");
   fflush(stdout);

   tr7_engine_destroy(eng);
   printf("abi: ok\n");
   return 0;
}
