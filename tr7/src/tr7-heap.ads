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

   --  The roots of one collection, as cells: the caller (Collect_Garbage)
   --  resolves every root value to its live cell and hands the list over.
   --  The bound is the worst case without deduplication -- six frame slots
   --  per stack frame plus the direct roots -- and the caller can never
   --  reach it, because there are at most Max_Cells distinct cells.
   Max_Roots : constant := 6 * Max_Cells + 8;
   subtype Root_Count is Natural range 0 .. Max_Roots;
   type Root_Array is array (1 .. Max_Roots) of Valid_Cell_Index;

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

   --  An escape continuation.  The cell carries no depth: its own handle
   --  *is* the identity, stamped into the capturing frame's Sym, and an
   --  invocation finds that frame by scanning the stack -- so "is the
   --  dynamic extent still live" and "where do I deliver" are one test.
   procedure New_Continuation
     (H      : in out Heap_Type;
      Result : out Handle;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready and then (if Ok then Result.Index in Valid_Cell_Index);

   --  Wrap several values: the list already exists (an application's
   --  argument list), so the cell only adopts it.
   procedure New_Values
     (H      : in out Heap_Type;
      List   : Value;
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

   --  The cell a value points at, or 0 when the handle does not resolve:
   --  out of range, wrong generation, or already free.  Mark_Root-equivalent
   --  logic in one place, so the collector's closure predicate and its
   --  marking cannot disagree about what a child is.
   --  No H.Ready precondition: this is a pure read of the array (whose
   --  default is a free cell), and the reachability predicates call it
   --  from contexts that carry Ready anyway.
   function Live_Cell (H : Heap_Type; Hd : Handle) return Cell_Index
     with
       Inline           => True,
       Post => (Live_Cell'Result = 0
                or else Live_Cell'Result in Valid_Cell_Index)
         and then (if Live_Cell'Result /= 0
                   then Live_Cell'Result = Hd.Index
                     and then H.Cells (Live_Cell'Result).Kind /= Cell_Free
                     and then H.Cells (Live_Cell'Result).Generation =
                       Hd.Generation);

   function Live_Cell (H : Heap_Type; V : Value) return Cell_Index
     is (if Is_Handle (V) then Live_Cell (H, To_Handle (V)) else 0);

   --  A cell is marked when its epoch is the current cycle's.  Cell 0 is
   --  the nil marker and has no array slot, so it is never marked -- the
   --  guard makes the predicate total, which every caller (lemma included)
   --  relies on.
   function Is_Marked (H : Heap_Type; J : Cell_Index) return Boolean is
     (J /= 0 and then H.Cells (J).Mark_Epoch = H.Epoch);

   function On_Stack (H : Heap_Type; J : Cell_Index) return Boolean is
     (J /= 0 and then H.Cells (J).Queued = H.Epoch);

   --  One child is rooted when the value is dead (nothing to root) or its
   --  cell is marked.  A single atom: stated once here so neither the
   --  closure nor the drain's invariants pay for two Live_Cell expansions
   --  per child.
   function Child_Marked (H : Heap_Type; V : Value) return Boolean is
     (Live_Cell (H, V) = 0 or else Is_Marked (H, Live_Cell (H, V)));

   --  One-step closure of the marked set: every marked cell is either still
   --  on the worklist or has all of its children marked -- exactly the
   --  children the drain roots: Car, Cdr, and Env for closures and
   --  environments.  The reachability lemma takes this as its hypothesis.
   function Closure (H : Heap_Type) return Boolean is
     (for all J in Valid_Cell_Index =>
        (if Is_Marked (H, J)
         then On_Stack (H, J)
           or else (Child_Marked (H, H.Cells (J).Car)
                    and then Child_Marked (H, H.Cells (J).Cdr)
                    and then (if H.Cells (J).Kind = Cell_Closure
                                or else H.Cells (J).Kind = Cell_Environment
                              then Child_Marked
                                (H, From_Handle (H.Cells (J).Env))
                              else True))));

   --  The drain's own invariant, in processed-cells form: a marked cell
   --  that is no longer on the worklist has all of its children marked.
   --  Logically Closure with the worklist empty, but split per child:
   --  one invariant per child is one quantifier and one case split per
   --  preservation proof, where the conjunction made the prover chase
   --  every child of every cell at once and time out.  At drain exit
   --  (stack empty) the three coincide with Closure, which is what
   --  Collect's postcondition states.
   function Drained_Car (H : Heap_Type) return Boolean is
     (for all J in Valid_Cell_Index =>
        (if Is_Marked (H, J) and then not On_Stack (H, J)
         then Child_Marked (H, H.Cells (J).Car)));

   function Drained_Cdr (H : Heap_Type) return Boolean is
     (for all J in Valid_Cell_Index =>
        (if Is_Marked (H, J) and then not On_Stack (H, J)
         then Child_Marked (H, H.Cells (J).Cdr)));

   function Drained_Env (H : Heap_Type) return Boolean is
     (for all J in Valid_Cell_Index =>
        (if Is_Marked (H, J) and then not On_Stack (H, J)
           and then (H.Cells (J).Kind = Cell_Closure
                     or else H.Cells (J).Kind = Cell_Environment)
         then Child_Marked (H, From_Handle (H.Cells (J).Env))));

   function Drained (H : Heap_Type) return Boolean is
     (Drained_Car (H) and then Drained_Cdr (H) and then Drained_Env (H));

   function Roots_Marked (H : Heap_Type; Roots : Root_Array;
                          Count : Root_Count) return Boolean is
     (for all K in 1 .. Count => Is_Marked (H, Roots (K)));

   --  Collector: retire the previous cycle's marks by jumping Epoch past
   --  every mark in the arena (this cycle therefore starts clean, provably
   --  inside this procedure -- no cross-call reasoning about epochs), root
   --  the cells in Roots, drain the mark stack, and -- when marking
   --  completed -- leave exactly the closure facts the sweep needs.
   --  The sweep itself lives in Tr7.Reach, so reachability mathematics
   --  never enters this unit's proof obligations.
   --
   --  Marking cannot fail silently: a full mark stack sets Mark_Failed, a
   --  drain that runs out of rounds sets it too, and Collect then abandons
   --  the cycle without sweeping -- which can only leave garbage in place,
   --  never free a live cell.  The caller skips the sweep when
   --  Mark_Failed is set on return.
   procedure Collect
     (H     : in out Heap_Type;
      Roots : Root_Array;
      Count : Root_Count)
     with
       Pre  => H.Ready
         and then (for all K in 1 .. Count =>
                     H.Cells (Roots (K)).Kind /= Cell_Free),
       Post => H.Ready
         and then H.Mark_Top = 0
         and then H.Free_Count = H.Free_Count'Old
         and then (if not H.Mark_Failed
                   then Closure (H)
                     and then Roots_Marked (H, Roots, Count)
                     and then (for all J in Valid_Cell_Index =>
                                 not On_Stack (H, J))
                     and then (for all J in Valid_Cell_Index =>
                                 (if Is_Marked (H, J)
                                  then H.Cells (J).Kind /= Cell_Free)));

end Tr7.Heap;
