with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Interfaces; use Interfaces;
with Tr7.Bignums;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.IEEE;
with Tr7.Pairs; use Tr7.Pairs;
with Tr7.Runtime; use Tr7.Runtime;

package body Tr7.Reader with
   SPARK_Mode => On
is

   function Is_Space (C : Character) return Boolean is
     (C = ' ' or else C = HT or else C = LF
        or else C = CR or else C = FF or else C = VT);

   function Is_Delimiter (C : Character) return Boolean is
     (Is_Space (C) or else C = '(' or else C = ')' or else C = '"'
        or else C = ';' or else C = Character'Val (39));

   function Is_Digit (C : Character) return Boolean is
     (C in '0' .. '9');

   function Is_Sign (C : Character) return Boolean is
     (C = '+' or else C = '-');

   --  A whole token is an integer when it is an optional sign followed by at
   --  least one digit.  Parse_Integer answers the same question for values
   --  it can hold; this one must also accept a value too large for a fixnum,
   --  which Parse_Integer rejects before it has seen the trailing digits.
   function Is_Integer_Token (Text : String) return Boolean
     with Pre => Text'First >= 1 and then Text'Last < Natural'Last
   is
      Pos : Natural := Text'First;
   begin
      if Text'Length = 0 then
         return False;
      end if;
      if Is_Sign (Text (Pos)) then
         Pos := Pos + 1;
      end if;
      if Pos > Text'Last then
         return False;
      end if;
      while Pos <= Text'Last loop
         pragma Loop_Invariant (Pos >= Text'First);
         pragma Loop_Invariant (Pos <= Text'Last + 1);
         pragma Loop_Variant (Decreases => Text'Last - Pos + 1);
         if not Is_Digit (Text (Pos)) then
            return False;
         end if;
         Pos := Pos + 1;
      end loop;
      return True;
   end Is_Integer_Token;

   function To_Lower (C : Character) return Character is
     (if C in 'A' .. 'Z' then
        Character'Val (Character'Pos (C) - Character'Pos ('A') + Character'Pos ('a'))
      else
        C);

   function Is_Hex_Digit (C : Character) return Boolean is
     ((C in '0' .. '9') or else (C in 'a' .. 'f') or else (C in 'A' .. 'F'));

   --  Total by construction: every branch is non-negative, so the function
   --  needs no precondition even though callers only feed it hex digits.
   function Hex_Value (C : Character) return Unsigned_32 is
     (if C in '0' .. '9' then
        Unsigned_32 (Character'Pos (C) - Character'Pos ('0'))
      elsif C in 'a' .. 'f' then
        Unsigned_32 (Character'Pos (C) - Character'Pos ('a')) + 10
      elsif C in 'A' .. 'F' then
        Unsigned_32 (Character'Pos (C) - Character'Pos ('A')) + 10
      else
        0);

   procedure Skip_Atmosphere (S : String; Pos : in out Natural)
     with
       Pre  => S'First = 1
         and then S'Last <= Natural'Last - 2
         and then Pos <= S'Length,
       Post => Pos <= S'Length
   is
      C : Character;
   begin
      while Pos < S'Length loop
         pragma Loop_Invariant (Pos <= S'Length);
         C := S (Pos + 1);
         if Is_Space (C) then
            Pos := Pos + 1;
         elsif C = ';' then
            while Pos < S'Length and then S (Pos + 1) /= LF loop
               pragma Loop_Invariant (Pos <= S'Length);
               Pos := Pos + 1;
            end loop;
         elsif C = '#'
           and then S'Length >= 2
           and then Pos <= S'Length - 2
           and then S (Pos + 2) = '|'
         then
            --  #| ... |# block comment.
            Pos := Pos + 2;
            while Pos < S'Length
              and then not (S (Pos + 1) = '|'
                            and then Pos <= S'Length - 2
                            and then S (Pos + 2) = '#')
            loop
               pragma Loop_Invariant (Pos <= S'Length);
               Pos := Pos + 1;
            end loop;
            if Pos < S'Length then
               Pos := Pos + 2;
            end if;
         else
            return;
         end if;
      end loop;
   end Skip_Atmosphere;

   procedure Parse_Integer
     (Text        : String;
      Is_Integer  : out Boolean;
      N           : out Integer_64;
      Ok          : out Boolean)
     with
       Pre  => Text'First >= 1 and then Text'Last < Natural'Last,
       Post => (if Ok then N in Fixnum_Min .. Fixnum_Max)
   is
      I        : Natural;
      Neg      : Boolean := False;
      Acc      : Integer_64 := 0;
      D        : Integer_64;
      Mag_Max  : Integer_64;
   begin
      Is_Integer := False;
      N := 0;
      Ok := False;
      if Text'Length = 0 then
         return;
      end if;

      I := Text'First;
      if Is_Sign (Text (I)) then
         Neg := Text (I) = '-';
         I := I + 1;
         if I > Text'Last then
            return;
         end if;
      end if;

      if not Is_Digit (Text (I)) then
         return;
      end if;
      Is_Integer := True;

      if Neg then
         Mag_Max := -Fixnum_Min;
      else
         Mag_Max := Fixnum_Max;
      end if;

      while I <= Text'Last and then Is_Digit (Text (I)) loop
         pragma Loop_Invariant (Acc >= 0);
         pragma Loop_Invariant (I >= Text'First);
         pragma Loop_Invariant (I <= Text'Last);
         D := Integer_64 (Character'Pos (Text (I)) - Character'Pos ('0'));
         if Acc > (Mag_Max - D) / 10 then
            Ok := False;
            return;
         end if;
         Acc := Acc * 10 + D;
         I := I + 1;
      end loop;

      --  The whole token has to be digits: "1.5" is a flonum, "1e3" is a
      --  flonum, and "1abc" is a symbol -- none of them the integer 1.
      if I <= Text'Last then
         Is_Integer := False;
         return;
      end if;

      if Neg then
         N := -Acc;
      else
         N := Acc;
      end if;
      Ok := N in Fixnum_Min .. Fixnum_Max;
   end Parse_Integer;

   --  Turn an integer token into a value: a fixnum when it fits, a
   --  Cell_Bigint otherwise.  Used by ordinary atoms and by the two halves
   --  of a rational literal.
   procedure Integer_Value
     (H      : in out Heap_Type;
      Text   : String;
      Result : out Value;
      Status : out Read_Status)
     with
       Pre  => H.Ready
         and then Text'First >= 1
         and then Text'Last < Natural'Last
         and then Text'Length <= Max_Text,
       Post => H.Ready
   is
      Is_Num : Boolean;
      Num    : Integer_64;
      Ok     : Boolean;
   begin
      Result := Nil_Value;
      Status := Read_Error;
      Parse_Integer (Text, Is_Num, Num, Ok);
      if not Is_Num then
         return;
      end if;
      if Ok then
         Result := From_Fixnum (Num);
         Status := Read_Ok;
         return;
      end if;
      if not Is_Integer_Token (Text) then
         return;
      end if;
      declare
         T    : Text_Buffer;
         TLen : Natural;
         C_OK : Boolean;
         Hd   : Handle;
      begin
         Tr7.Bignums.Canonical (Text, T, TLen, C_OK);
         if not C_OK then
            return;
         end if;
         New_Bigint (H, T (1 .. TLen), Hd, C_OK);
         if not C_OK then
            Status := Read_Heap_Full;
            return;
         end if;
         Result := From_Handle (Hd);
         Status := Read_Ok;
      end;
   end Integer_Value;


   --  Powers of ten up to 10**22: every one of them still has all its bits
   --  in a double (10**22 = 2**22 * 5**22 and 5**22 fits in 53), so a single
   --  multiply or divide by one of them is a single rounding -- unlike a
   --  digit-by-digit loop, which rounds once per step and drifts.
   Ten_Powers : constant array (0 .. 22) of Long_Float :=
     (0  => 1.0E00,  1  => 1.0E01,  2  => 1.0E02,  3  => 1.0E03,
      4  => 1.0E04,  5  => 1.0E05,  6  => 1.0E06,  7  => 1.0E07,
      8  => 1.0E08,  9  => 1.0E09,  10 => 1.0E10,  11 => 1.0E11,
      12 => 1.0E12,  13 => 1.0E13,  14 => 1.0E14,  15 => 1.0E15,
      16 => 1.0E16,  17 => 1.0E17,  18 => 1.0E18,  19 => 1.0E19,
      20 => 1.0E20,  21 => 1.0E21,  22 => 1.0E22);

   --  Parse a decimal: digits with an optional point and an optional
   --  exponent.  The mantissa keeps up to 18 digits -- past double
   --  precision, and small enough that the multiply cannot overflow -- and
   --  digits dropped beyond that only cost precision, with pre-point ones
   --  counted into the exponent so the magnitude stays right.  Out of range
   --  is a failed parse (a read error), never a silently wrong value.
   procedure Parse_Float
     (Text     : String;
      Is_Float : out Boolean;
      X        : out Long_Float;
      Ok       : out Boolean)
   is
      I      : Natural;
      Neg    : Boolean := False;
      Mant   : Integer_64 := 0;
      Kept : Natural range 0 .. 18 := 0;
      Extra  : Natural range 0 .. Max_Text := 0;
      Frac   : Natural range 0 .. 18 := 0;
      Exp    : Integer range -99_999 .. 99_999 := 0;
      E_Neg  : Boolean := False;
      Seen   : Boolean := False;
      D      : Integer_64;
      Total  : Integer;
      Mag    : Long_Float;
      Limit  : constant Long_Float := 1.0E307;
   begin
      Is_Float := False;
      X := 0.0;
      Ok := False;
      if Text'Length = 0 then
         return;
      end if;

      I := Text'First;
      if Is_Sign (Text (I)) then
         Neg := Text (I) = '-';
         I := I + 1;
         if I > Text'Last then
            return;
         end if;
      end if;

      --  Integer part.
      while I <= Text'Last and then Is_Digit (Text (I)) loop
         pragma Loop_Invariant (I >= Text'First);
         pragma Loop_Invariant (I <= Text'Last);
         pragma Loop_Invariant (Mant >= 0);
         Seen := True;
         D := Integer_64 (Character'Pos (Text (I)) - Character'Pos ('0'));
         if Kept < 18 and then Mant <= (Integer_64'Last - D) / 10 then
            Mant := Mant * 10 + D;
            Kept := Kept + 1;
         elsif Extra < Max_Text then
            Extra := Extra + 1;
         end if;
         I := I + 1;
      end loop;

      --  Fractional part.
      if I <= Text'Last and then Text (I) = '.' then
         I := I + 1;
         while I <= Text'Last and then Is_Digit (Text (I)) loop
            pragma Loop_Invariant (I >= Text'First);
            pragma Loop_Invariant (I <= Text'Last);
            pragma Loop_Invariant (Frac <= Kept);
            pragma Loop_Invariant (Mant >= 0);
            Seen := True;
            D := Integer_64 (Character'Pos (Text (I)) - Character'Pos ('0'));
            if Kept < 18 and then Mant <= (Integer_64'Last - D) / 10 then
               Mant := Mant * 10 + D;
               Kept := Kept + 1;
               Frac := Frac + 1;
            end if;
            I := I + 1;
         end loop;
      end if;

      if not Seen then
         return;
      end if;

      --  Exponent.
      if I <= Text'Last and then To_Lower (Text (I)) = 'e' then
         I := I + 1;
         if I > Text'Last then
            return;
         end if;
         if Is_Sign (Text (I)) then
            E_Neg := Text (I) = '-';
            I := I + 1;
            if I > Text'Last then
               return;
            end if;
         end if;
         if not Is_Digit (Text (I)) then
            return;
         end if;
         while I <= Text'Last and then Is_Digit (Text (I)) loop
            pragma Loop_Invariant (I >= Text'First);
            pragma Loop_Invariant (I <= Text'Last);
            pragma Loop_Invariant (Exp >= 0);
            if Exp < 10_000 then
               Exp := Exp * 10
                 + (Character'Pos (Text (I)) - Character'Pos ('0'));
            end if;
            I := I + 1;
         end loop;
         if E_Neg then
            Exp := -Exp;
         end if;
      end if;

      --  Anything left means the token is not a number after all.
      if I <= Text'Last then
         return;
      end if;

      Is_Float := True;

      Total := Extra - Frac + Exp;
      if Total > 308 then
         return;
      end if;

      Mag := Long_Float (Mant);
      if Total >= -22 and then Total <= 22 then
         --  One operation, one rounding: the correctly rounded value of the
         --  decimal.  This covers every exponent ordinary notation uses,
         --  which is what makes 0.1 read as the same double every other
         --  Scheme reads it as.
         if Total >= 0 then
            if Ten_Powers (Total) > 1.0E22 or else Mag > 1.0E286 then
               return;
            end if;
            Mag := Mag * Ten_Powers (Total);
         else
            if Ten_Powers (-Total) < 1.0 then
               return;
            end if;
            Mag := Mag / Ten_Powers (-Total);
         end if;
      elsif Total >= -400 then
         --  Beyond 10**22 no exact power exists in a double, so the shift
         --  has to be stepped and rounds once per step: right for ordinary
         --  purposes, documented as the wide-exponent path.  The guards are
         --  unreachable (the table holds at most 10**22, the mantissa at
         --  most 18 digits) and exist so the products have constant bounds.
         if Total > 0 then
            if Mag > 1.0E307 then
               return;
            end if;
            for K in 1 .. Total loop
               pragma Loop_Invariant (Mag >= 0.0);
               pragma Loop_Invariant (Mag <= 1.0E308);
               if Mag > Limit then
                  return;
               end if;
               Mag := Mag * 10.0;
            end loop;
         else
            for K in 1 .. -Total loop
               pragma Loop_Invariant (Mag >= 0.0);
               pragma Loop_Invariant (Mag <= 1.0E19);
               if Mag > 1.0E19 then
                  return;
               end if;
               Mag := Mag / 10.0;
            end loop;
         end if;
      else
         --  Underflows to zero, which is what the value is.
         Mag := 0.0;
      end if;

      if Neg then
         X := -Mag;
      else
         X := Mag;
      end if;
      Ok := True;
   end Parse_Float;

   --  |...| symbols: everything between the bars is the name, with \| and
   --  \\ escapes.  This is the readable form the writer emits for names
   --  outside the ordinary symbol alphabet.
   procedure Read_Bar_Symbol
     (H      : in out Heap_Type;
      S      : String;
      Pos    : in out Natural;
      Result : out Value;
      Status : out Read_Status)
     with
       Pre  => H.Ready
         and then S'First = 1
         and then S'Last <= Natural'Last - 2
         and then Pos < S'Length,
       Post => H.Ready and then Pos <= S'Length
   is
      Buf : Text_Buffer := (others => ' ');
      Len : Natural := 0;
      C   : Character;
      Ok  : Boolean;
      Closed : Boolean := False;
      Steps : Natural := S'Length + 1;
   begin
      Result := Nil_Value;
      Status := Read_Error;
      Pos := Pos + 1;
      while Pos < S'Length and then Steps > 0 loop
         pragma Loop_Invariant (Pos <= S'Length);
         pragma Loop_Invariant (Len <= Max_Text);
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Steps >= 1);
         pragma Loop_Variant (Decreases => Steps);
         C := S (Pos + 1);
         if C = '|' then
            Pos := Pos + 1;
            Closed := True;
            exit;
         end if;
         if C = '\' then
            Pos := Pos + 1;
            if Pos >= S'Length then
               return;
            end if;
            C := S (Pos + 1);
            if C /= '|' and then C /= '\' then
               return;
            end if;
         end if;
         if Len >= Max_Text then
            return;
         end if;
         Len := Len + 1;
         Buf (Len) := C;
         Pos := Pos + 1;
         Steps := Steps - 1;
      end loop;
      if not Closed then
         return;
      end if;
      pragma Assert (Pos <= S'Length);
      Intern (H, Buf (1 .. Len), Result, Ok);
      if Ok then
         Status := Read_Ok;
      else
         Status := Read_Heap_Full;
      end if;
   end Read_Bar_Symbol;

   procedure Read_Internal
     (H      : in out Heap_Type;
      S      : String;
      Pos    : in out Natural;
      Depth  : Natural;
      Result : out Value;
      Status : out Read_Status)
     with
       Pre  => H.Ready
         and then S'First = 1
         and then S'Last <= Natural'Last - 2
         and then Pos <= S'Length
         and then Depth > 0,
       Post => H.Ready and then Pos <= S'Length,
       Subprogram_Variant => (Decreases => Depth);

   procedure Read_List
     (H      : in out Heap_Type;
      S      : String;
      Pos    : in out Natural;
      Depth  : Natural;
      Result : out Value;
      Status : out Read_Status)
     with
       Pre  => H.Ready
         and then S'First = 1
         and then S'Last <= Natural'Last - 2
         and then Pos < S'Length
         and then Depth > 0,
       Post => H.Ready and then Pos <= S'Length,
       Subprogram_Variant => (Decreases => Depth)
   is
      Head    : Handle := Null_Handle;
      Tail    : Handle := Null_Handle;
      Count   : Natural := 0;
      Dotted  : Boolean := False;
      Tail_V  : Value := Nil_Value;
      Item    : Value;
      St      : Read_Status;
      C       : Character;
      Hd      : Handle;
      Good    : Boolean;
   begin
      Result := Nil_Value;
      Status := Read_Error;

      --  Consume '('.
      Pos := Pos + 1;

      loop
         pragma Loop_Invariant (Pos <= S'Length);
         pragma Loop_Invariant (Count <= Max_List_Length);
         pragma Loop_Invariant (H.Ready);
         Skip_Atmosphere (S, Pos);
         if Pos >= S'Length then
            return;
         end if;

         C := S (Pos + 1);
         if C = ')' then
            Pos := Pos + 1;
            exit;
         end if;

         if Depth <= 1 then
            return;
         end if;

         if C = '.' then
            --  A dot is only special when followed by a delimiter.
            if Pos + 2 <= S'Length and then Is_Delimiter (S (Pos + 2)) then
               if Count = 0 then
                  return;
               end if;
               Pos := Pos + 1;
               Skip_Atmosphere (S, Pos);
               if Pos >= S'Length then
                  return;
               end if;
               Read_Internal (H, S, Pos, Depth - 1, Tail_V, St);
               if St /= Read_Ok then
                  return;
               end if;
               Skip_Atmosphere (S, Pos);
               if Pos >= S'Length or else S (Pos + 1) /= ')' then
                  return;
               end if;
               Pos := Pos + 1;
               Dotted := True;
               exit;
            end if;
         end if;

         Read_Internal (H, S, Pos, Depth - 1, Item, St);
         if St /= Read_Ok then
            return;
         end if;

         New_Pair (H, Item, Nil_Value, Hd, Good);
         if not Good then
            Status := Read_Heap_Full;
            return;
         end if;
         if Count = 0 then
            Head := Hd;
         else
            Set_Cdr (H, Tail, From_Handle (Hd), Good);
            if not Good then
               return;
            end if;
         end if;
         Tail := Hd;
         if Count >= Max_List_Length then
            return;
         end if;
         Count := Count + 1;
      end loop;

      if Count = 0 then
         Result := Nil_Value;
      else
         if Dotted then
            Set_Cdr (H, Tail, Tail_V, Good);
            if not Good then
               return;
            end if;
         end if;
         Result := From_Handle (Head);
      end if;
      Status := Read_Ok;
   end Read_List;

   procedure Read_String
     (H      : in out Heap_Type;
      S      : String;
      Pos    : in out Natural;
      Result : out Value;
      Status : out Read_Status)
     with
       Pre  => H.Ready
         and then S'First = 1
         and then S'Last <= Natural'Last - 2
         and then Pos < S'Length,
       Post => H.Ready and then Pos <= S'Length
   is
      Buf : Text_Buffer := (others => ' ');
      Len : Natural := 0;
      C   : Character;
      Esc : Character;
      Hd  : Handle;
      Ok  : Boolean;
      Closed : Boolean := False;
      Steps : Natural := S'Length + 1;
   begin
      Result := Nil_Value;
      Status := Read_Error;

      --  Consume the opening quote.
      Pos := Pos + 1;

      while Pos < S'Length and then Steps > 0 loop
         pragma Loop_Invariant (Pos <= S'Length);
         pragma Loop_Invariant (Len <= Max_Text);
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Steps >= 1);
         pragma Loop_Variant (Decreases => Steps);
         C := S (Pos + 1);
         if C = '"' then
            Pos := Pos + 1;
            Closed := True;
            exit;
         end if;

         if C = '\' then
            Pos := Pos + 1;
            if Pos >= S'Length then
               return;
            end if;
            Esc := S (Pos + 1);
            if Esc = 'n' then
               C := LF;
            elsif Esc = 't' then
               C := HT;
            elsif Esc = 'r' then
               C := CR;
            elsif Esc = 'a' then
               C := Character'Val (7);
            elsif Esc = 'b' then
               C := Character'Val (8);
            elsif Esc = '"' or else Esc = '\' then
               C := Esc;
            elsif Esc = 'x' then
               --  \x<hex>;
               declare
                  Code : Natural := 0;
                  Dig  : Natural;
                  Seen : Boolean := False;
                  Left : Natural := 8;
               begin
                  Pos := Pos + 1;
                  loop
                     pragma Loop_Invariant (Pos <= S'Length);
                     pragma Loop_Variant (Decreases => Left);
                     if Left = 0 then
                        return;
                     end if;
                     Left := Left - 1;
                     if Pos >= S'Length then
                        return;
                     end if;
                     declare
                        X : constant Character := S (Pos + 1);
                     begin
                        if X = ';' then
                           Pos := Pos + 1;
                           exit;
                        end if;
                        if X in '0' .. '9' then
                           Dig := Character'Pos (X) - Character'Pos ('0');
                        elsif X in 'a' .. 'f' then
                           Dig := Character'Pos (X) - Character'Pos ('a') + 10;
                        elsif X in 'A' .. 'F' then
                           Dig := Character'Pos (X) - Character'Pos ('A') + 10;
                        else
                           return;
                        end if;
                        if Code > 255 / 16 then
                           return;
                        end if;
                        Code := Code * 16 + Dig;
                        Seen := True;
                        Pos := Pos + 1;
                     end;
                  end loop;
                  if not Seen or else Code > 255 then
                     return;
                  end if;
                  C := Character'Val (Code);
               end;
            else
               return;
            end if;
            --  The \x<hex>; branch leaves Pos on the terminating ';';
            --  every other escape leaves Pos on the escaped character.
            if Esc /= 'x' then
               Pos := Pos + 1;
            end if;
         else
            Pos := Pos + 1;
         end if;

         if Len >= Max_Text then
            return;
         end if;
         Len := Len + 1;
         Buf (Len) := C;
         Steps := Steps - 1;
      end loop;
      if not Closed then
         return;
      end if;
      pragma Assert (Pos <= S'Length);

      New_String (H, Buf (1 .. Len), Hd, Ok);
      if not Ok then
         Status := Read_Heap_Full;
         return;
      end if;
      Result := From_Handle (Hd);
      Status := Read_Ok;
   end Read_String;

   procedure Read_Internal
     (H      : in out Heap_Type;
      S      : String;
      Pos    : in out Natural;
      Depth  : Natural;
      Result : out Value;
      Status : out Read_Status)
   is
      C      : Character;
      Buf    : Text_Buffer := (others => ' ');
      Len    : Natural;
      Ok     : Boolean;
      Is_Flt : Boolean;
      Flt    : Long_Float;
      Quote_Sym : Value;
      Quoted    : Value;
      Tail      : Value;
      St        : Read_Status;
      Elems     : Value;
      Hd        : Handle;
      N         : Natural;
      Left      : Natural := S'Length + 1;
   begin
      Result := Nil_Value;
      Status := Read_End;

      loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (Pos <= S'Length);
         pragma Loop_Variant (Decreases => Left);
         if Left = 0 then
            return;
         end if;
         Left := Left - 1;
         Skip_Atmosphere (S, Pos);
         if Pos >= S'Length then
            return;
         end if;
         if S'Length >= 2
           and then Pos <= S'Length - 2
           and then S (Pos + 1) = '#'
           and then S (Pos + 2) = ';'
         then
            if Depth <= 1 then
               return;
            end if;
            Pos := Pos + 2;
            Read_Internal (H, S, Pos, Depth - 1, Result, St);
            if St /= Read_Ok then
               Status := St;
               return;
            end if;
         else
            exit;
         end if;
      end loop;

      C := S (Pos + 1);
      Status := Read_Error;

      if C = '(' then
         if Depth <= 1 then
            return;
         end if;
         Read_List (H, S, Pos, Depth - 1, Result, Status);
         return;
      end if;

      if C = ')' then
         return;
      end if;

      if C = ''' or else C = '`' or else C = ',' then
         --  The three reader shorthands, all built the same way: name the
         --  keyword, read one datum, and make (keyword datum).  ' ,x and ,@x
         --  differ only in how much source they consume and which keyword
         --  they intern; the reader always produces *data*, so quoting a
         --  backtick form still yields (quasiquote ...) as data.
         if Depth <= 1 then
            return;
         end if;
         declare
            Sym     : String (1 .. 16) := (others => ' ');
            Sym_Len : Natural;
         begin
            if C = ''' then
               Sym (1 .. 5) := "quote";
               Sym_Len := 5;
               Pos := Pos + 1;
            elsif C = '`' then
               Sym (1 .. 10) := "quasiquote";
               Sym_Len := 10;
               Pos := Pos + 1;
            elsif Pos + 2 <= S'Length and then S (Pos + 2) = '@' then
               Sym (1 .. 16) := "unquote-splicing";
               Sym_Len := 16;
               Pos := Pos + 2;
            else
               Sym (1 .. 7) := "unquote";
               Sym_Len := 7;
               Pos := Pos + 1;
            end if;

            Read_Internal (H, S, Pos, Depth - 1, Quoted, St);
            if St /= Read_Ok then
               return;
            end if;
            Intern (H, Sym (1 .. Sym_Len), Quote_Sym, Ok);
            if not Ok then
               Status := Read_Heap_Full;
               return;
            end if;
            Cons (H, Quoted, Nil_Value, Tail, Ok);
            if not Ok then
               Status := Read_Heap_Full;
               return;
            end if;
            Cons (H, Quote_Sym, Tail, Result, Ok);
            if Ok then
               Status := Read_Ok;
            end if;
         end;
         return;
      end if;

      if C = '"' then
         Read_String (H, S, Pos, Result, Status);
         return;
      end if;

      if C = '|' then
         Read_Bar_Symbol (H, S, Pos, Result, Status);
         return;
      end if;

      if C = '#' then
         if Pos + 2 > S'Length then
            return;
         end if;
         C := S (Pos + 2);
         if C = 't' then
            if S'Length >= 5
              and then Pos <= S'Length - 5
              and then S (Pos + 3 .. Pos + 5) = "rue"
            then
               if Pos = S'Length - 5
                 or else (Pos <= S'Length - 6
                          and then Is_Delimiter (S (Pos + 6)))
               then
                  Pos := Pos + 5;
                  Result := True_Value;
                  Status := Read_Ok;
               end if;
               return;
            elsif Pos = S'Length - 2
              or else (Pos <= S'Length - 3
                       and then Is_Delimiter (S (Pos + 3)))
            then
               Pos := Pos + 2;
               Result := True_Value;
               Status := Read_Ok;
            end if;
            return;
         elsif C = 'f' then
            if S'Length >= 6
              and then Pos <= S'Length - 6
              and then S (Pos + 3 .. Pos + 6) = "alse"
            then
               if Pos = S'Length - 6
                 or else (Pos <= S'Length - 7
                          and then Is_Delimiter (S (Pos + 7)))
               then
                  Pos := Pos + 6;
                  Result := False_Value;
                  Status := Read_Ok;
               end if;
               return;
            elsif Pos = S'Length - 2
              or else (Pos <= S'Length - 3
                       and then Is_Delimiter (S (Pos + 3)))
            then
               Pos := Pos + 2;
               Result := False_Value;
               Status := Read_Ok;
            end if;
            return;
         elsif C = 'u' then
            --  #u8(...) is a bytevector datum, exactly like #(...) is a
            --  vector datum.  Reading it must not require evaluating the
            --  constructor, or writer output would not read back.
            if Pos + 4 > S'Length then
               return;
            end if;
            if S (Pos + 3) /= '8' or else S (Pos + 4) /= '(' then
               return;
            end if;
            if Depth <= 1 then
               return;
            end if;
            Pos := Pos + 3;
            Read_List (H, S, Pos, Depth - 1, Elems, St);
            if St /= Read_Ok then
               Status := St;
               return;
            end if;
            Length (H, Elems, N, Ok);
            if not Ok or else N > Max_Text then
               return;
            end if;
            declare
               Bytes : String (1 .. Max_Text) := (others => ' ');
               Elem  : Value;
            begin
               for I in 1 .. N loop
                  Nth (H, Elems, I - 1, Elem, Ok);
                  if not Ok or else not Is_Fixnum (Elem)
                    or else Elem.N < 0 or else Elem.N > 255
                  then
                     return;
                  end if;
                  Bytes (I) := Character'Val (Integer (Elem.N));
               end loop;
               New_Bytevector (H, Bytes (1 .. N), Hd, Ok);
            end;
            if not Ok then
               Status := Read_Heap_Full;
               return;
            end if;
            Result := From_Handle (Hd);
            Status := Read_Ok;
            return;
         elsif C = '(' then
            --  #(...) is a vector datum.  Building it here (rather than
            --  wrapping a `vector` call) makes quoted vectors, writer
            --  round-trips and self-evaluation all agree.
            if Depth <= 1 then
               return;
            end if;
            Pos := Pos + 1;
            Read_List (H, S, Pos, Depth - 1, Elems, St);
            if St /= Read_Ok then
               Status := St;
               return;
            end if;
            Length (H, Elems, N, Ok);
            if not Ok then
               return;
            end if;
            New_Vector (H, Elems, N, Hd, Ok);
            if not Ok then
               Status := Read_Heap_Full;
               return;
            end if;
            Result := From_Handle (Hd);
            Status := Read_Ok;
            return;
         elsif C = '\' then
            Pos := Pos + 2;
            if Pos >= S'Length then
               return;
            end if;
            --  Character literal.  Read a token, or take one delimiter char.
            if Is_Delimiter (S (Pos + 1)) then
               Result := From_Character (Unsigned_32 (Character'Pos (S (Pos + 1))));
               Pos := Pos + 1;
               Status := Read_Ok;
               return;
            end if;

            Len := 0;
            while Pos < S'Length and then not Is_Delimiter (S (Pos + 1)) loop
               pragma Loop_Invariant (Pos <= S'Length);
               pragma Loop_Invariant (Len <= Max_Text);
               if Len >= Max_Text then
                  return;
               end if;
               Len := Len + 1;
               Buf (Len) := S (Pos + 1);
               Pos := Pos + 1;
            end loop;

            if Len = 1 then
               Result := From_Character (Unsigned_32 (Character'Pos (Buf (1))));
               Status := Read_Ok;
               return;
            end if;

            --  #\x41 is a hexadecimal scalar value; a lone x is the character
            --  x, which the case above already accepted.
            if Len >= 2 and then Buf (1) = 'x' then
               declare
                  Code : Unsigned_32 := 0;
               begin
                  for I in 2 .. Len loop
                     pragma Loop_Invariant (Code <= 16#10FFFF#);
                     if not Is_Hex_Digit (Buf (I)) then
                        return;
                     end if;
                     if Code > 16#10FFFF# / 16 then
                        return;
                     end if;
                     Code := Code * 16 + Hex_Value (Buf (I));
                  end loop;
                  Result := From_Character (Code);
                  Status := Read_Ok;
                  return;
               end;
            end if;

            if Len = 5
              and then To_Lower (Buf (1)) = 'a'
              and then To_Lower (Buf (2)) = 'l'
              and then To_Lower (Buf (3)) = 'a'
              and then To_Lower (Buf (4)) = 'r'
              and then To_Lower (Buf (5)) = 'm'
            then
               Result := From_Character (7);
               Status := Read_Ok;
               return;
            end if;

            if Len = 9
              and then To_Lower (Buf (1)) = 'b'
              and then To_Lower (Buf (2)) = 'a'
              and then To_Lower (Buf (3)) = 'c'
              and then To_Lower (Buf (4)) = 'k'
              and then To_Lower (Buf (5)) = 's'
              and then To_Lower (Buf (6)) = 'p'
              and then To_Lower (Buf (7)) = 'a'
              and then To_Lower (Buf (8)) = 'c'
              and then To_Lower (Buf (9)) = 'e'
            then
               Result := From_Character (8);
               Status := Read_Ok;
               return;
            end if;

            if Len = 6
              and then To_Lower (Buf (1)) = 'd'
              and then To_Lower (Buf (2)) = 'e'
              and then To_Lower (Buf (3)) = 'l'
              and then To_Lower (Buf (4)) = 'e'
              and then To_Lower (Buf (5)) = 't'
              and then To_Lower (Buf (6)) = 'e'
            then
               Result := From_Character (127);
               Status := Read_Ok;
               return;
            end if;

            if Len = 6
              and then To_Lower (Buf (1)) = 'e'
              and then To_Lower (Buf (2)) = 's'
              and then To_Lower (Buf (3)) = 'c'
              and then To_Lower (Buf (4)) = 'a'
              and then To_Lower (Buf (5)) = 'p'
              and then To_Lower (Buf (6)) = 'e'
            then
               Result := From_Character (27);
               Status := Read_Ok;
               return;
            end if;

            if Len = 4
              and then To_Lower (Buf (1)) = 'n'
              and then To_Lower (Buf (2)) = 'u'
              and then To_Lower (Buf (3)) = 'l'
              and then To_Lower (Buf (4)) = 'l'
            then
               Result := From_Character (0);
               Status := Read_Ok;
               return;
            end if;

            if Len = 6
              and then To_Lower (Buf (1)) = 'r'
              and then To_Lower (Buf (2)) = 'e'
              and then To_Lower (Buf (3)) = 't'
              and then To_Lower (Buf (4)) = 'u'
              and then To_Lower (Buf (5)) = 'r'
              and then To_Lower (Buf (6)) = 'n'
            then
               Result := From_Character (Character'Pos (CR));
               Status := Read_Ok;
               return;
            end if;

            if Len = 5
              and then To_Lower (Buf (1)) = 's'
              and then To_Lower (Buf (2)) = 'p'
              and then To_Lower (Buf (3)) = 'a'
              and then To_Lower (Buf (4)) = 'c'
              and then To_Lower (Buf (5)) = 'e'
            then
               Result := From_Character (Character'Pos (' '));
               Status := Read_Ok;
               return;
            end if;

            if Len = 7
              and then To_Lower (Buf (1)) = 'n'
              and then To_Lower (Buf (2)) = 'e'
              and then To_Lower (Buf (3)) = 'w'
              and then To_Lower (Buf (4)) = 'l'
              and then To_Lower (Buf (5)) = 'i'
              and then To_Lower (Buf (6)) = 'n'
              and then To_Lower (Buf (7)) = 'e'
            then
               Result := From_Character (Character'Pos (LF));
               Status := Read_Ok;
               return;
            end if;

            if Len = 3
              and then To_Lower (Buf (1)) = 't'
              and then To_Lower (Buf (2)) = 'a'
              and then To_Lower (Buf (3)) = 'b'
            then
               Result := From_Character (Character'Pos (HT));
               Status := Read_Ok;
               return;
            end if;

            return;
         else
            return;
         end if;
      end if;

      --  Atom: number or symbol.
      Len := 0;
      while Pos < S'Length and then not Is_Delimiter (S (Pos + 1)) loop
         pragma Loop_Invariant (Pos <= S'Length);
         pragma Loop_Invariant (Len <= Max_Text);
         if Len >= Max_Text then
            return;
         end if;
         Len := Len + 1;
         Buf (Len) := S (Pos + 1);
         Pos := Pos + 1;
      end loop;

      if Len = 0 then
         return;
      end if;
      if Len = 1 and then Buf (1) = '.' then
         --  A lone dot is the dotted-pair marker, not a symbol.
         return;
      end if;

      if Len = 6 and then Buf (1 .. 6) = "+inf.0" then
         Result := From_Flonum (Tr7.IEEE.Plus_Infinity);
         Status := Read_Ok;
         return;
      elsif Len = 6 and then Buf (1 .. 6) = "-inf.0" then
         Result := From_Flonum (Tr7.IEEE.Minus_Infinity);
         Status := Read_Ok;
         return;
      elsif Len = 6 and then Buf (1 .. 6) = "+nan.0" then
         Result := From_Flonum (Tr7.IEEE.NaN);
         Status := Read_Ok;
         return;
      elsif Len = 6 and then Buf (1 .. 6) = "-nan.0" then
         Result := From_Flonum (Tr7.IEEE.NaN);
         Status := Read_Ok;
         return;
      end if;

      declare
         Slash : Natural := 0;
      begin
         for I in 1 .. Len loop
            if Buf (I) = '/' then
               Slash := I;
               exit;
            end if;
         end loop;
         if Slash > 1 and then Slash < Len
           and then Is_Integer_Token (Buf (1 .. Slash - 1))
           and then Is_Integer_Token (Buf (Slash + 1 .. Len))
         then
            declare
               N_V  : Value;
               D_V  : Value;
               N_St : Read_Status;
               D_St : Read_Status;
               R_St : Error_Code;
            begin
               Integer_Value (H, Buf (1 .. Slash - 1), N_V, N_St);
               if N_St /= Read_Ok then
                  return;
               end if;
               Integer_Value (H, Buf (Slash + 1 .. Len), D_V, D_St);
               if D_St /= Read_Ok then
                  return;
               end if;
               Tr7.Bignums.Make_Rational (H, N_V, D_V, Result, R_St);
               if R_St = No_Error then
                  Status := Read_Ok;
               elsif R_St = Error_Heap_Full then
                  Status := Read_Heap_Full;
               end if;
               return;
            end;
         end if;
      end;

      if Is_Integer_Token (Buf (1 .. Len)) then
         declare
            I_St : Read_Status;
         begin
            Integer_Value (H, Buf (1 .. Len), Result, I_St);
            if I_St = Read_Ok then
               Status := Read_Ok;
            elsif I_St = Read_Heap_Full then
               Status := Read_Heap_Full;
            end if;
            return;
         end;
      end if;

      Parse_Float (Buf (1 .. Len), Is_Flt, Flt, Ok);
      if Is_Flt then
         if not Ok then
            return;
         end if;
         Result := From_Flonum (Flt);
         Status := Read_Ok;
         return;
      end if;

      Intern (H, Buf (1 .. Len), Result, Ok);
      if Ok then
         Status := Read_Ok;
      end if;
   end Read_Internal;

   procedure Read_Datum
     (H      : in out Heap_Type;
      Source : String;
      Pos    : in out Natural;
      Result : out Value;
      Status : out Read_Status)
   is
   begin
      Read_Internal (H, Source, Pos, Max_Reader_Depth, Result, Status);
   end Read_Datum;

end Tr7.Reader;
