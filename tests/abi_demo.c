/*
 * The C ABI demo: identify the library, build a configuration, create two
 * engines (one from the config, one from NULL), load good and failing
 * source, destroy both.  Expected output: tests/abi.expected.
 *
 * Every line the Ada side writes is flushed, and so is every printf here:
 * the two buffering domains must not be allowed to reorder the report.
 */
#include "tr7.h"
#include <stdio.h>

static int fail(const char *why)
{
   fprintf(stderr, "abi demo: %s\n", why);
   return 1;
}

int main(void)
{
   tr7_config_t cfg;
   tr7_engine_t eng;
   tr7_engine_t eng2;

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

   tr7_engine_destroy(eng);
   printf("abi: ok\n");
   return 0;
}
