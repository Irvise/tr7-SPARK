pragma Ada_2022;


package body Tr7.Bignums with
   SPARK_Mode => On
is

   function Is_Bigint (H : Heap_Type; V : Value) return Boolean
   is
      C    : Cell;
      Good : Boolean;
   begin
      if not Is_Handle (V) then
         return False;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      return Good and then C.Kind = Cell_Bigint;
   end Is_Bigint;

   function Is_Exact_Integer (H : Heap_Type; V : Value) return Boolean is
     (Is_Fixnum (V) or else Is_Bigint (H, V));

   function Is_Integer_Text (Text : String) return Boolean
     with Pre => Text'First >= 1 and then Text'Last < Natural'Last
   is
      Pos : Natural := Text'First;
   begin
      if Text'Length = 0 then
         return False;
      end if;
      if Text (Pos) = '-' or else Text (Pos) = '+' then
         Pos := Pos + 1;
      end if;
      if Pos > Text'Last then
         return False;
      end if;
      while Pos <= Text'Last loop
         pragma Loop_Invariant (Pos >= Text'First);
         pragma Loop_Invariant (Pos <= Text'Last + 1);
         pragma Loop_Variant (Decreases => Text'Last - Pos + 1);
         if Text (Pos) not in '0' .. '9' then
            return False;
         end if;
         Pos := Pos + 1;
      end loop;
      return True;
   end Is_Integer_Text;

   function Parse_Value (Text : String) return Valid_Big_Integer
     with Pre => Text'First >= 1
       and then Text'Last < Natural'Last
       and then Text'Length > 0
       and then Is_Integer_Text (Text)
   is
      Acc : Valid_Big_Integer := To_Big_Integer (0);
      Neg : constant Boolean := Text (Text'First) = '-';
      Fixed : constant Natural :=
        (if Text (Text'First) = '-' or else Text (Text'First) = '+'
         then Text'First + 1 else Text'First);
   begin
      for I in Fixed .. Text'Last loop
         Acc := Acc * To_Big_Integer (10)
           + To_Big_Integer
               (Character'Pos (Text (I)) - Character'Pos ('0'));
      end loop;
      return (if Neg then -Acc else Acc);
   end Parse_Value;

   procedure Parse
     (Text : String;
      B    : out Valid_Big_Integer;
      Ok   : out Boolean)
   is
   begin
      B := To_Big_Integer (0);
      Ok := False;
      if Text'Length = 0 then
         return;
      end if;
      if not Is_Integer_Text (Text) then
         return;
      end if;
      B := Parse_Value (Text);
      Ok := True;
   end Parse;

   procedure Image
     (B   : Valid_Big_Integer;
      T   : out Text_Buffer;
      Len : out Natural;
      Ok  : out Boolean)
   is
      S : constant String := To_String (B);
      --  Ada's image leaves a blank in the sign column of a non-negative
      --  value (the same convention as Integer'Image); the canonical
      --  Scheme text has no such blank.
      Start : constant Natural :=
        (if S'Length > 0 and then S (S'First) = ' ' then S'First + 1
         else S'First);
      N : constant Natural :=
        (if S'Length > 0 and then S (S'First) = ' ' then S'Length - 1
         else S'Length);
   begin
      T := [others => ' '];
      Len := 0;
      Ok := False;
      if N > Max_Text then
         return;
      end if;
      for I in Start .. S'Last loop
         T (I - Start + 1) := S (I);
      end loop;
      Len := N;
      Ok := True;
   end Image;

   procedure Canonical
     (Text : String;
      T    : out Text_Buffer;
      Len  : out Natural;
      Ok   : out Boolean)
   is
   begin
      T := [others => ' '];
      Len := 0;
      Ok := False;
      if Text'Length = 0 or else not Is_Integer_Text (Text) then
         return;
      end if;
      declare
         B : constant Valid_Big_Integer := Parse_Value (Text);
      begin
         Image (B, T, Len, Ok);
      end;
   end Canonical;

   procedure To_Big
     (H  : Heap_Type;
      V  : Value;
      B  : out Valid_Big_Integer;
      Ok : out Boolean)
   is
      C    : Cell;
      Good : Boolean;
   begin
      B := To_Big_Integer (0);
      Ok := False;
      if Is_Fixnum (V) then
         if V.N not in Fixnum_Min .. Fixnum_Max then
            return;
         end if;
         B := To_Big_Integer (Integer (V.N));
         Ok := True;
         return;
      end if;
      if not Is_Handle (V) then
         return;
      end if;
      Fetch (H, To_Handle (V), C, Good);
      if not Good or else C.Kind /= Cell_Bigint then
         return;
      end if;
      Parse (Text_Of (C), B, Ok);
   end To_Big;

   function To_Big_Value
     (H : Heap_Type;
      V : Value) return Valid_Big_Integer
   is
      B    : Valid_Big_Integer := To_Big_Integer (0);
      Good : Boolean;
   begin
      if Is_Fixnum (V) then
         if V.N in Fixnum_Min .. Fixnum_Max then
            B := To_Big_Integer (Integer (V.N));
         end if;
         return B;
      end if;
      if Is_Handle (V) then
         declare
            C : Cell;
            Fetched : Boolean;
         begin
            Fetch (H, To_Handle (V), C, Fetched);
            if Fetched and then C.Kind = Cell_Bigint then
               Parse (Text_Of (C), B, Good);
               if not Good then
                  B := To_Big_Integer (0);
               end if;
            end if;
         end;
      end if;
      return B;
   end To_Big_Value;

   procedure From_Big
     (H      : in out Heap_Type;
      B      : Valid_Big_Integer;
      Result : out Value;
      Status : out Error_Code)
   is
      T    : Text_Buffer;
      Len  : Natural;
      Good : Boolean;
      Hd   : Handle;
   begin
      Result := Void_Value;
      if Fits_Fixnum (B) then
         Result := From_Fixnum (To_Fixnum (B));
         Status := No_Error;
         return;
      end if;
      Image (B, T, Len, Good);
      if not Good then
         Status := Error_Overflow;
         return;
      end if;
      New_Bigint (H, T (1 .. Len), Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end From_Big;

   procedure From_Big_Ratio
     (H      : in out Heap_Type;
      N      : Valid_Big_Integer;
      D      : Valid_Big_Integer;
      Result : out Value;
      Status : out Error_Code)
   is
      Num : Valid_Big_Integer := N;
      Den : Valid_Big_Integer := D;
      NV  : Value;
      DV  : Value;
      Hd  : Handle;
      Good : Boolean;
   begin
      Result := Void_Value;
      if Den = To_Big_Integer (0) then
         Status := Error_Division_By_Zero;
         return;
      end if;
      if Den < To_Big_Integer (0) then
         Num := -Num;
         Den := -Den;
      end if;
      if Num = To_Big_Integer (0) then
         Result := From_Fixnum (0);
         Status := No_Error;
         return;
      end if;
      declare
         G : constant Valid_Big_Integer :=
           Greatest_Common_Divisor (abs Num, abs Den);
      begin
         Num := Num / G;
         Den := Den / G;
      end;
      if Den = To_Big_Integer (1) then
         From_Big (H, Num, Result, Status);
         return;
      end if;
      From_Big (H, Num, NV, Status);
      if Status /= No_Error then
         return;
      end if;
      From_Big (H, Den, DV, Status);
      if Status /= No_Error then
         return;
      end if;
      New_Rational (H, NV, DV, Hd, Good);
      if not Good then
         Status := Error_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := No_Error;
   end From_Big_Ratio;

   procedure Make_Rational
     (H      : in out Heap_Type;
      Num    : Value;
      Den    : Value;
      Result : out Value;
      Status : out Error_Code)
   is
   begin
      Result := Void_Value;
      Status := Error_Type;
      if not Is_Exact_Integer (H, Num)
        or else not Is_Exact_Integer (H, Den)
      then
         return;
      end if;
      declare
         N : constant Valid_Big_Integer := To_Big_Value (H, Num);
         D : constant Valid_Big_Integer := To_Big_Value (H, Den);
      begin
         if D = To_Big_Integer (0) then
            Status := Error_Division_By_Zero;
            return;
         end if;
         From_Big_Ratio (H, N, D, Result, Status);
      end;
   end Make_Rational;

end Tr7.Bignums;
