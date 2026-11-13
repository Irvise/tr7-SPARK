with Interfaces; use Interfaces;
with Tr7.Config; use Tr7.Config;
with Tr7.Pairs; use Tr7.Pairs;

package body Tr7.Records with
   SPARK_Mode => On
is

   function Is_Member
     (H : Heap_Type; Sym, List : Value) return Boolean
     with Pre => H.Ready
   is
      Cur  : Value := List;
      Left : Natural := Max_List_Length + 1;
      Item : Value;
      Good : Boolean;
      Next : Value;
   begin
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         Car_Of (H, Cur, Item, Good);
         if not Good then
            return False;
         end if;
         if Same_Value (Item, Sym) then
            return True;
         end if;
         Cdr_Of (H, Cur, Next, Good);
         if not Good then
            return False;
         end if;
         Cur := Next;
         Left := Left - 1;
      end loop;
      return False;
   end Is_Member;

   procedure Call1
     (H : in out Heap_Type; S, A : Value; Result : out Value; Ok : out Boolean)
     with Pre => H.Ready, Post => H.Ready
   is
      Item : Value;
   begin
      Result := Nil_Value;
      Cons (H, A, Nil_Value, Item, Ok);
      if Ok then
         Cons (H, S, Item, Result, Ok);
      end if;
   end Call1;

   procedure Call2
     (H : in out Heap_Type; S, A, B : Value; Result : out Value; Ok : out Boolean)
     with Pre => H.Ready, Post => H.Ready
   is
      Item, Tmp : Value;
   begin
      Result := Nil_Value;
      Cons (H, B, Nil_Value, Item, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, A, Item, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, S, Tmp, Result, Ok);
   end Call2;

   procedure Call3
     (H : in out Heap_Type; S, A, B, C : Value;
      Result : out Value; Ok : out Boolean)
     with Pre => H.Ready, Post => H.Ready
   is
      Item, Tmp, Tmp2 : Value;
   begin
      Result := Nil_Value;
      Cons (H, C, Nil_Value, Item, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, B, Item, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, A, Tmp, Tmp2, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, S, Tmp2, Result, Ok);
   end Call3;

   procedure Lambda_List
     (H : in out Heap_Type; L, Params, Bdy : Value;
      Result : out Value; Ok : out Boolean)
     with Pre => H.Ready, Post => H.Ready
   is
      Body_L, Tmp : Value;
   begin
      Result := Nil_Value;
      Cons (H, Bdy, Nil_Value, Body_L, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, Params, Body_L, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, L, Tmp, Result, Ok);
   end Lambda_List;

   procedure Lambda1
     (H : in out Heap_Type; L, P, Bdy : Value;
      Result : out Value; Ok : out Boolean)
     with Pre => H.Ready, Post => H.Ready
   is
      Params, Body_L, Tmp : Value;
   begin
      Result := Nil_Value;
      Cons (H, P, Nil_Value, Params, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, Bdy, Nil_Value, Body_L, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, Params, Body_L, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, L, Tmp, Result, Ok);
   end Lambda1;

   procedure Lambda2
     (H : in out Heap_Type; L, P, Q, Bdy : Value;
      Result : out Value; Ok : out Boolean)
     with Pre => H.Ready, Post => H.Ready
   is
      Params, Body_L, Tmp, Tmp2 : Value;
   begin
      Result := Nil_Value;
      Cons (H, Q, Nil_Value, Params, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, P, Params, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, Bdy, Nil_Value, Body_L, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, Tmp, Body_L, Tmp2, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, L, Tmp2, Result, Ok);
   end Lambda2;

   procedure Define_One
     (H : in out Heap_Type; D, Name, Expr : Value;
      Result : out Value; Ok : out Boolean)
     with Pre => H.Ready, Post => H.Ready
   is
      Item, Tmp : Value;
   begin
      Result := Nil_Value;
      Cons (H, Expr, Nil_Value, Item, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, Name, Item, Tmp, Ok);
      if not Ok then
         return;
      end if;
      Cons (H, D, Tmp, Result, Ok);
   end Define_One;

   procedure Build
     (H      : in out Heap_Type;
      Form   : Value;
      Result : out Value;
      Ok     : out Boolean)
   is
      Def_Sym, Begin_Sym, Lambda_Sym, Vector_Sym : Value;
      And_Sym, Eq_Sym, Eqv_Sym, Quote_Sym : Value;
      VectorP_Sym, VectorLen_Sym, VectorRef_Sym, VectorSet_Sym : Value;
      Obj, Val : Value;
      Rest, Tail, Tail2, Next : Value;
      Name, Ctor_Spec, Ctor_Name, Ctor_Fields : Value;
      Pred_Name, Field_Specs : Value;
      Cur, Spec, Field, Accessor, Modifier : Value;
      Defs_Rev, Defs, Def, Bdy, Lambda, Args, Args_Rev : Value;
      Item, Tmp, If_Unspec, Quote_Name : Value;
      N : Natural;
      Index : Natural;
      Left : Natural;
      Good, Has_Mod : Boolean;
   begin
      Result := Nil_Value;
      Defs_Rev := Nil_Value;
      Ok := False;

      Cdr_Of (H, Form, Rest, Good);
      if not Good or else Is_Nil (Rest) then
         return;
      end if;
      Car_Of (H, Rest, Name, Good);
      if not Good or else not Is_Handle (Name) then
         return;
      end if;
      Cdr_Of (H, Rest, Tail, Good);
      if not Good or else Is_Nil (Tail) then
         return;
      end if;
      Car_Of (H, Tail, Ctor_Spec, Good);
      if not Good or else not Is_Handle (Ctor_Spec) then
         return;
      end if;
      Car_Of (H, Ctor_Spec, Ctor_Name, Good);
      if not Good or else not Is_Handle (Ctor_Name) then
         return;
      end if;
      Cdr_Of (H, Ctor_Spec, Ctor_Fields, Good);
      if not Good then
         return;
      end if;
      Cdr_Of (H, Tail, Tail2, Good);
      if not Good or else Is_Nil (Tail2) then
         return;
      end if;
      Car_Of (H, Tail2, Pred_Name, Good);
      if not Good or else not Is_Handle (Pred_Name) then
         return;
      end if;
      Cdr_Of (H, Tail2, Field_Specs, Good);
      if not Good then
         return;
      end if;
      Length (H, Field_Specs, N, Good);
      if not Good then
         return;
      end if;

      Intern (H, "define", Def_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "begin", Begin_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "lambda", Lambda_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "vector", Vector_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "and", And_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "=", Eq_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "eq?", Eqv_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "quote", Quote_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "vector?", VectorP_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "vector-length", VectorLen_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "vector-ref", VectorRef_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "vector-set!", VectorSet_Sym, Good);
      if not Good then
         return;
      end if;
      Intern (H, "obj", Obj, Good);
      if not Good then
         return;
      end if;
      Intern (H, "val", Val, Good);
      if not Good then
         return;
      end if;

      Cons (H, Name, Nil_Value, Item, Good);
      if not Good then
         return;
      end if;
      Cons (H, Quote_Sym, Item, Quote_Name, Good);
      if not Good then
         return;
      end if;

      --  (if #f #f) as the unspecified value: use (quote #f)? No -- use
      --  the false value itself; missing fields are simply #f.
      If_Unspec := False_Value;

      --  Constructor args: tag first, then each field's init.
      Args_Rev := Nil_Value;
      Cur := Field_Specs;
      Left := Max_List_Length + 1;
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         Car_Of (H, Cur, Spec, Good);
         if not Good or else not Is_Handle (Spec) then
            return;
         end if;
         Car_Of (H, Spec, Field, Good);
         if not Good then
            return;
         end if;
         if Is_Member (H, Field, Ctor_Fields) then
            Item := Field;
         else
            Item := If_Unspec;
         end if;
         Cons (H, Item, Args_Rev, Tmp, Good);
         if not Good then
            return;
         end if;
         Args_Rev := Tmp;
         Cdr_Of (H, Cur, Next, Good);
         if not Good then
            return;
         end if;
         Cur := Next;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         return;
      end if;
      Reverse_List (H, Args_Rev, Args, Good);
      if not Good then
         return;
      end if;
      Cons (H, Quote_Name, Args, Tmp, Good);
      if not Good then
         return;
      end if;
      Args := Tmp;
      if not Good then
         return;
      end if;
      Cons (H, Vector_Sym, Args, Bdy, Good);
      if not Good then
         return;
      end if;
      Lambda_List (H, Lambda_Sym, Ctor_Fields, Bdy, Lambda, Good);
      if not Good then
         return;
      end if;
      Define_One (H, Def_Sym, Ctor_Name, Lambda, Def, Good);
      if not Good then
         return;
      end if;
      Cons (H, Def, Defs_Rev, Tmp, Good);
      if not Good then
         return;
      end if;
      Defs_Rev := Tmp;
      if not Good then
         return;
      end if;

      --  Predicate: (and (vector? obj) (= (vector-length obj) N+1)
      --                  (eq? (vector-ref obj 0) 'name))
      declare
         C1, C2, C3, Len_Call, Ref_Call : Value;
         Idx : Value;
      begin
         Call1 (H, VectorP_Sym, Obj, C1, Good);
         if not Good then
            return;
         end if;
         Call1 (H, VectorLen_Sym, Obj, Len_Call, Good);
         if not Good then
            return;
         end if;
         Call2 (H, Eq_Sym, Len_Call, From_Fixnum (Integer_64 (N + 1)),
                C2, Good);
         if not Good then
            return;
         end if;
         Idx := From_Fixnum (0);
         Call2 (H, VectorRef_Sym, Obj, Idx, Ref_Call, Good);
         if not Good then
            return;
         end if;
         Call2 (H, Eqv_Sym, Ref_Call, Quote_Name, C3, Good);
         if not Good then
            return;
         end if;
         Call3 (H, And_Sym, C1, C2, C3, Bdy, Good);
         if not Good then
            return;
         end if;
         Lambda1 (H, Lambda_Sym, Obj, Bdy, Lambda, Good);
         if not Good then
            return;
         end if;
         Define_One (H, Def_Sym, Pred_Name, Lambda, Def, Good);
         if not Good then
            return;
         end if;
         Cons (H, Def, Defs_Rev, Tmp, Good);
      if not Good then
         return;
      end if;
      Defs_Rev := Tmp;
         if not Good then
            return;
         end if;
      end;

      --  Accessors and modifiers.
      Cur := Field_Specs;
      Index := 0;
      Left := Max_List_Length + 1;
      while not Is_Nil (Cur) and then Left > 0 loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Variant (Decreases => Left);
         Car_Of (H, Cur, Spec, Good);
         if not Good or else not Is_Handle (Spec) then
            return;
         end if;
         Cdr_Of (H, Spec, Tmp, Good);
         if not Good then
            return;
         end if;
         Car_Of (H, Tmp, Accessor, Good);
         if not Good then
            return;
         end if;
         Cdr_Of (H, Tmp, Next, Good);
      if not Good then
         return;
      end if;
      Tmp := Next;
         if not Good then
            return;
         end if;
         Has_Mod := not Is_Nil (Tmp);
         if Has_Mod then
            Car_Of (H, Tmp, Modifier, Good);
            if not Good then
               return;
            end if;
            Cdr_Of (H, Tmp, Next, Good);
      if not Good then
         return;
      end if;
      Tmp := Next;
            if not Good or else not Is_Nil (Tmp) then
               return;
            end if;
         else
            Modifier := Nil_Value;
         end if;
         if Index >= Max_List_Length then
            return;
         end if;
         Index := Index + 1;

         declare
            Idx : constant Value := From_Fixnum (Integer_64 (Index));
         begin
            Call2 (H, VectorRef_Sym, Obj, Idx, Bdy, Good);
            if not Good then
               return;
            end if;
            Lambda1 (H, Lambda_Sym, Obj, Bdy, Lambda, Good);
            if not Good then
               return;
            end if;
            Define_One (H, Def_Sym, Accessor, Lambda, Def, Good);
            if not Good then
               return;
            end if;
            Cons (H, Def, Defs_Rev, Tmp, Good);
      if not Good then
         return;
      end if;
      Defs_Rev := Tmp;
            if not Good then
               return;
            end if;

            if Has_Mod then
               Call3 (H, VectorSet_Sym, Obj, Idx, Val, Bdy, Good);
               if not Good then
                  return;
               end if;
               Lambda2 (H, Lambda_Sym, Obj, Val, Bdy, Lambda, Good);
               if not Good then
                  return;
               end if;
               Define_One (H, Def_Sym, Modifier, Lambda, Def, Good);
               if not Good then
                  return;
               end if;
               Cons (H, Def, Defs_Rev, Tmp, Good);
      if not Good then
         return;
      end if;
      Defs_Rev := Tmp;
               if not Good then
                  return;
               end if;
            end if;
         end;

         Cdr_Of (H, Cur, Next, Good);
         if not Good then
            return;
         end if;
         Cur := Next;
         Left := Left - 1;
      end loop;
      if not Is_Nil (Cur) then
         return;
      end if;

      Reverse_List (H, Defs_Rev, Defs, Good);
      if not Good then
         return;
      end if;
      Cons (H, Begin_Sym, Defs, Result, Good);
      Ok := Good;
   end Build;

end Tr7.Records;
