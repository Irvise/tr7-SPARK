--  Primitive procedure identifiers.
--
--  Keeping these in a standalone package avoids a dependency cycle between
--  the cell store and the primitive implementations.

package Tr7.Ids with
   SPARK_Mode => On
is

   type Primitive_Id is
     (P_None,
      P_Add,
      P_Sub,
      P_Mul,
      P_Num_Equal,
      P_Less,
      P_Greater,
      P_Less_Equal,
      P_Greater_Equal,
      P_Cons,
      P_Car,
      P_Cdr,
      P_List,
      P_Null_P,
      P_Pair_P,
      P_Eq_P,
      P_Not,
      P_Display,
      P_Newline,
      P_Write);

end Tr7.Ids;
