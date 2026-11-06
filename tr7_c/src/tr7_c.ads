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
--  What is implemented here is the core subset a C host needs to run source
--  text: identify the library, build a default configuration, create and
--  destroy an engine, and load a string.  Every other symbol declared by
--  include/tr7.h -- a copy of upstream TR7's header, 0BSD -- exists as a
--  generated stub in src/tr7_c_stubs.c; scripts/gen_abi.py produces that
--  file, --check proves the checked-in copy is current, and --check-lib
--  proves the built library defines every symbol the header declares.
--
--  Deliberate deviations from upstream, recorded in docs/architecture.md:
--  the engine keeps its arena in Ada's heap, so the custom allocators in
--  tr7_config_t are validated but not honored; tr7_t values are not
--  exposed at all (no tagged-pointer ABI in v1); output and error text go
--  to this process's C stdout, where tr7i writes them too.

with Interfaces.C;
with Interfaces.C.Strings;
with System;

use type Interfaces.C.Strings.chars_ptr;
use type Interfaces.C.int;
use type System.Address;

package Tr7_C with SPARK_Mode => On is

   --  Contract support: True when A sits on an engine-object boundary.  It
   --  is pure arithmetic on the address and never dereferences, so a
   --  contract may call it on any pointer, garbage included, without
   --  risking a fault inside the assertion itself.
   function Is_Aligned (A : System.Address) return Boolean
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
                         or else Is_Aligned (Config),
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
                         or else Is_Aligned (Config),
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

end Tr7_C;
