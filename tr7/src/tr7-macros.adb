with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;

package body Tr7.Macros with
   SPARK_Mode => On
is

   --  Enough for every list level and every rule in a practical macro; a
   --  malformed or unsupported pattern runs out of fuel and simply fails to
   --  match (the caller reports an error rather than looping).
   Macro_Fuel : constant := 8 * Max_List_Length;

   function Is_Symbol_Named
     (H : Heap_Type; V : Value; Name : String) return Boolean
     with Pre => H.Ready
   is
      C : Cell;
      Good : Boolean;
   begin
      if not Is_Handle (V) then
         return False;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      return Good
        and then C.Kind = Cell_Symbol
        and then C.Name_Len = Name'Length
        and then C.Name (1 .. C.Name_Len) = Name;
   end Is_Symbol_Named;

   function Is_Ellipsis (H : Heap_Type; V : Value) return Boolean is
     (Is_Symbol_Named (H, V, "..."))
     with Pre => H.Ready;

   --  Membership in the literals list.
   function Is_Literal
     (H : Heap_Type; Sym, Lits : Value) return Boolean
     with Pre => H.Ready
   is
      Cur  : Value := Lits;
      Left : Natural := Max_List_Length + 1;
      C    : Cell;
      Good : Boolean;
   begin
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            return False;
         end if;
         Fetch (H, To_Handle (Cur), C, Good);
         if not Good or else C.Kind /= Cell_Pair then
            return False;
         end if;
         if Same_Value (C.Car, Sym) then
            return True;
         end if;
         Cur := C.Cdr;
         Left := Left - 1;
      end loop;
      return False;
   end Is_Literal;

   --  Look up a (key . value) association built by Bind / Rep_Add.  The list
   --  may contain shadowed duplicates; the newest entry is at the front.
   procedure Lookup_Binding
     (H        : Heap_Type;
      Bindings : Value;
      Key      : Value;
      Val      : out Value;
      Found    : out Boolean;
      Ok       : out Boolean)
     with Pre => H.Ready
   is
      Cur  : Value := Bindings;
      Left : Natural := Max_List_Length + 1;
      C    : Cell;
      B    : Cell;
      Good : Boolean;
   begin
      Val := Nil_Value;
      Found := False;
      Ok := True;
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            Ok := False;
            return;
         end if;
         Fetch (H, To_Handle (Cur), C, Good);
         if not Good or else C.Kind /= Cell_Pair then
            Ok := False;
            return;
         end if;
         --  Each element is itself the (key . value) binding pair.
         if not Is_Handle (C.Car) then
            Ok := False;
            return;
         end if;
         Fetch (H, To_Handle (C.Car), B, Good);
         if not Good or else B.Kind /= Cell_Pair then
            Ok := False;
            return;
         end if;
         if Same_Value (B.Car, Key) then
            Val := B.Cdr;
            Found := True;
            return;
         end if;
         Cur := C.Cdr;
         Left := Left - 1;
      end loop;
   end Lookup_Binding;

   procedure Bind
     (H      : in out Heap_Type;
      Sym    : Value;
      Val    : Value;
      Vars   : in out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Item : Value;
   begin
      Cons (H, Sym, Val, Item, Ok);
      if not Ok then
         return;
      end if;
      declare
         New_Vars : Value;
      begin
         Cons (H, Item, Vars, New_Vars, Ok);
         if Ok then
            Vars := New_Vars;
         end if;
      end;
   end Bind;

   --  Add one value to the list stored for Sym in Reps, creating the entry if
   --  this is the first repetition.  Appending keeps the source order that
   --  the template sees.
   procedure Rep_Add
     (H    : in out Heap_Type;
      Sym  : Value;
      Val  : Value;
      Reps : in out Value;
      Ok   : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready
   is
      Old   : Value;
      Found : Boolean;
      Good  : Boolean;
      Cur   : Value;
      Acc   : Value;
      Item  : Value;
      Rev   : Value;
      New_L : Value;
      Left  : Natural := Max_List_Length + 1;
   begin
      Lookup_Binding (H, Reps, Sym, Old, Found, Good);
      if not Good then
         Ok := False;
         return;
      end if;
      if Found then
         --  Reverse Old, cons Val, reverse back: append in one pass each way.
         Cur := Old;
         Acc := Nil_Value;
         while not Is_Nil (Cur) and then Left > 0 loop
            pragma Loop_Invariant (H.Ready);
            pragma Loop_Variant (Decreases => Left);
            if not Is_Handle (Cur) then
               Ok := False;
               return;
            end if;
            declare
               C : Cell;
            begin
               Fetch (H, To_Handle (Cur), C, Good);
               if not Good or else C.Kind /= Cell_Pair then
                  Ok := False;
                  return;
               end if;
               Cons (H, C.Car, Acc, Item, Ok);
               if not Ok then
                  return;
               end if;
               Acc := Item;
               Cur := C.Cdr;
               Left := Left - 1;
            end;
         end loop;
         Cons (H, Val, Acc, Rev, Ok);
         if not Ok then
            return;
         end if;
         Reverse_List (H, Rev, New_L, Ok);
      else
         Cons (H, Val, Nil_Value, New_L, Ok);
      end if;
      if not Ok then
         return;
      end if;
      Cons (H, Sym, New_L, Item, Ok);
      if not Ok then
         return;
      end if;
      declare
         New_Reps : Value;
      begin
         Cons (H, Item, Reps, New_Reps, Ok);
         if Ok then
            Reps := New_Reps;
         end if;
      end;
   end Rep_Add;

   --  Match Pat against Form, extending Vars (scalars) and Reps (ellipsis
   --  variables).  Only a trailing ellipsis is supported at each list level.
   procedure Match
     (H     : in out Heap_Type;
      Pat   : Value;
      Form  : Value;
      Lits  : Value;
      Vars  : in out Value;
      Reps  : in out Value;
      Fuel  : Natural;
      Ok    : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready,
       Subprogram_Variant => (Decreases => Fuel)
   is
      PC    : Cell;
      FC    : Cell;
      Good  : Boolean;
      Pat_Rest : Value;
      Maybe_Ell : Value;
      Tail  : Value;
      Elem  : Value;
      Cur   : Value;
      Sub_Vars : Value;
      Sub_Reps : Value;
      Left  : Natural;
      Inner_Left : Natural;
   begin
      Ok := False;
      if Fuel = 0 then
         return;
      end if;

      if Is_Nil (Pat) then
         Ok := Is_Nil (Form);
         return;
      end if;

      if not Is_Handle (Pat) then
         Ok := Same_Value (Pat, Form);
         return;
      end if;
      Fetch (H, To_Handle (Pat), PC, Good);
      if not Good then
         return;
      end if;

      if PC.Kind = Cell_Symbol then
         if Is_Ellipsis (H, Pat) then
            return;
         end if;
         if Is_Symbol_Named (H, Pat, "_") then
            Ok := True;
            return;
         end if;
         if Is_Literal (H, Pat, Lits) then
            Ok := Is_Handle (Form) and then Same_Value (Pat, Form);
            return;
         end if;
         Bind (H, Pat, Form, Vars, Ok);
         return;
      end if;
      if PC.Kind /= Cell_Pair then
         Ok := Same_Value (Pat, Form);
         return;
      end if;

      Cdr_Of (H, Pat, Pat_Rest, Good);
      if not Good then
         return;
      end if;

      --  (element ...) -- the only repetition shape supported.
      if Is_Handle (Pat_Rest) then
         Fetch (H, To_Handle (Pat_Rest), FC, Good);
         if not Good then
            return;
         end if;
         if FC.Kind = Cell_Pair then
            Car_Of (H, Pat_Rest, Maybe_Ell, Good);
            if not Good then
               return;
            end if;
            if Is_Ellipsis (H, Maybe_Ell) then
               Cdr_Of (H, Pat_Rest, Tail, Good);
               if not Good or else not Is_Nil (Tail) then
                  return;
               end if;

               --  Form must be a proper list; every element matches the
               --  repeated subpattern, and its bindings become Reps lists.
               Cur := Form;
               Left := Max_List_Length + 1;
               while not Is_Nil (Cur) and then Left > 0 loop
                  pragma Loop_Invariant (H.Ready);
                  pragma Loop_Variant (Decreases => Left);
                  if not Is_Handle (Cur) then
                     return;
                  end if;
                  Fetch (H, To_Handle (Cur), FC, Good);
                  if not Good or else FC.Kind /= Cell_Pair then
                     return;
                  end if;
                  Elem := FC.Car;
                  Sub_Vars := Nil_Value;
                  Sub_Reps := Nil_Value;
                  Match (H, PC.Car, Elem, Lits, Sub_Vars, Sub_Reps,
                         Fuel - 1, Good);
                  if not Good or else not Is_Nil (Sub_Reps) then
                     return;
                  end if;
                  --  Move every scalar binding of this iteration into the
                  --  repetition table for its variable.
                  declare
                     Bind_Cur : Value := Sub_Vars;
                     Bind_C   : Cell;
                     Bind_P   : Cell;
                  begin
                     Inner_Left := Max_List_Length + 1;
                     while not Is_Nil (Bind_Cur) and then Inner_Left > 0 loop
                        pragma Loop_Invariant (H.Ready);
                        pragma Loop_Variant (Decreases => Inner_Left);
                        if not Is_Handle (Bind_Cur) then
                           return;
                        end if;
                        Fetch (H, To_Handle (Bind_Cur), Bind_C, Good);
                        if not Good
                          or else Bind_C.Kind /= Cell_Pair
                          or else not Is_Handle (Bind_C.Car)
                        then
                           return;
                        end if;
                        --  Bind_C.Car is the (variable . value) pair.
                        Fetch (H, To_Handle (Bind_C.Car), Bind_P, Good);
                        if not Good or else Bind_P.Kind /= Cell_Pair then
                           return;
                        end if;
                        Rep_Add (H, Bind_P.Car, Bind_P.Cdr, Reps, Good);
                        if not Good then
                           return;
                        end if;
                        Bind_Cur := Bind_C.Cdr;
                        Inner_Left := Inner_Left - 1;
                     end loop;
                  end;
                  Cur := FC.Cdr;
                  Left := Left - 1;
               end loop;
               Ok := True;
               return;
            end if;
         end if;
      end if;

      --  Ordinary pair: both must be pairs, then match car and cdr.
      if not Is_Handle (Form) then
         return;
      end if;
      Fetch (H, To_Handle (Form), FC, Good);
      if not Good or else FC.Kind /= Cell_Pair then
         return;
      end if;
      Match (H, PC.Car, FC.Car, Lits, Vars, Reps, Fuel - 1, Good);
      if not Good then
         return;
      end if;
      Match (H, PC.Cdr, FC.Cdr, Lits, Vars, Reps, Fuel - 1, Ok);
   end Match;

   --  Find a repetition variable inside T and report its length.  This is
   --  what gives a template ellipsis its iteration count.
   procedure Rep_Count
     (H     : Heap_Type;
      T     : Value;
      Reps  : Value;
      N     : out Natural;
      Found : out Boolean;
      Fuel  : Natural;
      Ok    : out Boolean)
     with
       Pre  => H.Ready,
       Post => (if Ok then N <= Max_List_Length),
       Subprogram_Variant => (Decreases => Fuel)
   is
      C    : Cell;
      Good : Boolean;
      V    : Value;
      Sub  : Natural;
      Sub_Found : Boolean;
   begin
      N := 0;
      Found := False;
      Ok := True;
      if Fuel = 0 then
         return;
      end if;
      if not Is_Handle (T) then
         return;
      end if;
      Fetch (H, To_Handle (T), C, Good);
      if not Good then
         Ok := False;
         return;
      end if;
      if C.Kind = Cell_Symbol then
         Lookup_Binding (H, Reps, T, V, Found, Good);
         if not Good then
            Ok := False;
            return;
         end if;
         if Found then
            Length (H, V, N, Good);
            if not Good then
               Ok := False;
               return;
            end if;
            if N > Max_List_Length then
               --  The repetition count feeds the expansion budget, which
               --  is itself Max_List_Length-bounded: more repetitions
               --  than the budget can spend are rejected, not truncated.
               Ok := False;
               return;
            end if;
         end if;
         return;
      end if;
      if C.Kind /= Cell_Pair then
         return;
      end if;
      Rep_Count (H, C.Car, Reps, N, Found, Fuel - 1, Good);
      if not Good then
         Ok := False;
         return;
      end if;
      if Found then
         return;
      end if;
      Rep_Count (H, C.Cdr, Reps, Sub, Sub_Found, Fuel - 1, Ok);
      if not Ok then
         return;
      end if;
      if Sub_Found then
         N := Sub;
         Found := True;
      end if;
   end Rep_Count;

   --  Instantiate a template.  In_Rep says whether we are inside an ellipsis
   --  expansion; Index is the iteration currently being emitted.
   procedure Inst
     (H      : in out Heap_Type;
      Tmpl   : Value;
      Vars   : Value;
      Reps   : Value;
      In_Rep : Boolean;
      Index  : Natural;
      Result : out Value;
      Fuel   : Natural;
      Ok     : out Boolean)
     with
       Pre  => H.Ready,
       Post => H.Ready,
       Subprogram_Variant => (Decreases => Fuel)
   is
      C     : Cell;
      RC    : Cell;
      Good  : Boolean;
      Rest  : Value;
      Maybe_Ell : Value;
      Tail  : Value;
      Sub   : Value;
      V     : Value;
      Found : Boolean;
      N     : Natural;
      Has   : Boolean;
      Head  : Value;
      Tail_V : Value;
      Acc   : Value;
      Elem  : Value;
      Item  : Value;
      Tmp   : Value;
   begin
      Result := Nil_Value;
      Ok := False;
      if Fuel = 0 then
         return;
      end if;

      if Is_Handle (Tmpl) then
         Fetch (H, To_Handle (Tmpl), C, Good);
         if not Good then
            return;
         end if;
      end if;
      if Is_Handle (Tmpl) and then C.Kind = Cell_Symbol then
         Lookup_Binding (H, Vars, Tmpl, V, Found, Good);
         if not Good then
            return;
         end if;
         if Found then
            Result := V;
            Ok := True;
            return;
         end if;
         Lookup_Binding (H, Reps, Tmpl, V, Found, Good);
         if not Good then
            return;
         end if;
         if Found then
            if not In_Rep then
               return;
            end if;
            declare
               Nth_V : Value;
            begin
               Nth (H, V, Index, Nth_V, Good);
               if not Good then
                  return;
               end if;
               Result := Nth_V;
            end;
            Ok := True;
            return;
         end if;
         --  An identifier not bound by the pattern is introduced as-is
         --  (non-hygienic expansion).
         Result := Tmpl;
         Ok := True;
         return;
      end if;

      if not Is_Handle (Tmpl) then
         Result := Tmpl;
         Ok := True;
         return;
      end if;
      if C.Kind /= Cell_Pair then
         Result := Tmpl;
         Ok := True;
         return;
      end if;

      Cdr_Of (H, Tmpl, Rest, Good);
      if not Good then
         return;
      end if;

      --  (subtemplate ...): repeat the subtemplate N times, where N comes
      --  from the first repetition variable found inside it.
      if Is_Handle (Rest) then
         Fetch (H, To_Handle (Rest), RC, Good);
         if not Good then
            return;
         end if;
         if RC.Kind = Cell_Pair then
            Car_Of (H, Rest, Maybe_Ell, Good);
            if not Good then
               return;
            end if;
            if Is_Ellipsis (H, Maybe_Ell) then
               Cdr_Of (H, Rest, Tail, Good);
               if not Good or else not Is_Nil (Tail) then
                  return;
               end if;
               declare
                  Sub_T : Value;
               begin
                  Car_Of (H, Tmpl, Sub_T, Good);
                  if not Good then
                     return;
                  end if;
                  Sub := Sub_T;
               end;
               Rep_Count (H, Sub, Reps, N, Has, Fuel - 1, Good);
               if not Good or else not Has then
                  return;
               end if;
               Acc := Nil_Value;
               if N > 0 then
               for I in 0 .. N - 1 loop
                  pragma Loop_Invariant (H.Ready);
                  pragma Loop_Invariant (Fuel >= 1);
                  Inst (H, Sub, Vars, Reps, True, I, Elem,
                        Fuel - 1, Good);
                  if not Good then
                     return;
                  end if;
                  Cons (H, Elem, Acc, Tmp, Good);
                  if not Good then
                     return;
                  end if;
                  Acc := Tmp;
               end loop;
               end if;
               Reverse_List (H, Acc, Result, Good);
               Ok := Good;
               return;
            end if;
         end if;
      end if;

      --  Ordinary template list: instantiate car and cdr, then cons.
      Inst (H, C.Car, Vars, Reps, In_Rep, Index, Head, Fuel - 1, Good);
      if not Good then
         return;
      end if;
      Inst (H, C.Cdr, Vars, Reps, In_Rep, Index, Tail_V, Fuel - 1, Good);
      if not Good then
         return;
      end if;
      Cons (H, Head, Tail_V, Item, Good);
      if not Good then
         return;
      end if;
      Result := Item;
      Ok := True;
   end Inst;

   procedure Build
     (H      : in out Heap_Type;
      Spec   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Head  : Value;
      Lits  : Value;
      Rules : Value;
      Hd    : Handle;
      Good  : Boolean;
   begin
      Result := Nil_Value;
      Ok := False;
      Car_Of (H, Spec, Head, Good);
      if not Good or else not Is_Symbol_Named (H, Head, "syntax-rules") then
         return;
      end if;
      Cadr_Of (H, Spec, Lits, Good);
      if not Good then
         return;
      end if;
      Cddr_Of (H, Spec, Rules, Good);
      if not Good then
         return;
      end if;
      Allocate (H, Cell_Macro, Hd, Good);
      if not Good then
         return;
      end if;
      H.Cells (Hd.Index).Car := Lits;
      H.Cells (Hd.Index).Cdr := Rules;
      Result := From_Handle (Hd);
      Ok := True;
   end Build;

   procedure Expand
     (H      : in out Heap_Type;
      Macro  : Handle;
      Form   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      MC     : Cell;
      Lits   : Value;
      Rules  : Value;
      Cur    : Value;
      Rule   : Value;
      Rest   : Value;
      Pat    : Value;
      Tmpl   : Value;
      Pat_Rest : Value;
      Form_Rest : Value;
      Vars   : Value;
      Reps   : Value;
      Good   : Boolean;
      Matched : Boolean;
      Left  : Natural := Max_List_Length + 1;
   begin
      Result := Nil_Value;
      Ok := False;
      Fetch (H, Macro, MC, Good);
      if not Good or else MC.Kind /= Cell_Macro then
         return;
      end if;
      Lits := MC.Car;
      Rules := MC.Cdr;
      Cdr_Of (H, Form, Form_Rest, Good);
      if not Good then
         return;
      end if;
      Cur := Rules;
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         if not Is_Handle (Cur) then
            return;
         end if;
         Car_Of (H, Cur, Rule, Good);
         if not Good or else not Is_Handle (Rule) then
            return;
         end if;
         Car_Of (H, Rule, Pat, Good);
         if not Good then
            return;
         end if;
         Cdr_Of (H, Rule, Rest, Good);
         if not Good then
            return;
         end if;
         Car_Of (H, Rest, Tmpl, Good);
         if not Good then
            return;
         end if;
         Cdr_Of (H, Pat, Pat_Rest, Good);
         if not Good then
            return;
         end if;
         Vars := Nil_Value;
         Reps := Nil_Value;
         Match (H, Pat_Rest, Form_Rest, Lits, Vars, Reps,
                Macro_Fuel, Matched);
         if Matched then
            Inst (H, Tmpl, Vars, Reps, False, 0, Result,
                  Macro_Fuel, Ok);
            return;
         end if;
         declare
            Next : Value;
         begin
            Cdr_Of (H, Cur, Next, Good);
            if not Good then
               return;
            end if;
            Cur := Next;
            Left := Left - 1;
         end;
      end loop;
   end Expand;

end Tr7.Macros;
