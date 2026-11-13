--  Reachability mathematics and the sweep: the second half of the collector.
--
--  This unit exists separately from Tr7.Heap on purpose.  Reachable's
--  definition axiom seeds an instantiation storm in every VC of any unit
--  that mentions it -- measured at over a million quantifier instantiations
--  on goals that never touch reachability -- so only the sweep, whose goals
--  are reachability-directed, may depend on it.  The drain's proofs stay
--  clean in Tr7.Heap.
--
--  Nothing here is evaluated at run time except Sweep's own loop: the
--  reachability predicates appear only in loop invariants, which the
--  build's assertion policy (tr7/gnat.adc) compiles away, because
--  evaluating them costs more than the collection itself.

with Interfaces; use Interfaces;
with Tr7.Cells; use Tr7.Cells;
with Tr7.Config; use Tr7.Config;
with Tr7.Heap;
with Tr7.Values;

package Tr7.Reach with
   SPARK_Mode => On
is

   --  Fuel-bounded reachability along exactly the edges the drain roots:
   --  Car, Cdr, and Env for closures and environments; cell 0 is nil and
   --  never reached.  An expression function with an explicit variant: the
   --  definition is what the lemma unfolds, the variant is what terminates
   --  it.
   function Reachable
     (H     : Tr7.Heap.Heap_Type;
      From  : Cell_Index;
      To    : Cell_Index;
      Fuel  : Natural)
      return Boolean
     is ((From = To and then From /= 0)
         or else (Fuel > 0
                  and then From /= 0
                  and then
                    (Reachable (H, Tr7.Heap.Live_Cell (H, H.Cells (From).Car),
                                To, Fuel - 1)
                     or else Reachable
                       (H, Tr7.Heap.Live_Cell (H, H.Cells (From).Cdr),
                        To, Fuel - 1)
                     or else (if H.Cells (From).Kind = Cell_Closure
                                or else H.Cells (From).Kind = Cell_Environment
                              then Reachable
                                (H, Tr7.Heap.Live_Cell
                                     (H, Tr7.Values.From_Handle
                                       (H.Cells (From).Env)),
                                 To, Fuel - 1)
                              else False))))
     with Subprogram_Variant => (Decreases => Fuel);

   --  Reachable from any of the first Count roots.
   function From_Roots
     (H     : Tr7.Heap.Heap_Type;
      Roots : Tr7.Heap.Root_Array;
      Count : Tr7.Heap.Root_Count;
      To    : Cell_Index;
      Fuel  : Natural)
      return Boolean
     is (for some K in 1 .. Count =>
            Reachable (H, Roots (K), To, Fuel));

   --  The path induction: a marked cell with a path to To ends at a marked
   --  To, provided the worklist has drained and the marked set is closed.
   --  Proved by recursion on Fuel -- the recursive call receives this very
   --  contract as its induction hypothesis, which is the only way a
   --  single-step prover ever walks a whole path.
   function Marked_If_Reached
     (H    : Tr7.Heap.Heap_Type;
      From : Cell_Index;
      To   : Cell_Index;
      Fuel : Natural)
      return Boolean
     with
       Subprogram_Variant => (Decreases => Fuel),
       Post => (if H.Mark_Top = 0
                  and then Tr7.Heap.Closure (H)
                  and then Tr7.Heap.Is_Marked (H, From)
                  and then Reachable (H, From, To, Fuel)
                then Marked_If_Reached'Result
                  and then Tr7.Heap.Is_Marked (H, To));

   --  Sweep the unmarked cells back onto the free list.  The caller runs it
   --  only when Collect returned without Mark_Failed, so the closure facts
   --  in Collect's postcondition are plain call-site hypotheses here.
   --
   --  The M5 goal lives in this loop's invariants, deliberately:
   --  reachability is exponential to evaluate, so it may never appear in a
   --  precondition, postcondition or assert -- only in invariants, which
   --  the build's assertion policy does not compile into run time.  Both
   --  invariants speak of H'Loop_Entry, the post-drain heap: the sweep
   --  only ever writes Kind and the free list, so anchoring there avoids
   --  proving congruence of Reachable under an array update, which would
   --  need an induction no single proof step can do.
   procedure Sweep
     (H     : in out Tr7.Heap.Heap_Type;
      Roots : Tr7.Heap.Root_Array;
      Count : Tr7.Heap.Root_Count)
     with
       Pre  => H.Ready
         and then not H.Mark_Failed
         and then H.Mark_Top = 0
         and then Tr7.Heap.Closure (H)
         and then Tr7.Heap.Roots_Marked (H, Roots, Count)
         and then (for all J in Valid_Cell_Index =>
                     (if Tr7.Heap.Is_Marked (H, J)
                      then H.Cells (J).Kind /= Cell_Free)),
       Post => H.Ready
         and then H.Mark_Top = 0
         and then H.Free_Count >= H.Free_Count'Old
         and then H.Epoch = H.Epoch'Old;

end Tr7.Reach;
