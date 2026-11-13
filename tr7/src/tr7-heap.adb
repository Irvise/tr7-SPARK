
package body Tr7.Heap with
   SPARK_Mode => On
is


   procedure Initialize (H : out Heap_Type) is
   begin
      H.Cells := (others => (Kind => Cell_Free, others => <>));
      H.Mark_Stack := (others => Valid_Cell_Index'First);
      H.Epoch := 1;
      H.Collect_Stopped := False;
      H.Error_Msg := Nil_Value;
      H.Mark_Top := 0;
      H.Mark_Failed := False;
      H.Stress_GC := False;

      for I in Valid_Cell_Index loop
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if J < I then H.Cells (J).Kind = Cell_Free));
         if I < Max_Cells then
            H.Cells (I).Next_Free := I + 1;
         else
            H.Cells (I).Next_Free := 0;
         end if;
         H.Cells (I).Generation := 0;
         H.Cells (I).Mark_Epoch := 0;
      end loop;

      H.Free_Head := 1;
      H.Free_Count := Max_Cells;
      H.Ready := True;
   end Initialize;

   procedure Allocate
     (H      : in out Heap_Type;
      Kind   : Cell_Kind;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      if H.Free_Head = 0 or else H.Free_Count = 0 then
         Result := Null_Handle;
         Ok := False;
         return;
      end if;

      declare
         Idx  : constant Valid_Cell_Index := Valid_Cell_Index (H.Free_Head);
         Next : constant Cell_Index := H.Cells (Idx).Next_Free;
         Gen  : Unsigned_32 := H.Cells (Idx).Generation + 1;
      begin
         if Gen = 0 then
            Gen := 1;
         end if;

         H.Cells (Idx) :=
           (Kind       => Kind,
            Generation => Gen,
            Next_Free  => 0,
            Mark_Epoch => 0,
            others     => <>);
         H.Free_Head := Next;
         H.Free_Count := H.Free_Count - 1;
         Result := (Index => Idx, Generation => Gen);
         Ok := True;
      end;
   end Allocate;

   procedure Release
     (H  : in out Heap_Type;
      Hd : Handle;
      Ok : out Boolean)
   is
      C : Cell;
      Valid : Boolean;
   begin
      Ok := False;
      Fetch (H, Hd, C, Valid);
      if not Valid or else H.Free_Count = Max_Cells then
         return;
      end if;
      pragma Unreferenced (C);

      H.Cells (Valid_Cell_Index (Hd.Index)).Kind := Cell_Free;
      H.Cells (Valid_Cell_Index (Hd.Index)).Mark_Epoch := 0;
      H.Cells (Valid_Cell_Index (Hd.Index)).Next_Free := H.Free_Head;
      H.Free_Head := Valid_Cell_Index (Hd.Index);
      H.Free_Count := H.Free_Count + 1;
      Ok := True;
   end Release;

   function Live_Cell (H : Heap_Type; Hd : Handle) return Cell_Index is
   begin
      if Hd.Index in Valid_Cell_Index
        and then H.Cells (Hd.Index).Generation = Hd.Generation
        and then H.Cells (Hd.Index).Kind /= Cell_Free
      then
         return Hd.Index;
      end if;
      return 0;
   end Live_Cell;

   procedure Fetch
     (H  : Heap_Type;
      Hd : Handle;
      C  : out Cell;
      Ok : out Boolean)
   is
      Idx : Cell_Index;
   begin
      C := (Kind => Cell_Free, others => <>);
      Ok := False;
      Idx := Live_Cell (H, Hd);
      if Idx /= 0 then
         C := H.Cells (Idx);
         Ok := True;
      end if;
   end Fetch;

   procedure Kind_Of
     (H    : Heap_Type;
      Hd   : Handle;
      Kind : out Cell_Kind;
      Ok   : out Boolean)
   is
      C : Cell;
   begin
      Kind := Cell_Free;
      Fetch (H, Hd, C, Ok);
      if Ok then
         Kind := C.Kind;
      end if;
   end Kind_Of;

   procedure New_Pair
     (H      : in out Heap_Type;
      Car    : Value;
      Cdr    : Value;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      Allocate (H, Cell_Pair, Result, Ok);
      if Ok then
         H.Cells (Result.Index).Car := Car;
         H.Cells (Result.Index).Cdr := Cdr;
      end if;
   end New_Pair;

   procedure Intern
     (H      : in out Heap_Type;
      Name   : String;
      Result : out Value;
      Ok     : out Boolean)
   is
      Hd : Handle;
   begin
      Result := Nil_Value;
      Ok := False;
      for I in Valid_Cell_Index loop
         pragma Loop_Invariant (Ok = False);
         if H.Cells (I).Kind = Cell_Symbol
           and then H.Cells (I).Name_Len = Name'Length
           and then H.Cells (I).Name (1 .. H.Cells (I).Name_Len) = Name
         then
            Result := From_Handle ((Index => I, Generation => H.Cells (I).Generation));
            Ok := True;
            return;
         end if;
      end loop;

      New_Symbol (H, Name, Hd, Ok);
      if Ok then
         Result := From_Handle (Hd);
      end if;
   end Intern;

   procedure New_Symbol
     (H      : in out Heap_Type;
      Name   : String;
      Result : out Handle;
      Ok     : out Boolean)
   is
      Pos : Natural;
   begin
      if Name'Length > Max_Text then
         Result := Null_Handle;
         Ok := False;
         return;
      end if;

      Allocate (H, Cell_Symbol, Result, Ok);
      if Ok then
         Pos := Name'First;
         for I in 1 .. Name'Length loop
            pragma Loop_Invariant (Pos = Name'First + (I - 1));
            H.Cells (Result.Index).Name (I) := Name (Pos);
            Pos := Pos + 1;
         end loop;
         H.Cells (Result.Index).Name_Len := Name'Length;
      end if;
   end New_Symbol;

   procedure New_String
     (H      : in out Heap_Type;
      Text   : String;
      Result : out Handle;
      Ok     : out Boolean)
   is
      Pos : Natural;
   begin
      if Text'Length > Max_Text then
         Result := Null_Handle;
         Ok := False;
         return;
      end if;

      Allocate (H, Cell_String, Result, Ok);
      if Ok then
         Pos := Text'First;
         for I in 1 .. Text'Length loop
            pragma Loop_Invariant (Pos = Text'First + (I - 1));
            H.Cells (Result.Index).Name (I) := Text (Pos);
            Pos := Pos + 1;
         end loop;
         H.Cells (Result.Index).Name_Len := Text'Length;
      end if;
   end New_String;

   procedure New_Vector
     (H        : in out Heap_Type;
      Elements : Value;
      Arity    : Natural;
      Result   : out Handle;
      Ok       : out Boolean)
   is
   begin
      Allocate (H, Cell_Vector, Result, Ok);
      if Ok then
         H.Cells (Result.Index).Car := Elements;
         H.Cells (Result.Index).Arity := Arity;
      end if;
   end New_Vector;

   procedure New_Bytevector
     (H      : in out Heap_Type;
      Data   : String;
      Result : out Handle;
      Ok     : out Boolean)
   is
      Pos : Natural;
   begin
      if Data'Length > Max_Text then
         Result := Null_Handle;
         Ok := False;
         return;
      end if;

      Allocate (H, Cell_Bytevector, Result, Ok);
      if Ok then
         Pos := Data'First;
         for I in 1 .. Data'Length loop
            pragma Loop_Invariant (Pos = Data'First + (I - 1));
            H.Cells (Result.Index).Name (I) := Data (Pos);
            Pos := Pos + 1;
         end loop;
         H.Cells (Result.Index).Name_Len := Data'Length;
      end if;
   end New_Bytevector;

   procedure New_Input_Port
     (H      : in out Heap_Type;
      Source : Value;
      Result : out Handle;
      Ok     : out Boolean)
   is
      C    : Cell;
      Hd   : Handle;
      Good : Boolean;
   begin
      Result := Null_Handle;
      Ok     := False;
      if not Is_Handle (Source) then
         return;
      end if;
      Fetch (H, To_Handle (Source), C, Good);
      if not Good or else C.Kind /= Cell_String then
         return;
      end if;
      Allocate (H, Cell_Input_Port, Hd, Ok);
      if not Ok then
         return;
      end if;
      for I in 1 .. C.Name_Len loop
         H.Cells (Hd.Index).Name (I) := C.Name (I);
      end loop;
      H.Cells (Hd.Index).Name_Len := C.Name_Len;
      H.Cells (Hd.Index).Arity := 0;
      Result := Hd;
   end New_Input_Port;

   procedure New_Output_Port
     (H      : in out Heap_Type;
      Result : out Handle;
      Ok     : out Boolean)
   is
      Hd : Handle;
   begin
      Result := Null_Handle;
      Allocate (H, Cell_Output_Port, Hd, Ok);
      if not Ok then
         return;
      end if;
      H.Cells (Hd.Index).Name_Len := 0;
      H.Cells (Hd.Index).Arity := 0;
      Result := Hd;
   end New_Output_Port;

   procedure New_Continuation
     (H      : in out Heap_Type;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      Allocate (H, Cell_Continuation, Result, Ok);
   end New_Continuation;

   procedure New_Values
     (H      : in out Heap_Type;
      List   : Value;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      Allocate (H, Cell_Values, Result, Ok);
      if Ok then
         H.Cells (Result.Index).Car := List;
      end if;
   end New_Values;

   procedure Set_Port_Pos
     (H   : in out Heap_Type;
      V   : Value;
      Pos : Natural;
      Ok  : out Boolean)
   is
      C    : Cell;
      Good : Boolean;
   begin
      Ok := False;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good or else C.Kind /= Cell_Input_Port then
         return;
      end if;
      H.Cells (Valid_Cell_Index (To_Handle (V).Index)).Arity := Pos;
      Ok := True;
   end Set_Port_Pos;

   procedure Set_Port_Text
     (H    : in out Heap_Type;
      V    : Value;
      Text : String;
      Ok   : out Boolean)
   is
      C    : Cell;
      Good : Boolean;
      Idx  : Valid_Cell_Index;
   begin
      Ok := False;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good or else C.Kind /= Cell_Output_Port then
         return;
      end if;
      Idx := Valid_Cell_Index (To_Handle (V).Index);
      for I in 1 .. Text'Length loop
         pragma Loop_Invariant (I <= Max_Text);
         H.Cells (Idx).Name (I) := Text (Text'First + (I - 1));
      end loop;
      H.Cells (Idx).Name_Len := Text'Length;
      H.Cells (Idx).Arity := Text'Length;
      Ok := True;
   end Set_Port_Text;

   procedure New_Closure
     (H      : in out Heap_Type;
      Params : Value;
      Forms  : Value;
      Env    : Handle;
      Arity  : Natural;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      Allocate (H, Cell_Closure, Result, Ok);
      if Ok then
         H.Cells (Result.Index).Car := Params;
         H.Cells (Result.Index).Cdr := Forms;
         H.Cells (Result.Index).Env := Env;
         H.Cells (Result.Index).Arity := Arity;
      end if;
   end New_Closure;

   procedure New_Primitive
     (H      : in out Heap_Type;
      Prim   : Primitive_Id;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      Allocate (H, Cell_Primitive, Result, Ok);
      if Ok then
         H.Cells (Result.Index).Prim := Prim;
      end if;
   end New_Primitive;

   procedure New_Environment
     (H      : in out Heap_Type;
      Parent : Handle;
      Result : out Handle;
      Ok     : out Boolean)
   is
   begin
      Allocate (H, Cell_Environment, Result, Ok);
      if Ok then
         H.Cells (Result.Index).Car := Nil_Value;
         H.Cells (Result.Index).Env := Parent;
      end if;
   end New_Environment;

   procedure Set_Byte
     (H     : in out Heap_Type;
      V     : Value;
      Index : Natural;
      Byte  : Character;
      Ok    : out Boolean)
   is
      C    : Cell;
      Good : Boolean;
   begin
      Ok := False;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good
        or else C.Kind /= Cell_Bytevector
        or else Index >= C.Name_Len
      then
         return;
      end if;
      H.Cells (Valid_Cell_Index (To_Handle (V).Index)).Name (Index + 1) := Byte;
      Ok := True;
   end Set_Byte;

   procedure Set_Car
     (H    : in out Heap_Type;
      Pair : Handle;
      V    : Value;
      Ok   : out Boolean)
   is
      C : Cell;
   begin
      Fetch (H, Pair, C, Ok);
      if Ok and then C.Kind = Cell_Pair then
         H.Cells (Valid_Cell_Index (Pair.Index)).Car := V;
      else
         Ok := False;
      end if;
   end Set_Car;

   procedure Set_Cdr
     (H    : in out Heap_Type;
      Pair : Handle;
      V    : Value;
      Ok   : out Boolean)
   is
      C : Cell;
   begin
      Fetch (H, Pair, C, Ok);
      if Ok and then C.Kind = Cell_Pair then
         H.Cells (Valid_Cell_Index (Pair.Index)).Cdr := V;
      else
         Ok := False;
      end if;
   end Set_Cdr;

   --  Collector
   --  ----------------

   procedure Collect
     (H     : in out Heap_Type;
      Roots : Root_Array;
      Count : Root_Count)
   is
      Free_Before : constant Natural := H.Free_Count;
      Max_Mark    : Unsigned_64 := 0;
      Next_Idx    : Integer range 1 .. Max_Cells + 1 := 1;
      Idx         : Valid_Cell_Index;
      Car_V       : Value;
      Cdr_V       : Value;
      Env_H       : Handle;
      Verified    : Boolean;

      --  Mark one child of the cell being drained and push it on the
      --  worklist.  The liveness test is written out rather than through
      --  Live_Cell so the marked index and the closure predicate's index
      --  are the same expression.  Nested on purpose: GNATprove inlines
      --  local subprograms for proof, and the inlined body is what lets the
      --  worklist invariant see the mark-and-push directly.
      procedure Mark_Child (V : Value) is
      begin
         if Is_Handle (V)
           and then To_Handle (V).Index in Valid_Cell_Index
           and then H.Cells (To_Handle (V).Index).Kind /= Cell_Free
           and then H.Cells (To_Handle (V).Index).Generation =
             To_Handle (V).Generation
           and then H.Cells (To_Handle (V).Index).Mark_Epoch /= H.Epoch
         then
            H.Cells (To_Handle (V).Index).Mark_Epoch := H.Epoch;
            if H.Mark_Top = Max_Cells then
               --  Unreachable while each cell is pushed at most once, but
               --  keeping the guard makes the failure explicit.
               H.Mark_Failed := True;
            else
               H.Mark_Top := H.Mark_Top + 1;
               H.Mark_Stack (Valid_Cell_Index (H.Mark_Top)) :=
                 Valid_Cell_Index (To_Handle (V).Index);
            end if;
         end if;
      end Mark_Child;

   begin
      H.Mark_Failed := False;
      H.Mark_Top := 0;

      --  A previous cycle already at the last epoch cannot be retired
      --  again without wrapping: stop freeing altogether rather than ever
      --  sweeping against a stale epoch.
      if H.Collect_Stopped then
         H.Mark_Failed := True;
         return;
      end if;

      --  Jump the epoch past every mark in the arena.  After this loop the
      --  heap is provably clean for the new cycle -- no cell carries the
      --  new epoch -- derived here and nowhere else, so no call site ever
      --  has to reason about what a previous collection left behind.
      while Next_Idx <= Max_Cells loop
         pragma Loop_Invariant (Next_Idx <= Max_Cells + 1);
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Free_Count = Free_Before);
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if Integer (J) < Next_Idx
               then H.Cells (J).Mark_Epoch <= Max_Mark));
         if H.Cells (Cell_Index (Next_Idx)).Mark_Epoch > Max_Mark then
            Max_Mark := H.Cells (Cell_Index (Next_Idx)).Mark_Epoch;
         end if;
         Next_Idx := Next_Idx + 1;
      end loop;

      if Max_Mark = Unsigned_64'Last then
         H.Collect_Stopped := True;
         H.Mark_Failed := True;
         return;
      end if;
      H.Epoch := Max_Mark + 1;

      --  Mark the caller's cells and seed the worklist.  The root
      --  precondition gives Kind /= Cell_Free, and this loop only raises a
      --  Mark_Epoch to Epoch, so "every marked cell is live" starts here
      --  and is preserved by Mark_Child, which only marks live children.
      for R in 1 .. Count loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Free_Count = Free_Before);
         pragma Loop_Invariant (H.Mark_Top <= Max_Cells);
         pragma Loop_Invariant
           (for all K in 1 .. H.Mark_Top =>
              Is_Marked (H, H.Mark_Stack (Valid_Cell_Index (K))));
         pragma Loop_Invariant
           (for all K in 1 .. R - 1 => Is_Marked (H, Roots (K)));
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if Is_Marked (H, J) then H.Cells (J).Kind /= Cell_Free));
         exit when H.Mark_Failed;
         if not Is_Marked (H, Roots (R)) then
            H.Cells (Roots (R)).Mark_Epoch := H.Epoch;
            if H.Mark_Top = Max_Cells then
               H.Mark_Failed := True;
            else
               H.Mark_Top := H.Mark_Top + 1;
               H.Mark_Stack (Valid_Cell_Index (H.Mark_Top)) := Roots (R);
            end if;
         end if;
      end loop;

      if H.Mark_Failed then
         H.Mark_Top := 0;
         return;
      end if;

      --  Drain the worklist.  The invariants deliberately say nothing about
      --  closure: that is checked afterwards in a read-only scan, where no
      --  array update is interleaved with the quantified fact and the
      --  preservation proofs are trivial.  Here it is enough that every
      --  entry on the stack is marked, that marked cells stay live, and
      --  that the roots stay marked.
      --  Max_Cells + 1 rounds: each round pops one cell, and in the worst
      --  case the final cell is marked and pushed by the last pop, so one
      --  extra round is needed to drain it.  Total pushes are bounded by
      --  Max_Cells because a cell is pushed only when it becomes marked.
      for K in 1 .. Max_Cells + 1 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Mark_Top <= Max_Cells);
         pragma Loop_Invariant (H.Free_Count = Free_Before);
         pragma Loop_Invariant
           (for all N in 1 .. H.Mark_Top =>
              Is_Marked (H, H.Mark_Stack (Valid_Cell_Index (N))));
         pragma Loop_Invariant
           (for all R in 1 .. Count => Is_Marked (H, Roots (R)));
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if Is_Marked (H, J) then H.Cells (J).Kind /= Cell_Free));
         exit when H.Mark_Top = 0 or else H.Mark_Failed;

         Idx := H.Mark_Stack (Valid_Cell_Index (H.Mark_Top));
         H.Mark_Top := H.Mark_Top - 1;
         --  Copy only the fields marking needs; a Cell carries a 256-byte
         --  text buffer, so copying it would dominate a collection.
         Car_V := H.Cells (Idx).Car;
         Cdr_V := H.Cells (Idx).Cdr;
         Mark_Child (Car_V);
         Mark_Child (Cdr_V);
         if H.Cells (Idx).Kind = Cell_Closure
           or else H.Cells (Idx).Kind = Cell_Environment
         then
            Env_H := H.Cells (Idx).Env;
            Mark_Child (From_Handle (Env_H));
         end if;
      end loop;

      --  A for-loop that runs to completion does not imply its exit
      --  condition: a non-empty worklist here means the rounds ran out.
      if H.Mark_Top /= 0 then
         H.Mark_Failed := True;
      end if;

      if H.Mark_Failed then
         H.Mark_Top := 0;
         return;
      end if;

      --  Verification scan: check the closure of the marked set on the
      --  finished heap, without writing it.  The loop invariants are the
      --  three per-child facts over the cells already scanned; because the
      --  body does not touch H, their preservation is immediate, and a
      --  failure simply abandons the cycle (Mark_Failed), which can only
      --  leave garbage in place, never free live data.  This is what lets
      --  the drain above keep trivial invariants and stay O(n).
      Verified := True;
      for J in Valid_Cell_Index loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Mark_Top = 0);
         pragma Loop_Invariant (H.Free_Count = Free_Before);
         pragma Loop_Invariant
           (for all R in 1 .. Count => Is_Marked (H, Roots (R)));
         pragma Loop_Invariant
           (for all K in Valid_Cell_Index =>
              (if Is_Marked (H, K) then H.Cells (K).Kind /= Cell_Free));
         pragma Loop_Invariant
           (for all K in Valid_Cell_Index =>
              (if K < J and then Is_Marked (H, K)
               then Child_Marked (H, H.Cells (K).Car)));
         pragma Loop_Invariant
           (for all K in Valid_Cell_Index =>
              (if K < J and then Is_Marked (H, K)
               then Child_Marked (H, H.Cells (K).Cdr)));
         pragma Loop_Invariant
           (for all K in Valid_Cell_Index =>
              (if K < J and then Is_Marked (H, K)
                 and then (H.Cells (K).Kind = Cell_Closure
                           or else H.Cells (K).Kind = Cell_Environment)
               then Child_Marked (H, From_Handle (H.Cells (K).Env))));

         if Is_Marked (H, J) then
            if not (Child_Marked (H, H.Cells (J).Car)
                    and then Child_Marked (H, H.Cells (J).Cdr)
                    and then
                      (if H.Cells (J).Kind = Cell_Closure
                         or else H.Cells (J).Kind = Cell_Environment
                       then Child_Marked
                         (H, From_Handle (H.Cells (J).Env))
                       else True))
            then
               Verified := False;
               exit;
            end if;
         end if;
      end loop;

      if not Verified then
         H.Mark_Failed := True;
      end if;
   end Collect;

end Tr7.Heap;
