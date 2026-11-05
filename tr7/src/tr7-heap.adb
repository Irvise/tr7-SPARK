
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

   procedure Fetch
     (H  : Heap_Type;
      Hd : Handle;
      C  : out Cell;
      Ok : out Boolean)
   is
   begin
      C := (Kind => Cell_Free, others => <>);
      Ok := False;
      if Hd.Index in Valid_Cell_Index then
         if H.Cells (Hd.Index).Generation = Hd.Generation
           and then H.Cells (Hd.Index).Kind /= Cell_Free
         then
            C := H.Cells (Hd.Index);
            Ok := True;
         end if;
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

   procedure Mark_Root (H : in out Heap_Type; V : Value) is
      Hd    : Handle;
      C     : Cell;
      Valid : Boolean;
   begin
      if H.Collect_Stopped then
         --  Epochs are exhausted, so marking again could only produce a set
         --  the sweep would misread: report failure instead.  Collect then
         --  skips the sweep and never frees anything again -- the heap fills
         --  up and reports exhaustion, which is a Scheme error rather than a
         --  freed live cell.
         H.Mark_Failed := True;
         return;
      end if;

      if not Is_Handle (V) then
         return;
      end if;

      Hd := To_Handle (V);
      --  Fetch rejects stale handles, freed cells and index 0, so a root that
      --  no longer resolves is simply ignored.
      Fetch (H, Hd, C, Valid);
      if not Valid then
         return;
      end if;
      if C.Mark_Epoch = H.Epoch then
         --  Already rooted in this cycle; its children were queued on the
         --  first visit, so it must not be queued twice.
         return;
      end if;

      if H.Mark_Top = Max_Cells then
         H.Mark_Failed := True;
         return;
      end if;

      H.Cells (Valid_Cell_Index (Hd.Index)).Mark_Epoch := H.Epoch;
      H.Mark_Top := H.Mark_Top + 1;
      H.Mark_Stack (Valid_Cell_Index (H.Mark_Top)) := Valid_Cell_Index (Hd.Index);
   end Mark_Root;

   procedure Collect (H : in out Heap_Type) is
      Free_Before  : constant Natural := H.Free_Count;
      Epoch_Before : constant Unsigned_64 := H.Epoch;
      Idx          : Valid_Cell_Index;
      C            : Cell;
   begin
      --  Drain the mark stack.  Each round visits one cell and roots its
      --  children; a cell is pushed at most once, so Max_Cells rounds always
      --  empty the stack.  The bound also keeps the work of one collection
      --  explicit.
      for K in 1 .. Max_Cells loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Mark_Top <= Max_Cells);
         --  Rooting only writes mark epochs, so the free list is still
         --  exactly what it was when Collect was entered and the cycle has
         --  not moved on; the sweep relies on both.
         pragma Loop_Invariant (H.Free_Count = Free_Before);
         pragma Loop_Invariant (H.Epoch = Epoch_Before);
         exit when H.Mark_Top = 0 or else H.Mark_Failed;

         Idx := H.Mark_Stack (Valid_Cell_Index (H.Mark_Top));
         H.Mark_Top := H.Mark_Top - 1;
         C := H.Cells (Idx);

         --  Every kind that can hold values holds them in Car/Cdr, and they
         --  default to nil for the kinds that do not -- allocation resets
         --  them -- so marking both unconditionally means no future cell kind
         --  can be silently unrooted.  Only closures and environments carry a
         --  separate environment handle.
         Mark_Root (H, C.Car);
         Mark_Root (H, C.Cdr);
         if C.Kind = Cell_Closure or else C.Kind = Cell_Environment then
            Mark_Root (H, From_Handle (C.Env));
         end if;
      end loop;

      if H.Mark_Failed or else H.Mark_Top /= 0 then
         --  Marking did not finish, so the marked set is not known to cover
         --  everything reachable: abandon the cycle without sweeping.  The
         --  epoch still advances, and that is what retires the marks made
         --  above -- no clearing pass over the arena, and the heap is left
         --  exactly as it was.  The caller gets less garbage reclaimed: a
         --  Scheme error at worst, never a freed live cell.
         H.Mark_Top := 0;
         H.Mark_Failed := False;
         if H.Epoch = Unsigned_64'Last then
            H.Collect_Stopped := True;
         else
            H.Epoch := H.Epoch + 1;
         end if;
         return;
      end if;

      --  Sweep.  A cell whose mark epoch is not the current cycle's was never
      --  reached from a root, so it is unreachable.  This is a single linear
      --  pass with scalar invariants -- no quantified invariant, which matters
      --  because -gnata evaluates those at run time and a 4,096 x 4,096 one
      --  costs milliseconds per collection (docs/findings.md).
      for I in Valid_Cell_Index loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Mark_Top = 0);
         pragma Loop_Invariant (H.Free_Count >= Free_Before);
         pragma Loop_Invariant (H.Epoch = Epoch_Before);
         if H.Cells (I).Mark_Epoch /= H.Epoch
           and then H.Cells (I).Kind /= Cell_Free
         then
            --  Unreachable: push it back on the free list, exactly as Release
            --  would.  The guard keeps Free_Count inside its subtype; if the
            --  list were ever full the cell would simply stay allocated.
            if H.Free_Count < Max_Cells then
               H.Cells (I).Kind := Cell_Free;
               H.Cells (I).Next_Free := H.Free_Head;
               H.Free_Head := I;
               H.Free_Count := H.Free_Count + 1;
            end if;
         end if;
      end loop;

      --  Retire this cycle's marks.  From the next Mark_Root on, every cell
      --  looks unmarked, which replaces the clearing pass that used to live
      --  here.
      if H.Epoch = Unsigned_64'Last then
         H.Collect_Stopped := True;
      else
         H.Epoch := H.Epoch + 1;
      end if;
   end Collect;

end Tr7.Heap;
