--  Pair and list helpers.
--
--  All operations take the heap explicitly and report failure through Ok
--  instead of raising, so the evaluator can turn bad input into a Scheme
--  error value at a well-defined point.

with Tr7.Config; use Tr7.Config;
with Tr7.Heap; use Tr7.Heap;
with Tr7.Runtime; use Tr7.Runtime;
with Tr7.Values; use Tr7.Values;

package Tr7.Pairs with
   SPARK_Mode => On
is

   procedure Cons
     (H      : in out Heap_Type;
      A      : Value;
      D      : Value;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Car_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
     with Pre => H.Ready;

   procedure Cdr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
     with Pre => H.Ready;

   procedure Cadr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
     with Pre => H.Ready;

   procedure Caddr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
     with Pre => H.Ready;

   procedure Cadddr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
     with Pre => H.Ready;

   procedure Cddr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
     with Pre => H.Ready;

   --  Length of a proper list.  The walk is bounded by the arena -- a
   --  proper list holds one cell per element, so Max_Cells is the honest
   --  limit, and the former Max_List_Length cap reported a type error for
   --  lists the arena could hold.  A ring or a damaged list leaves Ok
   --  False.
   procedure Length
     (H    : Heap_Type;
      List : Value;
      Len  : out Natural;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Len <= Max_Cells);

   procedure Nth
     (H      : Heap_Type;
      List   : Value;
      N      : Natural;
      Result : out Value;
      Ok     : out Boolean)
     with Pre => H.Ready;

   procedure Reverse_List
     (H      : in out Heap_Type;
      List   : Value;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   --  The same walk, with the reason attached: a non-list (or a ring, which
   --  walks until it fails) is a type error, while an allocation failure is
   --  heap exhausted.  User-facing primitives use this form so a large
   --  list's failure names the real cause instead of a blanket type error.
   procedure Reverse_List
     (H      : in out Heap_Type;
      List   : Value;
      Result : out Value;
      Ok     : out Boolean;
      Err    : out Error_Code)
     with
       Pre  => H.Ready,
       Post => H.Ready and then (if Ok then Err = No_Error);

   procedure To_Array
     (H      : Heap_Type;
      List   : Value;
      Arr    : out Value_Array;
      Len    : out Natural;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Len <= Arr'Length);

   --  Deep, cycle-safe structural equality behind `equal?` and the R7RS
   --  `member`/`assoc`.  Pairs and vectors compare element-wise, strings
   --  and bytevectors by content, symbols by name; every other kind
   --  (booleans, numbers, characters, closures, ...) compares as `eqv?`
   --  does.  Rings built with set-car!/set-cdr! terminate: comparing two
   --  cells that are already paired (in either order) answers the
   --  coinductive fixpoint -- True -- so the walk visits every distinct
   --  pairing at most once and its recursion depth is bounded by the
   --  number of pairings, hence by the arena.  Ok is False only when the
   --  pairing table fills, which needs more distinct pairings than the
   --  arena can hold; callers report that as a resource error rather than
   --  a silently wrong answer.
   procedure Deep_Equal
     (H      : Heap_Type;
      A, B   : Value;
      Result : out Boolean;
      Ok     : out Boolean)
     with Pre => H.Ready;

   --  Value_Array is declared in Tr7.Values.
end Tr7.Pairs;
