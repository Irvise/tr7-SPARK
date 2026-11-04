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
      C : Cell;
   begin
      Result := Nil_Value;
      Pair_Cell (H, V, C, Ok);
      if Ok then
         Result := C.Car;
      end if;
   end Car_Of;

   procedure Cdr_Of
     (H      : Heap_Type;
      V      : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      C : Cell;
   begin
      Result := Nil_Value;
      Pair_Cell (H, V, C, Ok);
      if Ok then
         Result := C.Cdr;
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
         pragma Loop_Invariant (Count <= Max_List_Length);
         if Is_Nil (Cur) then
            Len := Count;
            Ok := True;
            return;
         end if;
         if Count >= Max_List_Length then
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
      Cur : Value := List;
      Acc : Value := Nil_Value;
   begin
      Result := Nil_Value;
      Ok := False;
      loop
         pragma Loop_Invariant (H.Ready);
         if Is_Nil (Cur) then
            Result := Acc;
            Ok := True;
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

end Tr7.Pairs;
