--  Heap with a free list and a mark-sweep collector.
--
--  v1 uses an engine-owned arena of fixed-size cells.  Allocation pops from a
--  singly linked free list; release pushes back.  The collector reuses the
--  same free list: callers root what they are holding with Mark_Root and then
--  call Collect, which drains the mark stack and sweeps unmarked cells back
--  onto the free list.

with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Ids; use Tr7.Ids;
with Tr7.Values; use Tr7.Values;

package Tr7.Heap with
   SPARK_Mode => On
is

   --  The mark stack holds cells whose outgoing references still have to be
   --  visited.  A cell is pushed at most once (it is marked on the way in), so
   --  Max_Cells entries are enough for any object graph in the arena.
   type Mark_Array is array (Valid_Cell_Index) of Valid_Cell_Index;

   type Heap_Type is record
      Cells       : Cell_Array;
      Free_Head   : Cell_Index := 0;
      Free_Count  : Natural range 0 .. Max_Cells := 0;
      Ready       : Boolean := False;
      --  The text of the last (error ...) raised, when it has one: a string
      --  value the printer prefers over the generic Error_Name.  It lives
      --  here because a primitive sees the heap and not the machine; it is
      --  cleared at the start of every evaluation and only ever set on the
      --  step that halts, so nothing can collect it in between -- the mark
      --  below is defence in depth.
      Error_Msg   : Value := Nil_Value;
      Mark_Stack  : Mark_Array := (others => Valid_Cell_Index'First);
      Mark_Top    : Natural range 0 .. Max_Cells := 0;
      Mark_Failed : Boolean := False;
      --  Collection cycle.  A cell is marked when its Mark_Epoch equals Epoch,
      --  and Epoch advances after every sweep, which retires the cycle's marks
      --  without touching the arena -- no clearing pass, and no quantified
      --  invariant in the sweep loop (which cost O(n^2) at run time under
      --  -gnata; see docs/findings.md).  Zero is reserved for "never marked"
      --  and Epoch starts at 1, so a fresh cell can never look marked.
      Epoch         : Unsigned_64 := 1;
      --  Set when Epoch can no longer advance (2**64 cycles).  Collection then
      --  stops for good: the heap keeps every cell it has, reports exhaustion
      --  if it fills, and never frees anything against stale marks.
      Collect_Stopped : Boolean := False;
      --  Collect at every safe point instead of only below GC_Low_Water; the
      --  REPL enables it with --stress-gc so the suites exercise the
      --  collector continuously.
      Stress_GC   : Boolean := False;
   end record;

   procedure Initialize (H : out Heap_Type)
     with
       Post => H.Ready
         and then H.Free_Count = Max_Cells
         and then H.Free_Head = 1
         and then H.Mark_Top = 0
         and then not H.Mark_Failed;

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

   --  Find the symbol with this name, creating it if needed.  This belongs to
   --  the heap because that is where symbols live -- the reader, the engine
   --  and the quasiquote converter all need it.
   procedure Intern
     (H      : in out Heap_Type;
      Name   : String;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready
         and then Name'First >= 1
         and then Name'Last < Natural'Last
         and then Name'Length <= Max_Text,
       Post => H.Ready and then (if Ok then Is_Handle (Result));

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

   --  Vectors keep their length in Arity and their elements as a proper list
   --  in Car, so a vector is one cell plus one cell per element.
   procedure New_Vector
     (H        : in out Heap_Type;
      Elements : Value;
      Arity    : Natural;
      Result   : out Handle;
      Ok       : out Boolean)
     with
       Pre  => H.Ready and then Arity <= Max_List_Length,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   --  Bytevectors keep their bytes in the same buffer strings use, so a byte
   --  read or write is a field access; the length is Name_Len.
   procedure New_Bytevector
     (H      : in out Heap_Type;
      Data   : String;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready
         and then Data'First >= 1
         and then Data'Last < Natural'Last
         and then Data'Length <= Max_Text,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   --  A string port over the text of a string value; the text is copied
   --  into the port itself, so no handle is involved.
   procedure New_Input_Port
     (H      : in out Heap_Type;
      Source : Value;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   procedure New_Output_Port
     (H      : in out Heap_Type;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   --  Move a port's position (input) or length (output).
   procedure Set_Port_Pos
     (H   : in out Heap_Type;
      V   : Value;
      Pos : Natural;
      Ok  : out Boolean)
     with
       Pre  => H.Ready and then Pos <= Max_Text,
       Post => H.Ready;

   --  Replace an output port's text (the caller has already checked the
   --  length against Max_Text).
   procedure Set_Port_Text
     (H    : in out Heap_Type;
      V    : Value;
      Text : String;
      Ok   : out Boolean)
     with
       Pre  => H.Ready
         and then Text'First >= 1
         and then Text'Last < Natural'Last
         and then Text'Length <= Max_Text,
       Post => H.Ready;

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

   --  Store one byte of a bytevector (Index is 0-based, like bytevector-u8-ref).
   procedure Set_Byte
     (H     : in out Heap_Type;
      V     : Value;
      Index : Natural;
      Byte  : Character;
      Ok    : out Boolean)
     with
       Pre  => H.Ready and then Index < Max_Text,
       Post => H.Ready;

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

   --  Collector.
   --
   --  Usage: root everything live (Mark_Root), then call Collect.  Registering
   --  a root never allocates, so nothing can be lost between the two calls.
   --  Marking cannot fail silently: a full mark stack sets Mark_Failed, and
   --  Collect then abandons the cycle without sweeping -- which can only leave
   --  garbage in place, never free a live cell.
   --  Rooting only writes mark epochs: it never allocates, never frees, never
   --  touches the free list and never advances the cycle, which is what lets
   --  Collect reason about Free_Count and Epoch across the whole drain phase.
   procedure Mark_Root (H : in out Heap_Type; V : Value)
     with
       Pre  => H.Ready,
       Post => H.Ready
         and then H.Free_Count = H.Free_Count'Old
         and then H.Epoch = H.Epoch'Old;

   --  Collect has no success flag on purpose: when marking cannot complete the
   --  cycle is abandoned without sweeping, so the only consequence is that less
   --  garbage is reclaimed.  Every path retires the cycle's marks by advancing
   --  Epoch, which is why the postconditions below are all scalar.
   procedure Collect (H : in out Heap_Type)
     with
       Pre  => H.Ready,
       Post => H.Ready
         and then H.Mark_Top = 0
         and then not H.Mark_Failed
         and then H.Free_Count >= H.Free_Count'Old
         and then H.Epoch >= H.Epoch'Old;

end Tr7.Heap;
