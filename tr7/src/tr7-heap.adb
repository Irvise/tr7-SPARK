
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
      C           : Cell;

      --  Root one child of the cell being drained, exactly as the old
      --  Mark_Root did.  Nested on purpose: GNATprove inlines local
      --  subprograms for proof, and the inlined body is what lets the
      --  drain's closure invariant see the mark-and-push directly -- a
      --  contract could not, without an unaffordable array-frame clause
      --  that would keep the other invariants from proving.
      procedure Root_Child (V : Value) is
         Child : Cell_Index;
      begin
         Child := Live_Cell (H, V);
         if Child /= 0 and then not Is_Marked (H, Child) then
            if H.Mark_Top = Max_Cells then
               H.Mark_Failed := True;
            else
               H.Cells (Child).Mark_Epoch := H.Epoch;
               H.Cells (Child).Queued := H.Epoch;
               H.Mark_Top := H.Mark_Top + 1;
               H.Mark_Stack (Valid_Cell_Index (H.Mark_Top)) :=
                 Valid_Cell_Index (Child);
            end if;
         end if;
      end Root_Child;

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

      --  Root the caller's cells.  The stack starts empty (just reset), so
      --  the worklist invariants below begin from nothing on it.
      for R in 1 .. Count loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Free_Count = Free_Before);
         pragma Loop_Invariant (H.Mark_Top <= Max_Cells);
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if Is_Marked (H, J) then On_Stack (H, J)));
         pragma Loop_Invariant
           (for all K in 1 .. H.Mark_Top => Is_Marked (H, H.Mark_Stack (Valid_Cell_Index (K))));
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if Is_Marked (H, J) then H.Cells (J).Kind /= Cell_Free));
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if H.Cells (J).Queued /= 0
               then H.Cells (J).Queued = H.Cells (J).Mark_Epoch));
         exit when H.Mark_Failed;
         if not Is_Marked (H, Roots (R)) then
            if H.Mark_Top = Max_Cells then
               H.Mark_Failed := True;
            else
               H.Cells (Roots (R)).Mark_Epoch := H.Epoch;
               H.Cells (Roots (R)).Queued := H.Epoch;
               H.Mark_Top := H.Mark_Top + 1;
               H.Mark_Stack (Valid_Cell_Index (H.Mark_Top)) := Roots (R);
            end if;
         end if;
      end loop;

      --  Drain the mark stack.  Each round visits one cell and roots its
      --  children; a cell is pushed at most once (marked on the way in).
      for K in 1 .. Max_Cells loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Mark_Top <= Max_Cells);
         pragma Loop_Invariant (H.Free_Count = Free_Before);
         --  One-step closure of the marked set: every marked cell is still
         --  on the worklist or has all of its children marked.  Root_Child
         --  is nested precisely so this preservation proof sees its body.
         pragma Loop_Invariant (H.Mark_Failed or else Drained_Car (H));
         pragma Loop_Invariant (H.Mark_Failed or else Drained_Cdr (H));
         pragma Loop_Invariant (H.Mark_Failed or else Drained_Env (H));
         pragma Loop_Invariant
           (for all K in 1 .. H.Mark_Top =>
              Is_Marked (H, H.Mark_Stack (Valid_Cell_Index (K))));
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if Is_Marked (H, J) then H.Cells (J).Kind /= Cell_Free));
         --  A live queue tag is always the epoch the cell was marked with,
         --  which the epoch jump has already pushed past: that is what
         --  makes "no cell is queued" follow at a successful exit.
         pragma Loop_Invariant
           (for all J in Valid_Cell_Index =>
              (if H.Cells (J).Queued /= 0
               then H.Cells (J).Queued = H.Cells (J).Mark_Epoch));
         exit when H.Mark_Top = 0 or else H.Mark_Failed;

         Idx := H.Mark_Stack (Valid_Cell_Index (H.Mark_Top));
         H.Mark_Top := H.Mark_Top - 1;
         H.Cells (Idx).Queued := 0;
         C := H.Cells (Idx);

         Root_Child (C.Car);
         Root_Child (C.Cdr);
         if C.Kind = Cell_Closure or else C.Kind = Cell_Environment then
            Root_Child (From_Handle (C.Env));
         end if;
      end loop;

      --  A for-loop that runs to completion does not imply its exit
      --  condition: a non-empty stack here means the rounds ran out, which
      --  is exactly the "marking did not finish" case -- record it as a
      --  failure so the caller skips the sweep.  The epoch jump at the next
      --  call retires whatever was marked.
      if H.Mark_Top /= 0 then
         H.Mark_Failed := True;
      end if;

      if H.Mark_Failed then
         H.Mark_Top := 0;
         return;
      end if;
      --  Marking completed: the closure facts are in the postcondition and
      --  the sweep runs in Tr7.Reach, on the caller's side of the failure
      --  flag.
   end Collect;

end Tr7.Heap;
