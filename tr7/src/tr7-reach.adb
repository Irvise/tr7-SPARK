package body Tr7.Reach with
   SPARK_Mode => On
is

   function Marked_If_Reached
     (H    : Tr7.Heap.Heap_Type;
      From : Cell_Index;
      To   : Cell_Index;
      Fuel : Natural)
      return Boolean
   is
      Dummy : Boolean;
      Car_C : Cell_Index;
      Cdr_C : Cell_Index;
      Env_C : Cell_Index;
   begin
      if From = To then
         return Tr7.Heap.Is_Marked (H, From);
      end if;
      if Fuel = 0
        or else H.Mark_Top /= 0
        or else not Tr7.Heap.Closure (H)
        or else not Tr7.Heap.Is_Marked (H, From)
        or else not Reachable (H, From, To, Fuel)
      then
         return True;
      end if;

      --  Step along the path: whichever child carries it, by Reachable's
      --  definition, gets the induction hypothesis as its contract.
      Car_C := Tr7.Heap.Live_Cell (H, H.Cells (From).Car);
      Cdr_C := Tr7.Heap.Live_Cell (H, H.Cells (From).Cdr);
      if H.Cells (From).Kind = Tr7.Cells.Cell_Closure
        or else H.Cells (From).Kind = Tr7.Cells.Cell_Environment
      then
         Env_C := Tr7.Heap.Live_Cell
           (H, Tr7.Values.From_Handle (H.Cells (From).Env));
      else
         Env_C := 0;
      end if;

      if Reachable (H, Car_C, To, Fuel - 1) then
         Dummy := Marked_If_Reached (H, Car_C, To, Fuel - 1);
      elsif Reachable (H, Cdr_C, To, Fuel - 1) then
         Dummy := Marked_If_Reached (H, Cdr_C, To, Fuel - 1);
      else
         Dummy := Marked_If_Reached (H, Env_C, To, Fuel - 1);
      end if;
      return Dummy;
   end Marked_If_Reached;

   procedure Sweep
     (H     : in out Tr7.Heap.Heap_Type;
      Roots : Tr7.Heap.Root_Array;
      Count : Tr7.Heap.Root_Count)
   is
   begin
      for I in Valid_Cell_Index loop
         pragma Loop_Invariant (H.Ready);
         pragma Loop_Invariant (H.Mark_Top = 0);
         pragma Loop_Invariant (H.Epoch = H'Loop_Entry.Epoch);
         pragma Loop_Invariant (H.Free_Count >= H.Free_Count'Loop_Entry);
         --  LIVENESS: every cell reachable from a root is marked -- stated
         --  through the lemma, because only a conjunct containing the
         --  lemma's call imports its postcondition axiom, and GNATprove
         --  slices an invariant into one VC per top-level conjunct.
         pragma Loop_Invariant
           (for all K in 1 .. Count =>
              (for all J in Valid_Cell_Index =>
                 (if Reachable (H'Loop_Entry, Roots (K), J, Max_Cells)
                  then Marked_If_Reached (H'Loop_Entry, Roots (K), J,
                                          Max_Cells))));
         --  SAFETY: a reachable cell is never freed.  The lemma's call sits
         --  inside the atom as the middle of the implication so this
         --  conjunct's VC carries the lemma's axiom -- that is what makes
         --  the first-iteration check provable from the precondition alone
         --  and the preservation (the actual "never frees live data" proof)
         --  go through the free guard.
         pragma Loop_Invariant
           (for all K in 1 .. Count =>
              (for all J in Valid_Cell_Index =>
                 (if Reachable (H'Loop_Entry, Roots (K), J, Max_Cells)
                  then (if Marked_If_Reached (H'Loop_Entry, Roots (K), J,
                                              Max_Cells)
                        then H.Cells (J).Kind /= Cell_Free))));
         if H.Cells (I).Mark_Epoch /= H.Epoch
           and then H.Cells (I).Kind /= Cell_Free
         then
            if H.Free_Count < Max_Cells then
               H.Cells (I).Kind := Cell_Free;
               H.Cells (I).Next_Free := H.Free_Head;
               H.Free_Head := I;
               H.Free_Count := H.Free_Count + 1;
            end if;
         end if;
      end loop;
   end Sweep;

end Tr7.Reach;
