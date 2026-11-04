--  Pair and list helpers.
--
--  All operations take the heap explicitly and report failure through Ok
--  instead of raising, so the evaluator can turn bad input into a Scheme
--  error value at a well-defined point.

with Tr7.Config; use Tr7.Config;
with Tr7.Heap; use Tr7.Heap;
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

   procedure Length
     (H    : Heap_Type;
      List : Value;
      Len  : out Natural;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Len <= Max_List_Length);

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

   procedure To_Array
     (H      : Heap_Type;
      List   : Value;
      Arr    : out Value_Array;
      Len    : out Natural;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Len <= Arr'Length);

   --  Value_Array is declared in Tr7.Values.
end Tr7.Pairs;
