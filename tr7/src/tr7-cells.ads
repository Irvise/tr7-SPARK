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
      Cell_Continuation,
      --  String ports: the text lives in Name (so a port carries no handle
      --  and the collector needs no extra root for it), Name_Len is its
      --  length, and Arity is the read position (input) or the write length
      --  (output).  Both are capped at Max_Text: a port is a string port,
      --  and the OS boundary -- loading a file into one -- stays in tr7i.
      Cell_Input_Port,
      Cell_Output_Port,
      --  Several values in flight: Car holds the list of them (kind-agnostic
      --  marking covers it), and only `values` builds one.
      Cell_Values);

   subtype Text_Buffer is String (1 .. Max_Text);

   type Cell is record
      Kind       : Cell_Kind := Cell_Free;
      Generation : Unsigned_32 := 0;
      Next_Free  : Cell_Index := 0;
      --  Marked means "marked in cycle Mark_Epoch": the collector advances
      --  Heap.Epoch after every sweep, which retires all earlier marks in one
      --  assignment instead of a pass over the arena (see Tr7.Heap).
      Mark_Epoch : Unsigned_64 := 0;
      --  The epoch at which this cell was pushed on the mark stack, or 0
      --  when it is not on it.  Epoch-stamped rather than a flag so tags
      --  from an abandoned cycle expire with the next epoch jump instead
      --  of needing a clearing pass.
      Queued     : Unsigned_64 := 0;

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
