--  C ABI layer: the second half of the trusted boundary, where C pointers and
--  the tr7.h entry points live.  The verified core never sees either.
--
--  The package is in SPARK and every signature is annotated with Pre/Post
--  contracts; each subprogram is individually SPARK_Mode => Off because its
--  body works with raw addresses, unchecked conversions and C stdio, and is
--  therefore trusted rather than proven.  The contracts are not dead text:
--  this crate builds with -gnata, so they are checked at run time, and the
--  C demo in tests/abi_demo.c exercises every one of them.
--
--  What is implemented here is a functional subset of the header: the six
--  entry points a host needs to run source text, plus a value ABI that
--  forwards to the verified core -- constructors, predicates and accessors
--  for immediates, pairs, strings, symbols and vectors, list operations,
--  printing, and evaluation (tr7_eval / tr7_define / tr7_apply0 /
--  tr7_run_string / tr7_import_lib).  Every other symbol declared by
--  include/tr7.h -- a copy of upstream TR7's header, 0BSD -- exists as a
--  generated stub in src/tr7_c_stubs.c; scripts/gen_abi.py produces that
--  file, --check proves the checked-in copy is current, and --check-lib
--  proves the built library defines every symbol the header declares.
--
--  Deliberate deviations from upstream, recorded in docs/architecture.md:
--  the engine keeps its arena in Ada's heap, so the custom allocators in
--  tr7_config_t are validated but not honored; tr7_t values carry this
--  implementation's own encoding -- bit-compatible with upstream for the
--  pure-integer immediates (fixnums, booleans, characters, TR7_NIL,
--  TR7_EOF, TR7_VOID) and for doubles, but engine-local opaque handles for
--  heap objects, so the TR7_IS_PAIR/TR7_CAR macros are not meaningful for
--  our heap values (use the tr7_cXr_or_void functions instead); output and
--  error text go to this process's C stdout, where tr7i writes them too.

with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;
with Tr7.Config;

use type Interfaces.C.Strings.chars_ptr;
use type Interfaces.C.int;
use type Interfaces.C.unsigned;
use type Interfaces.C.unsigned_long;
use type Interfaces.C.size_t;
use type Interfaces.C.ptrdiff_t;
use type Interfaces.Unsigned_64;
use type System.Address;

