--  Heap cells.
--
--  Cells are non-variant records.  Using one fixed layout for every object
--  keeps the allocator and the mark-sweep collector simple and avoids
--  discriminant-dependent access paths in the verified core.  Heap references
--  are index+generation handles (see Tr7.Values), never access values.

with Interfaces; use Interfaces;
with Tr7.Config; use Tr7.Config;
with Tr7.Ids; use Tr7.Ids;
with Tr7.Values; use Tr7.Values;

package Tr7.Cells with
   SPARK_Mode => On
is

   type Cell_Kind is
     (Cell_Free,
      Cell_Pair,
      Cell_Symbol,
      Cell_String,
      Cell_Vector,
      Cell_Bytevector,
      Cell_Closure,
      Cell_Primitive,
      Cell_Environment,
      Cell_Continuation);

   subtype Text_Buffer is String (1 .. Max_Text);

   type Cell is record
      Kind       : Cell_Kind := Cell_Free;
      Generation : Unsigned_32 := 0;
      Next_Free  : Cell_Index := 0;
      --  Marked means "marked in cycle Mark_Epoch": the collector advances
      --  Heap.Epoch after every sweep, which retires all earlier marks in one
      --  assignment instead of a pass over the arena (see Tr7.Heap).
      Mark_Epoch : Unsigned_64 := 0;

      --  Pair, closure parameters/body, environment bindings.
      Car : Value := Nil_Value;
      Cdr : Value := Nil_Value;

      --  Symbol and string text.
      Name     : Text_Buffer := (others => ' ');
      Name_Len : Natural range 0 .. Max_Text := 0;

      --  Primitive procedure.
      Prim : Primitive_Id := P_None;

      --  Closure / environment parent.
      Env : Handle := Null_Handle;

      --  Closure parameter count.
      Arity : Natural range 0 .. Max_List_Length := 0;
   end record;

   type Cell_Array is array (Valid_Cell_Index) of Cell;

   function Is_Free (C : Cell) return Boolean is
     (C.Kind = Cell_Free);

   function Valid_Handle (C : Cell; H : Handle) return Boolean is
     (H.Index in Valid_Cell_Index
        and then C.Generation = H.Generation
        and then C.Kind /= Cell_Free);

   function Text_Of (C : Cell) return String is
     (C.Name (1 .. C.Name_Len));

end Tr7.Cells;
