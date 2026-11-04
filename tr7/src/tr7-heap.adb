
package body Tr7.Heap with
   SPARK_Mode => On
is

   procedure Initialize (H : out Heap_Type) is
   begin
      H.Cells := (others => (Kind => Cell_Free, others => <>));

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
         H.Cells (I).Mark := False;
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
            Mark       => False,
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
      H.Cells (Valid_Cell_Index (Hd.Index)).Mark := False;
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

end Tr7.Heap;
