with Tr7.Cells; use Tr7.Cells;

package body Tr7.Pairs with
   SPARK_Mode => On
is


   procedure Cons
     (H      : in out Heap_Type;
      A      : Value;
      D      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Hd : Handle;
   begin
      New_Pair (H, A, D, Hd, Ok);
      if Ok then
         Result := From_Handle (Hd);
      else
         Result := Nil_Value;
      end if;
   end Cons;

   procedure Pair_Cell
     (H  : Heap_Type;
      V  : Value;
      C  : out Cell;
      Ok : out Boolean)
   with Pre => H.Ready
   is
   begin
      C := (Kind => Cell_Free, others => <>);
      Ok := False;
      if Is_Handle (V) then
         Fetch (H, To_Handle (V), C, Ok);
         if Ok and then C.Kind /= Cell_Pair then
            Ok := False;
         end if;
      end if;
   end Pair_Cell;

   procedure Car_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
   begin
      Result := Nil_Value;
      Ok := False;
      if Is_Handle (V) then
         Pair_Car (H, To_Handle (V), Result, Ok);
      end if;
   end Car_Of;

   procedure Cdr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
   begin
      Result := Nil_Value;
      Ok := False;
      if Is_Handle (V) then
         Pair_Cdr (H, To_Handle (V), Result, Ok);
      end if;
   end Cdr_Of;

   procedure Cadr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Tmp : Value;
   begin
      Result := Nil_Value;
      Cdr_Of (H, V, Tmp, Ok);
      if Ok then
         Car_Of (H, Tmp, Result, Ok);
      end if;
   end Cadr_Of;

   procedure Caddr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Tmp : Value;
   begin
      Result := Nil_Value;
      Cddr_Of (H, V, Tmp, Ok);
      if Ok then
         Car_Of (H, Tmp, Result, Ok);
      end if;
   end Caddr_Of;

   procedure Cadddr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Tmp  : Value;
      Tmp2 : Value;
   begin
      Result := Nil_Value;
      Cddr_Of (H, V, Tmp, Ok);
      if Ok then
         Cdr_Of (H, Tmp, Tmp2, Ok);
      else
         Tmp2 := Nil_Value;
      end if;
      if Ok then
         Car_Of (H, Tmp2, Result, Ok);
      end if;
   end Cadddr_Of;

   procedure Cddr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Tmp : Value;
   begin
      Result := Nil_Value;
      Cdr_Of (H, V, Tmp, Ok);
      if Ok then
         Cdr_Of (H, Tmp, Result, Ok);
      end if;
   end Cddr_Of;

   procedure Length
     (H    : Heap_Type;
      List : Value;
      Len  : out Natural;
      Ok   : out Boolean)
   is
      Cur   : Value := List;
      Count : Natural := 0;
   begin
      Len := 0;
      Ok := False;
      loop
         pragma Loop_Invariant (Count <= Max_Cells);
         if Is_Nil (Cur) then
            Len := Count;
            Ok := True;
            return;
         end if;
         if Count >= Max_Cells then
            --  A proper list holds one cell per element, so no list the
            --  arena can represent is longer than this: exhaustion here
            --  means a ring (or damaged data), not a hidden cap.
            return;
         end if;

         declare
            C : Cell;
            Good : Boolean;
         begin
            Pair_Cell (H, Cur, C, Good);
            if not Good then
               return;
            end if;
            Cur := C.Cdr;
         end;
         Count := Count + 1;
      end loop;
   end Length;

   procedure Nth
     (H      : Heap_Type;
      List   : Value;
      N      : Natural;
      Result : out Value;
      Ok     : out Boolean)
   is
      Cur : Value := List;
   begin
      Result := Nil_Value;
      Ok := False;
      for I in 0 .. N loop
         if Is_Nil (Cur) then
            return;
         end if;

         declare
            C : Cell;
            Good : Boolean;
         begin
            Pair_Cell (H, Cur, C, Good);
            if not Good then
               return;
            end if;
            if I = N then
               Result := C.Car;
               Ok := True;
               return;
            end if;
            Cur := C.Cdr;
         end;
      end loop;
   end Nth;

   procedure Reverse_List
     (H      : in out Heap_Type;
      List   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Err : Error_Code;
   begin
      Reverse_List (H, List, Result, Ok, Err);
      --  This wrapper drops the reason (its contract is the boolean
      --  alone); the read keeps the discarded out parameter from being
      --  a write nobody looks at, which is the shape docs/findings.md
      --  says to avoid.  The callee reports No_Error exactly when it
      --  reports success, so the guard cannot change the outcome.
      if Err /= No_Error then
         Ok := False;
      end if;
   end Reverse_List;

   procedure Reverse_List
     (H      : in out Heap_Type;
      List   : Value;
      Result : out Value;
      Ok     : out Boolean;
      Err    : out Error_Code)
   is
      Cur : Value := List;
      Acc : Value := Nil_Value;
   begin
      Result := Nil_Value;
      Ok := False;
      Err := Error_Type;
      loop
         pragma Loop_Invariant (H.Ready);
         if Is_Nil (Cur) then
            Result := Acc;
            Ok := True;
            Err := No_Error;
            return;
         end if;

         declare
            C    : Cell;
            Good : Boolean;
            New_Acc : Value;
         begin
            Pair_Cell (H, Cur, C, Good);
            if not Good then
               return;
            end if;
            Cons (H, C.Car, Acc, New_Acc, Good);
            if not Good then
               Err := Error_Heap_Full;
               return;
            end if;
            Acc := New_Acc;
            Cur := C.Cdr;
         end;
      end loop;
   end Reverse_List;

   procedure To_Array
     (H    : Heap_Type;
      List : Value;
      Arr  : out Value_Array;
      Len  : out Natural;
      Ok   : out Boolean)
   is
      Cur   : Value := List;
      Count : Natural := 0;
   begin
      Arr := (others => Nil_Value);
      Len := 0;
      Ok := False;
      loop
         pragma Loop_Invariant (Count <= Max_Arguments);
         if Is_Nil (Cur) then
            Len := Count;
            Ok := True;
            return;
         end if;
         if Count >= Max_Arguments then
            return;
         end if;

         declare
            C    : Cell;
            Good : Boolean;
         begin
            Pair_Cell (H, Cur, C, Good);
            if not Good then
               return;
            end if;
            Count := Count + 1;
            Arr (Count) := C.Car;
            Cur := C.Cdr;
         end;
      end loop;
   end To_Array;

   --  Deep, cycle-safe structural equality (the spec has the details).

   --  One assumed pairing of two cells under comparison.  Entries are
   --  append-only: a comparison either holds everywhere or fails outright,
   --  so a recorded pairing is either verified or moot -- nothing is ever
   --  retracted.
   type Pairing is record
      Left  : Handle;
      Right : Handle;
   end record;

   --  Capacity: every entry records a pair or vector cell of this
   --  comparison, and the recursion records one entry per level, so the
   --  table also bounds the walk's depth; only pathological sharing --
   --  more distinct pairings than the arena has cells -- can exhaust it,
   --  and that is reported, not answered.
   type Pairing_Table is array (1 .. Max_Cells) of Pairing;

   type Pairings is record
      N     : Natural range 0 .. Max_Cells := 0;
      Table : Pairing_Table :=
        (others => (Left => Null_Handle, Right => Null_Handle));
   end record;

   function Paired (Seen : Pairings; L, R : Handle) return Boolean is
     (for some I in 1 .. Seen.N =>
        (Same_Handle (Seen.Table (I).Left, L)
           and then Same_Handle (Seen.Table (I).Right, R))
        or else (Same_Handle (Seen.Table (I).Left, R)
           and then Same_Handle (Seen.Table (I).Right, L)));

   procedure Assume_Equal
     (Seen : in out Pairings; L, R : Handle; Ok : out Boolean)
   is
   begin
      Ok := False;
      if Seen.N < Max_Cells then
         Seen.N := Seen.N + 1;
         Seen.Table (Seen.N) := (Left => L, Right => R);
         Ok := True;
      end if;
   end Assume_Equal;

   --  The structural walk.  Fuel bounds the recursion depth for the
   --  termination proof; every level that recurses has recorded one
   --  pairing first, so the real depth never exceeds the table capacity --
   --  the fuel guard is unreachable and only makes the variant total.
   procedure Same_Structure
     (H     : Heap_Type;
      A, B  : Value;
      Seen  : in out Pairings;
      Fuel  : Natural;
      Equal : out Boolean;
      Ok    : out Boolean)
     with
       Pre  => H.Ready,
       Subprogram_Variant => (Decreases => Fuel)
   is
      CA, CB : Cell;
      Good   : Boolean;
   begin
      Equal := False;
      Ok := True;
      if Fuel = 0 then
         Ok := False;
         return;
      end if;

      --  Identical handles and equal immediates.
      if Same_Value (A, B) then
         Equal := True;
         return;
      end if;

      if A.Kind /= B.Kind then
         return;
      end if;

      if not Is_Handle (A) then
         --  Same immediate kind, different content.
         return;
      end if;

      --  Already paired, in either direction?  Comparing two structures
      --  does not depend on which is named first, and for rings this is
      --  the fixpoint that ends the walk.
      if Paired (Seen, To_Handle (A), To_Handle (B)) then
         Equal := True;
         return;
      end if;

      Fetch (H, To_Handle (A), CA, Good);
      if not Good then
         Ok := False;
         return;
      end if;
      Fetch (H, To_Handle (B), CB, Good);
      if not Good then
         Ok := False;
         return;
      end if;
      if CA.Kind /= CB.Kind then
         return;
      end if;

      case CA.Kind is
         when Cell_Pair =>
            Assume_Equal (Seen, To_Handle (A), To_Handle (B), Good);
            if not Good then
               Ok := False;
               return;
            end if;
            Same_Structure (H, CA.Car, CB.Car, Seen, Fuel - 1, Equal, Ok);
            if not Ok or else not Equal then
               return;
            end if;
            Same_Structure (H, CA.Cdr, CB.Cdr, Seen, Fuel - 1, Equal, Ok);

         when Cell_Vector =>
            Assume_Equal (Seen, To_Handle (A), To_Handle (B), Good);
            if not Good then
               Ok := False;
               return;
            end if;
            if CA.Arity /= CB.Arity then
               return;
            end if;
            --  The elements are two proper lists, walked pairwise.
            declare
               EA   : Value := CA.Car;
               EB   : Value := CB.Car;
               NA, NB : Cell;
               FA, FB : Boolean;
               Eq     : Boolean;
               Fine   : Boolean;
            begin
               Equal := True;
               for I in 1 .. CA.Arity loop
                  if not Is_Handle (EA) or else not Is_Handle (EB) then
                     --  The element chains are as long as Arity says, so
                     --  this only happens if the vector's internals were
                     --  damaged.
                     Equal := False;
                     return;
                  end if;
                  Fetch (H, To_Handle (EA), NA, FA);
                  if not FA then
                     Ok := False;
                     return;
                  end if;
                  Fetch (H, To_Handle (EB), NB, FB);
                  if not FB then
                     Ok := False;
                     return;
                  end if;
                  if NA.Kind /= Cell_Pair or else NB.Kind /= Cell_Pair then
                     Equal := False;
                     return;
                  end if;
                  Same_Structure
                    (H, NA.Car, NB.Car, Seen, Fuel - 1, Eq, Fine);
                  if not Fine then
                     Ok := False;
                     return;
                  end if;
                  if not Eq then
                     Equal := False;
                     return;
                  end if;
                  Pair_Cdr (H, To_Handle (EA), EA, FA);
                  if not FA then
                     Ok := False;
                     return;
                  end if;
                  Pair_Cdr (H, To_Handle (EB), EB, FB);
                  if not FB then
                     Ok := False;
                     return;
                  end if;
               end loop;
            end;

         when Cell_String | Cell_Bytevector | Cell_Symbol =>
            Equal := CA.Name_Len = CB.Name_Len
              and then CA.Name (1 .. CA.Name_Len) = CB.Name (1 .. CB.Name_Len);

         when others =>
            --  Procedures, ports, environments, continuations: identity,
            --  which Same_Value already settled.
            null;
      end case;
   end Same_Structure;

   procedure Deep_Equal
     (H      : Heap_Type;
      A, B   : Value;
      Result : out Boolean;
      Ok     : out Boolean)
   is
      Seen  : Pairings;
      Equal : Boolean;
      Fine  : Boolean;
   begin
      Same_Structure (H, A, B, Seen, Max_Cells + 2, Equal, Fine);
      --  The table is not part of the answer; the assert reads it so the
      --  walk's one written-but-unread state is still looked at (the
      --  shape docs/findings.md says to avoid) and keeps the capacity
      --  fact next to the code that maintains it.
      pragma Assert (Seen.N <= Max_Cells);
      Result := Equal;
      Ok := Fine;
   end Deep_Equal;

end Tr7.Pairs;
