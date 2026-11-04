with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;

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
       Pre  => S'First = 1 and then Pos <= S'Length,
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

      if Neg then
         N := -Acc;
      else
         N := Acc;
      end if;
      Ok := N in Fixnum_Min .. Fixnum_Max;
   end Parse_Integer;

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
   begin
      Result := Nil_Value;
      Status := Read_Error;

      --  Consume the opening quote.
      Pos := Pos + 1;

      loop
         pragma Loop_Invariant (Pos <= S'Length);
         pragma Loop_Invariant (Len <= Max_Text);
         pragma Loop_Invariant (H.Ready);
         if Pos >= S'Length then
            return;
         end if;
         C := S (Pos + 1);
         if C = '"' then
            Pos := Pos + 1;
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
            elsif Esc = '"' or else Esc = '\' then
               C := Esc;
            else
               return;
            end if;
            Pos := Pos + 1;
         else
            Pos := Pos + 1;
         end if;

         if Len >= Max_Text then
            return;
         end if;
         Len := Len + 1;
         Buf (Len) := C;
      end loop;

      New_String (H, Buf (1 .. Len), Hd, Ok);
      if not Ok then
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
      Is_Num : Boolean;
      Num    : Integer_64;
      Quote_Sym : Value;
      Quoted    : Value;
      Tail      : Value;
      St        : Read_Status;
      Elems     : Value;
      Vec_Sym   : Value;
   begin
      Result := Nil_Value;
      Status := Read_End;

      Skip_Atmosphere (S, Pos);
      if Pos >= S'Length then
         return;
      end if;

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
               return;
            end if;
            Cons (H, Quoted, Nil_Value, Tail, Ok);
            if not Ok then
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

      if C = '#' then
         if Pos + 2 > S'Length then
            return;
         end if;
         C := S (Pos + 2);
         if C = 't' then
            Pos := Pos + 2;
            Result := True_Value;
            Status := Read_Ok;
            return;
         elsif C = 'f' then
            Pos := Pos + 2;
            Result := False_Value;
            Status := Read_Ok;
            return;
         elsif C = 'u' then
            --  #u8(1 2 3) is (bytevector 1 2 3), the same wrap as #( ... ).
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
            Intern (H, "bytevector", Vec_Sym, Ok);
            if not Ok then
               return;
            end if;
            Cons (H, Vec_Sym, Elems, Result, Ok);
            if Ok then
               Status := Read_Ok;
            end if;
            return;
         elsif C = '(' then
            --  #(1 2 3) is (vector 1 2 3): the elements are expressions and
            --  get evaluated, so the reader only wraps what Read_List already
            --  knows how to read -- the same trick as 'x becoming (quote x).
            if Depth <= 1 then
               return;
            end if;
            Pos := Pos + 1;
            Read_List (H, S, Pos, Depth - 1, Elems, St);
            if St /= Read_Ok then
               Status := St;
               return;
            end if;
            Intern (H, "vector", Vec_Sym, Ok);
            if not Ok then
               return;
            end if;
            Cons (H, Vec_Sym, Elems, Result, Ok);
            if Ok then
               Status := Read_Ok;
            end if;
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

      Parse_Integer (Buf (1 .. Len), Is_Num, Num, Ok);
      if Is_Num then
         if not Ok then
            return;
         end if;
         Result := From_Fixnum (Num);
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