package Tr7_C with SPARK_Mode => On is

   --  tr7_t as the C header defines it: an intptr_t.  All the constants
   --  below are this implementation's (and, for immediates, upstream's)
   --  encodings; see the long comment at the value ABI for the layout.
   subtype Tr7_T is Interfaces.C.ptrdiff_t;

   Tr7_Void  : constant Tr7_T := 0;    --  TR7_VOID / TR7_MAKE_VSP (0, k) family:
   Tr7_Nil   : constant Tr7_T := 3;    --  TR7_NIL   = (0 << 5) | 3
   Tr7_False : constant Tr7_T := 35;   --  TR7_FALSE = (1 << 5) | 3
   Tr7_True  : constant Tr7_T := 67;   --  TR7_TRUE  = (2 << 5) | 3
   Tr7_Eof   : constant Tr7_T := 99;   --  TR7_EOF   = (3 << 5) | 3

   --  Upstream's TR7_CHAR_MAX on an LP64 host, and the null chars_ptr.
   Tr7_Char_Max   : constant := 16#FFFF_FFFF#;
   Tr7_Null_String : constant Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.Null_Ptr;

   --  Contract support: True when A sits on an engine-object boundary.  It
   --  is pure arithmetic on the address and never dereferences, so a
   --  contract may call it on any pointer, garbage included, without
   --  risking a fault inside the assertion itself.
   function Is_Aligned (A : System.Address) return Boolean
     with SPARK_Mode => Off;  --  trusted: raw-address arithmetic

   --  The config struct carries two pointers and is a different alignment
   --  fact from an Engine object.
   function Is_Aligned_Config (A : System.Address) return Boolean
     with SPARK_Mode => Off;  --  trusted: raw-address arithmetic

   --  Contract support for Config_Init_Default: True when the four fields
   --  at Config hold the defaults this package writes (or Config is null).
   --  It reads through a raw address, so it is trusted like the bodies;
   --  it is declared here only so that postcondition can name it.
   function Defaults_Written (Config : System.Address) return Boolean
     with SPARK_Mode => Off;  --  trusted: reads through a raw address

   --  The identity of this implementation.  The header's convention is
   --  that the id names the build and the version numbers it, so a host
   --  can tell this library from upstream's by asking for either.
   function Get_Id return Interfaces.C.Strings.chars_ptr
     with
       SPARK_Mode     => Off,  --  trusted: New_String allocates outside SPARK
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_id",
       Post           => Get_Id'Result /= Interfaces.C.Strings.Null_Ptr;

   function Get_Version return Interfaces.C.Strings.chars_ptr
     with
       SPARK_Mode     => Off,  --  trusted: New_String allocates outside SPARK
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_version",
       Post           => Get_Version'Result /= Interfaces.C.Strings.Null_Ptr;

   --  Fill a config with this package's defaults, as upstream's does.  A
   --  null pointer is accepted and does nothing; a non-null one must be
   --  aligned as its C type is (the struct carries two pointers), and is
   --  then guaranteed to hold the defaults.  The allocator fields are
   --  written but never honored: the arena lives in Ada's heap.
   procedure Config_Init_Default (Config : System.Address)
     with
       SPARK_Mode     => Off,  --  trusted: writes through a raw address
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_config_init_default",
       Pre            => Config = System.Null_Address
                         or else Is_Aligned_Config (Config),
       Post           => Config = System.Null_Address
                         or else Defaults_Written (Config);

   --  Create an engine.  Null means "use the defaults"; a non-null config
   --  must satisfy Config_Init_Default's pointer contract and, as
   --  upstream does, is rejected (null result) when it lacks an allocator
   --  pair or a dictionary size.  A non-null result is a fresh, aligned
   --  engine; null means every failure, so a host tests one thing.
   function Engine_Create (Config : System.Address) return System.Address
     with
       SPARK_Mode     => Off,  --  trusted: new and an unchecked conversion
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_engine_create",
       Pre            => Config = System.Null_Address
                         or else Is_Aligned_Config (Config),
       Post           => Engine_Create'Result = System.Null_Address
                         or else Is_Aligned (Engine_Create'Result);

   --  Destroy an engine returned by Engine_Create; null does nothing.
   --  Double destruction is the host's bug, as in C.  Nothing can be said
   --  after the call -- the memory is back with the allocator -- so there
   --  is deliberately no postcondition.
   procedure Engine_Destroy (Engine : System.Address)
     with
       SPARK_Mode     => Off,  --  trusted: an unchecked deallocation
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_engine_destroy",
       Pre            => Engine = System.Null_Address
                         or else Is_Aligned (Engine);

   --  Evaluate every datum of the NUL-terminated Cmd, write what the
   --  program printed to stdout, and report the first error the way tr7i
   --  does.  Returns 1 on success and 0 when the load failed: an error is
   --  reported and trapped, never raised, so the host carries on with the
   --  next load.  A null engine or command returns 0 rather than faulting.
   function Load_String
     (Engine : System.Address;
      Cmd    : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with
       SPARK_Mode     => Off,  --  trusted: C strings, stdio, evaluation
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_load_string",
       Pre            => Engine = System.Null_Address
                         or else Is_Aligned (Engine),
       Post           => Load_String'Result = 0
                         or else Load_String'Result = 1;

   ---------------------------------------------------------------------
   --  The value ABI.
   --
   --  A tr7_t in this implementation is one of:
   --
   --    * 0 -- TR7_VOID, the absent value, exactly as the header defines it;
   --    * a fixnum: (n << 2) | 1 -- upstream's own bit encoding, so the
   --      TR7_IS_INT / TR7_TO_INT / TR7_FROM_INT macros work on our values
   --      and on host-forged ones alike;
   --    * the VSP immediates: TR7_NIL = 3, TR7_FALSE = 35, TR7_TRUE = 67,
   --      TR7_EOF = 99 -- again upstream's exact encodings ((k << 5) | 3),
   --      so TR7_IS_NIL/TR7_IS_TRUE/... and TR7_FROM_CHAR all work;
   --    * a character: (code << 5) | 11, upstream's encoding;
   --    * a double: a tagged pointer (tag 6) to a stable 8-byte double this
   --      package owns until the engine is destroyed, so TR7_IS_DOUBLE and
   --      TR7_TO_DOUBLE work and host-forged TR7_FROM_DOUBLE values deref;
   --    * a heap value (pair, symbol, string, vector, ...): an opaque,
   --      engine-local handle -- (engine_id << 47) | (generation << 15) |
   --      (cell_index << 3) | tag 2.  It carries the owning engine, the
   --      arena cell's index and its generation, so every accessor can
   --      resolve it and reject a stale one.  This is the one place this
   --      ABI is deliberately NOT bit-compatible with upstream (whose heap
   --      values are real tagged pointers): the macros TR7_IS_PAIR /
   --      TR7_IS_STRING / ... are not meaningful here, the tr7_* functions
   --      are.  Needs a 64-bit intptr_t (LP64); heap constructors return
   --      TR7_NIL on a 32-bit host.
   --
   --  Immediates need no engine, so the pure constructors accept a null
   --  one; every wrapper that touches engine state validates its engine
   --  and its host pointers in the body and returns the documented failure
   --  value (TR7_NIL / TR7_VOID / NULL / 0) instead of faulting.  The
   --  posts are run-time checked (-gnata): each predicate returns 0/1 and
   --  each constructor returns either the encoding its argument names or
   --  the failure constant.
   ---------------------------------------------------------------------

   --  Contract support.  The encoding is plain bit arithmetic, but on the
   --  signed C integer type, so -- like Is_Aligned above -- these are
   --  trusted bodies over unchecked conversions; they never dereference
   --  and are safe to call on any value a host can forge.
   function Is_Fixnum_T (T : Tr7_T) return Boolean
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   function Decode_Int_Of (T : Tr7_T) return Tr7_T
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   function Is_Char_T (T : Tr7_T) return Boolean
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   function Decode_Char_Of (T : Tr7_T) return Interfaces.Unsigned_64
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   --  The fixnum bit pattern of an integer, (n << 2) | 1: what Tr7_From_Int
   --  builds.  In the contracts so decode-after-encode round trips exactly.
   function Encode_Int_Bits (Value : Tr7_T) return Tr7_T
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   function Is_Double_T (T : Tr7_T) return Boolean
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   function Is_Heap_T (T : Tr7_T) return Boolean
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   function Is_Any_Value_T (T : Tr7_T) return Boolean
     with SPARK_Mode => Off;  --  trusted: bit arithmetic over a UC

   --  eq? is raw equality of the encodings: immediates are canonical, so
   --  content, and a heap handle is its identity -- the same answer
   --  upstream's TR7EQ gives.
   function Tr7_Eq (A, B : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,  --  trusted: C ABI, encoding arithmetic
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_eq",
       Post           => Tr7_Eq'Result = 0 or else Tr7_Eq'Result = 1;

   --  eqv?: the same relation here -- immediates are canonical and heap
   --  values are identities, so eqv agrees with eq.  (Upstream's eqv on
   --  two equal-but-distinct doubles is 0; ours is 1 because doubles are
   --  cached -- R7RS eqv on equal inexact numbers, not upstream's accident.)
   function Tr7_Eqv (A, B : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_eqv",
       Post           => Tr7_Eqv'Result = 0 or else Tr7_Eqv'Result = 1;

   --  equal?: structural equality over pairs, strings, symbols and
   --  vectors; bounded, so a cyclic structure answers 0 instead of
   --  hanging (upstream loops forever; ours is the documented deviation).
   function Tr7_Equal (A, B : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_equal",
       Post           => Tr7_Equal'Result = 0 or else Tr7_Equal'Result = 1;

   --  The exact-integer constructor.  The verified core's fixnum range is
   --  -(2**31) .. 2**31 - 1 (docs/findings.md); a value outside it has no
   --  representation here and yields TR7_NIL, where upstream's range is
   --  62 bits -- a documented capacity limit, reported, not wrapped.
   --  Immediates need no engine: a null one is accepted.
   function Tr7_From_Int
     (Engine : System.Address;
      Value  : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_from_int",
       Post           => (if Value in Tr7.Config.Fixnum_Min .. Tr7.Config.Fixnum_Max
                          then Is_Fixnum_T (Tr7_From_Int'Result)
                            and then Decode_Int_Of (Tr7_From_Int'Result) = Value
                          else Tr7_From_Int'Result = Tr7_Nil);

   --  The exact-integer accessor.  The header says the caller guarantees a
   --  tr7 integer; a non-fixnum still answers 0 rather than garbage.
   function Tr7_To_Int (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_to_int",
       Post           => (if Is_Fixnum_T (T)
                          then Encode_Int_Bits (Tr7_To_Int'Result) = T
                          else Tr7_To_Int'Result = 0);

   function Tr7_Is_Integer (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_integer",
       Post           => Tr7_Is_Integer'Result = 0
                         or else Tr7_Is_Integer'Result = 1;

   --  A flonum.  The double lives in a per-engine arena (freed at engine
   --  destroy) and is cached by bit pattern, so equal doubles share one
   --  pointer and compare equal.  Needs the engine for that arena; a null
   --  engine answers TR7_NIL.
   function Tr7_From_Double
     (Engine : System.Address;
      Value  : Interfaces.C.double) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_from_double",
       Post           => Tr7_From_Double'Result = Tr7_Nil
                         or else Is_Double_T (Tr7_From_Double'Result);

   --  The flonum accessor.  TR7_FROM_DOUBLE makes a host double addressable
   --  as a value, so this dereferences any tag-6 pointer the host hands it
   --  -- the same trust the header's macro contract carries; null and the
   --  tag check keep it total on non-doubles.
   function Tr7_To_Double (T : Tr7_T) return Interfaces.C.double
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_to_double";

   --  True when the code point is a valid UNICODE scalar value (no
   --  surrogates, no values beyond 16#10FFFF#).
   function Tr7_Is_Char_Unicode (Value : Interfaces.C.unsigned_long)
     return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_char_unicode",
       Post           => Tr7_Is_Char_Unicode'Result = 0
                         or else Tr7_Is_Char_Unicode'Result = 1;

   --  A character value: upstream's bit encoding, so TR7_FROM_CHAR /
   --  TR7_TO_CHAR agree.  No engine needed.
   function Tr7_From_Character
     (Engine : System.Address;
      Value  : Interfaces.C.unsigned_long) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_from_character",
       Post           => Tr7_From_Character'Result = Tr7_Void
                         or else (Is_Char_T (Tr7_From_Character'Result)
                                  and then (if Value <= Tr7_Char_Max
                                   then Decode_Char_Of (Tr7_From_Character'Result)
                                     = Interfaces.Unsigned_64 (Value)));

   --  The character accessor; the caller guarantees a character, a
   --  non-character still answers 0 rather than garbage bits.
   function Tr7_To_Character (T : Tr7_T) return Interfaces.C.unsigned_long
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_to_character",
       Post           => (if Is_Char_T (T)
                          then Interfaces.Unsigned_64 (Tr7_To_Character'Result)
                            = Decode_Char_Of (T)
                          else Tr7_To_Character'Result = 0);
   function Tr7_Is_Character (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_character",
       Post           => Tr7_Is_Character'Result = 0
                         or else Tr7_Is_Character'Result = 1;

   function Tr7_Is_Unicode_Character (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_unicode_character",
       Post           => Tr7_Is_Unicode_Character'Result = 0
                         or else Tr7_Is_Unicode_Character'Result = 1;

   --  The safe cXr family: each walks its path of cars and cdrs and
   --  answers TR7_VOID when a step is not a pair.  Level 1..3 are here;
   --  the level-4 names remain generated stubs.
   function Tr7_Car_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_car_or_void",
       Post           => Tr7_Car_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Car_Or_Void'Result);

   function Tr7_Cdr_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cdr_or_void",
       Post           => Tr7_Cdr_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cdr_Or_Void'Result);

   function Tr7_Caar_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_caar_or_void",
       Post           => Tr7_Caar_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Caar_Or_Void'Result);

   function Tr7_Cadr_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cadr_or_void",
       Post           => Tr7_Cadr_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cadr_Or_Void'Result);

   function Tr7_Cdar_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cdar_or_void",
       Post           => Tr7_Cdar_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cdar_Or_Void'Result);

   function Tr7_Cddr_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cddr_or_void",
       Post           => Tr7_Cddr_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cddr_Or_Void'Result);

   function Tr7_Caaar_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_caaar_or_void",
       Post           => Tr7_Caaar_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Caaar_Or_Void'Result);

   function Tr7_Caadr_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_caadr_or_void",
       Post           => Tr7_Caadr_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Caadr_Or_Void'Result);

   function Tr7_Cadar_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cadar_or_void",
       Post           => Tr7_Cadar_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cadar_Or_Void'Result);

   function Tr7_Caddr_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_caddr_or_void",
       Post           => Tr7_Caddr_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Caddr_Or_Void'Result);

   function Tr7_Cdaar_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cdaar_or_void",
       Post           => Tr7_Cdaar_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cdaar_Or_Void'Result);

   function Tr7_Cdadr_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cdadr_or_void",
       Post           => Tr7_Cdadr_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cdadr_Or_Void'Result);

   function Tr7_Cddar_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cddar_or_void",
       Post           => Tr7_Cddar_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cddar_Or_Void'Result);

   function Tr7_Cdddr_Or_Void (T : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cdddr_or_void",
       Post           => Tr7_Cdddr_Or_Void'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Cdddr_Or_Void'Result);

   --  Pair constructor.  Needs the engine (null gives TR7_NIL); allocation
   --  failure -- a full arena -- gives TR7_NIL, exactly as the header says.
   --  No collection runs inside the ABI: the collector only runs at
   --  evaluator safe points, so values built and used between two loads
   --  are never swept -- and values the host keeps across an evaluation
   --  are unrooted, like upstream's, and can be collected (use and drop,
   --  or store them in the engine via tr7_define).
   function Tr7_Cons
     (Engine : System.Address;
      A, B   : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cons",
       Post           => Tr7_Cons'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Cons'Result);

   --  The (car[0] ... car[count-1] . cdr) constructor.  A negative count
   --  is a host bug and answers TR7_NIL; a null array with count > 0 too;
   --  count = 0 is exactly cdr.
   function Tr7_Cons_N
     (Engine : System.Address;
      Count  : Interfaces.C.int;
      Cars   : System.Address;
      Cdr    : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_cons_n",
       Post           => Tr7_Cons_N'Result = Tr7_Nil
                         or else Is_Any_Value_T (Tr7_Cons_N'Result);

   --  Length of a proper list; -1 for a cycle, -(length before the dot + 2)
   --  for an improper or non-list value ('(a b . c) -> -4, 42 -> -2), and 0
   --  for nil.  Bounded by the arena size, so a cycle terminates.
   function Tr7_List_Length (A : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_list_length",
       Post           => Tr7_List_Length'Result in 0 .. 4_096
                         or else Tr7_List_Length'Result = -1
                         or else Tr7_List_Length'Result in -4_097 .. -2;

   --  Length of a proper list without cycle checks, upstream's contract;
   --  -1 minus the length before the dot otherwise.  Upstream never
   --  returns on a cycle; ours is bounded and answers -1 - length seen
   --  (a documented deviation that cannot hang a host).
   function Tr7_Unsafe_List_Length (A : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_unsafe_list_length",
       Post           => Tr7_Unsafe_List_Length'Result in 0 .. 4_096
                         or else Tr7_Unsafe_List_Length'Result in -4_097 .. -2;

   --  A fresh reversed copy of Head with Tail at its end; TR7_VOID when
   --  Head is not nil-terminated, TR7_NIL when the arena is full.
   function Tr7_Reverse
     (Engine : System.Address;
      Head, Tail : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_reverse",
       Post           => Tr7_Reverse'Result = Tr7_Void
                         or else Tr7_Reverse'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Reverse'Result);

   --  In-place reversal with no allocation: Head's pairs are rewired and
   --  Tail put at the end.  TR7_VOID when Head is not nil-terminated
   --  (upstream warns the list is then "mostly reversed"; ours is bounded
   --  by the arena and rewires at most that many pairs).
   function Tr7_Reverse_In_Place (Head, Tail : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_reverse_in_place",
       Post           => Tr7_Reverse_In_Place'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Reverse_In_Place'Result);

   --  R7RS append over the first Nitem entries of Items, sharing the last;
   --  TR7_FALSE when an entry before the last is not a proper list (or the
   --  array pointer is null), TR7_NIL for Nitem = 0.
   function Tr7_Append
     (Engine : System.Address;
      Nitem  : Interfaces.C.int;
      Items  : System.Address) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_append",
       Post           => Tr7_Append'Result = Tr7_Nil
                         or else Tr7_Append'Result = Tr7_False
                         or else Is_Any_Value_T (Tr7_Append'Result);

   --  The first Count cars of List into Cars, and the rest into *Cdr when
   --  Cdr is not null.  Returns how many were stored (0 when List is not a
   --  pair); a null Cars with Count > 0 stores nothing and returns 0.
   function Tr7_Get_List_Cars
     (List  : Tr7_T;
      Count : Interfaces.C.int;
      Cars  : System.Address;
      Cdr   : System.Address) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_list_cars",
       Post           => Tr7_Get_List_Cars'Result >= 0;

   --  The memq/memv/assq/assv/meme/asse family and the general member /
   --  assoc with a host equality callback.  All return the found pair as a
   --  tr7_t (upstream returns the pair object; ours is the handle value of
   --  the same pair, usable with tr7_car_or_void / tr7_cdr_or_void) and
   --  TR7_FALSE when absent; every walk is bounded, so a cyclic list
   --  answers TR7_FALSE where upstream would hang or where it documents
   --  TR7_FALSE already.
   function Tr7_Memq (X, List : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_memq",
       Post           => Tr7_Memq'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Memq'Result);

   function Tr7_Memv (X, List : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_memv",
       Post           => Tr7_Memv'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Memv'Result);

   function Tr7_Meme (X, List : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_meme",
       Post           => Tr7_Meme'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Meme'Result);

   function Tr7_Assq (X, List : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_assq",
       Post           => Tr7_Assq'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Assq'Result);

   function Tr7_Assv (X, List : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_assv",
       Post           => Tr7_Assv'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Assv'Result);

   function Tr7_Asse (X, List : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_asse",
       Post           => Tr7_Asse'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Asse'Result);

   function Tr7_Member
     (X, List : Tr7_T; Eq : System.Address) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_member",
       Post           => Tr7_Member'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Member'Result);

   function Tr7_Assoc
     (X, List : Tr7_T; Eq : System.Address) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_assoc",
       Post           => Tr7_Assoc'Result = Tr7_False
                         or else Is_Heap_T (Tr7_Assoc'Result);

   --  Vectors.  Length is bounded by the core's Max_List_Length (1,024);
   --  a longer request answers TR7_NIL, a documented capacity, not a wrap.
   function Tr7_Make_Vector_Fill
     (Engine : System.Address;
      Len    : Interfaces.C.size_t;
      Value  : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_vector_fill",
       Post           => Tr7_Make_Vector_Fill'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_Vector_Fill'Result);

   function Tr7_Make_Vector_Copy
     (Engine : System.Address;
      Len    : Interfaces.C.size_t;
      Items  : System.Address) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_vector_copy",
       Post           => Tr7_Make_Vector_Copy'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_Vector_Copy'Result);

   function Tr7_Make_Vector_Stride
     (Engine : System.Address;
      Len    : Interfaces.C.size_t;
      Items  : System.Address;
      Stride : Interfaces.C.size_t) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_vector_stride",
       Post           => Tr7_Make_Vector_Stride'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_Vector_Stride'Result);

   --  The accessors answer 0 / TR7_VOID gracefully for a non-vector or an
   --  out-of-range index (upstream's caller contract is "MUST be a
   --  vector"); vector_set answers the value it stored, TR7_VOID on
   --  failure, as upstream does.
   function Tr7_Vector_Length (Vec : Tr7_T) return Interfaces.C.size_t
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_vector_length",
       Post           => Tr7_Vector_Length'Result <= 1024;

   function Tr7_Vector_Ref
     (Vec : Tr7_T; Ielem : Interfaces.C.size_t) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_vector_ref",
       Post           => Tr7_Vector_Ref'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Vector_Ref'Result);

   function Tr7_Vector_Set
     (Vec   : Tr7_T;
      Ielem : Interfaces.C.size_t;
      Value : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_vector_set",
       Post           => Tr7_Vector_Set'Result = Tr7_Void
                         or else Tr7_Vector_Set'Result = Value;

   function Tr7_List_To_Vector
     (Engine : System.Address; List : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_list_to_vector",
       Post           => Tr7_List_To_Vector'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_List_To_Vector'Result);

   function Tr7_Vector_To_List
     (Engine : System.Address; Vec : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_vector_to_list",
       Post           => Tr7_Vector_To_List'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Vector_To_List'Result);

   --  Strings.  v1 strings are byte strings (docs/architecture.md), so
   --  make_string_fill rejects a character above 255 with TR7_NIL and
   --  string_length counts bytes, where upstream counts UNICODE
   --  characters -- both documented deviations.  Text longer than the
   --  core's Max_Text (256 bytes) answers TR7_NIL.  The *_static and
   --  *_take variants stay stubs: this ABI copies, it cannot adopt or
   --  free host memory.
   function Tr7_Make_String_Fill
     (Engine : System.Address;
      Car    : Interfaces.C.unsigned_long;
      Ncars  : Interfaces.C.size_t) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_string_fill",
       Post           => Tr7_Make_String_Fill'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_String_Fill'Result);

   function Tr7_Make_String_Copy_Length
     (Engine : System.Address;
      Sutf8  : System.Address;
      Size   : Interfaces.C.size_t) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_string_copy_length",
       Post           => Tr7_Make_String_Copy_Length'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_String_Copy_Length'Result);

   function Tr7_Make_String_Copy
     (Engine : System.Address; Sutf8 : System.Address) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_string_copy",
       Post           => Tr7_Make_String_Copy'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_String_Copy'Result);

   --  The copy dispatcher: copy /= 0 copies (as above), copy = 0 is the
   --  static path this ABI does not implement and answers TR7_NIL --
   --  reported, not aliased.
   function Tr7_Make_String_Length
     (Engine : System.Address;
      Sutf8  : System.Address;
      Size   : Interfaces.C.size_t;
      Copy   : Interfaces.C.int) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_string_length",
       Post           => Tr7_Make_String_Length'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_String_Length'Result);

   function Tr7_Make_String
     (Engine : System.Address;
      Sutf8  : System.Address;
      Copy   : Interfaces.C.int) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_make_string",
       Post           => Tr7_Make_String'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Make_String'Result);

   function Tr7_Is_String (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_string",
       Post           => Tr7_Is_String'Result = 0
                         or else Tr7_Is_String'Result = 1;

   function Tr7_String_Size (T : Tr7_T) return Interfaces.C.size_t
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_string_size",
       Post           => Tr7_String_Size'Result <= 256;

   --  A fresh NUL-terminated copy of the text, in a per-engine arena freed
   --  at engine destroy: the pointer stays valid until then, which is the
   --  upstream lifetime shape without the GC coupling.  NULL for a
   --  non-string (upstream's caller contract is "MUST be a string").
   function Tr7_String_Buffer (T : Tr7_T) return Interfaces.C.Strings.chars_ptr
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_string_buffer";

   function Tr7_String_Length (T : Tr7_T) return Interfaces.C.size_t
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_string_length",
       Post           => Tr7_String_Length'Result <= 256;

   --  The byte at Pos as a character value, or the invalid ((tr7_char_t)-1)
   --  answer the header documents for a bad position.
   function Tr7_String_Ref
     (T  : Tr7_T;
      Pos : Interfaces.C.size_t) return Interfaces.C.unsigned_long
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_string_ref",
       Post           => Tr7_String_Ref'Result = Interfaces.C.unsigned_long'Last
                         or else Tr7_String_Ref'Result <= 255;

   --  Store a byte-representable character at Pos; anything above 255 (or
   --  a bad position) answers 0, as the header's failure value.
   function Tr7_String_Set
     (Engine : System.Address;
      T      : Tr7_T;
      Pos    : Interfaces.C.size_t;
      Car    : Interfaces.C.unsigned_long) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_string_set",
       Post           => Tr7_String_Set'Result = 0
                         or else Tr7_String_Set'Result = 1;

   function Tr7_Is_Symbol (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_symbol",
       Post           => Tr7_Is_Symbol'Result = 0
                         or else Tr7_Is_Symbol'Result = 1;

   function Tr7_Symbol_String (T : Tr7_T) return Interfaces.C.Strings.chars_ptr
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_symbol_string";

   function Tr7_Symbol_Size (T : Tr7_T) return Interfaces.C.size_t
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_symbol_size",
       Post           => Tr7_Symbol_Size'Result <= 256;

   function Tr7_Symbol_Length (T : Tr7_T) return Interfaces.C.size_t
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_symbol_length",
       Post           => Tr7_Symbol_Length'Result <= 256;

   function Tr7_Symbol_Ref
     (T  : Tr7_T;
      Pos : Interfaces.C.size_t) return Interfaces.C.unsigned_long
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_symbol_ref",
       Post           => Tr7_Symbol_Ref'Result = Interfaces.C.unsigned_long'Last
                         or else Tr7_Symbol_Ref'Result <= 255;

   --  Dictionary lookup over the engine's symbols.  Create = 0 never
   --  allocates: it answers TR7_FALSE when the name is not interned.
   function Tr7_Symbol_Lookup
     (Engine : System.Address;
      Name   : System.Address;
      Length : Interfaces.C.size_t;
      Copy   : Interfaces.C.int;
      Create : Interfaces.C.int) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_symbol_lookup",
       Post           => Tr7_Symbol_Lookup'Result = Tr7_False
                         or else Tr7_Symbol_Lookup'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Symbol_Lookup'Result);

   function Tr7_Get_Symbol_Length
     (Engine : System.Address;
      Name   : System.Address;
      Size   : Interfaces.C.size_t;
      Copy   : Interfaces.C.int) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_symbol_length",
       Post           => Tr7_Get_Symbol_Length'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Get_Symbol_Length'Result);

   function Tr7_Get_Symbol
     (Engine : System.Address;
      Name   : System.Address;
      Copy   : Interfaces.C.int) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_symbol",
       Post           => Tr7_Get_Symbol'Result = Tr7_Nil
                         or else Is_Heap_T (Tr7_Get_Symbol'Result);

   --  Numeric predicates, the C equivalents of number?, real?, exact?,
   --  exact-integer?, nan?, finite? and infinite?.  Our number tower is
   --  fixnum + flonum, so real = number.
   function Tr7_Is_Number (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_number",
       Post           => Tr7_Is_Number'Result = 0
                         or else Tr7_Is_Number'Result = 1;

   function Tr7_Is_Real (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_real",
       Post           => Tr7_Is_Real'Result = 0
                         or else Tr7_Is_Real'Result = 1;

   function Tr7_Is_Exact (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_exact",
       Post           => Tr7_Is_Exact'Result = 0
                         or else Tr7_Is_Exact'Result = 1;

   function Tr7_Is_Exact_Integer (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_exact_integer",
       Post           => Tr7_Is_Exact_Integer'Result = 0
                         or else Tr7_Is_Exact_Integer'Result = 1;

   function Tr7_Is_Nan (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_NaN",
       Post           => Tr7_Is_Nan'Result = 0
                         or else Tr7_Is_Nan'Result = 1;

   function Tr7_Is_Finite (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_finite",
       Post           => Tr7_Is_Finite'Result = 0
                         or else Tr7_Is_Finite'Result = 1;

   function Tr7_Is_Infinite (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_infinite",
       Post           => Tr7_Is_Infinite'Result = 0
                         or else Tr7_Is_Infinite'Result = 1;

   --  procedure? is the core's own relation: closure, primitive or
   --  continuation; closure? is closure cells only.
   function Tr7_Is_Procedure (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_procedure",
       Post           => Tr7_Is_Procedure'Result = 0
                         or else Tr7_Is_Procedure'Result = 1;

   function Tr7_Is_Closure (T : Tr7_T) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_is_closure",
       Post           => Tr7_Is_Closure'Result = 0
                         or else Tr7_Is_Closure'Result = 1;

   --  Printing.  Each call writes one value through a local buffer and
   --  flushes, so C printf and ABI output stay in order; write_simple /
   --  write_shared coincide with write because this implementation has no
   --  shared-structure notation (a documented deviation).
   procedure Tr7_Write (Engine : System.Address; Item : Tr7_T)
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_write";

   procedure Tr7_Write_Simple (Engine : System.Address; Item : Tr7_T)
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_write_simple";

   procedure Tr7_Write_Shared (Engine : System.Address; Item : Tr7_T)
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_write_shared";

   procedure Tr7_Display (Engine : System.Address; Item : Tr7_T)
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_display";

   function Tr7_Display_String
     (Engine : System.Address; S : System.Address) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_display_string",
       Post           => Tr7_Display_String'Result = 0
                         or else Tr7_Display_String'Result = 1;

   procedure Tr7_Flush (Engine : System.Address)
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_flush";

   --  Run source without trapping: like load_string but the error text is
   --  not printed and the failure is the host's to inspect -- 1 on
   --  success, 0 on error, exactly upstream's run contract.
   function Tr7_Run_String
     (Engine : System.Address;
      Cmd    : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_run_string",
       Post           => Tr7_Run_String'Result = 0
                         or else Tr7_Run_String'Result = 1;

   --  Read one datum from Length bytes of source text (no NUL scan): the
   --  value on success, the EOF object when the text holds no datum, and
   --  TR7_VOID on a read error -- upstream returns an error object, which
   --  this ABI has no representation for (documented deviation).  Text
   --  longer than the core's reader source bound answers TR7_VOID.
   function Tr7_From_Utf8_Length
     (Engine : System.Address;
      Expr   : System.Address;
      Length : Interfaces.C.size_t) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_from_utf8_length",
       Post           => Tr7_From_Utf8_Length'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_From_Utf8_Length'Result);

   --  The NUL-terminated variant, the length from the string.
   function Tr7_From_Utf8
     (Engine : System.Address; Expr : System.Address) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_from_utf8",
       Post           => Tr7_From_Utf8'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_From_Utf8'Result);

   --  The last returned value.  One value is retained (the engine's
   --  evaluation result): count is 1 after a successful load / run / eval
   --  and 0 otherwise; index 0 fetches it, any other index is TR7_VOID.
   --  Upstream keeps an error object after a failed evaluation; this ABI
   --  has none to expose, so a failure clears the slot (documented
   --  deviation).
   function Tr7_Get_Values_Count (Engine : System.Address)
     return Interfaces.C.unsigned
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_values_count",
       Post           => Tr7_Get_Values_Count'Result = 0
                         or else Tr7_Get_Values_Count'Result = 1;

   function Tr7_Get_Value
     (Engine : System.Address;
      Index  : Interfaces.C.unsigned) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_value",
       Post           => Tr7_Get_Value'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Get_Value'Result);

   function Tr7_Get_Last_Value (Engine : System.Address) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_last_value",
       Post           => Tr7_Get_Last_Value'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Get_Last_Value'Result);

   function Tr7_Get_Values
     (Engine : System.Address;
      Count  : Interfaces.C.unsigned;
      Values : System.Address) return Interfaces.C.unsigned
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_get_values",
       Post           => Tr7_Get_Values'Result = 0
                         or else Tr7_Get_Values'Result = 1;

   --  Evaluate one value in the engine's global environment (the safe
   --  point and the error handling are the engine's own): the value on
   --  success, TR7_VOID on failure -- upstream returns an error object,
   --  which this ABI has no representation for (documented deviation).
   --  Output the evaluation printed is flushed to stdout, then discarded
   --  from the engine's buffer.
   function Tr7_Eval (Engine : System.Address; Obj : Tr7_T) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_eval",
       Post           => Tr7_Eval'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Eval'Result);

   --  Call the global binding of the NUL-terminated Procname with no
   --  arguments ((procname)), as upstream does; TR7_VOID on failure.
   function Tr7_Apply0
     (Engine   : System.Address;
      Procname : Interfaces.C.Strings.chars_ptr) return Tr7_T
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_apply0",
       Post           => Tr7_Apply0'Result = Tr7_Void
                         or else Is_Any_Value_T (Tr7_Apply0'Result);

   --  Bind Symbol to Value: in Env when Env is a live environment value,
   --  in the global environment when it is TR7_VOID / TR7_NIL.  A bad
   --  engine, symbol or environment is silently ignored, like upstream's
   --  void contract.
   procedure Tr7_Define
     (Engine : System.Address;
      Env    : Tr7_T;
      Symbol : Tr7_T;
      Value  : Tr7_T)
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_define";

   --  Import a library by its slash-separated name ("srfi/1"): evaluate
   --  (import (a b c)) in the global environment.  0 is success (the
   --  header's Tr7_GetLib_No_Error), a negative Tr7_GetLib_Error_* the
   --  failure: -Not_Found for a bad name, -Eval when the evaluation
   --  fails.  Unknown library names are accepted as declarations, our
   --  core's import rule; (srfi 1) loads the prelude.
   function Tr7_Import_Lib
     (Engine : System.Address;
      Name   : System.Address) return Interfaces.C.int
     with
       SPARK_Mode     => Off,
       Convention     => C,
       Export         => True,
       External_Name  => "tr7_import_lib",
       Post           => Tr7_Import_Lib'Result = 0
                         or else Tr7_Import_Lib'Result in -5 .. -1;

end Tr7_C;
