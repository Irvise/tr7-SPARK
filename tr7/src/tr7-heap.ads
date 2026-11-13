--  Heap with a free list and a mark-sweep collector.
--
--  v1 uses an engine-owned arena of fixed-size cells.  Allocation pops from a
--  singly linked free list; release pushes back.  The collector reuses the
--  same free list: the caller (Collect_Garbage) resolves the machine's roots
--  and calls Collect, which propagates marks to a fixed point and then sweeps
--  unmarked cells back onto the free list.

with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Ids; use Tr7.Ids;
with Tr7.Values; use Tr7.Values;

package Tr7.Heap with
   SPARK_Mode => On
is

   --  The roots of one collection, as cells: the caller (Collect_Garbage)
   --  resolves every root value to its live cell and hands the list over.
   --  The bound is the worst case without deduplication -- six frame slots
   --  per stack frame plus the direct roots -- and the caller can never
   --  reach it, because there are at most Max_Cells distinct cells.
   Max_Roots : constant := 6 * Max_Cells + 8;
   subtype Root_Count is Natural range 0 .. Max_Roots;
   type Root_Array is array (1 .. Max_Roots) of Valid_Cell_Index;

   --  The mark worklist.  A cell is pushed when it is first marked, so a
   --  cell appears at most once and Max_Cells entries suffice for any graph
   --  in the arena.
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
      --  Number of live entries in Mark_Stack; zero means the marking
      --  worklist has drained.  The reachability lemma and the collector's
      --  contracts speak about this being zero.
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
       --  Fetch is on every pair and environment access.  Inlining it lets
       --  the compiler forward only the fields a caller reads instead of
       --  materialising the whole Cell (a 256-byte text buffer included);
       --  measured as a clear win on the interpreter workloads, and the
       --  proofs are unchanged.
       Inline => True,
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

   --  One child is rooted when the value is dead (nothing to root) or its
   --  cell is marked.  A single atom: stated once here so neither the
   --  closure nor the collector's invariants pay for two Live_Cell
   --  expansions per child.
   --  Stated directly on the cell fields rather than through Live_Cell:
   --  logically the same (dead/out-of-range/free/stale-generation children
   --  need no mark), but with no Live_Cell postcondition to re-instantiate
   --  inside quantified preservation proofs.  That postcondition was the
   --  main source of quantifier instantiation in the collector's VCs.
   function Child_Marked (H : Heap_Type; V : Value) return Boolean is
     (if not Is_Handle (V)
      then True
      elsif To_Handle (V).Index not in Valid_Cell_Index
      then True
      elsif H.Cells (To_Handle (V).Index).Kind = Cell_Free
      then True
      elsif H.Cells (To_Handle (V).Index).Generation /= To_Handle (V).Generation
      then True
      else H.Cells (To_Handle (V).Index).Mark_Epoch = H.Epoch);

   --  Closedness of the marked set, split per child.  Splitting matters for
   --  proof: GNATprove slices a loop invariant into one VC per top-level
   --  conjunct, so each child is one quantifier and one case split per
   --  preservation proof instead of the prover chasing every child of every
   --  cell at once.  Closure conjoins them for the callers (the reachability
   --  lemma and the sweep) that want the single fact.
   function Closed_Car (H : Heap_Type) return Boolean is
     (for all J in Valid_Cell_Index =>
        (if Is_Marked (H, J)
         then Child_Marked (H, H.Cells (J).Car)));

   function Closed_Cdr (H : Heap_Type) return Boolean is
     (for all J in Valid_Cell_Index =>
        (if Is_Marked (H, J)
         then Child_Marked (H, H.Cells (J).Cdr)));

   function Closed_Env (H : Heap_Type) return Boolean is
     (for all J in Valid_Cell_Index =>
        (if Is_Marked (H, J)
           and then (H.Cells (J).Kind = Cell_Closure
                     or else H.Cells (J).Kind = Cell_Environment)
         then Child_Marked (H, From_Handle (H.Cells (J).Env))));

   --  One-step closure of the marked set: every marked cell has all of its
   --  children marked -- exactly the children the collector marks: Car, Cdr,
   --  and Env for closures and environments.  The reachability lemma takes
   --  this as its hypothesis.
   function Closure (H : Heap_Type) return Boolean is
     (Closed_Car (H) and then Closed_Cdr (H) and then Closed_Env (H));

   function Roots_Marked (H : Heap_Type; Roots : Root_Array;
                          Count : Root_Count) return Boolean is
     (for all K in 1 .. Count => Is_Marked (H, Roots (K)));

   --  Collector: retire the previous cycle's marks by jumping Epoch past
   --  every mark in the arena (this cycle therefore starts clean, provably
   --  inside this procedure -- no cross-call reasoning about epochs), mark
   --  the cells in Roots, propagate marks to a fixed point, and -- when
   --  marking completed -- leave exactly the closure facts the sweep needs.
   --  The sweep itself lives in Tr7.Reach, so reachability mathematics
   --  never enters this unit's proof obligations.
   --
   --  Marking cannot fail silently: if the fixed point is not reached within
   --  the bounded number of passes, Mark_Failed is set and Collect abandons
   --  the cycle without sweeping -- which can only leave garbage in place,
   --  never free a live cell.  The caller skips the sweep when Mark_Failed
   --  is set on return.
   --
   --  The postcondition states the three closedness facts separately rather
   --  than as Closure: each top-level conjunct is one proof slice (see the
   --  note on Closed_Car), and Closure would make the prover chase all
   --  children of every cell in a single VC.
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
                   then Closed_Car (H)
                     and then Closed_Cdr (H)
                     and then Closed_Env (H)
                     and then Roots_Marked (H, Roots, Count)
                     and then (for all J in Valid_Cell_Index =>
                                 (if Is_Marked (H, J)
                                  then H.Cells (J).Kind /= Cell_Free)));

end Tr7.Heap;
