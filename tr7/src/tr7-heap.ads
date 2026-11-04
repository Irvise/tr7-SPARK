--  Heap with a free list.
--
--  v1 uses an engine-owned arena of fixed-size cells.  Allocation pops from a
--  singly linked free list; release pushes back.  A later mark-sweep collector
--  can reuse the same free list without changing the value representation.

with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Ids; use Tr7.Ids;
with Tr7.Values; use Tr7.Values;

package Tr7.Heap with
   SPARK_Mode => On
is

   type Heap_Type is record
      Cells      : Cell_Array;
      Free_Head  : Cell_Index := 0;
      Free_Count : Natural range 0 .. Max_Cells := 0;
      Ready      : Boolean := False;
   end record;

   procedure Initialize (H : out Heap_Type)
     with
       Post => H.Ready
         and then H.Free_Count = Max_Cells
         and then H.Free_Head = 1;

   procedure Allocate
     (H      : in out Heap_Type;
      Kind   : Cell_Kind;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
         and then (if Ok
                  then Result.Index in Valid_Cell_Index
                    and then Result.Generation /= 0
                    and then H.Free_Count = H.Free_Count'Old - 1
                  else Result = Null_Handle
                    and then H.Free_Count = H.Free_Count'Old);

   procedure Release
     (H  : in out Heap_Type;
      Hd : Handle;
      Ok : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
         and then (if Ok
                  then H.Free_Count = H.Free_Count'Old + 1
                  else H.Free_Count = H.Free_Count'Old);

   procedure Fetch
     (H  : Heap_Type;
      Hd : Handle;
      C  : out Cell;
      Ok : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then Valid_Handle (C, Hd));

   procedure Kind_Of
     (H  : Heap_Type;
      Hd : Handle;
      Kind : out Cell_Kind;
      Ok : out Boolean)
     with
       Pre  => H.Ready;

   --  Constructors.  Each allocates one cell and fills its fields.
   procedure New_Pair
     (H      : in out Heap_Type;
      Car    : Value;
      Cdr    : Value;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure New_Symbol
     (H      : in out Heap_Type;
      Name   : String;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready
         and then Name'First >= 1
         and then Name'Last < Natural'Last
         and then Name'Length <= Max_Text,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   procedure New_String
     (H      : in out Heap_Type;
      Text   : String;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready
         and then Text'First >= 1
         and then Text'Last < Natural'Last
         and then Text'Length <= Max_Text,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   procedure New_Closure
     (H      : in out Heap_Type;
      Params : Value;
      Forms  : Value;
      Env    : Handle;
      Arity  : Natural;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready and then Arity <= Max_List_Length,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   procedure New_Primitive
     (H      : in out Heap_Type;
      Prim   : Primitive_Id;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   procedure New_Environment
     (H      : in out Heap_Type;
      Parent : Handle;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   --  In-place mutation used by the environment and set-cdr!-style helpers.
   procedure Set_Car
     (H    : in out Heap_Type;
      Pair : Handle;
      V    : Value;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

   procedure Set_Cdr
     (H    : in out Heap_Type;
      Pair : Handle;
      V    : Value;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready;

end Tr7.Heap;
