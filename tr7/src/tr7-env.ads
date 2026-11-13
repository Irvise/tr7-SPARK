--  Lexical environments.
--
--  An environment is a heap cell holding an association list of
--  (symbol . value) bindings and a parent handle.  The representation is small
--  and easy to prove; a later version can switch to compile-time frame
--  offsets without changing the evaluator interface.

with Tr7.Heap; use Tr7.Heap;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Env with
   SPARK_Mode => On
is

   procedure New_Environment
     (H      : in out Heap_Type;
      Parent : Handle;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Define
     (H   : in out Heap_Type;
      Env : Handle;
      Sym : Value;
      Val : Value;
      Ok  : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Set
     (H      : in out Heap_Type;
      Env    : Handle;
      Sym    : Value;
      Val    : Value;
      Status : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Lookup
     (H      : Heap_Type;
      Env    : Handle;
      Sym    : Value;
      Val    : out Value;
      Status : out Error_Code)
     with Pre => H.Ready;

end Tr7.Env;
